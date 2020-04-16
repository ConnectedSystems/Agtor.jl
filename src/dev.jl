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
const gs_start = (5, 1)

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
                    ws.allocation = 150.0
                elseif ws.name == "groundwater"
                    ws.allocation = 40.0
                end
            end
        end
    end

    incomes::OrderedDict, irrigations::OrderedDict, irrig_ws::OrderedDict = collect_results(z1)

    # TODO:
    # Under debug mode or something
    # * Provide copy of rainfall
    # * Leftover allocations
    # * time series of SWD (?)
    

    # println(incomes)
    # println(irrigations)
    return incomes, irrigations, irrig_ws
end

expected_income = OrderedDict{Date,Float64}(Date("1981-09-08") => 248683.83673146638,Date("1982-09-08") => -10107.585552493996,Date("1983-09-13") => 94652.7641827164,Date("1984-12-27") => 71511.89210086883,Date("1985-09-08") => 42891.25808561602,Date("1986-09-13") => 38721.4217772555,Date("1987-12-27") => 89334.9343651311,Date("1988-09-08") => 144750.68799670527,Date("1989-09-13") => 62012.82084529553,Date("1990-12-27") => 61329.83630500174,Date("1991-09-08") => 78292.45108649295,Date("1992-09-13") => 46428.60393192546,Date("1993-12-27") => 156300.15488156804,Date("1994-09-08") => -9426.0,Date("1995-09-13") => 40372.80635230639,Date("1996-12-27") => 130187.89452390373,Date("1997-09-08") => 72519.9426519837,Date("1998-09-13") => 4850.041281212702,Date("1999-12-27") => 100750.65770198585,Date("2000-09-08") => 67664.07867661327,Date("2001-09-13") => 13934.402323825274,Date("2002-12-27") => -5890.616092651941,Date("2003-09-08") => 91908.97796981408,Date("2004-09-13") => 26023.055489752747,Date("2005-12-27") => 86424.70252009845,Date("2006-09-08") => -9426.0,Date("2007-09-13") => 20230.916002017384,Date("2008-12-27") => 62812.717770092786,Date("2009-09-08") => 26997.6035176571,Date("2010-09-13") => 58004.31089308266,Date("2011-12-27") => 101394.44820234174,Date("2012-09-08") => 43248.923464677544,Date("2013-09-13") => 30119.781468260127,Date("2014-12-27") => 73688.79360696144,Date("2015-09-08") => -12420.261421517933,Date("2016-09-13") => 62000.39461506376)
expected_irrigations = OrderedDict{Date,Float64}(Date("1981-09-08") => 70.46271999999999,Date("1982-09-08") => 20.761662244864,Date("1983-09-13") => 43.713041112903724,Date("1984-12-27") => 86.59260328431924,Date("1985-09-08") => 0.0,Date("1986-09-13") => 48.380219999999994,Date("1987-12-27") => 0.0,Date("1988-09-08") => 39.477536,Date("1989-09-13") => 79.970965835936,Date("1990-12-27") => 57.545352400377276,Date("1991-09-08") => 0.0,Date("1992-09-13") => 92.23339999999999,Date("1993-12-27") => 20.552951742828405,Date("1994-09-08") => 0.0,Date("1995-09-13") => 96.62492,Date("1996-12-27") => 0.0,Date("1997-09-08") => 37.956576,Date("1998-09-13") => 56.297410126479996,Date("1999-12-27") => 31.33960938897873,Date("2000-09-08") => 0.0,Date("2001-09-13") => 88.73004,Date("2002-12-27") => 32.345063135296,Date("2003-09-08") => 0.0,Date("2004-09-13") => 93.47604,Date("2005-12-27") => 15.317187575999968,Date("2006-09-08") => 0.0,Date("2007-09-13") => 96.60252,Date("2008-12-27") => 1.2225896739437303e-15,Date("2009-09-08") => 38.608416000000005,Date("2010-09-13") => 54.812713794592,Date("2011-12-27") => 62.231281206172056,Date("2012-09-08") => 0.0,Date("2013-09-13") => 96.72138000000001,Date("2014-12-27") => 0.0,Date("2015-09-08") => 41.011264000000004,Date("2016-09-13") => 4.111679164879992)

# Run twice to get compiled performance
@time income, irrigations, irrig_ws = test_short_run()

# println(income)
# println(irrigations)

try
    @assert income == expected_income
    @assert irrigations == expected_irrigations
catch e
    println("$e")
end


### Run again for log capture

# using Logging

# io = open("log.txt", "w+")  # Open a textfile for writing
# logger = SimpleLogger(io)  # Create a simple logger

# global_logger(logger)  # Set the global logger to logger

# test_short_run()

# flush(io)  # write out any buffered messages
# close(io)


@time comp_income, comp_irrigations, irrig_ws = test_short_run()

println(irrig_ws)

try
    @assert comp_income == expected_income
    @assert comp_irrigations == expected_irrigations
catch e
    println("$e")
end

using DataFrames
col_income = collect(values(comp_income))
col_irrigations = collect(values(comp_irrigations))

res = DataFrame(Dict("Index"=>collect(keys(comp_income)),
               "Income" => col_income, 
               "Irrigation" => col_irrigations)
)

println(res)

CSV.write("dev_result.csv", res)


### Profiling 

# println(comp_income, comp_irrigations)

# using ProfileView

# Profile.clear_malloc_data()  # Ignore this one - forces compilation of target function
# @profile test_short_run()

# Profile.clear_malloc_data()
# @profile test_short_run()
# Profile.print(format=:flat, sortedby=:count)
# @profview test_short_run()  # Ignore this one - only to invoke pre-compilation
# @profview test_short_run()

