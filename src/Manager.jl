
"""An 'economically rational' crop farm manager."""
struct Manager <: AgComponent
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
    calc = []
    areas = []
    constraints = []
    zone_ws = zone.water_sources
    
    total_avail_water = zone.avail_allocation

    field_areas = Dict()
    for f in zone.fields
        area_to_consider = f.total_area_ha
        did = replace("$(f.name)__", " " => "_")

        naive_crop_income = estimate_income_per_ha(f.crop)
        naive_req_water = f.crop.water_use_ML_per_ha
        app_cost_per_ML = ML_water_application_cost(m, zone, f, naive_req_water)

        pos_field_area = [w.allocation / naive_req_water
                            for (ws_name, w) in zone_ws]
        pos_field_area = min(sum(pos_field_area), area_to_consider)
        
        field_areas[f.name] = Dict(
            ws_name => Variable("$(did)$(ws_name)",
                                lb=0,
                                ub=min(w.allocation / naive_req_water, area_to_consider))
            for (ws_name, w) in zone_ws
        )

        # total_pump_cost = sum([ws.pump.maintenance_cost(year_step) for ws in zone_ws])
        profits = [field_areas[f.name][ws_name] * 
                    (naive_crop_income - app_cost_per_ML[ws_name])
                    for ws_name in zone_ws
        ]

        calc += profits
        curr_field_areas = collect(values(field_areas[f.name]))
        areas = append!(areas, curr_field_areas)

        # Total irrigated area cannot be greater than field area
        # or area possible with available water
        constraints += [
            Constraint(sum(curr_field_areas), lb=0.0, ub=pos_field_area)
        ]
    end

    constraints += [Constraint(sum(areas),
                                lb=0.0,
                                ub=zone.total_area_ha)]

    # Generate appropriate OptLang model
    model = Model.clone(m.opt_model)
    model.objective = Objective(sum(calc), direction="max")
    model.add(constraints)
    model.optimize()

    if model.status != "optimal"
        error("Could not optimize!")
    end

    return model.primal_values
end

function optimize_irrigation(m::Manager, zone::FarmZone, dt::DateTime)::Tuple
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
    model = m.opt_model
    areas = []
    profit = []
    app_cost = OrderedDict()
    constraints = []

    zone_ws = zone.water_sources
    total_irrigated_area = sum(map(f -> f.irrigated_area != Nothing ? f.irrigated_area : 0.0ha, 
                                   zone.fields))

    field_area = Dict()
    possible_area = Dict()
    for f in zone.fields
        f_name = f.name
        did = replace("$(f_name)__", " " => "_")
        
        if f.irrigation.name == "dryland"
            append!(areas, [Variable("$(did)$(ws_name)", lb=0, ub=0) 
                           for ws_name in zone_ws])
            continue
        end

        # Disable this for now - estimated income includes variable costs
        # Will always incur maintenance costs and crop costs
        # total_pump_cost = sum([ws.pump.maintenance_cost(dt.year) for ws in zone_ws])
        # total_irrig_cost = f.irrigation.maintenance_cost(dt.year)
        # maintenance_cost = (total_pump_cost + total_irrig_cost)

        # estimated gross income - variable costs per ha
        crop_income_per_ha = estimate_income_per_ha(f.crop)
        req_water_ML_ha = uconvert(ML/ha, calc_required_water(f, dt))

        if req_water_ML_ha == 0.0ML/ha
            field_area[f_name] = Dict(
                ws_name => Variable("$(did)$(ws_name)",
                                    lb=0.0,
                                    ub=0.0)
                for ws_name in zone_ws
            )
        else
            max_ws_area = possible_area_by_allocation(zone, f)

            field_area[f_name] = Dict(
                ws_name => Variable("$(did)$(ws_name)",
                                    lb=0, 
                                    ub=max_ws_area[ws_name])
                for ws_name in zone_ws
            )
        end

        # Costs to pump needed water volume from each water source
        app_cost_per_ML = ML_water_application_cost(m, zone, f, req_water_ML_ha)

        tmp_d = Dict(
            "$(did)$(k)" => v
            for (k, v) in app_cost_per_ML
        )
        app_cost = merge!(app_cost, tmp_d)

        tmp_l = [
            (crop_income_per_ha 
            - (app_cost_per_ML[ws_name] * req_water_ML_ha)
            ) * field_area[f_name][ws_name]
            for ws_name in zone_ws
        ]
        append!(profit, tmp_l)
    end

    # Total irrigation area cannot be more than available area
    append!(constraints, [Constraint(sum(areas),
                        lb=0.0,
                        ub=min(total_irrigated_area, zone.total_area_ha))
                    ]
    )

    # 0 <= field1*sw + field2*sw + field_n*sw <= possible area to be irrigated by sw
    for (ws_name, w) in zone_ws
        alloc = w.allocation
        pos_area = possible_irrigation_area(zone, alloc)

        f_ws_var = [field_area[f.name][ws_name] for f in zone.fields]
        # for f in zone.fields
        #     append!(f_ws_var, [field_area[f.name][ws_name]])
        # end

        tmp_l = [Constraint(sum(f_ws_var),
                 lb=0.0,
                 ub=pos_area)]
        append!(constraints, tmp_l)
    end

    # Generate appropriate OptLang model
    model = Model.clone(m.opt_model)
    model.objective = Objective(sum(profit), direction="max")
    model.add(constraints)
    model.optimize()

    return model.primal_values, app_cost
end

# function possible_area(m::Manager, field::FarmField, allocation::Quantity{ML})::Quantity{ha}

#     if field.irrigated_area == Nothing
#         area_to_consider = field.total_area_ha
#     else
#         # Get possible irrigation area based on available water
#         area_to_consider = min(calc_possible_area(field, allocation), 
#                                field.irrigated_area)
#     end

#     return area_to_consider
# end

function get_optimum_irrigated_area(m::Manager, field::FarmField, primals::Dict)::Quantity{ha}
    """Extract total irrigated area from OptLang optimized results."""
    return sum([v for (k, v) in primals if occursin(field.name, k)])
end

function perc_irrigation_sources(m::Manager, field::FarmField, water_sources::Array, primals::Dict)::Dict
    """Calculate percentage of area to be watered by a specific water source.

    Returns
    -------
    * Dict[str, float] : name of water source as key and perc. area as value
    """
    area = field.irrigated_area
    opt = Dict()

    for (k,v) in primals
        for ws_name in water_sources
            if occursin(field.name, k) && occursin(ws_name, k)
                opt[ws_name] = v / area
            end
        end
    end

    return opt
end

function ML_water_application_cost(m::Manager, zone::FarmZone, field::FarmField, req_water_ML_ha::Quantity{ML/ha})::Dict
    """Calculate water application cost/ML by each water source.

    Returns
    -------
    * dict[str, float] : water source name and cost per ML
    """
    zone_ws = zone.water_sources
    irrigation = field.irrigation
    i_pressure = irrigation.head_pressure
    flow_rate = irrigation.flow_rate_Lps

    costs = Dict(
        ws_name => (w.source.pump.pumping_costs_per_ML(flow_rate, 
                                                w.source.head + i_pressure) 
                                                * req_water_ML_ha) 
                                                + (w.source.cost_per_ML*req_water_ML_ha)
        for (ws_name, w) in zone_ws
    )
    return costs
end

function calc_ML_pump_costs(m::Manager, zone::FarmZone,
                            flow_rate_Lps::Float64)::Dict{String, Float64}
    """Calculate pumping costs (per ML) for each water source.

    Parameters
    ----------
    * zone : FarmZone
    * flow_rate_Lps : float, desired flow rate in Litres per second.

    Returns
    ---------
    * dict[str, float] : cost of pumping per ML for each water source
    """
    ML_costs = Dict(ws.name => pump_cost_per_ML(ws, flow_rate_Lps)
                    for ws in zone.water_sources)

    return ML_costs
end

function calc_potential_crop_yield(m::Manager, ssm_mm::Quantity{mm}, 
                                   gsr_mm::Quantity{mm}, crop::AgComponent)::Float64
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
    evap_coef_mm = crop.et_coef  # Crop evapotranspiration coefficient (mm)
    wue_coef_mm = crop.wue_coef  # Water Use Efficiency coefficient (kg/mm)

    # maximum rainfall threshold in mm
    # water above this amount does not contribute to crop yield
    max_thres = crop.rainfall_threshold  

    gsr_mm = min(gsr_mm, max_thres)
    return max(0.0, ((ssm_mm + gsr_mm - evap_coef_mm) * wue_coef_mm) / 1000.0)
end

function run_timestep(farmer::Manager, zone::FarmZone, dt::DateTime)
    seasonal_ts = zone.yearly_timestep
    apply_rainfall(zone, dt)

    for f in zone.fields
        s_start = f.plant_date
        s_end = Nothing
        try
            s_end = f.harvest_date
        catch e
            is_season_month = month(dt) == month(s_start)
            is_season_day = (day(dt) == day(s_start))
            if is_season_month && is_season_day
                s_start = DateTime(year(dt), month(s_start), day(s_start))
                f.harvest_date = s_start + day(f.crop.harvest_offset)
                s_end = f.harvest_date
            end
        end

        if !s_end
            continue
        end

        crop = f.crop
        within_season = (dt > s_start) && (dt < s_end)
        if within_season
            if f.irrigated_area == 0.0
                # no irrigation occurred!
                continue
            end

            # Get percentage split between water sources
            opt_field_area = zone.opt_field_area
            irrigation, cost_per_ML = optimize_irrigation(farmer, zone::FarmZone, dt)
            split = perc_irrigation_sources(farmer, f, zone.water_sources, irrigation)

            water_to_apply_mm = calc_required_water(f, dt)
            for ws in zone.water_sources
                ws_name = ws.name
                ws_proportion = split[ws_name]
                if ws_proportion == 0.0
                    continue
                end
                vol_to_apply = ws_proportion * water_to_apply_mm
                apply_irrigation(zone, f, ws_name, vol_to_apply)

                tmp = sum([v for (k, v) in cost_per_ML if occursin(f.name, k) && occursin(ws_name, k)])

                vol = uconvert(ML/ha, vol_to_apply)
                log_irrigation_cost(f, uconvert(ML, tmp * vol * f.irrigated_area))
            end 
        elseif dt == s_start
            # cropping for this field begins
            print("Cropping started:", f.name, dt.year, "\n")
            opt_field_area = optimize_irrigated_area(farmer, zone)
            f.irrigated_area = get_optimum_irrigated_area(farmer, f, opt_field_area)
            f.plant_date = s_start
            f.sowed = true
            update_stages(crop, dt)

            zone.opt_field_area = opt_field_area
        elseif (dt == s_end) && f.sowed
            # end of season
            print(f.name, "harvested! -", dt.year)

            # growing season rainfall
            gsr_mm = get_seasonal_rainfall(f, zone.climate)
            # gsr_mm = zone.climate.get_seasonal_rainfall([f.plant_date, f.harvest_date], f.name)
            irrig_mm = f.irrigated_vol_mm

            # The French-Schultz method assumes 30% of previous season's
            # rainfall contributed towards crop growth
            prev = f.plant_date - month(3)
            fs_ssm_assumption = 0.3
            # ssm_mm = zone.climate.get_seasonal_rainfall([prev, f.plant_date], f.name) * fs_ssm_assumption
            ssm_mm = get_seasonal_rainfall(f, zone.climate) * fs_ssm_assumption

            crop_yield_calc = farmer.calc_potential_crop_yield
            nat = ssm_mm + gsr_mm
            income = total_income(f, crop_yield_calc, 
                                  ssm_mm,
                                  gsr_mm,
                                  irrig_mm,
                                  (dt, zone.water_sources))

            # crop_yield = farmer.calc_potential_crop_yield(ssm_mm, gsr_mm+irrig_mm, crop)
            # Unfinished - not account for cost of pumping water
            print("Est. Total Income:", income)
            print("------------------\n")

            set_next_crop(f)
        end
    end
end
