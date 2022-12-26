using Test

using Agtor, Dates, CSV


@testset "Loading YAML spec" begin
    data_dir::String="test/data/"
    pump_spec_dir::String = "$(data_dir)pumps/"
    pump_specs::Dict{String, Dict} = load_yaml(pump_spec_dir)

    @test pump_specs["groundwater"]["capital_cost"][1] == "RealParameter"
end


@testset "Updating an AgParameter" begin

    test = Agtor.RealParameter("Test", 0.0, 1.0, 0.5)

    @test test.value == 0.5
    set_params!(test, 0.75)
    @test test.value == 0.75

    z1 = setup_zone()
    tc_z1 = deepcopy(z1)  # test copy

    samples = CSV.read("test/data/scenarios/sampled_params.csv", DataFrame)

    # set_params!(z1.fields[1].irrigation.efficiency, 0.7)
    @test z1.fields[1].irrigation.efficiency.value == tc_z1.fields[1].irrigation.efficiency.value
    update_model!(z1, samples[1, :])

    @info z1.fields[1].irrigation.efficiency.value
    @info tc_z1.fields[1].irrigation.efficiency.value
    @info samples[1, "FarmZone-Zone_1└──CropField-field1└──Irrigation-gravity~efficiency"]
    @info z1.fields[1].irrigation.name
    @info z1.fields[1]

    @test z1.fields[1].irrigation.efficiency.value != tc_z1.fields[1].irrigation.efficiency.value || "Parameter value was not correctly updated!"
end


@testset "No duplicate parameters" begin
    zone = setup_zone()

    all_params = collect_agparams!(zone)
    param_names = all_params[!, :name]
    uni_params = unique(param_names)

    @test length(param_names) == length(uni_params)
end