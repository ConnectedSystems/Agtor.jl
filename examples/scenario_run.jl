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

    return create(zone_params[:Zone_3])
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
    z1.manager = EconManager("test")

    scen_data = joinpath(data_dir, "scenarios", "sampled_params.csv")
    samples = DataFrame!(CSV.File(scen_data))

    @sync for (row_id, r) in enumerate(eachrow(samples))
        tmp_z = deepcopy(z1)
        update_model!(tmp_z, r)

        results = run_model(tmp_z, run_timestep!; post=allocation_callback!)

        # Save results as they complete
        @async save_results!("async_save.jld2", row_id, results)
    end
end


"""
Same example as above, but collect all results before saving.

Should be faster than the first example (for the small number of scenarios run) as all
results are kept in memory until the end.
"""
function example_batch_save(data_dir::String="test/data/")::Nothing
    z1 = setup_zone(data_dir)
    z1.manager = EconManager("test")

    scen_data = joinpath(data_dir, "scenarios", "sampled_params.csv")
    samples = DataFrame!(CSV.File(scen_data))

    all_results = Dict()
    for (row_id, r) in enumerate(eachrow(samples))
        tmp_z = deepcopy(z1)
        update_model!(tmp_z, r)

        all_results[row_id] = run_model(tmp_z, run_timestep!; post=allocation_callback!)
    end

    save_results!("batch_run.jld2", all_results)
end


# @btime example_scenario_run()
# @btime example_batch_save()


example_batch_save()

# Loading and displaying results
saved_results = load("batch_run.jld2")
# @info saved_results

# @info saved_results["1/zone_results"]

# df = collate_results("batch_run.jld2", "zone_results", "irrigated_yield_sum")
df = collate_results("batch_run.jld2", "zone_results", "dryland_yield_sum")

using Gadfly

col_names = map(Symbol, names(df))
# p = plot(df, x=Row, y=Col.value(col_names...), color=Col.index(col_names...), Geom.line)
p = plot(df, y=Col.value(col_names...), color=Col.index(col_names...), Geom.line)
