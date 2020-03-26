include("Agtor.jl")

using Profile

using CSV
using Dates
using DataStructures
using .Agtor

# Start with the environment variable set for multi-threading
# $ JULIA_NUM_THREADS=4 ./julia

# Windows:
# $ set JULIA_NUM_THREADS=4 && julia dev.jl

# Start month/day of growing season
const gs_start = (5, 15)

function setup_zone(data_dir::String="../test/data/")
    climate_dir = "$(data_dir)climate/"  
    tgt = climate_dir * "farm_climate_data.csv"

    use_threads = Threads.nthreads() > 1
    data = CSV.read(tgt, threaded=use_threads, dateformat="dd-mm-YYYY")
    climate_data = Climate(data)

    crop_dir = "$(data_dir)crops/"
    crop_data = load_yaml(crop_dir)
    crop_rotation = [create(Crop, data) for data in values(crop_data)]

    irrig_dir = "$(data_dir)irrigations/"
    irrig_specs = load_yaml(irrig_dir)
    irrig = nothing
    for v in values(irrig_specs)
        # `implemented` can be set at the field or zone level...
        irrig = create(Irrigation, v)
    end

    water_spec_dir = "$(data_dir)water_sources/"
    pump_spec_dir = "$(data_dir)pumps/"
    water_specs = load_yaml(water_spec_dir)
    pump_specs = load_yaml(pump_spec_dir)
    w_specs = []
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
        
        ws = create(WaterSource, v)
        push!(w_specs, ws)
    end

    f1_spec = Dict(
        :name => "field1",
        :total_area_ha => 100.0,
        :irrigation => irrig,
        :crop => crop_rotation[1],
        :crop_choices => crop_rotation,
        :crop_rotation => crop_rotation,
        :soil_TAW => 100.0,
        :soil_SWD => 20.0
    )
    f2_spec = copy(f1_spec)
    f2_spec[:name] = "field2"
    f2_spec[:total_area_ha] = 90.0
    field1 = CropField(; f1_spec...)
    field2 = CropField(; f2_spec...)

    zone_spec = Dict(
        :name => "Zone_1",
        :climate => climate_data,
        :fields => [field1, field2],
        :water_sources => w_specs
    )

    z1 = FarmZone(; zone_spec...)

    return z1, w_specs
end

function test_short_run(data_dir::String="../test/data/")
    z1, (deeplead, channel_water) = setup_zone(data_dir)

    farmer = Manager()
    time_sequence = z1.climate.time_steps
    for dt_i in time_sequence
        run_timestep(farmer, z1, dt_i)

        # Resetting allocations for test run
        if monthday(dt_i) == gs_start
            for ws in z1.water_sources
                if ws.name == "surface_water"
                    ws.allocation = 100.0
                elseif ws.name == "groundwater"
                    ws.allocation = 40.0
                end
            end
        end
    end

    incomes::OrderedDict, irrigations::OrderedDict = collect_results(z1)

    # println(collect_results(z1; last=true))

    # println(incomes)
    # println(irrigations)
    return incomes, irrigations
end

expected_income = OrderedDict(Date("1981-09-08") => 244313.98386267252,Date("1982-09-08") => -11559.59643529012,Date("1983-09-13") => 92551.26805889815,Date("1984-12-27") => 63808.03614607529,Date("1985-09-08") => 42891.25808561602,Date("1986-09-13") => 42253.431939398,Date("1987-12-27") => 89334.9343651311,Date("1988-09-08") => 143959.55745592792,Date("1989-09-13") => 59088.939975231166,Date("1990-12-27") => 63651.484236312834,Date("1991-09-08") => 78292.45108649295,Date("1992-09-13") => 43015.00489135986,Date("1993-12-27") => 153073.4176533377,Date("1994-09-08") => -9426.0,Date("1995-09-13") => 36746.97385739302,Date("1996-12-27") => 130187.89452390373,Date("1997-09-08") => 75731.22454594003,Date("1998-09-13") => 8311.450494144456,Date("1999-12-27") => 99047.47775346626,Date("2000-09-08") => 67664.07867661327,Date("2001-09-13") => 16699.254527614954,Date("2002-12-27") => -10575.742340466755,Date("2003-09-08") => 91908.97796981408,Date("2004-09-13") => 19268.445972084148,Date("2005-12-27") => 87647.3240923745,Date("2006-09-08") => -9426.0,Date("2007-09-13") => 13406.167553121915,Date("2008-12-27") => 62812.717770092786,Date("2009-09-08") => 48258.298524112804,Date("2010-09-13") => 60415.07118181099,Date("2011-12-27") => 95337.84548624678,Date("2012-09-08") => 43248.923464677544,Date("2013-09-13") => 32359.549025852994,Date("2014-12-27") => 73688.79360696144,Date("2015-09-08") => 274.4833330613601,Date("2016-09-13") => 61266.286087214576)
expected_irrigations = OrderedDict(Date("1981-09-08") => 70.46271999999999,Date("1982-09-08") => 33.991533969407996,Date("1983-09-13") => 43.42294326801344,Date("1984-12-27") => 78.35036066266281,Date("1985-09-08") => 0.0,Date("1986-09-13") => 88.38022,Date("1987-12-27") => 1.1603262350945443e-15,Date("1988-09-08") => 39.477536,Date("1989-09-13") => 79.970965835936,Date("1990-12-27") => 77.02590665560061,Date("1991-09-08") => 0.0,Date("1992-09-13") => 92.23339999999999,Date("1993-12-27") => 24.289034307948416,Date("1994-09-08") => 0.0,Date("1995-09-13") => 92.22252,Date("1996-12-27") => 0.0,Date("1997-09-08") => 44.636144,Date("1998-09-13") => 100.698236069296,Date("1999-12-27") => 14.292297464335594,Date("2000-09-08") => 0.0,Date("2001-09-13") => 128.5565365354881,Date("2002-12-27") => 23.136858980352,Date("2003-09-08") => 0.0,Date("2004-09-13") => 93.47604,Date("2005-12-27") => 32.217683196703994,Date("2006-09-08") => 0.0,Date("2007-09-13") => 91.30356,Date("2008-12-27") => 0.0,Date("2009-09-08") => 79.80636799999999,Date("2010-09-13") => 70.26552617683201,Date("2011-12-27") => 82.51460326800809,Date("2012-09-08") => 0.0,Date("2013-09-13") => 133.7348535919069,Date("2014-12-27") => 0.0,Date("2015-09-08") => 69.63687999999999,Date("2016-09-13") => 0.0)

# Run twice to get compiled performance
income, irrigations = test_short_run()

# println(income)
# println(irrigations)

try
    @assert income == expected_income
    @assert irrigations == expected_irrigations
catch e
    println("$e")
end


using Logging

io = open("log.txt", "w+")  # Open a textfile for writing
logger = SimpleLogger(io)  # Create a simple logger

global_logger(logger)  # Set the global logger to logger

test_short_run()

flush(io)  # write out any buffered messages
close(io)


@time comp_income, comp_irrigations = test_short_run()

try
    @assert comp_income == expected_income
    @assert comp_irrigations == expected_irrigations
catch e
    println("$e")
end

# println(comp_income, comp_irrigations)

# using ProfileView

# Profile.clear_malloc_data()  # Ignore this one - forces compilation of target function
# @profile test_short_run()

# Profile.clear_malloc_data()
# @profile test_short_run()
# Profile.print(format=:flat, sortedby=:count)
# @profview test_short_run()  # Ignore this one - only to invoke pre-compilation
# @profview test_short_run()

# using DataFrames
# col_income = collect(values(comp_income))
# col_irrigations = collect(values(comp_irrigations))

# res = DataFrame(Dict("Index"=>collect(keys(comp_income)),
#                "Income" => col_income, 
#                "Irrigation" => col_irrigations)
# )

# CSV.write("dev_result.csv", res)