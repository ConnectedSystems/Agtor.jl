
"""On-farm irrigation infrastructure component"""
@with_kw mutable struct Irrigation <: Infrastructure
    @infrastructure_fields

    efficiency::Union{Float64,AgParameter}
    flow_ML_day::Union{Float64,AgParameter}
    head_pressure::Union{Float64,AgParameter}

end

"""Getters for Irrigation"""
function Base.getproperty(irrig::Irrigation, v::Symbol)
    if v == :flow_rate_Lps
        # Calculate flow rate in litres per second
        return (irrig.flow_ML_day * 1e6) / 86400.0
    end

    return getfield(irrig, v)
end


function cost_per_ha(irrig::Irrigation, year_step::Int64, area::Float64)::Float64
    return maintenance_cost(irrig, year_step) * area
end

"""Calculate sub-total of irrigation costs"""
function subtotal_costs(irrig::Irrigation, year_step::Int64)::Float64
    # cost per ha divides maintenance costs by the
    # area considered, so simply use 1 to get total.
    return cost_per_ha(irrig, year_step, 1.0)
end
