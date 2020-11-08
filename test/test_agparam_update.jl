"""
Example illustrating how to update a model with new parameters.
"""

using CSV
using DataStructures
using DataFrames
using Agtor

# Start with the environment variable set for multi-threading
# $ JULIA_NUM_THREADS=4 ./julia

# Windows:
# $ set JULIA_NUM_THREADS=4 && julia dev.jl

function setup_zone(data_dir::String="test/data/")
    zone_spec_dir::String = "$(data_dir)zones/"
    zone_specs::Dict{String, Dict} = load_yaml(zone_spec_dir)

    zone_params = generate_agparams("", zone_specs["Zone_1"])

    climate_fn::String = "$(data_dir)climate/farm_climate_data.csv"
    climate::Climate = Agtor.load_climate(climate_fn)

    return create(zone_params, climate)
end


test = Agtor.RealParameter("Test", 0.0, 1.0, 0.5)

@assert test.value == 0.5
set_params!(test, 0.75)
@assert test.value == 0.75


data_dir = "test/data/"

z1 = setup_zone(data_dir)
tc_z1 = deepcopy(z1)  # test copy

samples = DataFrame!(CSV.File("test/data/scenarios/sampled_params.csv"))

@assert z1.fields[1].irrigation.efficiency.value == tc_z1.fields[1].irrigation.efficiency.value
update_model!(z1, samples[1, :])
@assert z1.fields[1].irrigation.efficiency.value != tc_z1.fields[1].irrigation.efficiency.value

@info z1.fields[1].irrigation.efficiency.value tc_z1.fields[1].irrigation.efficiency.value

