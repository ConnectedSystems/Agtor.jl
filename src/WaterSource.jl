@with_kw mutable struct WaterSource <: AgComponent
    name::String
    cost_per_ML::Float64
    cost_per_ha::Float64
    yearly_cost::Float64
    pump::Pump
    head::Float64
    allocation::Float64
end

function pump_cost_per_ML(ws::WaterSource, flow_rate_Lps::Float64)::Float64
    return pumping_costs_per_ML(ws.pump, flow_rate_Lps, ws.head)
end

function usage_costs(ws::WaterSource, water_used_ML::Float64)::Float64
    return ws.cost_per_ML * water_used_ML
end

function subtotal_costs(ws::WaterSource, area::Float64, water_used_ML::Float64)::Float64
    usage_fee::Float64 = usage_costs(ws, water_used_ML)
    area_fee::Float64 = ws.cost_per_ha * area
    return ws.yearly_cost + usage_fee + area_fee
end