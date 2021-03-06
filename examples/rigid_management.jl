using DataFrames, CSV, FileIO, Dates
using BenchmarkTools
using Agtor

import Agtor: run_model

import OrderedCollections: LittleDict


# Start month/day of growing season
# Represents when water allocations are announced.
const gs_start = (5, 1)

function setup_zone(data_dir::String="test/data/")
    zone_spec_dir::String = "$(data_dir)zones"
    zone_params::Dict{Symbol, Dict} = load_spec(zone_spec_dir)

    return create(zone_params[:Zone_1])
end


"""
Allocation callback for example.
"""
function allocation_callback!(zone, dt_i)

    # Resetting allocations for example run
    if monthday(dt_i) == gs_start
        # Example annual water allocations
        allocs = (surface_water=150.0, groundwater=40.0)

        update_available_water!(zone, allocs)
    end
end


data_dir = "test/data/"
rigid_zone = setup_zone(data_dir)
scen_data = joinpath(data_dir, "scenarios", "sampled_params.csv")
samples = DataFrame!(CSV.File(scen_data))

farmer = RigidManager("Rigid", 0.04)

all_results = []
tmp_zone = deepcopy(rigid_zone)
for (row_id, r) in enumerate(eachrow(samples))
    update_model!(tmp_zone, r)

    zone_results, field_results = run_model(farmer, tmp_zone; post=allocation_callback!)
    # push!(all_results, (zone_results, field_results))

    save_results!("rigid_run.jld2", row_id, (zone_results, field_results))
end

# save_results!("rigid_run.jld2", all_results)

# Loading and displaying results
saved_results = load("rigid_run.jld2")
@info saved_results