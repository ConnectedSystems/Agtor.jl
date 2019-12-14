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
    minor_maintenance_cost::Float64
    major_maintenance_cost::Float64
    maintenance_year() = Dict(
        "minor" => minor_maintenance_schedule,
        "major" => major_maintenance_schedule
    )

    minor_maintenance_cost() = capital_cost * minor_maintenance_rate
    major_maintenance_cost() = capital_cost * major_maintenance_rate
end

"""Calculate maintenance costs.

Warning: This can be on a per ha basis or given as a total.
"""
function maintenance_cost(infra::Infrastructure, year_step::Int64)::Float64
    mr = infra.maintenance_year

    if year_step % mr["major"] == 0
        maintenance_cost = infra.major_maintenance_cost
    elseif year_step % mr["minor"] == 0
        maintenance_cost = infra.minor_maintenance_cost
    else
        maintenance_cost = 0.0
    end

    return maintenance_cost
end