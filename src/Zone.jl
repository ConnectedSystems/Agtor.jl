using Dates

using Base.Threads
using Printf
using Formatting


@with_kw mutable struct FarmZone <: AgComponent
    name::String
    climate::Any
    fields::Array{FarmField}

    water_sources::Array{WaterSource}
    opt_field_area = Nothing
end


"""
Use a volume of water from either groundwater or surface water.
If water source name does not specify 'groundwater' then use
water from Low Reliability shares first, then High Reliability.
Expected volume unit is megaliters (ML).
"""
# function use_allocation!(zone::FarmZone, ws_name::String, value::Float64)
#     if occursin("groundwater", lowercase(ws_name))
#         vol = zone.gw_allocation
#         zone.gw_allocation = vol - value
#         return
#     end

#     lr_tmp = (zone.lr_allocation - value)

#     if lr_tmp > 0.0
#         zone.lr_allocation = lr_tmp
#         return
#     end

#     left_over = abs(lr_tmp)
#     zone.lr_allocation =  0.0

#     sub = zone.hr_allocation - left_over
#     zone.hr_allocation = sub

#     new_hr = zone.hr_allocation
#     if zone.hr_allocation < 0.0
#         throw("HR Allocation cannot be below 0 ML! Currently: $(new_hr)")
#     end
# end


"""Use allocation volume from a particular water source.

If surface water, uses Low Reliability first, then
High Reliability allocations.
"""
function use_allocation!(z::FarmZone, ws::WaterSource, value::Float64)
    ws.allocation -= value
    ws_name = ws.name

    if ws.allocation < 0.0
        msg = "Allocation cannot be below 0 ML! Currently: $(ws.allocation)\n"
        msg *= "Tried to use: $value\n"
        msg *= "From: $ws_name\n"
        error(msg)
    end
end

function Base.getproperty(z::FarmZone, v::Symbol)
    if v == :avail_allocation
        """Available water allocation in ML."""
        all_allocs = [ws.allocation for ws in z.water_sources]
        return round(sum(all_allocs), digits=4)
    elseif v == :total_area_ha
        return sum([f.total_area_ha for f in z.fields])
    elseif v == :total_irrigated_area
        return sum([f.irrigated_area for f in z.fields])
    end

    return getfield(z, v)
end

# function Base.setproperty!(z::FarmZone, v::Symbol, value)
#     if v == :hr_allocation
#         z._allocation["HR"] = value
#     elseif v == :lr_allocation
#         z._allocation["LR"] = value
#     elseif v == :gw_allocation
#         z._allocation["GW"] = value
#     else
#         setfield!(z, v, value)
#     end
# end


"""Determine the possible irrigation area using water from each water source."""
function possible_area_by_allocation(zone::FarmZone, field::FarmField, req_water_ML::Float64)
    @assert in(field.name, [f.name for f in zone.fields]) "Field must be in zone"

    tmp = Dict()
    for ws in zone.water_sources
        ws_name = ws.name
        tmp[ws_name] = possible_irrigation_area(field, ws.allocation, req_water_ML)
    end

    return tmp
end

"""The total area marked for irrigation."""
function irrigated_area(zone::FarmZone)
    fields = zone.fields
    return sum([f.irrigated_area for f in fields])
end


"""Calculate ML per ha to apply."""
function calc_irrigation_water(zone::FarmZone, field::FarmField)::Float64
    req_water_ML = required_water(field)

    # Can only apply water that is available
    ML_per_ha = zone.avail_allocation / field.irrigated_area
    if req_water_ML < ML_per_ha
        irrig_water = req_water_ML
    else
        irrig_water = ML_per_ha
    end

    return irrig_water
end

function apply_irrigation!(zone::FarmZone, field::CropField, 
                          ws::WaterSource, water_to_apply_mm::Float64,
                          area_to_apply::Float64)
    vol_ML_ha = water_to_apply_mm / mm_to_ML
    vol_ML = vol_ML_ha * area_to_apply
    use_allocation!(zone, ws, vol_ML)

    field.soil_SWD -= max(0.0, (water_to_apply_mm * field.irrigation.efficiency))
    field.irrigated_volume = (ws.name, vol_ML)
end

function apply_rainfall!(zone::FarmZone, dt::Date)
    Threads.@threads for f in zone.fields
        # get rainfall and et for datetime
        f_name = f.name
        rain_col = Symbol("$(f_name)_rainfall")
        et_col = Symbol("$(f_name)_ET")

        data = zone.climate.data
        idx = data[:, :Date] .== dt
        subset = data[findall(idx), [rain_col, et_col]]
        rainfall, et = subset[:, rain_col][1], subset[:, et_col][1]

        update_SWD!(f, rainfall, et)
    end
end
