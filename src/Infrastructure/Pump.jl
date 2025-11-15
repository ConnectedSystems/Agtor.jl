
"""
    Pump(pump_efficiency=0.7, cost_per_kW=0.28, derating=0.75)

An on-farm pump to access water.
"""
@with_kw mutable struct Pump <: Infrastructure

    @infrastructure_fields

    pump_efficiency::Union{Float64,AgParameter} = 0.7  # Efficiency of pump. Defaults to 0.7 (70%)
    cost_per_kW::Union{Float64,AgParameter} = 0.28  # cost in dollars/kW. Defaults to 0.28/kW

    # Accounts for efficiency losses between the energy required at the pump
    # shaft and the total energy required. Defaults to 0.75
    derating::Union{Float64,AgParameter} = 0.75
end

function cost_per_ha(p::Pump, year_step::Int64, area::Float64)::Float64
    return maintenance_cost(p, year_step) / area
end

function subtotal_costs(p::Pump, year_step::Int64)::Float64
    return cost_per_ha(p, year_step, 1.0)
end


"""
    pumping_costs_per_ML(p::Pump, head_pressure::Float64)::Float64

Calculate the energy cost to pump one megalitre of water.

The energy required to pump water is determined by the head pressure (vertical lift
plus friction losses) and system efficiency, independent of flow rate.

Energy per megalitre:

``kWh/ML = (H ⋅ 2.725) / (η_pump ⋅ D)``

where:
* `H` is total head pressure in metres (m)
* `2.725` is the gravitational constant: (g × ρ) / kWh = (9.81 m/s² × 1000 kg/m³) / 3,600,000 J/kWh
* `η_pump` is pump efficiency (typically 0.65-0.85)
* `D` is the derating factor accounting for motor and drive losses (typically 0.75-0.95)

Cost per megalitre:

``Cost/ML = (kWh/ML) ⋅ (electricity rate in \$/kWh)``

See:
    * [Robinson, D. W. (2002)](http://www.clw.csiro.au/publications/technical2002/tr20-02.pdf)
    * [Vic. Dept. Agriculture (2006)](http://agriculture.vic.gov.au/agriculture/farm-management/soil-and-water/irrigation/border-check-irrigation-design>)
    * [Vellotti & Kalogernis (2013)](http://irrigation.org.au/wp-content/uploads/2013/06/Gennaro-Velloti-and-Kosi-Kalogernis-presentation.pdf>)

# Arguments
- `p` : Pump object containing efficiency, derating, and electricity cost parameters
- `head_pressure` : Total dynamic head in metres (static lift + pressure head + friction losses)

# Parameters taken from `p::Pump`
- `pump_efficiency` : Efficiency of pump. Defaults to 0.7 (70%)
- `derating` : Accounts for efficiency losses between the energy required at the pump
                    shaft and the total energy required. Defaults to 0.75
# Returns
- float, cost_per_ML

# Notes
- Flow rate does not affect cost per ML - it only affects pumping duration
- Higher head pressures increase energy requirements linearly
- Poor efficiency (pump or motor) significantly increases costs
- For gravity-fed systems where H ≈ 0, pumping costs approach zero

# See also
- link to [`Pump(pump_efficiency, cost_per_kW, derating)`](@ref)
"""
function pumping_costs_per_ML(p::Pump, head_pressure::Float64)::Float64
    if flow_rate_Lps <= 0.0
        return 0.0
    end

    pe::Float64 = p.pump_efficiency
    dr::Float64 = p.derating

    # 2.725 = [constant representing gravitational acceleration] ⋅ [water density] / kWh
    # kWh = [gravity: 9.81 m/s²] × [water density: (1000 kg/m³ * 1000 m³)] / kWh
    # = 9.81 * 1000² / 3,600,000
    # where 3,600,000 joules = 1 kWh
    # = 2.725
    kWh_per_ML = (head_pressure * 2.725) / (pe * dr)
    cost_per_ML::Float64 = p.cost_per_kW * kWh_per_ML

    @assert cost_per_ML >= 0.0 "Pumping costs cannot be negative.
    $cost_per_ML
    $head_pressure"

    return cost_per_ML
end