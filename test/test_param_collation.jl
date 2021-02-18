using Test

using Agtor, Dates, CSV


function setup_zone(data_dir::String="test/data/")
    zone_spec_dir::String = "$(data_dir)zones"
    zone_params::Dict{Symbol, Dict} = load_spec(zone_spec_dir)

    return create(zone_params[:Zone_1])
end


function test_no_duplicate_params()
    zone = setup_zone()

    all_params = collect_agparams!(zone)
    param_names = all_params[:name]
    uni_params = unique(param_names)

    @test length(param_names) == length(uni_params)
end

    
test_no_duplicate_params()