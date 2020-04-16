
using JuMP, GLPK
using Statistics
import Base.Threads


"""An 'economically rational' crop farm manager."""
mutable struct Manager <: AgComponent
    # function __init__(m::Manager)
    #     m.opt_model = Model(name="Farm Decision model")
    # end
end

function optimize_irrigated_area(m::Manager, zone::FarmZone)::Dict
    """Apply Linear Programming to naively optimize irrigated area.
    
    Occurs at start of season.

    Parameters
    ----------
    * zone : FarmZone object, representing a farm or a farming zone.
    """
    model = Model(with_optimizer(GLPK.Optimizer))

    calc::Array = []
    num_fields::Int64 = length(zone.fields)
    sizehint!(calc, num_fields)

    areas::Array{JuMP.VariableRef} = JuMP.VariableRef[]
    sizehint!(areas, num_fields)

    field_areas::Dict{String, Dict} = Dict{String, Dict}()
    sizehint!(field_areas, num_fields)

    zone_ws::Array{WaterSource} = zone.water_sources

    # Threads.@threads for f in zone.fields
    for f in zone.fields
        area_to_consider::Float64 = f.total_area_ha
        did::String = replace("$(f.name)__", " " => "_")

        naive_crop_income::Float64 = estimate_income_per_ha(f.crop)
        naive_req_water::Float64 = f.crop.water_use_ML_per_ha
        app_cost_per_ML::Dict{String, Float64} = ML_water_application_cost(m, zone, f, naive_req_water)

        pos_field_area::Float64 = sum(Float64[w.allocation / naive_req_water
                                        for w in zone_ws])
        pos_field_area = min(pos_field_area, area_to_consider)
        
        field_areas[f.name] = Dict{String, JuMP.VariableRef}(
            w.name => @variable(model, 
                                base_name="$(did)$(w.name)", 
                                lower_bound=0, 
                                upper_bound=min((w.allocation / naive_req_water), area_to_consider))
            for w in zone_ws
        )

        # total_pump_cost = sum([ws.pump.maintenance_cost(year_step) for ws in zone_ws])
        profits::Array = [field_areas[f.name][w.name] * 
                            (naive_crop_income - app_cost_per_ML[w.name])
                          for w in zone_ws]

        append!(calc, profits)
        curr_field_areas = collect(values(field_areas[f.name]))
        areas = append!(areas, curr_field_areas)

        # Total irrigated area cannot be greater than field area
        # or area possible with available water
        @constraint(model, 0.0 <= sum(curr_field_areas) <= pos_field_area)
    end

    @constraint(model, 0.0 <= sum(areas) <= zone.total_area_ha)

    # Generate appropriate OptLang model
    # model = Model.clone(m.opt_model)
    @objective(model, Max, sum(calc))

    JuMP.optimize!(model)
    if termination_status(model) != MOI.OPTIMAL
        error("Could not optimize!")
    end

    opt_vals::Dict{String, Float64} = Dict(name(v) => JuMP.value(v) for v in all_variables(model))
    opt_vals["optimal_result"] = objective_value(model)

    return opt_vals
end

function optimize_irrigation(m::Manager, zone::FarmZone, dt::Date)::Tuple
    """Apply Linear Programming to optimize irrigation water use.

    Results can be used to represent percentage mix
    e.g. if the field area is 100 ha, and the optimal area to be
            irrigated by a water source is

        `SW: 70 ha
        GW: 30 ha`

    and the required amount is 20mm

        `SW: 70 / 100 = 0.7 (irrigated area / total area, 70%)
        GW: 30 / 100 = 0.3 (30%)`
        
    Then the per hectare amount to be applied from each 
    water source is calculated as:

        `SW = 20mm * 0.7
            = 14mm

        GW = 20mm * 0.3
            = 6mm`
    
    Parameters
    ----------
    * zone : FarmZone
    * dt : datetime object, current datetime

    Returns
    ---------
    * Tuple : OrderedDict[str, float] : keys based on field and water source names
                                        values are hectare area
                Float : \$/ML cost of applying water
    """
    model = Model(GLPK.Optimizer)
    num_fields::Int64 = length(zone.fields)

    profit::Array = []
    sizehint!(profit, num_fields)

    app_cost::OrderedDict{String, Float64} = OrderedDict()
    sizehint!(app_cost, num_fields)

    zone_ws::Array{WaterSource} = zone.water_sources
    total_irrigated_area::Float64 = zone.total_irrigated_area

    field_area::Dict = Dict{String, Dict}(f.name => Dict{String, Float64}() 
                                            for f::FarmField in zone.fields)
    # sizehint!(field_area, num_fields)

    req_water::Array{Float64} = []
    sizehint!(req_water, num_fields)

    opt_vals::OrderedDict{String, Float64} = OrderedDict()

    max_ws_area::Dict{String, Dict} = Dict{String, Dict}()
    for f::FarmField in zone.fields
        f_name::String = f.name
        did::String = replace("$(f_name)__", " " => "_")

        req_water_ML_ha::Float64 = calc_required_water(f, dt) / mm_to_ML
        push!(req_water, req_water_ML_ha)

        max_ws_area[f_name] = possible_area_by_allocation(zone, f, req_water_ML_ha)
        total_pos_area = min(sum(values(max_ws_area[f_name])), f.irrigated_area)
        crop_income_per_ha::Float64 = estimate_income_per_ha(f.crop)
        if f.irrigation.name == "dryland" || req_water_ML_ha == 0.0 || total_pos_area == 0.0
            field_area[f_name] = Dict{String, JuMP.VariableRef}(
                ws.name => @variable(model,
                                     base_name="$(did)$(ws.name)",
                                     lower_bound=0.0,
                                     upper_bound=0.0)
                for ws in zone_ws
            )

            tmp_l::Array = Float64[
                crop_income_per_ha * f.irrigated_area
                for ws in zone_ws
            ]
            append!(profit, tmp_l)
            continue
        end

        # Disable this for now - estimated income includes variable costs
        # Will always incur maintenance costs and crop costs
        # total_pump_cost = sum([ws.pump.maintenance_cost(dt.year) for ws in zone_ws])
        # total_irrig_cost = f.irrigation.maintenance_cost(dt.year)
        # maintenance_cost = (total_pump_cost + total_irrig_cost)

        # estimated gross income - variable costs per ha
        max_ws_area[f.name] = possible_area_by_allocation(zone, f, req_water_ML_ha)

        # Creating individual field area variables
        field_area[f_name] = Dict(
            ws.name => @variable(model,
                                 base_name="$(did)$(ws.name)",
                                 lower_bound=0.0,
                                 upper_bound=max_ws_area[f_name][ws.name])
            for ws in zone_ws
        )

        # (field_n_gw + field_n_sw) <= possible area
        irrig_area = sum(values(field_area[f.name]))
        total_pos_area = sum(values(max_ws_area[f.name]))
        @constraint(model, irrig_area <= min(total_pos_area, f.irrigated_area))

        # Costs to pump needed water volume from each water source
        app_cost_per_ML = ML_water_application_cost(m, zone, f, req_water_ML_ha)

        tmp_d::Dict = Dict{String, Float64}(
            "$(did)$(k)" => v
            for (k, v) in app_cost_per_ML
        )
        app_cost = merge!(app_cost, tmp_d)

        tmp_l = [
            (crop_income_per_ha 
            - (app_cost_per_ML[ws.name] * req_water_ML_ha)
            ) * field_area[f_name][ws.name]
            for ws in zone_ws
        ]
        append!(profit, tmp_l)
    end

    # (field1_sw + ... + fieldn_sw) * ML_per_ha <= avail_sw
    avg_req_water::Float64 = mean(req_water)
    for ws in zone_ws
        irrig_area = sum([field_area[f.name][ws.name] for f in zone.fields])
        @constraint(model, (irrig_area * avg_req_water) <= ws.allocation)
    end

    @objective(model, Max, sum(profit))
    JuMP.optimize!(model)

    if termination_status(model) != MOI.OPTIMAL
        error("Could not optimize!")
    end

    opt_vals = Dict(name(v) => JuMP.value(v) for v in JuMP.all_variables(model))
    opt_vals["optimal_result"] = JuMP.objective_value(model)

    return opt_vals, app_cost
end

"""Extract total irrigated area from OptLang optimized results."""
function get_optimum_irrigated_area(m::Manager, field::FarmField, primals::Dict)::Float64
    return sum([v for (k, v) in primals if occursin(field.name, k)])
end


"""Calculate percentage of area to be watered by a specific water source.

Returns
-------
* Dict[str, float] : name of water source as key and percent area as value
"""
function perc_irrigation_sources(m::Manager, field::FarmField, water_sources::Array, primals::Dict)::Dict
    area::Float64 = field.irrigated_area
    opt::Dict = Dict{String, Float64}()

    f_name::String = field.name
    for (k, v) in primals
        for ws in water_sources
            if occursin(f_name, k) && occursin(ws.name, k)
                opt[ws.name] = v / area
            end
        end
    end

    return opt
end


"""Calculate water application cost/ML by each water source.

Returns
-------
* dict[str, float] : water source name and cost per ML
"""
function ML_water_application_cost(m::Manager, zone::FarmZone, field::FarmField, req_water_ML_ha::Float64)::Dict
    zone_ws::Array{WaterSource} = zone.water_sources
    flow_rate::Float64 = field.irrigation.flow_rate_Lps

    costs::Dict = Dict(
        w.name => (pump_cost_per_ML(w, flow_rate) 
                    * req_water_ML_ha)
                    + (w.cost_per_ML*req_water_ML_ha)
        for w in zone_ws
    )
    return costs
end


"""Calculate pumping costs (per ML) for each water source.

Parameters
----------
* zone : FarmZone
* flow_rate_Lps : float, desired flow rate in Litres per second.

Returns
---------
* dict[str, float] : cost of pumping per ML for each water source
"""
function calc_ML_pump_costs(m::Manager, zone::FarmZone,
                            flow_rate_Lps::Float64)::Dict{String, Float64}
    ML_costs = Dict(ws.name => pump_cost_per_ML(ws, flow_rate_Lps)
                    for ws in zone.water_sources)

    return ML_costs
end

function calc_potential_crop_yield(ssm_mm::Float64, gsr_mm::Float64, 
                                   crop::AgComponent)::Float64
    """Uses French-Schultz equation, taken from [Oliver et al. 2008 (Equation 1)](<http://www.regional.org.au/au/asa/2008/concurrent/assessing-yield-potential/5827_oliverym.htm>)

    The method here uses the farmer friendly modified version as given in the above.

    Represents Readily Available Water - (Crop evapotranspiration * Crop Water Use Efficiency Coefficient)

    .. math::
        YP = (SSM + GSR - E) * WUE

    where

    * :math:`YP` is yield potential in kg/Ha
    * :math:`SSM` is Stored Soil Moisture (at start of season) in mm, assumed to be 30% of summer rainfall
    * :math:`GSR` is Growing Season Rainfall in mm
    * :math:`E` is Crop Evaporation coefficient in mm, the amount of rainfall required before the crop will start
        to grow, commonly 110mm, but can range from 30-170mm [Whitbread and Hancock 2008](http://www.regional.org.au/au/asa/2008/concurrent/assessing-yield-potential/5803_whitbreadhancock.htm),
    * :math:`WUE` is Water Use Efficiency coefficient in kg/mm

    Parameters
    ----------
    * ssm_mm : float, Stored Soil Moisture (mm) at start of season.
    * gsr_mm : float, Growing Season Rainfall (mm)
    * crop : object, Crop component object

    Returns
    -----------
    * Potential yield in tonnes/Ha
    """
    evap_coef_mm::Float64 = crop.et_coef  # Crop evapotranspiration coefficient (mm)
    wue_coef_mm::Float64 = crop.wue_coef  # Water Use Efficiency coefficient (kg/mm)

    # maximum rainfall threshold in mm
    # water above this amount does not contribute to crop yield
    max_thres::Float64 = crop.rainfall_threshold  

    gsr_mm::Float64 = min(gsr_mm, max_thres)
    return max(0.0, ((ssm_mm + gsr_mm - evap_coef_mm) * wue_coef_mm) / 1000.0)
end

function in_season(dt::Date, s_start::Date, s_end::Date)::Bool
    c_month::Int64, c_day::Int64 = monthday(dt)
    s_month::Int64, s_day::Int64 = monthday(s_start)
    e_month::Int64, e_day::Int64 = monthday(s_end)

    s::Bool = (c_month >= s_month) && (c_day > s_day)
    e::Bool = (c_month <= e_month) && (c_day < e_day)

    return s && e
end

function is_season_start(dt::Date, s_start::Date)::Bool
    return monthday(dt) == monthday(s_start)
end

function is_season_end(dt::Date, s_end::Date)::Bool
    return monthday(dt) == monthday(s_end)
end


function run_timestep(farmer::Manager, zone::FarmZone, dt::Date)

    for f::FarmField in zone.fields
        s_start::Date = f.plant_date
        s_end::Date = f.harvest_date

        within_season::Bool = in_season(dt, s_start, s_end)
        crop::Crop = f.crop
        if within_season
            apply_rainfall!(zone, dt)
            if f.irrigated_area == 0.0 || f.irrigation.name == "dryland"
                # no irrigation occurred!
                continue
            end

            # Get percentage split between water sources
            opt_field_area::Dict = zone.opt_field_area
            irrigation, cost_per_ML = optimize_irrigation(farmer, zone::FarmZone, dt)
            water_to_apply_mm = calc_required_water(f, dt)
            for ws in zone.water_sources
                ws_name = ws.name
                did = replace("$(f.name)__$(ws_name)", " " => "_")
                area_to_apply::Float64 = irrigation[did]

                if area_to_apply == 0.0
                    continue
                end

                vol_to_apply_ML_ha::Float64 = (water_to_apply_mm / mm_to_ML)
                apply_irrigation!(zone, f, ws, water_to_apply_mm, area_to_apply)

                tmp::Float64 = sum([v for (k, v) in cost_per_ML if occursin(f.name, k) && occursin(ws_name, k)])

                # println("Irrigation cost: ", tmp)
                # println("vol to apply (mm, ML): ", water_to_apply_mm, " ", vol_to_apply_ML_ha)
                # println("Irrig area: ", area_to_apply)
                # println("Costs: ", (tmp * vol_to_apply_ML_ha * area_to_apply))
                # println("-----------------------------")

                log_irrigation_cost(f, (tmp * vol_to_apply_ML_ha * area_to_apply))
            end 
        elseif is_season_start(dt, s_start)
            f.crop.plant_date = dt
            yeardiff::Int64 = year(s_end) - year(s_start)
            hm::Int64, hd::Int64 = monthday(s_end)

            cy::Int64 = year(dt)
            f.crop.harvest_date = Date(cy + yeardiff, hm, hd)
            s_start = f.plant_date
            s_end = f.harvest_date
            apply_rainfall!(zone, dt)

            # cropping for this field begins
            opt_field_area = optimize_irrigated_area(farmer, zone)
            f.irrigated_area = get_optimum_irrigated_area(farmer, f, opt_field_area)

            f.plant_date = s_start
            f.sowed = true

            zone.opt_field_area = opt_field_area
        elseif is_season_end(dt, s_end) && f.sowed
            # End of season

            # growing season rainfall
            gsr_mm::Float64 = get_seasonal_rainfall(zone.climate, [s_start, s_end], f.name)
            irrig_mm::Float64 = f.irrigated_vol_mm

            # The French-Schultz method assumes 30% of previous 3 months
            # rainfall contributed towards crop growth
            prev::Date = f.plant_date - Month(3)
            prev_mm::Float64 = get_seasonal_rainfall(zone.climate, [prev, s_start], f.name)

            fs_ssm_assumption::Float64 = 0.3
            ssm_mm::Float64 = prev_mm * fs_ssm_assumption

            income::Float64 = total_income(f, calc_potential_crop_yield, 
                                           ssm_mm,
                                           gsr_mm,
                                           irrig_mm,
                                           (dt, zone.water_sources))

            log_seasonal_income(f, income, dt)
            log_seasonal_irrigation(f, f.irrigated_volume, dt)

            # println(f.name, " harvested! - ", dt)
            # println("Est. Total Income: ", f._seasonal_income[dt])
            # println("------------------")

            set_next_crop!(f)
        end
    end

    # Need to return or log irrigation water used and irrigated area considered
end
