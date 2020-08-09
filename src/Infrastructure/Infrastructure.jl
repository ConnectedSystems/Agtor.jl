import Agtor.@def

"""Represents generic farm infrastructure."""
abstract type Infrastructure <: AgComponent end


@def infrastructure_fields begin
    name::String

    # capital per ha or total implementation cost.
    # up to each implementing component to correctly calculate
    # maintenance, etc.
    capital_cost::Union{AgParameter, Float64}

    # num years maintenance occurs, and 
    # assumed proportion of capital cost
    minor_maintenance_schedule::Union{Int64, Float64, AgParameter}
    major_maintenance_schedule::Union{Int64, Float64, AgParameter}
    minor_maintenance_rate::Union{Float64, AgParameter}
    major_maintenance_rate::Union{Float64, AgParameter}
end

function minor_maintenance_cost(a::Infrastructure)::Float64
    return a.capital_cost * a.minor_maintenance_rate
end

function major_maintenance_cost(a::Infrastructure)::Float64
    return a.capital_cost * a.major_maintenance_rate
end

function maintenance_year(infra::Infrastructure)::Dict{String, Float64}
    maintenance_year::Dict{String, Float64} = Dict{String, Float64}(
        "minor" => infra.minor_maintenance_schedule,
        "major" => infra.major_maintenance_schedule
    )
    return maintenance_year
end


"""Calculate maintenance costs.

Warning: This can be on a per ha basis or given as a total.
"""
function maintenance_cost(infra::Infrastructure, year_step::Int64)::Float64
    mr::Dict{String, Float64} = maintenance_year(infra)

    maintenance_cost::Float64 = 0.0
    if year_step % mr["major"] == 0
        maintenance_cost = major_maintenance_cost(infra)
    elseif year_step % mr["minor"] == 0
        maintenance_cost = minor_maintenance_cost(infra)
    end

    return maintenance_cost
end