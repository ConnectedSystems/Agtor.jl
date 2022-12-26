
"""
    Pump(pump_efficiency=0.7, cost_per_kW=0.28, derating=0.75)

An on-farm pump to access water.
"""
@with_kw mutable struct Pump <: Infrastructure

    @infrastructure_fields

    pump_efficiency::Union{Float64, AgParameter} = 0.7  # Efficiency of pump. Defaults to 0.7 (70%)
    cost_per_kW::Union{Float64, AgParameter} = 0.28  # cost in dollars/kW. Defaults to 0.28/kW
    
    # Accounts for efficiency losses between the energy required at the pump
    # shaft and the total energy required. Defaults to 0.75
    derating::Union{Float64, AgParameter} = 0.75
end

function cost_per_ha(p::Pump, year_step::Int64, area::Float64)::Float64
    return maintenance_cost(p, year_step) / area
end

function subtotal_costs(p::Pump, year_step::Int64)::Float64
    return cost_per_ha(p, year_step, 1.0)
end


"""
    pumping_costs_per_ML(p::Pump, flow_rate_Lps::Float64, head_pressure::Float64)::Float64

Calculate pumping cost per ML for a given flow rate and head pressure.

``P(Kw) = (H * Q) / ((102 * Ep) * D)``

where:
* `H` is head pressure in metres (m)
* `Q` is Flow in Litres per Second
* `Ep` is Pump efficiency (defaults to 0.7)
* `D` is the derating factor
* `102` is a constant, as given in Velloti & Kalogernis (2013)

See:
    * [Robinson, D. W. (2002)](http://www.clw.csiro.au/publications/technical2002/tr20-02.pdf)
    * [Vic. Dept. Agriculture (2006)](http://agriculture.vic.gov.au/agriculture/farm-management/soil-and-water/irrigation/border-check-irrigation-design>)
    * [Vellotti & Kalogernis (2013)](http://irrigation.org.au/wp-content/uploads/2013/06/Gennaro-Velloti-and-Kosi-Kalogernis-presentation.pdf>)


# Arguments
- p : Pump object
- flow_rate_Lps : required flow rate in Litres per second over the irrigation duration
- head_pressure : Head pressure of pumping system in metres.


# Parameters taken from `p::Pump`
- `pump_efficiency` : Efficiency of pump. Defaults to 0.7 (70%)
- `derating` : Accounts for efficiency losses between the energy required at the pump
                    shaft and the total energy required. Defaults to 0.75

# Returns
- float, cost_per_ML

# See also
- link to [`Pump(pump_efficiency, cost_per_kW, derating)`](@ref)
"""
function pumping_costs_per_ML(p::Pump, flow_rate_Lps::Float64, 
                              head_pressure::Float64)::Float64
    if flow_rate_Lps <= 0.0
        return 0.0
    end

    c::Float64 = 102.0
    pe::Float64 = p.pump_efficiency
    dr::Float64 = p.derating
    energy_required_kW::Float64 = (head_pressure * flow_rate_Lps) / ((c * pe) * dr)

    # Litres / minutes in hour / seconds in minute
    hours_per_ML::Float64 = (1e6 / flow_rate_Lps) / 60.0^2

    cost_per_hour::Float64 = p.cost_per_kW * energy_required_kW
    cost_per_ML::Float64 = (cost_per_hour * hours_per_ML)

    @assert cost_per_ML >= 0.0 "Pumping costs cannot be negative. 
    $cost_per_ML
    $flow_rate_Lps
    $head_pressure"

    return cost_per_ML
end