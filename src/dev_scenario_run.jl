import Revise
import Agtor

using Profile, BenchmarkTools, OwnTime, Logging

using JLD, HDF5, CSV
using Dates
using DataStructures
using DataFrames
using Agtor
using Flatten
using Infiltrator

# Assumes we are in top-level project dir
# julia --project=.

# Start with the environment variable set for multi-threading
# $ JULIA_NUM_THREADS=4 ./julia

# Windows:
# $ set JULIA_NUM_THREADS=4 && julia dev.jl
# $ set JULIA_NUM_THREADS=4 && julia --project=.


# Start month/day of growing season
# Represents when water allocations start getting announced.
const gs_start = (5, 1)

function setup_zone(data_dir::String="test/data/")
    zone_spec_dir::String = "$(data_dir)zones/"
    zone_specs::Dict{String, Dict} = load_yaml(zone_spec_dir)

    zone_params = generate_agparams("", zone_specs["Zone_1"])

    collated_specs::Array = []
    agparams = collect_agparams!(zone_params, collated_specs; ignore=["crop_spec"])

    climate_data::String = "$(data_dir)climate/farm_climate_data.csv"

    # Expect only CSV for now...
    if endswith(climate_data, ".csv")
        use_threads = Threads.nthreads() > 1
        climate_seq = DataFrame!(CSV.File(climate_data, threaded=use_threads, dateformat="dd-mm-YYYY"))
    else
        error("Currently, climate data can only be provided in CSV format")
    end

    climate::Climate = Climate(climate_seq)

    return create(zone_params, climate), agparams
end


function run_model(farmer, zone)
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


function test_scenario_run(data_dir::String="test/data/")::Array
    z1, agparams = setup_zone(data_dir)

    scen_data = joinpath(data_dir, "scenarios", "sampled_params.csv")
    samples = DataFrame!(CSV.File(scen_data))

    farmer = Manager("test")

    all_results = []
    for r in eachrow(samples)
        tmp_z = modify_params(z1, r)

        zone_results, field_results = run_model(farmer, tmp_z)
        push!(all_results, zone_results)
    end

    return all_results
end

test_short_run()

@btime test_scenario_run()
