import Revise
import Agtor

using Profile, BenchmarkTools, OwnTime, Logging, Infiltrator

using CSV
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
    zone_specs::Dict{String, Dict} = load_yaml(zone_spec_dir)

    return [create(FarmZone, z_spec) for (z_name, z_spec) in zone_specs]
end

function test_short_run(data_dir::String="test/data/")
    z1, (deeplead, channel_water) = setup_zone(data_dir)

    farmer = Manager("test")
    
    return nothing
end


data_dir = "test/data/"

irrig_dir = "$(data_dir)irrigations/"
irrig_specs = load_yaml(irrig_dir)

farmer = Manager("test")

irrig_params = generate_agparams("", irrig_specs["gravity"], nothing)

# or_spec = param_values(irrig_params)
# or_spec[:Irrigation___gravity__efficiency] = 0.6
# or_spec[:Irrigation___gravity__head_pressure] = 15.0
# or_spec[:Irrigation___gravity__capital_cost] = 2250.0
test_irrig = create(irrig_params)
@info "creating irrigation" create(irrig_params)

# @assert test_irrig.efficiency == 0.6
# @assert test_irrig.head_pressure == 15.0
# @assert test_irrig.capital_cost == 2250.0

#################

using DataFrames

# @info flatten(test_irrig)
@info Flatten.flatten(test_irrig, Agtor.AgParameter)

entries = map(ap -> param_info(ap), Flatten.flatten(test_irrig, Agtor.AgParameter))

@info DataFrame(entries)

#################

# collated = []
# println("Testing collation")
# @create Irrigation irrig_specs["gravity"] "Test"
# @info collated


# @create Irrigation irrig_specs["gravity"] "Test**" collated
# @info collated

zone_dir = "$(data_dir)zones/"
zone_specs = load_yaml(zone_dir)

zone_params = generate_agparams("", zone_specs["Zone_1"])

collated_specs = []
collect_agparams!(zone_params, collated_specs)

z1 = create(FarmZone, zone_params)

@infiltrate

@info z1

# @create FarmZone zone_specs["Zone_1"] ""

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

# see also test_param_collation.jl
