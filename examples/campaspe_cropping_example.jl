"""A full basin scenario example replicating the Lower Campaspe subcatchment."""

using DataFrames, CSV, FileIO
using Statistics, OrderedCollections
using Surrogates
using Agtor, Dates

import Base.Filesystem: rm


"""Reallocate water on given date."""
function allocation_precall!(zone, dt_i)
    # Resetting allocations for each growing season
    if monthday(dt_i) == gs_start
        # Full annual water allocations each year
        tmp = LittleDict(ws.name=>ws.entitlement for ws in zone.water_sources)
        t_names = Tuple(Symbol.(collect(keys(tmp))))
        allocs = NamedTuple{t_names}(collect(values(tmp)))

        update_available_water!(zone, allocs)
    end
end


function scenario_run(samples, basin; pre=nothing, post=nothing)::Array
    # Need to change this to be a Dict so we have scenario/
    scenario_results = []
    sizehint!(scenario_results, nrow(samples))

    for (row_id, r) in enumerate(eachrow(samples))
        tmp_b = deepcopy(basin)
        
        update_model!(tmp_b, r)
        push!(scenario_results, run_model(tmp_b, run_timestep!; pre=pre, post=post))
    end

    return scenario_results
end


# Start month/day of growing season
# Represents when water allocations are announced.
const gs_start = (5, 1)

data_dir = "test/data/"

# Basin setup
basin_spec_dir = "examples/campaspe/basin/"
basin_spec = load_spec(basin_spec_dir)[:Campaspe]

basin_name = basin_spec[:name]
zone_specs = basin_spec[:zone_spec]

OptimizingManager = BaseManager("optimizing")

climate_data = "examples/campaspe/climate/basin_historic_climate_data.csv"

# Set the optimizing manager as the farmer for all zones
manage_zones = ((OptimizingManager, Tuple(collect(keys(zone_specs)))), )
campaspe_basin = Basin(name=basin_name, zone_spec=zone_specs, 
                       climate_data=climate_data, managers=manage_zones)

agparams = collect_agparams!(campaspe_basin)

# search_range = [(x[:min_val], x[:max_val]) for x in eachrow(agparams[:, [:min_val, :max_val]])]

samples = sample(10, agparams[:, :min_val], agparams[:, :max_val], SobolSample())

df = names!(DataFrame(samples), map(Symbol, agparams[:, :name]))

res = scenario_run(df, campaspe_basin; pre=allocation_precall!)

@info res