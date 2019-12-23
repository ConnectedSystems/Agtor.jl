"""Represents generic farm infrastructure."""
abstract type Infrastructure <: AgComponent end

macro def(name, definition)
    return quote
        macro $(esc(name))()
            esc($(Expr(:quote, definition)))
        end
    end
end

@def infrastructure_fields begin
    name::String

    # capital per ha or total implementation cost.
    # up to each implementing component to correctly calculate
    # maintenance, etc.
    capital_cost::Float64

    # num years maintenance occurs, and 
    # assumed proportion of capital cost
    minor_maintenance_schedule::Float64
    major_maintenance_schedule::Float64
    minor_maintenance_rate::Float64
    major_maintenance_rate::Float64
end

function Base.getproperty(a::Infrastructure, v::Symbol)
    if v == :minor_maintenance_cost
        return a.capital_cost * a.minor_maintenance_rate
    elseif v == :major_maintenance_cost
        return a.capital_cost * a.minor_maintenance_rate
    elseif v == :maintenance_year
        maintenance_year = Dict(
            "minor" => a.minor_maintenance_schedule,
            "major" => a.major_maintenance_schedule
        )
        return maintenance_year
    else
        return getfield(a, v)
    end
end

"""Calculate maintenance costs.

Warning: This can be on a per ha basis or given as a total.
"""
function maintenance_cost(infra::Infrastructure, year_step::Int64)::Float64
    mr = infra.maintenance_year

    maintenance_cost = 0.0
    if year_step % mr["major"] == 0
        maintenance_cost = infra.major_maintenance_cost
    elseif year_step % mr["minor"] == 0
        maintenance_cost = infra.minor_maintenance_cost
    end

    return maintenance_cost
end