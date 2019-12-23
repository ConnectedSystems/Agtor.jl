@with_kw mutable struct Crop <: AgComponent
    name::String
    crop_type::String

    # Growth pattern
    growth_stages::Dict

    plant_date::DateTime

    # Crop properties
    yield_per_ha::Float64
    price_per_yield::Float64
    variable_cost_per_ha::Float64
    water_use_ML_per_ha::Quantity
    root_depth_m::Quantity
    et_coef::Float64
    wue_coef::Float64
    rainfall_threshold::Float64
    ssm_coef::Float64
    effective_root_zone::Quantity
    harvest_date::DateTime

    function Crop(name::String, crop_type::String, growth_stages::Dict; props...)
        plant_date = props[:plant_date]
        yield_per_ha = props[:yield_per_ha]
        price_per_yield = props[:price_per_yield]
        variable_cost_per_ha = props[:variable_cost_per_ha]
        water_use_ML_per_ha = props[:water_use_ML_per_ha]
        root_depth_m = props[:root_depth_m]
        et_coef = props[:et_coef]
        wue_coef = props[:wue_coef]
        rainfall_threshold = props[:rainfall_threshold]
        ssm_coef = props[:ssm_coef]
        effective_root_zone = props[:effective_root_zone]

        sow_date = DateTime("1900-" * plant_date)

        h_day = 0  # sum([v["stage_length"] for v in values(growth_stages)])
        offset = 0
        start_date = sow_date
        _stages = Dict{Symbol, Dict{String, DateTime}}()

        for (k, v) in growth_stages
            offset = v[:stage_length]
            end_of_stage = start_date + Dates.Day(offset)
            _stages[k] = Dict(
                "start" => start_date,
                "end" => end_of_stage
            )

            h_day += offset

            start_date = end_of_stage + Dates.Day(offset+1)
        end

        harvest_offset = Dates.Day(h_day)
        harvest_date = sow_date + harvest_offset

        new(name, crop_type, growth_stages, sow_date,
            yield_per_ha, price_per_yield, variable_cost_per_ha, water_use_ML_per_ha*(ML/ha),
            root_depth_m*m, et_coef, wue_coef, rainfall_threshold, 
            ssm_coef, effective_root_zone*m, harvest_date)

    end
end

function update_stages(c::Crop, dt::Date)
    stages = c._stages

    new_date = Dates.year(dt), Dates.month(c.plant_date), Dates.day(c.plant_date)
    start_date = DateTime(new_date...)

    for (k, v) in c.growth_stages
        offset = v["stage_length"]
        end_of_stage = start_date + Dates.Day(offset)
        stages[k] = Dict(
            "start" => start_date,
            "end" => end_of_stage
        )

        start_date = end_of_stage + Dates.Day(offset+1)
    end
end

function get_stage_coefs(c::Crop, dt::Date)
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


function create(cls::Type{Crop}, data::Dict{Any, Any}, override=Nothing)
    tmp = copy(data)
    name = pop!(tmp, "name")
    prop = pop!(tmp, "properties")
    crop_type = pop!(tmp, "crop_type")
    growth_stages = pop!(tmp, "growth_stages")

    prefix = "Crop___$(name)__"
    props = generate_params(prefix * "properties", prop, override)
    stages = generate_params(prefix * "growth_stages", growth_stages, override)

    return cls(name, crop_type, stages; props...)
end
