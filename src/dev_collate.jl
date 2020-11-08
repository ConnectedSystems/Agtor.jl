import Revise

using Profile, BenchmarkTools, OwnTime, Logging, Infiltrator

using JLD2, HDF5, CSV
using Dates
using DataStructures
using DataFrames
using Agtor

import Flatten

# Start with the environment variable set for multi-threading
# $ JULIA_NUM_THREADS=4 ./julia

# Windows:
# $ set JULIA_NUM_THREADS=4 && julia dev.jl

# Start month/day of growing season
# Represents when water allocations start getting announced.
const gs_start = (5, 1)

function setup_zone(data_dir::String="test/data/")
    zone_spec_dir::String = "$(data_dir)zones/"
    # zone_specs::Dict{String, Dict} = load_yaml(zone_spec_dir)
    # zone_params = generate_agparams("", zone_specs["Zone_1"])
    zone_params = load_spec(zone_spec_dir)
    tgt_zone = zone_params[:Zone_1]
    collated_specs::Array = []
    agparams = collect_agparams!(tgt_zone, collated_specs; ignore=[:crop_spec])

    climate_fn::String = "$(data_dir)climate/farm_climate_data.csv"
    climate::Climate = load_climate(climate_fn)

    return create(tgt_zone, climate), agparams
end


data_dir = "test/data/"

# irrig_dir = "$(data_dir)irrigations/"
# irrig_specs = load_yaml(irrig_dir)
# irrig_params = generate_agparams("", irrig_specs["gravity"])

# test_irrig = create(irrig_params)
# @info "creating irrigation" create(irrig_params)

#################

# # @info flatten(test_irrig)
# @info Flatten.flatten(test_irrig, Agtor.AgParameter)
# entries = map(ap -> param_info(ap), Flatten.flatten(test_irrig, Agtor.AgParameter))
# @info DataFrame(entries)

#################

z1, collated = setup_zone(data_dir)

@info collated

CSV.write("test_params.csv", collated)

struct Foo{A,B,C}
    a::A
    b::B
    c::C
end


test = Foo([Agtor.RealParameter("Doo", 0, 1, 0.5), Agtor.RealParameter("Boo", 0, 1, 0.5)],
            Agtor.RealParameter("FooBar", -1, 1, 0.5), 
            Dict("Blig"=>Agtor.RealParameter("Blig___Blag", 0, 3, 0.5))
)

sample = [(Doo=0.3, Boo=0.3, FooBar=0.3, Blig___Blag=3.0)]
df = DataFrame(sample)

@info "Updating with values:" df
@info "DF before" test
set_params!(test, df[1, :])
@info "DF after" test


@info "Updating with values:" df
@info "DF before" test
set_params!(test, df[1, :])
@info "DF after" test


@info typeof(df[1, :])
sample = (Doo=0.2, Boo=0.2, FooBar=0.2, Blig___Blag=2.0)
@info "DF before" test
@info typeof(sample)
set_params!(test, sample)
@info "DF after" test

@assert test.c["Blig"].value == 2.0

# @create FarmZone zone_specs["Zone_1"] ""

# AgParameter collection now works fairly seamlessly
# Need to work out the best way to update all agparams with new sampled values.
# See notes below

# So far this is working for RealParameters, but CategoricalParameters 
# are a special case.
# CategoricalArrays can map string entries to numbered positions
# We assume min/max vals are simply 1 to length of array.
# When generating parameter values, we need to map the selected integer 
# to the appropriate array position...
#
# Rather than recreating the Component, why aren't we just updating an existing one?
# Can iterate through updating based on symbol match - we're doing exactly that to extract
# parameter specs anyway...
#
# But how to handle changes to climate sequences?
# Or do we side-step the issue and only pass in samples for each specific climate scenario...

# see also test_param_collation.jl
