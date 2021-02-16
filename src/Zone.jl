using Dates

using Base.Threads
using Formatting
using OrderedCollections
using Statistics


@with_kw mutable struct FarmZone <: AgComponent
    name::String
    climate::Any
    fields::Array{FarmField}
    water_sources::Array{WaterSource}
    _irrigation_volume_by_source::DataFrame = DataFrame()
    manager = nothing
end


# function Base.show(io::IO, z::FarmZone)
#     compact = get(io, :compact, false)

#     name = z.name
#     fields = Tuple((f.name, f.total_area_ha) for f in z.fields) 
#     zone_ws = Tuple(ws.name for ws in z.water_sources) 
#     manager = z.manager.name

#     if compact
#         print(z, " ($name)")
#     else
#         println("""
#         FarmZone ($name):

#         Fields: $(length(fields))

#         Water Sources: $(zone_ws)

#         Manager: $(manager)
#         """)
#     end
# end


"""Use allocation volume from a particular water source.

Volumes in ML.
"""
function use_allocation!(ws::WaterSource, vol_ML::Float64)::Nothing
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
        throw(ArgumentError(msg))
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
        return sum([!isnothing(f.irrigated_area) ? f.irrigated_area : 0.0 for f in z.fields])
    end

    return getfield(z, v)
end


"""Determine the possible irrigation area using water from each water source."""
function possible_area_by_allocation(zone::FarmZone, field::FarmField, req_water_ML::Float64)::NamedTuple
    @assert in(field.name, [f.name for f::FarmField in zone.fields]) "Field must be in zone"

    zone_ws::Tuple = Tuple(zone.water_sources)
    tmp = NamedTuple{Tuple(Symbol(ws.name) for ws::WaterSource in zone_ws)}(
        possible_irrigation_area(field, ws.allocation, req_water_ML) for ws::WaterSource in zone_ws
    )

    return tmp
end


"""The total area marked for irrigation."""
function irrigated_area(zone::FarmZone)::Float64
    fields::Array{FarmField} = zone.fields
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


"""Apply irrigation water to field"""
function apply_irrigation!(field::CropField, 
                          ws::WaterSource, water_to_apply_mm::Float64,
                          area_to_apply::Float64)::Nothing
    vol_ML_ha::Float64 = water_to_apply_mm / mm_to_ML
    vol_ML::Float64 = vol_ML_ha * area_to_apply
    use_allocation!(ws, vol_ML)

    apply::Float64 = (water_to_apply_mm * field.irrigation.efficiency)
    field.soil_SWD::Union{Float64, AgParameter} -= max(0.0, apply)::Float64
    field.irrigated_volume = (ws.name, vol_ML)

    return nothing
end


"""Apply rainfall and ET to influence soil water deficit."""
function apply_rainfall!(zone::FarmZone, dt::Date)::Nothing
    climate::Climate = zone.climate::Climate
    data::DataFrame = climate.data::DataFrame
    idx::BitArray = (climate.time_steps::Array .== dt)::BitArray
    subset::DataFrame = data[idx, :]

    z_name::String = zone.name::String
    @inbounds for f::FarmField in zone.fields
        # get rainfall and et for datetime
        zf_id::String = "$(z_name)_$(f.name)"
        rain_col::Symbol = Symbol(zf_id, "_rainfall")
        et_col::Symbol = Symbol(zf_id, "_ET")

        rainfall::Float64, et::Float64 = subset[1, rain_col], subset[1, et_col]

        update_SWD!(f, rainfall, et)
    end

    return nothing
end


"""Apply rainfall and ET to influence soil water deficit."""
function apply_rainfall!(zone::FarmZone, dt_idx::Int64)::Nothing
    data::DataFrame = zone.climate.data::DataFrame

    z_name::String = zone.name::String
    @inbounds for f::FarmField in zone.fields
        # get rainfall and et for datetime
        zf_id::String = "$(z_name)_$(f.name)"
        rain_col::Symbol = Symbol(zf_id, "_rainfall")
        et_col::Symbol = Symbol(zf_id, "_ET")

        rainfall::Float64, et::Float64 = data[dt_idx, rain_col], data[dt_idx, et_col]

        update_SWD!(f, rainfall, et)
    end

    return nothing
end


"""Update water allocations"""
function update_available_water!(zone::FarmZone, allocations::NamedTuple)::Nothing
    for (k, v) in pairs(allocations)
        for ws in zone.water_sources
            if ws.name == string(k)
                ws.allocation = v
            end
        end
    end
end
    

"""Log irrigation volumes from water sources"""
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
    for (i::Int64, ws::WaterSource) in enumerate(zone.water_sources)
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
    collated[:, Symbol("Dollar per Ha")] = collated[:, :income_sum] ./ (collated[:, :dryland_area_sum] .+ collated[:, :irrigated_area_sum])
    collated[:, Symbol("Mean Irrigated Yield")] = collated[:, :irrigated_yield_sum] ./ collated[:, :irrigated_area_sum]
    collated[:, Symbol("Mean Dryland Yield")] = collated[:, :dryland_yield_sum] ./ collated[:, :dryland_area_sum]

    collated[isnan.(collated[!,Symbol("Mean Dryland Yield")]), Symbol("Mean Dryland Yield")] .= 0
    collated[isnan.(collated[!,Symbol("Mean Irrigated Yield")]), Symbol("Mean Irrigated Yield")] .= 0

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


function water_used_by_source(zone::FarmZone)::DataFrame
    return water_used_by_source(zone, nothing)
end


function water_used_by_source(zone::FarmZone, dt)::DataFrame
    ws_irrig = zone._irrigation_volume_by_source

    if nrow(ws_irrig) == 0
        return DataFrame(Date=dt, surface_water_sum=0.0, groundwater_sum=0.0)
    end

    if !(isnothing(dt))
        ws_irrig = ws_irrig[ws_irrig[:Date] .== dt, :]
    end

    if nrow(ws_irrig) == 0
        if isnothing(dt)
            return aggregate(groupby(ws_irrig, :Date), sum)
        end

        # Catch empty subset
        return DataFrame(Date=dt, surface_water_sum=0.0, groundwater_sum=0.0)
    end

    return aggregate(groupby(ws_irrig, :Date), sum)
end


"""Collect model run results for a FarmZone"""
function collect_results(zone::FarmZone; last=false)::Tuple{DataFrame,Dict}
    field_logs = Dict(
        f.name => f._seasonal_log
        for f in zone.fields
    )

    collated = collate_field_logs(field_logs)

    irrig_ws::DataFrame = water_used_by_source(zone)

    collated_res = hcat(collated, irrig_ws[:, setdiff(names(irrig_ws), [:Date])])

    return collated_res, field_logs
end


function create(data::Dict{Symbol}, climate_data::Climate)::FarmZone
    spec = deepcopy(data)

    if haskey(spec, :component)
        _ = pop!(spec, :component)
    end

    name = spec[:name]
    water_specs::Dict{Symbol, Dict} = spec[:water_source_spec]
    pump_specs::Dict{Symbol, Dict} = spec[:pump_spec]

    water_sources::Array{WaterSource} = create(water_specs, pump_specs)

    # This will be used in future to provide list of irrigations/crops that could be considered
    # crop_specs::Dict{Symbol, Dict} = spec[:crop_spec]
    # irrig_spec::Dict{Symbol, Dict} = spec[:irrigation_spec]

    field_specs = deepcopy(spec[:fields])
    for (fk, f) in field_specs
        f[:irrigation] = create(collect(values(f[:irrigation_spec]))[1])
        f[:crop_rotation] = [create(c, climate_data.time_steps[1]) 
                             for c in collect(values(f[:crop_rotation_spec]))]
        f[:crop] = f[:crop_rotation][1]

        # Clean up unneeded specs
        delete!(f, :irrigation_spec)
        delete!(f, :crop_rotation_spec)
    end
    
    fields = [create(v) for (k,v) in field_specs]

    zone_spec::Dict{Symbol, Any} = Dict(
        :name => name,
        :climate => climate_data,
        :fields => fields,
        :water_sources => water_sources
    )

    zone = FarmZone(; zone_spec...)

    return zone
end

function reset!(z::FarmZone)::Nothing
    for f in z.fields
        reset!(f)

        initial_dt = z.climate.time_steps[1]

        f._next_crop_idx = 1
        set_next_crop!(z.manager, f, initial_dt)
        
    end

    return
end
