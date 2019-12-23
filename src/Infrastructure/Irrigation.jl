
import Unitful: uconvert, ML, L, ha

"""On-farm irrigation infrastructure component"""
@with_kw mutable struct Irrigation <: Infrastructure
    @infrastructure_fields

    efficiency::Float64
    flow_ML_day::Float64
    head_pressure::Float64

end

"""Calculate flow rate in litres per second"""
flow_rate_Lps(irrig::Irrigation) = uconvert(L, irrig.flow_ML_day * 1ML) / 86400.0


function cost_per_ha(irrig::Irrigation, year_step::Int64, area::Float64)::Float64
    return maintenance_cost(irrig, year_step) * area
end

function total_costs(irrig::Irrigation, year_step::Int64)::Float64
    """Calculate total costs.
    """
    # cost per ha divides maintenance costs by the
    # area considered, so simply use 1 to get total.
    return cost_per_ha(irrig, year_step, 1)
end
