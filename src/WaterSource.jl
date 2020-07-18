@with_kw mutable struct WaterSource <: AgComponent
    name::String
    cost_per_ML::Union{Int64, Float64, AgParameter}
    cost_per_ha::Union{Int64, Float64, AgParameter}
    yearly_cost::Union{Int64, Float64, AgParameter}
    pump::Pump
    head::Union{Int64, Float64, AgParameter}
    allocation::Union{Int64, Float64, AgParameter}
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


function create(cls::Type{WaterSource}, data::Dict{String, Dict},
                pump_specs::Dict{String, Dict}, 
                override=nothing, id_prefix::Union{String, Nothing}=nothing)::Array{WaterSource}
    cls_name = Base.typename(cls)
    tmp_prefix::String = "$(cls_name)___"

    ws::Array{WaterSource} = []
    for (k, v) in data
        pump_name = v["name"]  # pump will have same name as the water_source

        prefix = tmp_prefix * "$(pump_name)___"
        @add_preprefix

        v["pump"] = create(Pump, pump_specs[pump_name], override, prefix)
        
        ws_i::WaterSource = create(cls, v, override)
        push!(ws, ws_i)
    end

    return ws
end