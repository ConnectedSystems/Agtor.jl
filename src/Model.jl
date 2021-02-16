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
function run_model(zone, ts_func::Function; pre::Union{Function, Nothing}=nothing, post::Union{Function, Nothing}=nothing)
    
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
