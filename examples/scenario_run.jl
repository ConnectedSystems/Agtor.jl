"""
Running scenarios one after the other.
"""

using DataFrames, CSV, FileIO, Dates
using BenchmarkTools
using Agtor

import Agtor: run_model
import OrderedCollections: LittleDict


# Start month/day of growing season
# Represents when water allocations are announced.
const gs_start = (5, 1)

function setup_zone(data_dir::String="test/data/")
    zone_spec_dir::String = "$(data_dir)zones"
    zone_params::Dict{Symbol, Dict} = load_spec(zone_spec_dir)

    return create(zone_params[:Zone_1])
end


"""
Allocation callback for example.
"""
function allocation_callback!(zone, dt_i)

    # Resetting allocations for example run
    if monthday(dt_i) == gs_start
        # Example annual water allocations
        allocs = (surface_water=150.0, groundwater=40.0)

        update_available_water!(zone, allocs)
    end
end


"""
Run scenarios in sequence, and save results as they complete.

Compared to storing all results and saving in one go, this approach
is slower overall, but does not use as much memory.
"""
function example_scenario_run(data_dir::String="test/data/")::Nothing
    z1 = setup_zone(data_dir)

    scen_data = joinpath(data_dir, "scenarios", "sampled_params.csv")
    samples = DataFrame!(CSV.File(scen_data))

    tmp_z = deepcopy(z1)
    tmp_z.manager = BaseManager("test")
    @sync for (row_id, r) in enumerate(eachrow(samples))
        update_model!(tmp_z, r)

        results = run_model(tmp_z, run_timestep!, allocation_callback!)

        # Save results as they complete
        @async save_results!("async_save.jld2", string(row_id), results)
    end
end


"""
Same example as above, but collect all results before saving.

Should be faster than the first example (for the small number of scenarios run) as all
results are kept in memory until the end.
"""
function example_batch_save(data_dir::String="test/data/")::Nothing
    z1 = setup_zone(data_dir)

    scen_data = joinpath(data_dir, "scenarios", "sampled_params.csv")
    samples = DataFrame!(CSV.File(scen_data))

    all_results = Dict()
    tmp_z = deepcopy(z1)
    tmp_z.manager = BaseManager("test")
    for (row_id, r) in enumerate(eachrow(samples))
        update_model!(tmp_z, r)

        zone_results, field_results = run_model(tmp_z, run_timestep!, allocation_callback!)
        all_results[row_id] = (zone_results, field_results)
    end

    save_results!("batch_run.jld2", all_results)
end


@btime example_scenario_run()
@btime example_batch_save()


# Loading and displaying results
saved_results = load("async_save.jld2")
@info saved_results
