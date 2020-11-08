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

    collated_specs::Array = []
    agparams = collect_agparams!(zone_params, collated_specs; ignore=["crop_spec"])

    climate_fn::String = "$(data_dir)climate/farm_climate_data.csv"
    climate::Climate = load_climate(climate_fn)

    return create(zone_params, climate), agparams
end


data_dir = "test/data/"

z1, collated = setup_zone(data_dir)

samples = DataFrame!(CSV.File("test/data/scenarios/sampled_params.csv"))


# Here we update the model with the sampled values
# The "value" field for each parameter should change.
@info "before update" z1.fields[1].irrigation.efficiency

# We update the model using values from two rows to illustrate
# that it is changing...
update_model!(z1, samples[1, :])
@info "after update" z1.fields[1].irrigation.efficiency

update_model!(z1, samples[2, :])
@info z1.fields[1].irrigation.efficiency

