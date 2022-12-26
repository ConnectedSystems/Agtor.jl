using DataFrames, CSV, FileIO, Dates
using BenchmarkTools
using Agtor

import Agtor: run_model
import OrderedCollections: LittleDict


# Start month/day of growing season
# Represents when water allocations are announced.
const gs_start = (5, 1)


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
    z1 = setup_zone()
    z1.manager = EconManager("test")

    scen_data = joinpath(HERE, "data", "scenarios", "sampled_params.csv")
    samples = DataFrame!(CSV.File(scen_data))

    @sync for (row_id, r) in enumerate(eachrow(samples))
        tmp_z = deepcopy(z1)
        tmp_z = update_model!(tmp_z, r)

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
function example_batch_save(; data_dir::String="test/data/", output_fn::String="test_batch_save.jld2")::Nothing
    z1 = setup_zone()
    z1.manager = EconManager("test")

    scen_data = joinpath(HERE, "data", "scenarios", "sampled_params.csv")
    samples = CSV.read(scen_data, DataFrame)

    results = run_scenarios!(samples, z1; post=allocation_callback!)

    save_results!(output_fn, results)
end


@testset "Ensure irrigation occurs" begin
    zone = setup_zone()

    # Create temporary directory that is cleaned up on process exit
    temp_dir = mktempdir()
    fn = joinpath(temp_dir, "test_batch_save.jld2")

    example_batch_save(output_fn=fn)
    saved_results = load(fn)

    df = collate_results(saved_results, "zone_results", "irrigated_yield_sum")

    # compiled_results = for (idx, res) in results
    #     res_df = collate_results(res, "zone_results", "irrigated_yield_sum")
    #     res_stats = [scenario_stats(res_df, "$(i)/z") for i in 1:length(samples)]
    #     result_set = DataFrame(res_stats)
    #     mean(result_set[:total])
    # end

    scen_stats = scenario_stats(df, "1/zone")

    @test !isnan(scen_stats.mean)
    @test !isnan(scen_stats.median)
    @test !isnan(scen_stats.total)

    @test scen_stats.mean != 0.0
    @test scen_stats.median != 0.0
    @test scen_stats.total != 0.0
end
