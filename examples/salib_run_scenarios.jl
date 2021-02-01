"""Example showing how to use SALib (via PyCall) to generate, run, and analyze results"""

using Pkg

ENV["PYTHON"] = raw"C:\programs\miniconda3\envs\salib"  # Path to environment python.exe
ENV["CONDA_JL_HOME"] = raw"C:\programs\miniconda3\envs\salib"  # Path to conda environment folder

# Pkg.build("Conda")
Pkg.build("PyCall")

using PyCall
using Agtor
using Dates
using DataFrames


# Start month/day of growing season
# Represents when water allocations start getting announced.
const gs_start = (5, 1)

function setup_basin(data_dir, climate_data)
    basin_spec_dir::String = "$(data_dir)basins"
    basin_spec::Dict = load_spec(basin_spec_dir)[:TestBasin]

    basin_name = basin_spec[:name]
    zone_specs = basin_spec[:zone_spec]

    collated_specs = []
    agparams = collect_agparams!(zone_specs, collated_specs)

    Manager_A = BaseManager("optimizing")
    Manager_B = RigidManager("rigid", 0.05)
    manage_zones = ((Manager_A, ("Zone_1", )), (Manager_B, ("Zone_2", )))

    b = Basin(name=basin_name, zone_spec=zone_specs, climate_data=climate_data, managers=manage_zones)

    return b, agparams
end


function run_model(scenario_id, basin)

    # Example annual water allocations
    allocs = (surface_water=150.0, groundwater=40.0)

    for dt_i in basin.climate.time_steps
        # Resetting allocations for example run
        if monthday(dt_i) == gs_start
            for z in basin.zones
                update_available_water!(z, allocs)
            end
        end

        run_timestep!(basin)
    end

    # Save results as they complete
    all_res = []
    @sync for z in basin.zones
        results = collect_results(z)

        # Uncomment the below if intermediate results
        # are desired
        # run_id = "$(scenario_id)/$(z.name)"
        # @async save_results!("basin_async_save.jld2", run_id, results; mode="a+")

        push!(all_res, results[1])
    end

    return calculate_metrics(all_res)
end


function scenario_run(samples, basin)::Array{Array{Float64}}
    basin_wide_res = []
    for (row_id, r) in enumerate(eachrow(samples))
        tmp_b = deepcopy(basin)
        update_model!(tmp_b, r)
        push!(basin_wide_res, run_model(row_id, tmp_b))
    end

    return basin_wide_res        
end


function pd_to_df(df_pd)
    colnames = map(Symbol, df_pd.columns)
    df = DataFrame(Any[Array(df_pd[c].values) for c in colnames], colnames)

    return df
end


function calculate_metrics(collated_results::Union{Tuple, Array})::Array{Float64}

    z_res = DataFrame(fill(Float64, 4), Symbol.((i for i in range(1,4))), length(collated_results))

    for (idx, zone_res) in enumerate(collated_results)
        z_res[idx, :] = calculate_metrics(zone_res)
    end

    return [mean(z_res[:, i]) for i in names(z_res)]
end


data_dir = "test/data/"
example_basin, agparams = setup_basin(data_dir, "test/data/climate/basin_climate_data.csv")
# scen_data = joinpath(data_dir, "scenarios", "sampled_params.csv")
# samples = DataFrame!(CSV.File(scen_data))

param_names = agparams[:, :name]
param_bounds = agparams[:, [:min_val, :max_val]]

py"""
from SALib import ProblemSpec
import numpy as np
import pandas as pd

sp = ProblemSpec({
  'names': $(param_names),
  'bounds': list($(Array(param_bounds))),
  'output': ['CV', 'Mean ML per Yield [ML/t]', 'Mean Income [$]', 
             'Mean Water Use [ML]']
})

sp.sample_latin(4, seed=101)

orig_samples = sp.samples

tmp = pd.DataFrame(sp.samples, columns=sp['names'])
# tmp.to_csv("salib_example.csv", index=False)

# Attach Julia DataFrame, bypassing any checks...
sp._samples = $(pd_to_df)(tmp)

# Run model
sp.evaluate($(scenario_run), $(example_basin))

# Revert back to original samples as numpy array
sp.samples = orig_samples

# Have to coerce results to numpy array as these
# are returned as a Python list by Julia
sp.results = np.array(sp.results)

# Perform analysis
sp.analyze_rbd_fast()
"""

@info "Analysis:" py"sp.to_df()"


using PyCall

py"""
from SALib import ProblemSpec
import numpy as np
import pandas as pd

sp = ProblemSpec({
  'names': $(param_names),
  'bounds': list($(Array(param_bounds))),
  'output': ['CV', 'Mean ML per Yield [ML/t]', 'Mean Income [$]', 
             'Mean Water Use [ML]']
})

sp.sample_latin(4, seed=101)

orig_samples = sp.samples

# Convert Pandas DF to Julia DataFrame, bypassing any checks...
tmp = pd.DataFrame(sp.samples, columns=sp['names'])
sp._samples = $(pd_to_df)(tmp)

# Run model
sp.evaluate($(scenario_run), $(example_basin))

# Revert back to original samples as numpy array
sp.samples = orig_samples

# Have to coerce results to numpy array as these
# are returned as a Python list by Julia
sp.results = np.array(sp.results)

# Perform analysis
sp.analyze_rbd_fast()
"""

@info "Analysis:" py"sp.to_df()"
