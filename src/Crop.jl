@with_kw mutable struct Crop <: AgComponent
    name::String
    crop_type::String
    plant_date::DateTime

    # Growth pattern
    growth_stages::Dict
    growth_coefficients::Dict

    # Crop properties
    yield_per_ha::Quantity{ha}
    price_per_yield::Float64
    variable_cost_per_ha::Float64
    water_use_ML_per_ha::Quantity{ML}
    root_depth_m::Quantity{m}
    et_coef::Float64
    wue_coef::Float64
    rainfall_threshold::Float64
    ssm_coef::Float64
    effective_root_zone::Quantity{m}
    harvest_date::DateTime = Nothing

    function Crop(name, crop_type, plant_date, growth_stages,
                  growth_coefficients, yield_per_ha, price_per_yield,
                  variable_cost_per_ha, water_use_ML_per_ha, root_depth_m,
                  et_coef, wue_coef, rainfall_threshold, ssm_coef, effective_root_zone)
        sow_date = DateTime("1900-" * plant_date)

        h_day = 0  # sum([v["stage_length"] for v in values(growth_stages)])
        offset = 0
        start_date = copy(sow_date)
        _stages = Dict{String, DateTime}()

        for (k, v) in growth_stages
            offset = v["stage_length"]
            end_of_stage = start_date + Dates.day(offset)
            _stages[k] = Dict(
                "start" => start_date,
                "end" => end_of_stage
            )

            h_day += offset

            start_date = end_of_stage + Dates.day(offset+1)
        end

        harvest_offset = Dates.Day(days=h_day)
        harvest_date = sow_date + harvest_offset

        new(name, crop_type, plant_date, growth_stages,
            growth_coefficients, yield_per_ha, price_per_yield,
            variable_cost_per_ha, water_use_ML_per_ha, root_depth_m,
            et_coef, wue_coef, rainfall_threshold, ssm_coef, effective_root_zone, harvest_date)

    end
end

function update_stages(c::Crop, dt::DateTime)
    stages = c._stages

    new_date = Dates.year(dt), Dates.month(c.plant_date), Dates.day(c.plant_date)
    start_date = DateTime(new_date...)

    for (k, v) in c.growth_stages
        offset = v["stage_length"]
        end_of_stage = start_date + Dates.day(offset)
        stages[k] = Dict(
            "start" => start_date,
            "end" => end_of_stage
        )

        start_date = end_of_stage + Dates.day(offset+1)
    end
end

function get_stage_coefs(c::Crop, dt::DateTime)
    if dt == Nothing
        return c.growth_stages["initial"]
    end

    for (k, v) in c._stages
        s, e = v["start"], v["end"]
        in_season = false
        same_month = s.month == dt.month
        if same_month == true
            in_day = s.day >= dt.day
            in_season = same_month && in_day
        elseif (s.month <= dt.month)
            if (dt.month <= e.month)
                in_season = dt.day <= e.day
            end
        end

        if in_season == true
            return c.growth_stages[k]
        end
    end

    # Not in season so just return initial growth stage
    return c.growth_stages["initial"]
end

function estimate_income_per_ha(c::Crop)::Float64
    """Naive estimation of net income."""
    income = (c.price_per_yield * c.yield_per_ha) 
                - c.variable_cost_per_ha
    return income
end

function total_costs(c::Crop, year::Int64)
    # cost of production is handled by factoring in
    # water application costs and other maintenance costs.
    # The variable_cost_per_ha is only used to inform estimates.
    return 0.0
end

# @classmethod
# function collate_data(cls, data: Dict)
#     """Produce flat lists of crop-specific parameters.

#     Parameters
#     ----------
#     * data : Dict, of crop data

#     Returns
#     -------
#     * tuple[List] : (uncertainties, categoricals, and constants)
#     """
#     unc, cats, consts = sort_param_types(data['properties'], unc=[], cats=[], consts=[])

#     growth_stages = data['growth_stages']
#     unc, cats, consts = sort_param_types(growth_stages, unc, cats, consts)

#     return unc, cats, consts
# # End collate_data()

# @classmethod
# function create(cls, data, override=None)
#     tmp = data.copy()
#     name = tmp.pop('name')
#     prop = tmp.pop('properties')
#     crop_type = tmp.pop('crop_type')
#     growth_stages = tmp.pop('growth_stages')

#     prefix = f"Crop___{name}__{{}}"
#     props = generate_params(prefix.format('properties'), prop, override)
#     stages = generate_params(prefix.format('growth_stages'), growth_stages, override)

#     return cls(name, crop_type, growth_stages=stages, **props)
# # End create()
