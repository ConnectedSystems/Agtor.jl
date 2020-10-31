"""
Running scenarios one after the other.
"""

using DataFrames, CSV, FileIO, Dates
using BenchmarkTools
using Agtor

import OrderedCollections: LittleDict


# Start month/day of growing season
# Represents when water allocations are announced.
const gs_start = (5, 1)

function setup_zone(data_dir::String="test/data/")
    zone_spec_dir::String = "$(data_dir)zones"
    zone_params::Dict{Symbol, Dict} = load_spec(zone_spec_dir)

    # collated_specs::Array = []
    # agparams = collect_agparams!(zone_params[:Zone_1], collated_specs; ignore=[:crop_spec])

    return create(zone_params[:Zone_1])
end


function run_model(farmer, zone)
    time_sequence = zone.climate.time_steps
    allocs = LittleDict("surface_water"=> 150.0, "groundwater" => 40.0)
    @inbounds for (idx, dt_i) in enumerate(time_sequence)
        run_timestep(farmer, zone, idx, dt_i)

        # Resetting allocations for example run
        if monthday(dt_i) == gs_start
            update_available_water!(zone, allocs)
        end
    end

    zone_results, field_results = collect_results(zone)

    return zone_results, field_results
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

    farmer = BaseManager("test")

    tmp_z = deepcopy(z1)
    @sync for (row_id, r) in enumerate(eachrow(samples))
        update_model!(tmp_z, r)

        results = run_model(farmer, tmp_z)

        # Save results as they complete
        @async save_results!("async_save.jld2", string(row_id), results)
    end
end


"""
Same example as above, but collect all results before saving.

Faster than the first example (for the small number of scenarios run) as all 
results are kept in memory until the end.
"""
function example_batch_save(data_dir::String="test/data/")::Nothing
    z1 = setup_zone(data_dir)

    scen_data = joinpath(data_dir, "scenarios", "sampled_params.csv")
    samples = DataFrame!(CSV.File(scen_data))

    farmer = BaseManager("test")

    all_results = Dict()
    tmp_z = deepcopy(z1)
    for (row_id, r) in enumerate(eachrow(samples))
        update_model!(tmp_z, r)

        zone_results, field_results = run_model(farmer, tmp_z)
        all_results[row_id] = (zone_results, field_results)
    end

    save_results!("batch_run.jld2", all_results)
end


@btime example_scenario_run()
@btime example_batch_save()

using ProfileView
@profview example_scenario_run()
@profview example_scenario_run()


# Loading and displaying results
saved_results = load("async_save.jld2")
@info saved_results
