using Agtor, Dates, CSV
using Test
using DataFrames

import Flatten


function setup_zone(data_dir::String="test/data/")
    zone_spec_dir::String = "$(data_dir)zones"
    zone_params::Dict{Symbol, Dict} = load_spec(zone_spec_dir)

    return create(zone_params[:Zone_1])
end


function test_in_season()
    dt = Date("2010-03-01")
    s_start = Date("2010-01-01")
    s_end = Date("2010-05-01")

    @test Agtor.in_season(dt, s_start, s_end) == true
end


function test_out_of_season()
    dt = Date("2009-03-01")
    s_start = Date("2010-01-01")
    s_end = Date("2010-05-01")

    @test Agtor.in_season(dt, s_start, s_end) == false


    # Should return false because in_season is start and end exclusive
    dt = Date("2010-01-01")
    @test Agtor.in_season(dt, s_start, s_end) == false
end


function test_crop_plantings()
    z1 = setup_zone()
    field = z1.fields[1]

    for _ in field.crop_rotation
        crop = field.crop
        @test (crop.plant_date + crop.harvest_offset) == crop.harvest_date

        Agtor.set_next_crop!(field)
    end
end


function test_crop_update_stages()
    z1 = setup_zone()
    crop = z1.fields[1].crop

    Agtor.update_stages!(crop, Date("2010-01-01"))

    for (k,v) in pairs(crop.growth_stages)
        @test (v[:start] + Dates.Day(v[:stage_length])) == v[:end]
    end
end


function test_pump_creation(data_dir::String="test/data/")
    pump_spec_dir::String = "$(data_dir)pumps/"
    pump_specs::Dict{Symbol, Dict} = load_spec(pump_spec_dir)

    pumps = Pump[create(spec) for (pn, spec) in pump_specs]

    for created in pumps
        @test created isa Pump
        Flatten.flatten(created)
    end
end


function test_parameter_extraction(data_dir::String="test/data/")
    pump_spec_dir::String = "$(data_dir)pumps/"
    pump_specs::Dict{String, Dict} = load_yaml(pump_spec_dir)

    pump_specs
end


@testset "Agtor.jl" begin

    test_parameter_extraction()

    test_in_season()
    test_out_of_season()

    test_crop_plantings()
    test_crop_update_stages()

    test_pump_creation()

    

end
