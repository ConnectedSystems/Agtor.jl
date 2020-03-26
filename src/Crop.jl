using Dates

@with_kw mutable struct Crop <: AgComponent
    name::String
    crop_type::String

    # Growth pattern
    growth_stages::Dict
    coef_stages::Dict

    plant_date::Date

    # Crop properties
    yield_per_ha::Float64
    price_per_yield::Float64
    variable_cost_per_ha::Float64
    water_use_ML_per_ha::Float64
    root_depth_m::Float64
    et_coef::Float64
    wue_coef::Float64
    rainfall_threshold::Float64
    ssm_coef::Float64
    effective_root_zone::Float64
    harvest_date::Date

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

        sow_date = Date("1900-" * plant_date)

        h_day = 0
        offset = 0
        start_date = sow_date
        g_stages = Dict{Symbol, Dict{String, Date}}()
        coef_stages = Dict{Symbol, Dict{Symbol, Float64}}()

        for (k, v) in growth_stages
            offset = v[:stage_length]
            end_of_stage = start_date + Dates.Day(offset)
            g_stages[k] = Dict(
                "start" => start_date,
                "end" => end_of_stage
            )

            h_day += offset

            start_date = end_of_stage + Dates.Day(offset+1)

            coef_stages[k] = Dict(s => v for (s, v) in v)
        end

        harvest_offset = Dates.Day(h_day)
        harvest_date = sow_date + harvest_offset

        return new(name, crop_type, g_stages, coef_stages, sow_date,
            yield_per_ha, price_per_yield, variable_cost_per_ha, water_use_ML_per_ha,
            root_depth_m, et_coef, wue_coef, rainfall_threshold, 
            ssm_coef, effective_root_zone, harvest_date)

    end
end

function update_stages!(c::Crop, dt::Date)
    # This function marked for possible removal
    stages = c.growth_stages

    new_date::Tuple = yearmonthday(dt)
    start_date::Date = Date(new_date...)

    for (k, v) in c.growth_stages
        offset = v[:stage_length]
        end_of_stage = start_date + Day(offset)
        stages[k] = Dict(
            "start" => start_date,
            "end" => end_of_stage
        )

        start_date = end_of_stage + Dates.Day(offset+1)
    end
end

function get_stage_coefs(c::Crop, dt::Date)::Dict

    for (k, v) in c.growth_stages
        s, e = v["start"], v["end"]
        in_season = false
        s_month, s_day = monthday(s)
        c_month, c_day = monthday(dt)
        same_month = s_month == c_month
        if same_month == true
            in_day = s_day >= c_day
            in_season = same_month && in_day
        elseif (s_month <= c_month)
            e_month, e_day = monthday(e)
            if (c_month <= e_month)
                in_season = c_day <= e_day
            end
        end

        if in_season == true
            return c.coef_stages[k]
        end
    end

    # Not in season so just return initial growth stage
    return c.coef_stages[:initial]
end

function estimate_income_per_ha(c::Crop)::Float64
    """Naive estimation of net income."""
    return (c.price_per_yield * c.yield_per_ha) - c.variable_cost_per_ha
end

function subtotal_costs(c::Crop, year::Int64)::Float64
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


function create(cls::Type{Crop}, data::Dict{Any, Any}, override=nothing)::Crop
    name = data["name"]
    prop = data["properties"]
    crop_type = data["crop_type"]
    growth_stages = data["growth_stages"]

    prefix = "Crop___$(name)__"
    props = generate_params(prefix * "properties", prop, override)
    stages = generate_params(prefix * "growth_stages", growth_stages, override)

    return cls(name, crop_type, stages; props...)
end
