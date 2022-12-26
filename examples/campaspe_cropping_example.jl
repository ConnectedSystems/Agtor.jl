"""A full basin scenario example replicating the Lower Campaspe subcatchment."""

import Base.Filesystem: rm

using DataFrames, CSV, FileIO
using Statistics, OrderedCollections, Surrogates
using Agtor, Dates


"""Reallocate water on given date.

Example proxy for a policy model which is called every time step
for the given zone.

Water allocations are simply reset at start of season (1 May).
"""
function allocation_precall!(zone, dt_i; gs_start=(5, 1))
    # Resetting allocations for each growing season
    if monthday(dt_i) == gs_start
        # Full annual water allocations each year
        tmp = LittleDict(ws.name=>ws.entitlement for ws in zone.water_sources)
        t_names = Tuple(Symbol.(collect(keys(tmp))))
        allocs = NamedTuple{t_names}(collect(values(tmp)))

        update_available_water!(zone, allocs)
    end
end


# Start month/day of growing season
# Represents when water allocations are first announced.
const gs_start = (5, 1)

data_dir = "test/data/"

# Basin setup
basin_spec_dir = "examples/campaspe/basin/"
basin_spec = load_spec(basin_spec_dir)[:Campaspe]

basin_name = basin_spec[:name]
zone_specs = basin_spec[:zone_spec]

climate_data = "examples/campaspe/climate/basin_historic_climate_data.csv"

# Set the "economically rational" optimizing manager as the farmer for all zones
# Optimizes returns for the available water, given water needs and costs.
OptimizingManager = EconManager("optimizing")
manage_zones = ((OptimizingManager, Tuple(collect(keys(zone_specs)))), )
campaspe_basin = Basin(name=basin_name, zone_spec=zone_specs, 
                       climate_data=climate_data, managers=manage_zones)

agparams = collect_agparams!(campaspe_basin)

samples = sample(50, agparams[:, :min_val], agparams[:, :max_val], SobolSample())

# Match sampled values with parameter names
df = rename!(DataFrame(samples), map(Symbol, agparams[:, :name]))

res = run_scenarios!(df, campaspe_basin; pre=allocation_precall!)

save_results!("campaspe_example.jld2", res)

