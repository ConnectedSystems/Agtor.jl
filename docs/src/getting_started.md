# Getting Started

## A note on terminology

Agtor is a zonal agricultural cropping model, where a zone is defined by a collection of fields, and a basin/catchment is defined with a collection of zones.

- Field : An area used for cropping, e.g., a field
- FarmZone  : An arbitrary collection of fields, e.g., a farm or sub-catchment
- Basin : An arbitrary collection of zones, e.g., a catchment

In addition, each zone may be assigned a `Manager`, simulating an actor in charge of determining irrigation schedules and volume of water use.

Currently available `Manager`s include:

- `EconManager` : an "economically rational" actor that optimizes for farm profit
- `RigidManager` : applies a pre-determined volume of water every time step

Parameters at the field-level may be defined as:

- `RealParameter`, inputs that have a range of possible values
- `CategoricalParameter`, similar to `RealParameter` except that the range of values relate to specific "options"
- `ConstantParameter`, parameters that are held constant for a simulation.

Note that all dates follow `YYYY-mm-dd` format, or (`mm-dd`) if year is not specified.

## Required data

### Zones

- CSV of climate data for each zone (daily ET and rainfall, assumed daily)
- Estimated Total Available Water for each field's soil type
- Initial soil water deficit for each field

### Fields

- Access costs for each water source
- Operational costs of pumping from surface and groundwater
- Operational costs of each irrigation system
- Crop parameters

### Water allocations/policy

Agtor requires a water allocation model to be provided by the user.
This can represent a given policy, regional management approach, or other situation.

The example function below simply resets the water entitlement for a given zone/watersource
on 1 May (`(5, 1)`) every year.

```julia
"""Reallocate water on given date.

Example proxy for a policy model which is called every time step
for the given zone.

Water allocations are simply reset at start of season (1 May).
"""
function reset_allocation!(zone, dt_i; gs_start=(5, 1))
    # Resetting allocations for each growing season
    if monthday(dt_i) == gs_start
        # Full annual water allocations each year
        tmp = LittleDict(ws.name=>ws.entitlement for ws in zone.water_sources)
        t_names = Tuple(Symbol.(collect(keys(tmp))))
        allocs = NamedTuple{t_names}(collect(values(tmp)))

        update_available_water!(zone, allocs)
    end
end
```

## Defining Components

All components for Agtor are defined through YAML files which act as the `specifications` of each component.

See [Example Component Specifications](@ref) for an outline of each spec.

Specifications are loaded from the collection of YAML files as a dictionary.
A `Basin` may therefore be defined directly as a dictionary so long as it follows component specifications as outlined in [Example Component Specifications](@ref).


## Example: Running scenarios

At the highest level of use, Agtor runs multiple simulations ("scenarios").


```julia
using Agtor

# Load Basin specification from its directory
basin_spec_dir = "examples/campaspe/basin/"

# A directory may hold specs for multiple basins.
# Here, we are loading the Campaspe spec (the only one defined in the directory)
basin_spec = load_spec(basin_spec_dir)[:Campaspe]

# Extract name and zone specs
basin_name = basin_spec[:name]
zone_specs = basin_spec[:zone_spec]

# Specify location of shared climate data for all zones
climate_data = "examples/campaspe/climate/basin_historic_climate_data.csv"

# Create an "economically rational" manager to be shared by all zones.
# This manager optimizes returns for the available water, given water needs and costs.
OptimizingManager = EconManager("optimizing")

# We then assign this manager to all zones defined in the basin spec
# this associate a set of zones to a given manager by the zone name
# associate_managers([OptimizingManager], [[:Zone_1, :Zone_2, ..., :Zone_N]])
manage_zones = associate_managers([OptimizingManager], [keys(zone_specs)])

# Multiple associations can be created:
# associate_managers(
#    [OptimizingManager, RigidManager],
#    [[:Zone_1, :Zone_2], [:Zone_3, ..., :Zone_N]])

# Final step in the setup is to create the basin by specifying its name, the zones, 
# the climate data and the manager-zone relationship defined above.
campaspe_basin = Basin(name=basin_name, zone_spec=zone_specs, 
                       climate_data=climate_data, managers=manage_zones)

# We then create/run scenarios by sampling from possible parameter combinations
# We use the `Surrogates` package for the sampling:
agparams = collect_agparams!(campaspe_basin)  # collect all parameters
samples = sample(50, agparams[:, :min_val], agparams[:, :max_val], SobolSample())

# Match sampled values with parameter names
df = rename!(DataFrame(samples), map(Symbol, agparams[:, :name]))

# Run all defined scenarios
res = run_scenarios!(df, campaspe_basin; pre=reset_allocation!)
```

Note that the example water allocation model was passed into the `pre` argument.
Agtor defines `pre` and `post` and in cases functions are supplied, these are run
before each time step (in the case of `pre`) or after each time step (in the case of `post`).

Scenario results are held in the form of a dictionary with entries for aggregate zone level results...

```julia
julia> res
Dict{Any, Any} with 100 entries:
  "46/field_results" => Dict{String, Dict{String, DataFrame}}("Zone_5"=>Dict("field1"=>36×8 DataFrame…
  "12/zone_results"  => Dict{String, DataFrame}("Zone_5"=>36×13 DataFrame…

julia> res["1/zone_results"]
Dict{String, DataFrame} with 12 entries:
  "Zone_5"  => 36×13 DataFrame…
  "Zone_2"  => 36×15 DataFrame…
  "Zone_12" => 36×13 DataFrame…
```

... and results for each field for a given zone. In other words, finer-scale field level results:

```julia
julia> res["1/field_results"]["Zone_5"]
Dict{String, DataFrame} with 1 entry:
  "field1" => 36×8 DataFrame…
```

## Example: Within scenario/timestep

Finer-grain simulations are also possible with Agtor.

```julia
# Update the zone with some new parameter values if necessary
# update_model!(zone, some_parameters)
zone_results, field_results = run_model(OptimizingManager, zone; post=reset_allocation!)

# Run a specific timestep
run_timestep!(OptimizingManager, zone, timestep_id, timestep_date);
```

!!! warning
    In the case of running a timestep, all time stepping and 
    data handling is left to the user to specify.

    See example below.

### Example custom run function

```julia
# Define growing season start as 1 May
const gs_start = (5, 1);

function run_model(zone)
    time_sequence = zone.climate.time_steps

    # Example annual water allocations
    allocs = (surface_water=150.0, groundwater=40.0)

    for (idx, dt_i) in enumerate(time_sequence)
        run_timestep!(zone.manager, zone, idx, dt_i)

        # Resetting allocations for example run
        if monthday(dt_i) == gs_start
            update_available_water!(zone, allocs)
        end
    end

    zone_results, field_results = collect_results(zone)

    return zone_results, field_results
end
```