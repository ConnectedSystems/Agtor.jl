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


"""Calculate maintenance costs.

!!! warning 
    Don't forget that the output of this can be on a per hectare basis 
    or given as a total depending on how the model is parameterized.
"""
function maintenance_cost(infra::Infrastructure, year_step::Int64)::Float64
    minor=infra.minor_maintenance_schedule
    major=infra.major_maintenance_schedule
    maintenance_cost::Float64 = 0.0
    if year_step % major == 0
        maintenance_cost = infra.capital_cost * infra.major_maintenance_rate
    elseif year_step % minor == 0
        maintenance_cost = infra.capital_cost * infra.minor_maintenance_rate
    end

    return maintenance_cost
end