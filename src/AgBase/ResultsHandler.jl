using Statistics
using DataFrames


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
function collate_results(data::Dict, group::String, target::Array{String})::DataFrame
    res = Dict()
    for tgt in target
        res[tgt] = collate_results(data, group, tgt)
    end

    return res
end
function collate_results(data::Dict, group::String, target::String)::DataFrame

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
        elseif dataset isa Dict
            # collate basin level results
            compiled_results = for (idx, res) in dataset
                result_set = results_df(res, target; res_type="zone_results")
                mean(result_set[:total])
            end
            res[k] = compiled_results
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


function results_df(results::Union{Dict, String}, metric::String; res_type::String="zone_results")
    res_df = collate_results(results, res_type, metric)
    n_samples = ncol(res_df)
    res_stats = [scenario_stats(res_df, "$(i)/$(res_type)") for i in 1:n_samples]
    result_set = DataFrame(res_stats)

    return result_set
end
