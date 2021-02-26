using DataFrames


"""
Collate a given result name from across scenario runs into a single DataFrame.
"""
function collate_results(fn::String, group::String, target::String)::DataFrame

    @assert endswith(fn, ".jld2")

    x = load(fn)
    res = Dict()
    tgt_sym = Symbol(target)
    for (k, dataset) in x
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