import Agtor: set_next_crop!, update_stages!, in_season, load_yaml
using Agtor, Dates, CSV
using Test

import Flatten


function setup_zone(data_dir::String="test/data/")
    climate_dir::String = "$(data_dir)climate/"  
    tgt::String = climate_dir * "farm_climate_data.csv"

    use_threads = Threads.nthreads() > 1
    data = DataFrame!(CSV.File(tgt, threaded=use_threads, dateformat="dd-mm-YYYY"))
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
            ini_head = 25.0
            allocation = 50.0
        else
            ini_head = 0.0
            allocation = 225.0
        end

        pump_name = v["name"]
        v["pump"] = create(Pump, pump_specs[pump_name])
        v["head"] = ini_head
        v["allocation"] = allocation
        
        ws::WaterSource = create(WaterSource, v)
        push!(w_specs, ws)
    end

    f1_spec::Dict{Symbol, Any} = Dict(
        :name => "field1",
        :total_area_ha => 100.0,
        :irrigation => irrig,
        :crop => crop_rotation[1],
        # :crop_choices => crop_rotation,
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


function test_in_season()
    dt = Date("2010-03-01")
    s_start = Date("2010-01-01")
    s_end = Date("2010-05-01")

    @test in_season(dt, s_start, s_end) == true
end


function test_out_of_season()
    dt = Date("2009-03-01")
    s_start = Date("2010-01-01")
    s_end = Date("2010-05-01")

    @test in_season(dt, s_start, s_end) == false


    # Should return false because in_season is start and end exclusive
    dt = Date("2010-01-01")
    @test in_season(dt, s_start, s_end) == false
end


function test_crop_plantings()
    z1, (deeplead, channel_water) = setup_zone()
    field = z1.fields[1]

    for _ in field.crop_rotation
        crop = field.crop
        @test (crop.plant_date + crop.harvest_offset) == crop.harvest_date

        set_next_crop!(field, crop.harvest_date)
    end
end


function test_crop_update_stages()
    z1, (deeplead, channel_water) = setup_zone()
    crop = z1.fields[1].crop

    update_stages!(crop, Date("2010-01-01"))

    for (k,v) in crop.growth_stages
        @test (v[:start] + Dates.Day(v[:stage_length])) == v[:end]
    end
end


function test_pump_creation(data_dir::String="test/data/")
    pump_spec_dir::String = "$(data_dir)pumps/"
    pump_specs::Dict{String, Dict} = load_yaml(pump_spec_dir)

    pumps = Pump[create(Pump, spec) for (pn, spec) in pump_specs]

    for created in pumps
        @test created isa Pump
        @info Flatten.flatten(created)
    end
end


function test_parameter_extraction(data_dir::String="test/data/")
    pump_spec_dir::String = "$(data_dir)pumps/"
    pump_specs::Dict{String, Dict} = load_yaml(pump_spec_dir)

    @info pump_specs
end


@testset "Agtor.jl" begin

    test_parameter_extraction()


    
    test_in_season()
    test_out_of_season()

    test_crop_plantings()
    test_crop_update_stages()

    test_pump_creation()

    

end
