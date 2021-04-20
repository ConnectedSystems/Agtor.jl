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


data_dir = "test/data/"
zone_spec_dir::String = "$(data_dir)zones/"
zone_params::Dict{String, Dict} = load_spec(zone_spec_dir)

z1 = create(zone_params[:Zone_1])

# Grab some pre-generated parameter combinations
samples = DataFrame!(CSV.File("test/data/scenarios/sampled_params.csv"))

# Below we update the model with the sampled values

# The "value" field for each parameter should change.
@info "before update" z1.fields[1].irrigation.efficiency

# We update the model using values from two rows to illustrate
# that it is changing...
update_model!(z1, samples[1, :])
@info "after update" z1.fields[1].irrigation.efficiency

update_model!(z1, samples[2, :])
@info z1.fields[1].irrigation.efficiency

