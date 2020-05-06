import Agtor

using Profile, BenchmarkTools, OwnTime, Logging

using CSV
using Dates
using DataStructures
using DataFrames
using Agtor

# Start with the environment variable set for multi-threading
# $ JULIA_NUM_THREADS=4 ./julia

# Windows:
# $ set JULIA_NUM_THREADS=4 && julia dev.jl

# Start month/day of growing season
const gs_start = (5, 1)

function setup_zone(data_dir::String="../test/data/")
    climate_dir::String = "$(data_dir)climate/"  
    tgt::String = climate_dir * "farm_climate_data.csv"

    use_threads = Threads.nthreads() > 1
    data = CSV.read(tgt, threaded=use_threads, dateformat="dd-mm-YYYY")
    climate_data::Climate = Climate(data)

    climate_data.time_steps[1]

    crop_dir::String = "$(data_dir)crops/"
    crop_data::Dict{String, Dict} = load_yaml(crop_dir)
    crop_rotation::Array{Crop} = Crop[create(Crop, data, climate_data.time_steps[1]) for data in values(crop_data)]

    irrig_dir = "$(data_dir)irrigations/"
    irrig_specs::Dict{String, Dict} = load_yaml(irrig_dir)
    irrig = nothing
    # Only 1 irrigation type for now.
    for v in values(irrig_specs)
        # `implemented` can be set at the field or zone level...
        irrig = create(Irrigation, v)
    end

    water_spec_dir::String = "$(data_dir)water_sources/"
    pump_spec_dir::String = "$(data_dir)pumps/"
    water_specs::Dict{String, Dict} = load_yaml(water_spec_dir)
    pump_specs::Dict{String, Dict} = load_yaml(pump_spec_dir)
    w_specs::Array{WaterSource} = []
    for (k, v) in water_specs
        if v["name"] == "groundwater"
            # pump = Pump('groundwater', 2000.0, 1, 5, 0.05, 0.2, True, 0.7, 0.28, 0.75)
            pump_name = "groundwater"
            ini_head = 25.0
            allocation = 50.0
        else
            # pump = Pump('surface_water', 2000.0, 1, 5, 0.05, 0.2, True, 0.7, 0.28, 0.75)
            pump_name = "surface_water"
            ini_head = 0.0
            allocation = 225.0
        end

        v["pump"] = create(Pump, pump_specs[pump_name])
        v["head"] = ini_head  # convert to metre type
        v["allocation"] = allocation
        
        ws::WaterSource = create(WaterSource, v)
        push!(w_specs, ws)
    end

    f1_spec::Dict{Symbol, Any} = Dict(
        :name => "field1",
        :total_area_ha => 100.0,
        :irrigation => irrig,
        :crop => crop_rotation[1],
        :crop_choices => crop_rotation,
        :crop_rotation => crop_rotation,
        :soil_TAW => 100.0,
        :soil_SWD => 20.0
    )
    f2_spec::Dict{Symbol, Any} = copy(f1_spec)
    f2_spec[:name] = "field2"
    f2_spec[:total_area_ha] = 90.0
    field1::CropField = CropField(; f1_spec...)
    field2::CropField = CropField(; f2_spec...)

    zone_spec::Dict{Symbol, Any} = Dict(
        :name => "Zone_1",
        :climate => climate_data,
        :fields => CropField[field1, field2],
        :water_sources => w_specs
    )

    z1::FarmZone = FarmZone(; zone_spec...)

    return z1, w_specs
end

function test_short_run(data_dir::String="../test/data/")::DataFrame
    z1, (deeplead, channel_water) = setup_zone(data_dir)

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

    results = collect_results(z1)

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

    return results
end


# Run twice to get compiled performance
@time results = test_short_run()
@time results = test_short_run()

CSV.write("dev_result.csv", results)

@profile results = test_short_run()

# io = open("log.txt", "w+")
# logger = SimpleLogger(io, Logging.Debug)
# with_logger(logger) do
#     @time results = test_short_run()    
# end
# flush(io)
# close(io)
