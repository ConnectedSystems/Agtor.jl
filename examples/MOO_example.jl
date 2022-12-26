"""
Demonstration of multi-objective optimization using BlackBoxOptim.jl
"""

using DataFrames, Tables, CSV, FileIO, Dates
using BenchmarkTools
using Agtor

using BlackBoxOptim

import Agtor: run_model
import OrderedCollections: LittleDict


# Start month/day of growing season
# Represents when water allocations are announced.
const gs_start = (5, 1)

data_dir = "test/data/"

# Zone/Basin setup
zone_spec_dir = "$(data_dir)zones"
zone_params = load_spec(zone_spec_dir)

climate_data = "$(data_dir)/climate/farm_climate_data.csv"
climate = load_climate(climate_data)

example_zone = create(zone_params[:Zone_1], climate)
example_zone.manager = EconManager("Example")

@info example_zone





agparams = collect_agparams!(example_zone)

# If NamedTuple is desired
# search_range = Tables.rowtable(agparams[:, [:min_val, :max_val]])
# search_range = [(x[:min_val], x[:max_val]) for x in search_range]

search_range = [(x[:min_val], x[:max_val]) for x in eachrow(agparams[:, [:min_val, :max_val]])]

"""Reallocate water on given date."""
function allocation_callback!(zone, dt_i)

    # Resetting allocations for example run
    if monthday(dt_i) == gs_start
        # Example annual water allocations
        allocs = (surface_water=300.0, groundwater=190.0)

        update_available_water!(zone, allocs)
    end
end


function cost_func(params)
    tmp_z = deepcopy(example_zone)

    # Construct DF of updated parameters
    col_names = Tuple(Symbol.(agparams[:name]))
    new_params = DataFrame([NamedTuple{col_names}(params)])

    update_model!(tmp_z, new_params[1, :])

    # Here, we're not worried about field-level results
    zone_results, field_results = run_model(example_zone, run_timestep!; post=allocation_callback!)

    # maximize (we negate as the optimizer attempts to find the minimum)
    dollar_per_ML = mean(zone_results[:, Symbol("Dollar per ML")]) * -1.0

    # minimize
    sw_use = mean(zone_results[:, :surface_water_sum])
    gw_use = mean(zone_results[:, :groundwater_sum])

    return (dollar_per_ML, sw_use, gw_use)
end


result = bboptimize(
    cost_func, 
    Method=:borg_moea, 
    FitnessScheme = ParetoFitnessScheme{3}(is_minimizing=true),
    SearchRange = search_range,
    NumDimensions=length(search_range),
    MaxTime=55
)

@info result

bc = best_candidate(result)

best = DataFrame(name=agparams[:, :name], value=bc)
@info best
