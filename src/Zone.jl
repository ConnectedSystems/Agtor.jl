using Dates

import Unitful: ML
using Printf
using Formatting


mutable struct FarmZone <: AgComponent
    name::String
    climate::Any
    fields::Array{FarmField}
    crops::Array{Crop}

    water_sources::Array{WaterSource}
    allocation::Dict
end

function total_area_ha(zone::FarmZone)
    return sum([f.total_area_ha for f in zone.fields])
end


"""
Use a volume of water from either groundwater or surface water.
If water source name does not specify 'groundwater' then use
water from Low Reliability shares first, then High Reliability.
Expected volume unit is megaliters (ML).
"""
function use_allocation!(zone::FarmZone, ws_name::String, value::Float64)
    if occursin("groundwater", lowercase(ws_name))
        vol = zone.gw_allocation
        zone.gw_allocation = vol - value
        return
    end

    lr_tmp = (zone.lr_allocation - value)

    if lr_tmp > 0.0
        zone.lr_allocation = lr_tmp
        return
    end

    left_over = abs(lr_tmp)
    zone.lr_allocation =  0.0

    sub = zone.hr_allocation - left_over
    zone.hr_allocation = sub

    new_hr = zone.hr_allocation
    if zone.hr_allocation < 0.0
        throw("HR Allocation cannot be below 0 ML! Currently: $(new_hr)")
    end
end

"""
Get the available allocation value (in ML) for a named water source within a zone.
"""
function avail_allocation(zone::FarmZone)
    return round(sum(values(zone._allocation)), digits=4)
end


function Base.getproperty(z::FarmZone, v::Symbol)
    if v == :hr_allocation
        # Available High Reliability water allocation in ML.
        return z._allocation["HR"]
    elseif v == :lr_allocation
        return z._allocation["LR"]
    elseif v == :gw_allocation
        return z._allocation["GW"]
    end

    return getfield(z, v)
end

function Base.setproperty!(z::FarmZone, v::Symbol, value)
    if v == :hr_allocation
        z._allocation["HR"] = value
    elseif v == :lr_allocation
        z._allocation["LR"] = value
    elseif v == :gw_allocation
        z._allocation["GW"] = value
    else
        setproperty!(z, v, value)
    end
end


"""Determine the possible irrigation area using water from each water source."""
function possible_area_by_allocation(zone::FarmZone, field::FarmField)
    sw = zone.lr_allocation + zone.hr_allocation
    gw = zone.gw_allocation

    @assert field in zone.fields

    tmp = Dict()
    for ws in zone.water_sources
        ws_name = ws.name
        tmp[ws_name] = calc_possible_area(field, ws)
    end

    return tmp
end

"""The total area marked for irrigation."""
function irrigated_area(zone::FarmZone)
    fields = zone.fields
    return sum([f.irrigated_area for f in fields])
end


"""Calculate ML per ha to apply."""
function calc_irrigation_water(zone::FarmZone, field::FarmField)::Quantity{ML}
    req_water_ML = uconvert(ML/ha, required_water(field))

    # Can only apply water that is available
    ML_per_ha = avail_allocation(zone) / field.irrigated_area
    if req_water_ML <= ML_per_ha
        irrig_water = req_water_ML
    else
        irrig_water = ML_per_ha
    end

    return irrig_water
end

function apply_irrigation(zone::FarmZone, field::CropField, 
                          ws_name::String, water_to_apply_mm::Float64)
    vol_ML_ha = uconvert(ML/ha, water_to_apply_mm)
    vol_ML = vol_ML_ha * field.irrigated_area
    use_allocation!(zone, ws_name, vol_ML)

    field.soil_SWD -= max(0.0, (water_to_apply_mm * field.irrigation.efficiency))

    field.irrigated_volume = (ws_name, vol_ML)
end

function apply_rainfall(zone::FarmZone, dt::DateTime)
    for f in zone.fields
        # get rainfall and et for datetime
        f_name = f.name
        rain_col = "$(f_name)_rainfall"
        et_col = "$(f_name)_ET"

        subset = zone.climate[:, [:rain_col, :et_col]]
        rainfall, et = subset[:, :rain_col], subset[:, :et_col]

        update_SWD(f, rainfall, et)
    end
end
