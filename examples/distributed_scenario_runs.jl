"""
Example usage of Agtor which distributes runs across available processors.
"""

using Dates, DataFrames, CSV
using Agtor
using Distributed, FileIO, Glob
using JLD2

using Profile, BenchmarkTools, OwnTime, Logging

addprocs(2, exeflags="--project=.")


@everywhere begin

    using Dates, DataFrames, CSV

    using Agtor    

    # Start month/day of growing season
    # Represents when water allocations are announced.
    const gs_start = (5, 1)

    """
    Allocation callback for example.

    Any interactions with other models could be defined in these callbacks
    """
    function allocation_callback!(zone, dt_i)
        # Resetting allocations for example run
        if monthday(dt_i) == gs_start
            # Example annual water allocations
            allocs = (surface_water=150.0, groundwater=40.0)
    
            update_available_water!(zone, allocs)
        end
    end
    
end


"""
Model setup for example run.
"""
function setup_zone(data_dir::String="test/data/")
    zone_spec_dir::String = "$(data_dir)zones"
    zone_params::Dict{Symbol, Dict} = load_spec(zone_spec_dir)

    collated_specs::Array = []
    agparams = collect_agparams!(zone_params[:Zone_1], collated_specs; ignore=[:crop_spec])

    climate_data::String = "$(data_dir)climate/farm_climate_data.csv"
    climate::Climate = load_climate(climate_data)

    return create(zone_params[:Zone_1], climate), agparams
end


"""
Run example scenarios (for a single farm area) by distributing across available cores.
Results are saved to a file on completion, based on scenario id.
"""
function test_scenario_run(data_dir::String="test/data/", result_dir::String="")::Nothing
    z1, agparams = setup_zone(data_dir)

    scen_data = joinpath(data_dir, "scenarios", "sampled_params.csv")
    samples = DataFrame!(CSV.File(scen_data))

    # Each row represents a scenario to run.
    # We distribute these across available cores.
    tmp_z = deepcopy(z1)
    tmp_z.manager = BaseManager("test")
    @sync @distributed (hcat) for row_id in 1:nrow(samples)
        update_model!(tmp_z, samples[row_id, :])
        res = run_model(tmp_z, run_timestep!, allocation_callback!)

        pth = joinpath(result_dir, "sampled_params_batch_run_distributed_$(row_id).jld2")
        save_results!(pth, string(row_id), res)
    end

    # Collate all results into a single JLD2 file
    fn_pattern = joinpath(result_dir, "sampled_params_batch_run_distributed_*.jld2")
    collate_results!(fn_pattern, "dist_collated.jld2")

    return
end


@btime test_scenario_run()

# Loading and displaying results
saved_results = load("dist_collated.jld2")
@info saved_results
