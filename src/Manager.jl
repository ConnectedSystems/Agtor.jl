
using JuMP, GLPK, Statistics
using OrderedCollections
using Setfield

abstract type Manager <: AgComponent end


"""An 'economically rational' crop farm manager.

Water is applied for optimal farm profitability based on soil water deficit,
crop water requirements, and cost of water application.
"""
struct EconManager <: Manager
    name::String
    opt::DataType

    function EconManager(name::String)::Manager
        return new(name, GLPK.Optimizer)
    end
end


"""
Apply Linear Programming to naively optimize irrigated area.

Occurs at start of season.

# Arguments
- `m` : Agtor.Manager,
- `zone` : Agtor.FarmZone, representing a farm or a farming zone.
"""
function optimize_irrigated_area(m::Manager, zone::FarmZone)::OrderedDict{String,Float64}
    model::Model = Model(m.opt)
    # set_silent(model)  # disable output

    num_fields::Int64 = length(zone.fields)
    profit_calc::Array = []
    sizehint!(profit_calc, num_fields)

    field_areas::LittleDict{Symbol,VariableRef} = LittleDict{Symbol,VariableRef}()
    zone_ws::Tuple = Tuple(zone.water_sources)

    if isempty(zone_ws)
        # no water to irrigate with
        return OrderedDict("nowater" => 0.0)
    end

    @inbounds for f::FarmField in zone.fields
        area_to_consider::Float64 = f.total_area_ha
        did::String = f._fname
        f_name = Symbol(f.name)

        naive_crop_income_per_ha::Float64 = f.crop.naive_crop_income
        naive_req_water_per_ha::Float64 = f.crop.water_use_ML_per_ha * f.irrigation.efficiency
        app_cost_per_ML::NamedTuple = ML_water_application_cost(m, zone, f, naive_req_water_per_ha)

        pos_field_area::Float64 = sum(Float64[w.allocation / naive_req_water_per_ha
                                              for w::WaterSource in zone_ws])
        pos_field_area = min(pos_field_area, area_to_consider)

        profits::Array{JuMP.GenericAffExpr{Float64,JuMP.VariableRef}} = []
        for w::WaterSource in zone_ws
            __var = @variable(model,
                base_name = "$(did)$(w.name)",
                lower_bound = 0.0,
                upper_bound = min((w.allocation / naive_req_water_per_ha), area_to_consider))
            field_areas[Symbol(did, w.name)] = __var

            water_cost_per_ha = (app_cost_per_ML[Symbol(w.name)] * naive_req_water_per_ha)
            push!(profits, __var * (naive_crop_income_per_ha - water_cost_per_ha))
        end

        append!(profit_calc, profits)
        curr_field_areas::Vector{JuMP.VariableRef} = [
            v for (k, v) in field_areas if occursin(string(f_name), string(k))
        ]

        # Total irrigated area cannot be greater than field area
        # or area possible with available water
        @constraint(model, 0.0 <= sum(curr_field_areas) <= pos_field_area)
    end

    # Generate appropriate OptLang model
    @objective(model, Max, sum(profit_calc))
    optimize!(model)

    state = termination_status(model)
    if state == MOI.TIME_LIMIT && has_values(model)
        @warn "Farm model optimization was sub-optimal"
    elseif state != MOI.OPTIMAL
        throw(ArgumentError("Could not optimize farm water use."))
    end

    opt_vals::OrderedDict{String,Float64} = OrderedDict(JuMP.name(v) => value(v) for v in all_variables(model))
    opt_vals["optimal_result"] = objective_value(model)

    return opt_vals
end


"""
    optimize_irrigation(m::Manager, zone::FarmZone, dt::Date)::Tuple{OrderedDict, NamedTuple}

Apply Linear Programming to optimize irrigation water use.

Results can be used to represent percentage mix
e.g. if the field area is 100 ha, and the optimal area to be
        irrigated by a water source is

    SW: 70 ha
    GW: 30 ha

and the required amount is 20mm

    SW: 70 / 100 = 0.7 (irrigated area / total area, 70%)
    GW: 30 / 100 = 0.3 (30%)

Then the per hectare amount to be applied from each
water source is calculated as:

    SW = 20mm * 0.7
       = 14mm

    GW = 20mm * 0.3
       = 6mm

# Arguments
- `zone` : FarmZone
- `dt` : datetime object, current datetime

# Returns
Tuple
- OrderedDict{String, Float64} \
  keys based on field and water source names values are hectare area
- \$/ML cost of applying water
"""
function optimize_irrigation(m::Manager, zone::FarmZone, dt::Date)::Tuple{OrderedDict,NamedTuple}

    model::Model = Model(m.opt)

    num_fields::Int64 = length(zone.fields)
    profit::Array = []
    sizehint!(profit, num_fields)

    app_cost::NamedTuple = NamedTuple()
    zone_ws::Tuple = Tuple(zone.water_sources)

    if isempty(zone_ws)
        return OrderedDict("nowater" => 0.0), (nowater=0.0,)
    end

    field_area::LittleDict{Symbol,VariableRef} = LittleDict{Symbol,VariableRef}()
    req_water::Array{Float64} = Float64[]

    @inbounds for f::FarmField in zone.fields
        did::String = f._fname

        req_water_ML_ha::Float64 = calc_required_water(f, dt) / mm_to_ML
        max_ws_area::NamedTuple = possible_area_by_allocation(zone, f, req_water_ML_ha)
        total_pos_area::Float64 = min(sum(max_ws_area), f.irrigated_area)

        is_dryland = f.irrigation.name == "dryland"
        no_req_water = isapprox(req_water_ML_ha, 0.0; atol=1e-6)
        no_irrig_area = isapprox(total_pos_area, 0.0; atol=1e-6)

        # If no water available or required...
        if is_dryland || no_req_water || no_irrig_area
            @inbounds for ws::WaterSource in zone_ws
                ws_name = ws.name
                field_area[Symbol(did, ws_name)] = @variable(
                    model,
                    base_name = "$(did)$(ws_name)",
                    lower_bound = 0.0,
                    upper_bound = 0.0
                )
            end

            push!(req_water, 0.0)
            continue
        end

        push!(req_water, req_water_ML_ha)

        # Disable this for now - estimated income includes variable costs
        # Will always incur maintenance costs and crop costs
        # total_pump_cost = sum([ws.pump.maintenance_cost(dt.year) for ws in zone_ws])
        # total_irrig_cost = f.irrigation.maintenance_cost(dt.year)
        # maintenance_cost = (total_pump_cost + total_irrig_cost)

        # Costs to pump needed water volume from each water source
        app_cost_per_ML::NamedTuple = ML_water_application_cost(m, zone, f, req_water_ML_ha)

        crop = f.crop
        crop_income_per_ha::Float64 = crop.naive_crop_income

        # estimated gross income - variable costs per ha
        # Creating individual field area variables

        # (field_n_gw + field_n_sw) <= possible area
        for ws::WaterSource in zone_ws
            ws_name::Symbol = Symbol(ws.name)
            w_id::Symbol = Symbol(did, ws_name)
            var_area::VariableRef = @variable(
                model,
                base_name = "$(did)$(ws_name)",
                lower_bound = 0.0,
                upper_bound = max_ws_area[ws_name]
            )

            field_area[w_id] = var_area
            water_app_cost::Float64 = app_cost_per_ML[ws_name]
            @set! app_cost[w_id] = water_app_cost

            push!(profit, (crop_income_per_ha - water_app_cost) * var_area)
        end
    end

    # (field_1_sw + ... + field_n_sw) <= sw_irrigation_area
    # (field_1_gw + ... + field_n_gw) <= gw_irrigation_area
    opt_vals::OrderedDict{String,Float64} = OrderedDict()
    avg_req_water::Float64 = mean(req_water)
    if avg_req_water > 0.0
        @inbounds for ws::WaterSource in zone_ws
            @inbounds irrig_area = sum(field_area[Symbol(f._fname, ws.name)] for f::FarmField in zone.fields)
            @constraint(model, irrig_area <= (ws.allocation / avg_req_water))
        end
    else
        opt_vals = OrderedDict{String,Float64}(
            string(k) => 0.0
            for k in keys(field_area)
        )

        return opt_vals, app_cost
    end

    @objective(model, Max, sum(profit))
    optimize!(model)

    state = termination_status(model)
    if state == MOI.TIME_LIMIT && has_values(model)
        @warn "Farm model optimization was sub-optimal"
    elseif state != MOI.OPTIMAL
        throw(ArgumentError("Could not optimize farm water use."))
    end

    opt_vals = OrderedDict{String,Float64}(JuMP.name(v) => value(v) for v in JuMP.all_variables(model))

    return opt_vals, app_cost
end


"""Extract total irrigated area from OptLang optimized results."""
function get_optimum_irrigated_area(field::FarmField, primals::OrderedDict)::Float64
    return sum([v for (k, v) in primals if occursin(field.name, k)])
end


"""Calculate percentage of area to be watered by a specific water source.

# Returns
Name of water source as key and percent area as value
"""
function perc_irrigation_sources(m::Manager, field::FarmField, water_sources::Array, primals::Dict)::Dict
    area::Float64 = field.irrigated_area
    opt::Dict = Dict{String,Float64}()

    f_name::String = field.name
    @inbounds for (k, v) in primals
        @inbounds for ws::WaterSource in water_sources
            if occursin(f_name, k) && occursin(ws.name, k)
                opt[ws.name] = v / area
            end
        end
    end

    return opt
end


"""
    ML_water_application_cost(m::Manager, zone::FarmZone, field::FarmField, req_water_ML_ha::Float64)::NamedTuple

Calculate water application cost/ML by each water source.

# Returns
Water source name and cost per ML
"""
function ML_water_application_cost(m::Manager, zone::FarmZone, field::FarmField, req_water_ML_ha::Float64)::NamedTuple
    zone_ws::Array{WaterSource} = zone.water_sources
    flow_rate::Float64 = field.irrigation.flow_rate_Lps

    costs = NamedTuple()
    for w::WaterSource in zone_ws
        @set! costs[Symbol(w.name)] = ((pump_cost_per_ML(w, flow_rate)
                                        *
                                        req_water_ML_ha)
                                       +
                                       (w.cost_per_ML * req_water_ML_ha))
    end

    return costs
end


"""
Calculate pumping costs (per ML) for each water source.

# Arguments
- `m` : manager component
- `zone` : FarmZone
- `flow_rate_Lps` : float, desired flow rate in Litres per second.

# Returns
Dict{String,Float64} : Cost of pumping per ML for each water source.
"""
function calc_ML_pump_costs(
    m::Manager, zone::FarmZone, flow_rate_Lps::Float64
)::Dict{String,Float64}
    ML_costs = Dict(
        ws.name => pump_cost_per_ML(ws, flow_rate_Lps)
        for ws::WaterSource in zone.water_sources
    )

    return ML_costs
end


"""Check to see if given date is between start and end dates (exclusive of start and end)"""
function in_season(dt::Date, s_start::Date, s_end::Date)::Bool
    return s_start < dt < s_end
end


"""Check to see if two dates are identical"""
function matching_dates(dt::Date, s_start::Date)::Bool
    return dt == s_start
end


"""Sets next crop in rotation and updates sowing/planting dates."""
function set_next_crop!(m::Manager, f::FarmField, dt::Date)::Nothing
    set_next_crop!(f)

    cy, cm = yearmonth(dt)
    pm::Int64, pd::Int64 = monthday(f.plant_date)

    # Determine if planting will occur this year or next
    if cm <= pm
        sowing_date::Date = Date(cy, pm, pd)
    else
        sowing_date = Date(cy + 1, pm, pd)
    end

    f.plant_date = sowing_date
    f.harvest_date = sowing_date + f.crop.harvest_offset

    # Update growth stages with corresponding dates
    update_stages!(f.crop, sowing_date)

    return nothing
end


function run_timestep!(farmer::EconManager, zone::FarmZone, dt_idx::Int64, dt::Date)::Nothing

    for f::FarmField in zone.fields
        s_start::Date = f.plant_date
        s_end::Date = f.harvest_date

        within_season::Bool = in_season(dt, s_start, s_end)
        season_start::Bool = matching_dates(dt, s_start)
        season_end::Bool = matching_dates(dt, s_end)

        f_name::String = f.name

        if within_season || season_start
            apply_rainfall!(zone, dt_idx)

            if within_season
                if f.irrigated_area == 0.0 || f.irrigation.name == "dryland"
                    # no irrigation occurred!
                    continue
                end

                # Get percentage split between water sources
                irrigation, cost_per_ML = optimize_irrigation(farmer, zone::FarmZone, dt)
                water_to_apply_mm = calc_required_water(f, dt)
                for ws::WaterSource in zone.water_sources
                    ws_name::String = ws.name
                    did::String = "$(f._fname)$(ws_name)"
                    area_to_apply::Float64 = irrigation[did]

                    if area_to_apply == 0.0
                        continue
                    end

                    vol_to_apply_ML_ha::Float64 = (water_to_apply_mm / mm_to_ML)
                    apply_irrigation!(f, ws, water_to_apply_mm, area_to_apply)

                    # tmp::Float64 = sum([v for (k, v) in cost_per_ML if occursin(f_name, string(k)) && occursin(ws_name, string(k))])
                    tmp::Float64 = sum([v for (k, v) in pairs(cost_per_ML) if did == string(k)])

                    log_irrigation_cost(f, (tmp * vol_to_apply_ML_ha * area_to_apply))
                end
            elseif season_start
                f.sowed = true

                # cropping for this field begins
                opt_field_area = optimize_irrigated_area(farmer, zone)
                f.irrigated_area = get_optimum_irrigated_area(f, opt_field_area)

            end
        elseif season_end
            # End of season

            # growing season rainfall
            gsr_mm::Float64 = get_seasonal_rainfall(zone.climate, [s_start, s_end], f_name)

            if f.sowed == true

                irrig_mm::Float64 = f.irrigated_vol_mm

                # The French-Schultz method assumes 25-30% of previous 3 months
                # rainfall contributed towards crop growth
                # The SSM coefficient is set as a crop parameter.
                prev::Date = f.plant_date - Month(3)
                prev_mm::Float64 = get_seasonal_rainfall(zone.climate, [prev, s_start], f_name)
                ssm_mm::Float64 = prev_mm * f.crop.ssm_coef

                income::Float64, irrigated_yield::Float64, dryland_yield::Float64 =
                    total_income(
                        f, ssm_mm, gsr_mm, irrig_mm,
                        (dt, zone.water_sources)
                    )

                seasonal_field_log!(f, dt, income, f.irrigated_volume, irrigated_yield, dryland_yield, gsr_mm)
            else
                costs = total_costs(f, dt, zone.water_sources)
                seasonal_field_log!(f, dt, -costs, 0.0, 0.0, 0.0, gsr_mm)
            end

            log_irrigation_by_water_source(zone, f, dt)

            set_next_crop!(farmer, f, dt)
            reset_state!(f)
        end
    end

    return nothing
end
