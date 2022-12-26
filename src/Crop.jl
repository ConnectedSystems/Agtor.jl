using Dates
using OrderedCollections
using Setfield
using DataFrames

import Agtor: Climate


@with_kw mutable struct Crop <: AgComponent
    name::String
    crop_type::String

    # Growth pattern
    growth_stages::NamedTuple
    coef_stages::NamedTuple

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
    naive_crop_income::Float64

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
        dt = "$(start_year)-$(string(plant_date.default_val))"
        sow_date = Date(dt, "YYYY-mm-dd")

        h_day = 0
        offset = 0
        start_date = sow_date
        g_stages = NamedTuple()
        coef_stages = NamedTuple()

        @inbounds for (k, v) in growth_stages
            offset = v[:stage_length]
            end_of_stage = start_date + Dates.Day(offset)
            @set! g_stages[Symbol(k)] = (
                start = start_date,
                var"end" = end_of_stage,
                stage_length = offset
            )

            @set! coef_stages[k] = NamedTuple{Tuple(keys(v))}(values(v))

            h_day += offset
            start_date = end_of_stage + Dates.Day(offset+1)

        end

        harvest_offset = Dates.Day(h_day)
        harvest_date = sow_date + harvest_offset

        c = new(name, crop_type, g_stages, coef_stages, sow_date,
                yield_per_ha, price_per_yield, variable_cost_per_ha, water_use_ML_per_ha,
                root_depth_m, et_coef, wue_coef, rainfall_threshold,
                ssm_coef, effective_root_zone, harvest_date, harvest_offset)

        # variable cost does not include water usage costs (added later in optimized allocation step)
        c.naive_crop_income = (c.price_per_yield * c.yield_per_ha) - c.variable_cost_per_ha

        return c
    end
end


"""Update growth stages with corresponding dates from given sowing date."""
function update_stages!(c::Crop, dt::Date)::Nothing
    stages::NamedTuple = c.growth_stages::NamedTuple
    start_date::Date = Date(yearmonthday(dt)...)
    @inbounds for (k, v) in pairs(c.growth_stages)
        offset::Int64 = v[:stage_length]
        end_of_stage = start_date + Dates.Day(offset)
        @set! stages[k] = (
            start = start_date,
            var"end" = end_of_stage,
            stage_length = offset
        )

        start_date = end_of_stage + Dates.Day(offset+1)
    end

    c.growth_stages = stages

    return nothing
end


function get_stage_coefs(c::Crop, dt::Date)::NamedTuple
    @inbounds for (k::Symbol, v::NamedTuple) in pairs(c.growth_stages::NamedTuple)
        s::Date = v[:start]
        e::Date = v[:end]

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
    data = deepcopy(spec)
    _ = pop!(data, :component)
    return Crop(data[:name], data[:crop_type], data[:growth_stages], start_dt; data...)
end


"""Get all in-season dates for a given crop."""
function in_season_dates(c::Climate, crop::Crop)::DataFrame
    d = c.data
    sow_d = monthday(crop.plant_date)
    harvest_d = monthday(crop.harvest_date)
    mds = monthday.(d[:Date])

    return d[(mds .>= [sow_d]) .| (mds .< [harvest_d]), :]
end
