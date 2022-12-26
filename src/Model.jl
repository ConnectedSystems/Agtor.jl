using Distributed


"""
    run_model(zone::FarmZone; ts_func::Function=run_timestep!, pre::Union{Function, Nothing}=nothing, post::Union{Function, Nothing}=nothing)::NamedTuple

Run model for a single zone.

# Arguments
- zone : Zone AgComponent
- ts_func : Function, defining actions for a time step.
        Must accept a Manager, zone, int, and Date/DateTime
        `ts_func(manager, zone, idx, dt)`
        All operations must be in-place as changes will not propagate.
- pre : Function, defines additional actions for `zone` that occur 
        at end of time step `dt_i`:
        `callback_func(zone, dt_i)`
- post : Function, defines additional actions for `zone` that occur 
         at end of time step `dt_i`:
         `callback_func(zone, dt_i)`

# Returns
NamedTuple : results
"""
function run_model(zone::FarmZone; ts_func::Function=run_timestep!, pre::Union{Function, Nothing}=nothing, post::Union{Function, Nothing}=nothing)::NamedTuple
    
    time_sequence = zone.climate.time_steps

    @inbounds for (idx, dt_i) in enumerate(time_sequence)
        if !isnothing(pre)
            pre(zone, dt_i)
        end

        ts_func(zone.manager, zone, idx, dt_i)

        if !isnothing(post)
            post(zone, dt_i)
        end
    end

    return collect_results(zone)
end


"""Run timestep for all zones within a basin."""
function run_timestep!(basin::Basin, ts_func; pre::Union{Function, Nothing}=nothing, post::Union{Function, Nothing}=nothing)

    idx, dt_i = basin.current_ts

    for z in basin.zones
        if !isnothing(pre)
            pre(z, dt_i)
        end

        ts_func(z.manager, z, idx, dt_i)

        if !isnothing(post)
            post(z, dt_i)
        end
    end

    advance_timestep!(basin)
end


"""Run scenario for an entire basin."""
function run_model(basin::Basin, ts_func::Function; pre::Union{Function, Nothing}=nothing, post::Union{Function, Nothing}=nothing)
    for i in basin.climate.time_steps
        run_timestep!(basin, ts_func; pre=pre, post=post)
    end

    return collect_results(basin)
end


function advance_timestep!(basin)::Nothing
    idx::Int64, _ = basin.current_ts
    next_idx::Int64 = idx+1
    dt = nothing

    try
        dt = basin.climate.time_steps[next_idx]
    catch e
        if e isa BoundsError
            return
        end

        throw(e)
    end

    if isnothing(dt)
        throw(ArgumentError("datetime cannot be nothing"))
    end
    
    basin.current_ts = (idx=next_idx, dt=dt)

    return
end


"""
Run zone level scenarios for a given sample set.

Returns Dict with keys:
    "scenario_id/zone_results" = zone level results
    "scenario_id/field_results" = field level results
"""
function run_scenarios!(samples::DataFrame, zone::FarmZone, ts_func::Function; 
                        pre::Union{Function, Nothing}=nothing, post::Union{Function, Nothing}=nothing)::Dict
    results = @sync @distributed (hcat) for row_id in 1:nrow(samples)
        tmp_z = deepcopy(zone)
        update_model!(tmp_z, samples[row_id, :])
        res = run_model(tmp_z, ts_func; pre=pre, post=post)

        # Return pair of scenario_id and results
        string(row_id), res
    end

    # Prep results into expected form
    transformed = Dict()
    for (idx, res) in results
        transformed["$(idx)/zone_results"] = res.zone_results
        transformed["$(idx)/field_results"] = res.field_results
    end

    return transformed
end


"""
Run basin level scenarios for a given sample set.

Returns Dict with keys:
    "scenario_id/zone_results" = zone level results for each zone in basin
    "scenario_id/field_results" = field level results for each zone in basin
"""
function run_scenarios!(samples::DataFrame, basin::Basin, ts_func::Function; 
                        pre::Union{Function, Nothing}=nothing, post::Union{Function, Nothing}=nothing)::Dict
    results = @sync @distributed (hcat) for row_id in 1:nrow(samples)
        tmp_b = deepcopy(basin)
        update_model!(tmp_b, samples[row_id, :])
        res = run_model(tmp_b, ts_func; pre=pre, post=post)

        # Return pair of scenario_id and results
        string(row_id), res
    end

    # # Prep results into expected form
    transformed = Dict()
    for (idx, res) in results
        transformed["$(idx)/zone_results"] = Dict(
            k => v.zone_results for (k, v) in res
        )
        transformed["$(idx)/field_results"] = Dict(
            k => v.field_results for (k, v) in res
        )
    end

    return transformed
end


# todo
struct BasinResults
end

struct ZoneResults
end


# """
# Setup a model with a specific timestep function.
# """
# function setup_model(catchment::Union{FarmZone, Basin}, ts_func::Function; pre::Union{Function, Nothing}=nothing, post::Union{Function, Nothing}=nothing)
#     function run_model(catchment::Union{FarmZone, Basin})
#         time_sequence = catchment.climate.time_steps
#         @inbounds for (idx, dt_i) in enumerate(time_sequence)
#             if !isnothing(pre)
#                 pre(catchment, dt_i)
#             end

#             ts_func(catchment.manager, catchment, idx, dt_i)

#             if !isnothing(post)
#                 post(catchment, dt_i)
#             end
#         end

#         return collect_results(catchment)
#     end

#     return run_model
# end
