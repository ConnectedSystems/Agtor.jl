using Statistics
using DataFrames

const DICT_TYPE = Union{Dict,OrderedDict}

"""
    collate_results!(fn_pattern::String, main_fn::String)::Nothing

Collate individually saved `.jld2` files from distributed runs into a single JLD2 file.
"""
function collate_results!(fn_pattern::String, main_fn::String)::Nothing
    all_fns = glob(fn_pattern)
    jldopen(main_fn, "w") do file
        for fn in all_fns
            data = load(fn)
            for (grp_id, grp) in data
                file[grp_id] = grp
            end
        end
    end

    return nothing
end


"""
    collate_results(fn::String, group::String, target::Array{String})::DataFrame
    collate_results(data::Dict, group::String, target::Array{String})::DataFrame
    collate_results(fn::String, group::String, target::String)::DataFrame
    collate_results(data::Dict, group::String, target::String)::DataFrame

Collate a results from across scenario runs into an individual DataFrame.
"""
function collate_results(fn::String, group::String, target::Array{String})::DataFrame
    @assert endswith(fn, ".jld2")
    x = load(fn)

    return collate_results(x, group, target)
end
function collate_results(fn::String, group::String, target::String)::DataFrame
    @assert endswith(fn, ".jld2")
    x = load(fn)

    return collate_results(x, group, target)
end
function collate_results(data::DICT_TYPE, group::String, target::Array{String})::DataFrame
    res = Dict()
    for tgt in target
        res[tgt] = collate_results(data, group, tgt)
    end

    return res
end
function collate_results(data::DICT_TYPE, group::String, target::String)::DataFrame

    res = Dict()
    tgt_sym = Symbol(target)
    for (k, dataset) in data
        if !occursin(group, k)
            continue
        end

        if dataset isa NamedTuple
            for (fid, v) in dataset
                res[k*"_"*fid] = v[:, tgt_sym]
            end
        elseif dataset isa DataFrame
            res[k] = dataset[:, tgt_sym]
        elseif (dataset isa Dict) || (dataset isa OrderedDict)
            # collate basin level results
            result_var = for (idx, r) in dataset
                result_set = results_df(r, target; res_type="zone_results")
                mean(result_set[:, :total])
            end

            result_var = hcat([results_df(r, target; res_type="zone_results")[:, :total] for r in values(dataset)]...)
            compiled_results = map(sum, eachrow(result_var))

            scen_id = split(k, "/")[1]
            res[scen_id] = compiled_results
        end
    end

    return DataFrame(res)
end


"""Filter DataFrame down to a subset of results based on partial column name match."""
function select_results(data::DataFrame, needle::String)::DataFrame
    return data[:, [c for c in names(data) if contains(String(c), needle)]]
end


"""Get aggregate statistics for an entire scenario run."""
function scenario_stats(data::DataFrame, needle::String)::NamedTuple
    df = select_results(data, needle)
    total = sum(sum.(eachrow(df)))
    avg = mean(mean.(eachrow(df)))
    med = median(median.(eachrow(df)))

    return (total=total, mean=avg, median=med)
end


function results_df(results::Union{Dict,OrderedDict,String}, metric::String; res_type::String="zone_results")
    res_df = collate_results(results, res_type, metric)
    n_samples = ncol(res_df)
    res_stats = [scenario_stats(res_df, "$(i)/$(res_type)") for i in 1:n_samples]
    result_set = DataFrame(res_stats)

    return result_set
end
function results_df(results::DataFrame, metric::String; res_type::String="zone_results")
    return DataFrame(Dict(:Date => results[:, :Date], :total => results[:, metric]))
end

"""
    collate_by_scenario(results::DICT_TYPE, metric::String; res_type::String="zone_results")::OrderedDict

Collate results for each result type (`res_type`).

# Example

```julia
res = run_scenarios!(df, campaspe_basin; pre=allocation_precall!)
zone_results = collate_by_scenario(res, "irrigated_volume_sum")
# OrderedDict{String, DataFrame} with 2 entries:
#    "1" => 36×13 DataFrame…
#    "2" => 36×13 DataFrame…
#
#
# where each DataFrame contains results of the metric of interest by zone:
#
# 36×13 DataFrame
#  Row │ Date        Zone_9    Zone_8    Zone_6    Zone_5    Zone_1    Zone_2    Zone_3    Zone_10        Zone_12   Zone_4  ⋯
#      │ Date        Float64?  Float64?  Float64?  Float64?  Float64?  Float64?  Float64?  Float64?       Float64?  Float64 ⋯
# ─────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
#    1 │ 1982-01-20   3028.48   70415.2    2023.6       0.0       0.0   13348.2       0.0      1.26215e5       0.0   6955.9 ⋯
#    2 │ 1982-10-08   4497.18   35794.0    2023.6       0.0       0.0   13348.2       0.0  37563.1             0.0   6955.9
#    3 │ 1983-10-13   4497.18   36483.7    2023.6       0.0       0.0   13348.2       0.0  36700.1             0.0   6955.9
#    4 │ 1985-01-20   2854.3    70415.2    2023.6       0.0       0.0   13348.2       0.0      1.26121e5       0.0   6955.9
#   ⋮  │     ⋮          ⋮         ⋮         ⋮         ⋮         ⋮         ⋮         ⋮            ⋮           ⋮         ⋮    ⋱
```
"""
function collate_by_scenario(results::DICT_TYPE, metric::String; res_type::String="zone_results")::OrderedDict
    # Get keys related to result type
    target_keys = []
    for k in keys(results)
        if occursin(res_type, k)
            push!(target_keys, k)
        end
    end

    collated_results = OrderedDict{String,DataFrame}()
    for k in target_keys
        first_id = first(results[k])[1]
        first_df = first(results[k])[2]
        collated_df = first_df[:, ["Date", metric]]
        rename!(collated_df, metric => first_id)

        parent_id = split(k, "/")[1]
        zone_dfs = results[k]
        for (z_id, z) in zone_dfs
            if z_id in names(collated_df)
                continue
            end
            collated_df = outerjoin(collated_df, z[:, ["Date", metric]]; on="Date")
            rename!(collated_df, metric => z_id)
        end

        collated_results[parent_id] = collated_df
    end

    return sort(collated_results)
end

"""
    collate_scenario_results(results::DICT_TYPE, metric::String; op=sum)::DataFrame

Collate metric of interest for each scenario, aggregated by `op`.

# Example

```julia
res = run_scenarios!(df, campaspe_basin; pre=allocation_precall!)
scen_results = collate_scenario_results(res, "income_sum")
# 36×3 DataFrame
#  Row │ Date        1           2
#      │ Date        Float64     Float64
# ─────┼────────────────────────────────────
#    1 │ 1982-01-20  -1.14443e7  -3.83782e6
#    2 │ 1982-10-08  -6.23264e6   1.77937e6
#    3 │ 1983-10-13  -1.04992e7  -3.17234e6
#    4 │ 1985-01-20  -1.31009e8  -3.82679e6
#   ⋮  │     ⋮           ⋮           ⋮
#   33 │ 2013-10-13  -1.10069e7  -3.67198e6
#   34 │ 2015-01-20  -1.31051e8  -3.93724e6
#   35 │ 2015-10-08  -1.25556e8   1.77678e6
#   36 │ 2016-10-13  -1.0844e7   -3.52039e6
#                            28 rows omitted
```
"""
function collate_scenario_results(results::DICT_TYPE, metric::String; op=sum)::DataFrame
    zone_res = collate_by_scenario(results, metric; res_type="zone_results")

    scen_res = DataFrame("Date" => first(zone_res)[2][:, "Date"])
    for (scen_id, res) in zone_res
        scen_res[:, scen_id] = map(op, eachrow(res[:, 2:end]))
    end

    return scen_res
end