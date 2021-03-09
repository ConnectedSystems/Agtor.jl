using Statistics
using DataFrames


"""
Collate individually saved `.jld` files from distributed runs into a single JLD2 file.
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
Collate a given list of names from across scenario runs into a individual DataFrames.
"""
function collate_results(fn::String, group::String, target::Array{String})::DataFrame
    @assert endswith(fn, ".jld2")
    x = load(fn)

    return collate_results(x, group, target)
end


"""
Collate a given result name from across scenario runs into a single DataFrame.
"""
function collate_results(fn::String, group::String, target::String)::DataFrame
    @assert endswith(fn, ".jld2")
    x = load(fn)

    return collate_results(x, group, target)
end


"""
Collate a given list of names from across scenario runs into a individual DataFrames.
"""
function collate_results(data::Dict, group::String, target::Array{String})::DataFrame

    res = Dict()

    for tgt in target
        res[tgt] = collate_results(data, group, tgt)
    end

    return res
end



"""
Collate a given result name from across scenario runs into a single DataFrame.
"""
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
        else
            res[k] = dataset[:, tgt_sym]
        end
    end

    return DataFrame!(res)
end


"""Filter down to a subset of results based on partial column name match."""
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