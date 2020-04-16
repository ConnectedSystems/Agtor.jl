using Dates

using Base.Threads
using Printf
using Formatting
using DataStructures


@with_kw mutable struct FarmZone <: AgComponent
    name::String
    climate::Any
    fields::Array{FarmField}

    water_sources::Array{WaterSource}
    opt_field_area::Union{Dict, Nothing} = nothing
    _irrigation_volume_by_source::DataFrame = DataFrame()
end

"""Use allocation volume from a particular water source.

Volumes in ML.
"""
function use_allocation!(z::FarmZone, ws::WaterSource, vol_ML::Float64)
    ws.allocation -= vol_ML

    if ws.allocation < 0.0
        if isapprox(0.0, ws.allocation, atol=1e-8)
            ws.allocation = 0.0
            return
        end

        ws_name = ws.name
        msg = "Allocation cannot be below 0 ML! Currently: $(ws.allocation)ML\n"
        msg *= "Tried to use: $(vol_ML)ML\n"
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


"""Determine the possible irrigation area using water from each water source."""
function possible_area_by_allocation(zone::FarmZone, field::FarmField, req_water_ML::Float64)::Dict
    @assert in(field.name, [f.name for f in zone.fields]) "Field must be in zone"

    tmp::Dict = Dict{String, Float64}()
    for ws::WaterSource in zone.water_sources
        ws_name = ws.name
        tmp[ws_name] = possible_irrigation_area(field, ws.allocation, req_water_ML)
    end

    return tmp
end

"""The total area marked for irrigation."""
function irrigated_area(zone::FarmZone)::Float64
    fields::Array = zone.fields
    return sum([f.irrigated_area for f in fields])
end


"""Calculate ML per ha to apply."""
function calc_irrigation_water(zone::FarmZone, field::FarmField)::Float64
    req_water_ML::Float64 = required_water(field)

    # Can only apply water that is available
    ML_per_ha::Float64 = zone.avail_allocation / field.irrigated_area
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
    vol_ML_ha::Float64 = water_to_apply_mm / mm_to_ML
    vol_ML::Float64 = vol_ML_ha * area_to_apply
    use_allocation!(zone, ws, vol_ML)

    field.soil_SWD -= max(0.0, (water_to_apply_mm * field.irrigation.efficiency))
    field.irrigated_volume = (ws.name, vol_ML)
end

function apply_rainfall!(zone::FarmZone, dt::Date)
    data::DataFrame = zone.climate.data
    idx = zone.climate.time_steps .== dt
    subset::DataFrame = data[findall(idx), :]
    rainfall::Float64, et::Float64 = 0.0, 0.0

    Threads.@threads for f in zone.fields
        # get rainfall and et for datetime
        f_name = f.name
        rain_col = Symbol("$(f_name)_rainfall")
        et_col = Symbol("$(f_name)_ET")
        rainfall, et = subset[1, rain_col], subset[1, et_col]

        update_SWD!(f, rainfall, et)
    end
end


function log_irrigation_by_water_source(zone::FarmZone, f::FarmField, dt::Date)
    
    # Construct log structure if needed
    if nrow(zone._irrigation_volume_by_source) == 0
        tmp_dict = OrderedDict()
        tmp_dict[:Date] = Date[]
        for ws::WaterSource in zone.water_sources
            tmp_dict[Symbol(ws.name)] = Float64[]
        end

        zone._irrigation_volume_by_source = DataFrame(; tmp_dict...)
    end

    tmp = [0.0 for ws in zone.water_sources]
    for (i, ws::WaterSource) in enumerate(zone.water_sources)
        try
            tmp[i] += f.irrigation_from_source[ws.name]
        catch e
            if isa(e, KeyError)
                continue
            end
            throw(e)
        end
    end

    push!(zone._irrigation_volume_by_source, [dt tmp...])
end

"""Collate logged values, summing on identical datetimes"""
function collate_log(zone::FarmZone, sym::Symbol; last=false)::OrderedDict
    target_log::Dict = Dict{Date, Float64}()
    for f::FarmField in zone.fields
        tmp = getfield(f, sym)
        if last
            tmp = Dict(sort(collect(tmp))[end])
        end

        target_log = merge(+, target_log, tmp)
    end

    return OrderedDict(sort(collect(target_log)))
end


"""Collect model run results for a FarmZone"""
function collect_results(zone::FarmZone; last=false)::Tuple
    incomes::OrderedDict = collate_log(zone, :_seasonal_income; last=last)
    irrigations::OrderedDict = collate_log(zone, :_seasonal_irrigation_vol; last=last)
    irrig_ws::OrderedDict = OrderedDict()

    # res = zone._irrigation_volume_by_source
    # @info aggregate(groupby(res, :Date), sum)

    return incomes, irrigations, irrig_ws
end
