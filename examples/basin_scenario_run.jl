"""Running scenarios one after the other."""

using DataFrames, CSV, FileIO
using BenchmarkTools
using Agtor, Dates

import Base.Filesystem: rm

using Statistics
using PyCall


# Start month/day of growing season
# Represents when water allocations start getting announced.
const gs_start = (5, 1)

function setup_basin(data_dir, climate_data)
    basin_spec_dir::String = "$(data_dir)basins"
    basin_spec::Dict = load_spec(basin_spec_dir)[:TestBasin]

    basin_name = basin_spec[:name]
    zone_specs = basin_spec[:zone_spec]

    Manager_A = BaseManager("optimizing")
    Manager_B = RigidManager("rigid", 0.05)
    manage_zones = ((Manager_A, ("Zone_1", )), (Manager_B, ("Zone_2", )))

    b = Basin(name=basin_name, zone_spec=zone_specs, climate_data=climate_data, managers=manage_zones)

    return b
end


function calculate_metrics(collated_results::Union{Tuple, Array})::Array{Float64}

    z_res = DataFrame(fill(Float64, 4), Symbol.((i for i in range(1,4))), length(collated_results))

    for (idx, zone_res) in enumerate(collated_results)
        z_res[idx, :] = calculate_metrics(zone_res)
    end

    return [mean(z_res[:, i]) for i in names(z_res)]
end


function calculate_metrics(collated_logs::DataFrame)
    income = collated_logs[!, Symbol("income_sum")]

    cv = std(income) / mean(income)
    mean_ML_per_yield = mean(collated_logs[!, Symbol("ML per Irrigated Yield")])
    mean_income_per_ha = mean(collated_logs[!, Symbol("Dollar per Ha")])
    mean_water_use = mean(collated_logs[!, :irrigated_volume_sum])

    return [cv, mean_ML_per_yield, mean_income_per_ha, mean_water_use]
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
    for (z_id, z) in enumerate(basin.zones)
        results = collect_results(z)

        # run_id = "$(scenario_id)/$(z.name)"
        # save_results!("basin_async_save.jld2", run_id, results; mode="a+")

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

        # An alternative to using a deepcopy of the basin is
        # to reset its values (more flexible, but increases runtime slightly)
        # reset!(basin)
    end

    return basin_wide_res 
end


data_dir = "test/data/"
example_basin = setup_basin(data_dir, "test/data/climate/basin_climate_data.csv")

all_params = collect_agparams!(example_basin, [])
param_names = all_params[:name]
param_bounds = Array(all_params[:, [:min_val, :max_val]])

py"""
from SALib import ProblemSpec
import numpy as np
import pandas as pd

sp = ProblemSpec({
  'names': $(param_names),
  'bounds': $(Array(param_bounds)),
  'output': ['CV', 'Mean ML per Yield [ML/t]', 'Mean Income [$]', 'Mean Water Use [ML]']
})

sp.sample_latin(4, seed=101)
samples = pd.DataFrame(sp.samples, columns=sp['names'])
samples.to_csv("basin_samples.csv", index=False)
"""

samples = DataFrame!(CSV.File("basin_samples.csv"))
@time res = scenario_run(samples, example_basin)


py"""
sp.results = np.array($(res))
sp.analyze_rbd_fast()
"""

@info "Analysis:" py"sp.to_df()"

rm("basin_samples.csv")


