"""
Example usage of Agtor which distributes runs across available processors.
"""

using CSV
using Dates
using DataStructures, DataFrames
using Agtor
using Flatten
using Distributed, FileIO, Glob
using JLD2

using Profile, BenchmarkTools, OwnTime, Logging

addprocs(3, exeflags="--project=.")


@everywhere using CSV
@everywhere using Dates
@everywhere using DataStructures, DataFrames
@everywhere using Agtor
@everywhere using Flatten
# @everywhere using FileIO

# Assumes we are in top-level project dir
# julia --project=.

# Start with the environment variable set for multi-threading
# $ JULIA_NUM_THREADS=4 ./julia

# Windows:
# $ set JULIA_NUM_THREADS=4 && julia dev.jl
# $ set JULIA_NUM_THREADS=4 && julia --project=.


# Start month/day of growing season
# Represents when water allocations start getting announced.
@everywhere const gs_start = (5, 1)

@everywhere function setup_zone(data_dir::String="test/data/")
    zone_spec_dir::String = "$(data_dir)zones"
    # zone_specs::Dict{String, Dict} = load_yaml(zone_spec_dir)
    # zone_params = generate_agparams("", zone_specs["Zone_1"])
    zone_params::Dict{Symbol, Dict} = load_spec(zone_spec_dir)

    collated_specs::Array = []
    agparams = collect_agparams!(zone_params[:Zone_1], collated_specs; ignore=[:crop_spec])

    climate_data::String = "$(data_dir)climate/farm_climate_data.csv"

    # Expect only CSV for now...
    if endswith(climate_data, ".csv")
        use_threads = Threads.nthreads() > 1
        climate_seq = DataFrame!(CSV.File(climate_data, threaded=use_threads, dateformat="dd-mm-YYYY"))
    else
        error("Currently, climate data can only be provided in CSV format")
    end

    climate::Climate = Climate(climate_seq)

    return create(zone_params[:Zone_1], climate), agparams
end


@everywhere function run_model(farmer, zone)
    """
    An example model run.

    Per-time step interactions between other models should be defined here.
    """
    time_sequence = zone.climate.time_steps
    @inbounds for dt_i in time_sequence
        run_timestep(farmer, zone, dt_i)

        # Resetting allocations for test run
        if monthday(dt_i) == gs_start
            for ws in zone.water_sources
                if ws.name == "surface_water"
                    ws.allocation = 150.0
                elseif ws.name == "groundwater"
                    ws.allocation = 40.0
                end
            end
        end
    end

    zone_results, field_results = collect_results(zone)

    return zone_results, field_results
end


function test_short_run(data_dir::String="test/data/")::Tuple{DataFrame,Dict}
    z1, agparams = setup_zone(data_dir)

    farmer = Manager("test")
    zone_results, field_results = run_model(farmer, z1)

    return zone_results, field_results
end


"""
Run example scenarios by distributing these across available cores.
Results are saved to a file on completion, based on scenario id.
"""
function test_scenario_run(data_dir::String="test/data/", result_dir::String="")::Nothing
    z1, agparams = setup_zone(data_dir)

    scen_data = joinpath(data_dir, "scenarios", "sampled_params.csv")
    samples = DataFrame!(CSV.File(scen_data))

    farmer = Manager("test")

    @sync @distributed (hcat) for row_id in 1:nrow(samples)
        tmp_z = update_model(z1, samples[row_id, :])
        res = run_model(farmer, tmp_z)

        pth = joinpath(result_dir, "sampled_params_batch_run_distributed_$(row_id).jld2")
        save_results!(pth, string(row_id), res)
    end

    fn_pattern = joinpath(result_dir, "sampled_params_batch_run_distributed_*.jld2")
    collate_results!(fn_pattern, "dist_collated.jld2")

    return
end

# @btime test_short_run()

@time test_scenario_run()


# imported_res = load("dist_collated.jld2")
# @info imported_res