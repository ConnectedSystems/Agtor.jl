# from typing import Optional
# from dataclasses import dataclass

# from agtor.data_interface import generate_params
# from .Component import Component
# from .Pump import Pump

import Unitful: Quantity, ML, ha, m

@with_kw mutable struct WaterSource <: AgComponent
    name::String
    cost_per_ML::Float64
    cost_per_ha::Float64
    yearly_cost::Float64
    pump::Pump
    head::Quantity
end

function pump_cost_per_ML(ws::WaterSource, flow_rate_Lps::Float64)
    return pumping_costs_per_ML(ws.pump, flow_rate_Lps, ws.head)
end

function usage_costs(ws::WaterSource, water_used_ML::Quantity{ML})
    return ws.cost_per_ML * water_used_ML
end

function total_costs(ws::WaterSource, area::Quantity{ha}, water_used_ML::Quantity{ML})
    usage_fee = usage_costs(ws, water_used_ML)
    area_fee = ws.cost_per_ha * area
    return ws.yearly_cost + usage_fee + area_fee
end