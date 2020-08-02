using Dates

@with_kw mutable struct Crop <: AgComponent
    name::String
    crop_type::String

    # Growth pattern
    growth_stages::Dict{Symbol, Dict{Symbol, Union{Date, Int64, AgParameter}}}
    coef_stages::Dict{Symbol, Dict{Symbol, Union{Float64, Int64, AgParameter}}}

    # Crop properties
    plant_date::Union{Date, AgParameter}
    yield_per_ha::Union{Float64, AgParameter}
    price_per_yield::Union{Float64, AgParameter}
    variable_cost_per_ha::Union{Float64, AgParameter}
    water_use_ML_per_ha::Union{Float64, AgParameter}
    root_depth_m::Union{Float64, AgParameter}
    et_coef::Union{Float64, AgParameter}
    wue_coef::Union{Float64, AgParameter}
    rainfall_threshold::Union{Float64, AgParameter}
    ssm_coef::Union{Float64, AgParameter}
    effective_root_zone::Union{Float64, AgParameter}
    harvest_date::Union{Date, AgParameter}
    harvest_offset::Union{Day, Int64, AgParameter}

    function Crop(name::String, crop_type::String, growth_stages::Dict, start_dt::Date; props...)::Crop
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

        start_year = year(start_dt)
        sow_date = Date("$(start_year)-" * plant_date)

        h_day = 0
        offset = 0
        start_date = sow_date
        g_stages = Dict{Symbol, Dict{Symbol, Union{Date, Int64, AgParameter}}}()
        coef_stages = Dict{Symbol, Dict{Symbol, Union{Int64, Float64, AgParameter}}}()

        @inbounds for (k, v) in growth_stages
            offset = v[:stage_length]
            end_of_stage = start_date + Dates.Day(offset)
            g_stages[k] = Dict(
                :start => start_date,
                :end => end_of_stage,
                :stage_length => offset
            )

            h_day += offset

            start_date = end_of_stage + Dates.Day(offset+1)
            coef_stages[k] = Dict(Symbol(s) => v for (s, v) in v)
        end

        harvest_offset = Dates.Day(h_day)
        harvest_date = sow_date + harvest_offset

        return new(name, crop_type, g_stages, coef_stages, sow_date,
            yield_per_ha, price_per_yield, variable_cost_per_ha, water_use_ML_per_ha,
            root_depth_m, et_coef, wue_coef, rainfall_threshold, 
            ssm_coef, effective_root_zone, harvest_date, harvest_offset)

    end
end

"""Update growth stages with corresponding dates from given sowing date."""
function update_stages!(c::Crop, dt::Date)::Nothing
    stages = c.growth_stages
    start_date::Date = Date(yearmonthday(dt)...)
    @inbounds for (k, v) in c.growth_stages
        offset::Int64 = v[:stage_length]
        end_of_stage = start_date + Dates.Day(offset)
        stages[k] = Dict(
            :start => start_date,
            :end => end_of_stage,
            :stage_length => offset
        )

        start_date = end_of_stage + Dates.Day(offset+1)
    end

    c.growth_stages = stages

    return nothing
end


function get_stage_coefs(c::Crop, dt::Date)::Dict
    @inbounds for (k, v) in c.growth_stages
        s::Date, e::Date = v[:start], v[:end]

        # if in season...
        if (s <= dt <= e)
            return c.coef_stages[k]
        end
    end

    # Not in season so just return initial growth stage
    return c.coef_stages[:initial]
end


"""Naive estimation of net income."""
function estimate_income_per_ha(c::Crop)::Float64
    return (c.price_per_yield * c.yield_per_ha) - c.variable_cost_per_ha
end


function subtotal_costs(c::Crop, year::Int64)::Float64
    # cost of production is handled by factoring in
    # water application costs and other maintenance costs.
    # The variable_cost_per_ha is only used to inform estimates.
    return 0.0
end


function create(spec::Dict, start_dt::Date)::Crop

    # cls_name = Base.typename(cls)
    # prefix::String = "$(cls_name)___$(name)__"
    # @add_preprefix

    # props = generate_agparams(prefix * "properties", prop)
    # stages = generate_agparams(prefix * "growth_stages", growth_stages)
    data = copy(spec)
    cls_name = pop!(data, :component)
    cls = eval(Symbol(cls_name))
    return cls(spec[:name], spec[:crop_type], spec[:growth_stages], start_dt; spec...)
end
