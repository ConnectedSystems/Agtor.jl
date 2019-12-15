include("Agtor.jl")

using CSV
using .Agtor


function setup_zone(data_dir::String="../test/data/")
    climate_dir = "$(data_dir)climate/"  
    tgt = climate_dir * "farm_climate_data.csv"
    data = CSV.read(tgt, threaded=true, dateformat="dd-mm-YYYY")
    climate_data = Climate(data)

    crop_dir = "$(data_dir)crops/"
    crop_data = load_yaml(crop_dir)
    crop_rotation = [Crop.create(data) for data in crop_data.values()]

    irrig_dir = "$(data_dir)irrigations/"
    irrig_specs = load_yaml(irrig_dir)
    for v in irrig_specs.values()
        # implemented can be set at the field or zone level...
        irrig = Irrigation.create(v)
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
        else
            # pump = Pump('surface_water', 2000.0, 1, 5, 0.05, 0.2, True, 0.7, 0.28, 0.75)
            pump_name = "surface_water"
            ini_head = 0.0
        end

        pump = Pump.create(pump_specs[pump_name])
        ws = WaterSource.create(v)
        ws.pump = pump
        ws.head = ini_head
        w_specs.append(ws)
    end

    field1 = CropField("field1", 100.0, irrig, crop_rotation, 100.0, 20.0, 100.0)
    field2 = CropField("field2", 90.0, irrig, crop_rotation, 100.0, 30.0, 90.0)

    z1 = FarmZone("Zone_1", 
                  climate=climate_data,
                  fields=[field1, field2],
                  water_sources=w_specs,
                  allocation=Dict("surface_water" => 225.0, "groundwater" => 50.0))
    return z1, w_specs
end

function test_short_run()
    z1, (deeplead, channel_water) = setup_zone()

    farmer = Manager()
    zone = FarmZone("test_farm")

    for dt_i in time_sequence[1:(365*5)]
        run_timestep(farmer, zone, dt_i)
    end

    # time_sequence = z1.climate.time_steps

    # start = timer()
    # result_set = {f.name: {} for f in z1.fields}
    # for dt_i in time_sequence[0:(365*5)]:
    #     if (dt_i.month == 5) and (dt_i.day == 15):
    #         # reset allocation for test
    #         z1.water_sources['groundwater'].allocation = 50.0
    #         z1.water_sources['surface_water'].allocation = 125.0
    #     end

    #     res = z1.run_timestep(farmer, dt_i)

    #     if res is not None:
    #         for f in z1.fields:
    #             result_set[f.name].update(res[f.name])
    #         end
    #     end
    # end
    # t_end = timer()

    # scenario_result = {}
    # for f in z1.fields:
    #     scenario_result[f.name] = pd.DataFrame.from_dict(result_set[f.name], 
    #                                                      orient='index')
    # end

    # print(scenario_result)

    # print("Finished in:", timedelta(seconds=end-start))
end

test_short_run()