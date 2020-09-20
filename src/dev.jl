import Revise

using Profile, BenchmarkTools, OwnTime, Logging

using JLD2, HDF5, CSV
using Dates
using DataStructures
using DataFrames
using Agtor
using Flatten

# Assumes we are in top-level project dir
# julia --project=.

# Start with the environment variable set for multi-threading
# $ JULIA_NUM_THREADS=4 ./julia

# Windows:
# $ set JULIA_NUM_THREADS=4 && julia dev.jl
# $ set JULIA_NUM_THREADS=4 && julia --project=.
# $ julia --project=. -p 4


# Start month/day of growing season
# Represents when water allocations start getting announced.
const gs_start = (5, 1)

function setup_zone(data_dir::String="test/data/")
    zone_spec_dir::String = "$(data_dir)zones/"
    zone_specs::Dict{String, Dict} = load_yaml(zone_spec_dir)

    climate_data::String = "$(data_dir)climate/farm_climate_data.csv"

    # Expect only CSV for now...
    if endswith(climate_data, ".csv")
        use_threads = Threads.nthreads() > 1
        climate_seq = DataFrame!(CSV.File(climate_data, threaded=use_threads, dateformat="dd-mm-YYYY"))
    else
        error("Currently, climate data can only be provided in CSV format")
    end

    climate::Climate = Climate(climate_seq)
    return [create(z_spec, climate) for (z_name, z_spec) in zone_specs]
end

function test_short_run(data_dir::String="test/data/")::Tuple{DataFrame,Dict}
    # z1, (deeplead, channel_water) = setup_zone(data_dir)
    zones = setup_zone(data_dir)
    z1 = zones[1]

    farmer = Manager("test")
    time_sequence = z1.climate.time_steps
    @inbounds for dt_i in time_sequence
        run_timestep(farmer, z1, dt_i)

        # Resetting allocations for test run
        if monthday(dt_i) == gs_start
            for ws in z1.water_sources
                if ws.name == "surface_water"
                    ws.allocation = 150.0
                elseif ws.name == "groundwater"
                    ws.allocation = 40.0
                end
            end
        end
    end

    zone_results, field_results = collect_results(z1)

    # TODO:
    # Under debug mode or something
    # [] Provide copy of (seasonal) rainfall
    # [] Leftover allocations
    # [x] time series of SWD (after rainfall)
    # [x] time series of SWD (after irrigation)

    # For reporting results:
    # [x] irrigated area for season
    # [x] ML/ha used
    # [x] $/ML used
    # [x] $/ha generated
    # [x] yield/ha

    return zone_results, field_results
end


# Run twice to get compiled performance
@time zone_results, field_results = test_short_run()
@time zone_results, field_results = test_short_run()

# CSV.write("dev_result.csv", zone_results)

function save_results(fn, results)
    jldopen(fn, "w") do file
        for i in results
            g = g_create(file, i) # create a group
            g["zone_results"] = zone_results
            g["field_results"] = field_results
        end
    end
end


# Write out to Julia HDF5
jldopen("test.jld", "w") do file
    g = g_create(file, "zone_1") # create a group
    g["zone_results"] = zone_results
    g["field_results"] = field_results
end

zone_results = jldopen("test.jld", "r") do file
    read(file, "zone_1")
end

imported_res = jldopen("test.jld", "r") do file
    read(file)
end


@profile zone_results, field_results = test_short_run()

# io = open("log.txt", "w+")
# logger = SimpleLogger(io, Logging.Debug)
# with_logger(logger) do
#     @time results = test_short_run()    
# end
# flush(io)
# close(io)
