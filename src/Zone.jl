using Dates

using Base.Threads
using Formatting
using DataStructures
using Statistics
# using Infiltrator


@with_kw mutable struct FarmZone <: AgComponent
    name::String
    climate::Any
    fields::Array{FarmField}

    water_sources::Array{WaterSource}
    _irrigation_volume_by_source::DataFrame = DataFrame()
end


"""Use allocation volume from a particular water source.

Volumes in ML.
"""
function use_allocation!(z::FarmZone, ws::WaterSource, vol_ML::Float64)::Nothing
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

    return nothing
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
function possible_area_by_allocation(zone::FarmZone, field::FarmField, req_water_ML::Float64)::Dict{String, Float64}
    @assert in(field.name, [f.name for f in zone.fields]) "Field must be in zone"

    tmp::Dict{String, Float64} = Dict{String, Float64}()
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


# """Calculate ML per ha to apply."""
# function calc_irrigation_water(zone::FarmZone, field::FarmField)::Float64
#     req_water_ML::Float64 = required_water(field)

#     # Can only apply water that is available
#     ML_per_ha::Float64 = zone.avail_allocation / field.irrigated_area
#     if req_water_ML < ML_per_ha
#         irrig_water = req_water_ML
#     else
#         irrig_water = ML_per_ha
#     end

#     return irrig_water
# end


function apply_irrigation!(zone::FarmZone, field::CropField, 
                          ws::WaterSource, water_to_apply_mm::Float64,
                          area_to_apply::Float64)
    vol_ML_ha::Float64 = water_to_apply_mm / mm_to_ML
    vol_ML::Float64 = vol_ML_ha * area_to_apply
    use_allocation!(zone, ws, vol_ML)

    field.soil_SWD -= max(0.0, (water_to_apply_mm * field.irrigation.efficiency))
    field.irrigated_volume = (ws.name, vol_ML)
end


"""Apply rainfall and ET to influence soil water deficit."""
function apply_rainfall!(zone::FarmZone, dt::Date)::Nothing
    data::DataFrame = zone.climate.data
    idx::BitArray = zone.climate.time_steps .== dt
    subset::DataFrame = data[idx, :]

    @inbounds for f in zone.fields
        # get rainfall and et for datetime
        f_name::String = f.name
        rain_col::Symbol = Symbol("$(f_name)_rainfall")
        et_col::Symbol = Symbol("$(f_name)_ET")

        rainfall::Float64, et::Float64 = subset[1, rain_col], subset[1, et_col]

        update_SWD!(f, rainfall, et)

        @debug "SWD After Rainfall" f.soil_SWD rainfall et
    end

    return nothing
end


function log_irrigation_by_water_source(zone::FarmZone, f::FarmField, dt::Date)::Nothing
    
    # Construct log structure if needed
    if nrow(zone._irrigation_volume_by_source) == 0
        tmp_dict::OrderedDict = OrderedDict()
        tmp_dict[:Date] = Date[]
        for ws::WaterSource in zone.water_sources
            tmp_dict[Symbol(ws.name)] = Float64[]
        end

        zone._irrigation_volume_by_source = DataFrame(; tmp_dict...)
    end

    tmp::Array{Float64} = Float64[0.0 for ws in zone.water_sources]
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
    
    return nothing
end


"""Collate logged values, summing on identical datetimes"""
function collate_field_logs(zone::FarmZone, sym::Symbol; last=false)::OrderedDict{Date, Float64}
    target_log::Dict{Date, Float64} = Dict{Date, Float64}()
    for f::FarmField in zone.fields
        tmp = getfield(f, sym)

        if last
            tmp = Dict(sort(collect(tmp))[end])
        end

        target_log = merge(+, target_log, tmp)
    end

    return OrderedDict(sort(collect(target_log)))
end


function aggregate_field_logs(field_logs::DataFrame)::DataFrame
    collated::DataFrame = aggregate(groupby(field_logs, :Date), sum)

    collated[:, Symbol("Dollar per ML")] = collated[:, :income_sum] ./ collated[:, :irrigated_volume_sum]
    collated[:, Symbol("ML per Irrigated Yield")] = collated[:, :irrigated_volume_sum] ./ collated[:, :irrigated_yield_sum]
    collated[:, Symbol("Dollar per Ha")] = collated[:, :income_sum] ./ (collated[:, :dryland_area_sum] + collated[:, :irrigated_area_sum])
    collated[:, Symbol("Avg Irrigated Yield")] = collated[:, :irrigated_yield_sum] ./ collated[:, :irrigated_area_sum]
    collated[:, Symbol("Avg Dryland Yield")] = collated[:, :dryland_yield_sum] ./ collated[:, :dryland_area_sum]

    return collated
end


"""Collate logged values, aggregating to the zonal level based on identical datetimes."""
function collate_field_logs(zone::FarmZone)::DataFrame
    tmp::DataFrame = reduce(vcat, [f._seasonal_log for f in zone.fields])
    collated::DataFrame = aggregate_field_logs(tmp)

    return collated
end


"""Collate logged values, aggregating to the zonal level based on identical datetimes."""
function collate_field_logs(seasonal_logs::Dict)::DataFrame
    s_logs = values(seasonal_logs)
    tmp::DataFrame = reduce(vcat, s_logs)
    collated::DataFrame = aggregate_field_logs(tmp)

    return collated
end


"""Collect model run results for a FarmZone"""
function collect_results(zone::FarmZone; last=false)::Tuple{DataFrame,Dict{Any,Any}}
    field_logs = Dict(
        f.name => f._seasonal_log
        for f in zone.fields
    )

    collated = collate_field_logs(field_logs)

    ws_irrig = zone._irrigation_volume_by_source
    irrig_ws::DataFrame = aggregate(groupby(ws_irrig, :Date), sum)

    collated_res = hcat(collated, irrig_ws[:, setdiff(names(irrig_ws), [:Date])])

    return collated_res, field_logs
end
