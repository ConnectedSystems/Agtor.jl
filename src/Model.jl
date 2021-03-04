"""
Run model for a single zone.

    run_model(zone, ts_func, callback_func)

Parameters
----------
zone : Zone AgComponent
ts_func : Function, defining actions for a time step.
        Must accept a Manager, zone, int, and Date/DateTime
        `ts_func(manager, zone, idx, dt)`

        All operations must be in-place as changes will not propagate.
pre : Function, defines additional actions for `zone` that occur 
        at end of time step `dt_i`:

        `callback_func(zone, dt_i)`
post : Function, defines additional actions for `zone` that occur 
                at end of time step `dt_i`:

                `callback_func(zone, dt_i)`

Returns
----------
DataFrame : results
"""
function run_model(zone::FarmZone, ts_func::Function; pre::Union{Function, Nothing}=nothing, post::Union{Function, Nothing}=nothing)
    
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
