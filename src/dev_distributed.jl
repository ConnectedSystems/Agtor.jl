using Distributed, Serialization
using JLD2, FileIO
import Random

addprocs(3, exeflags="--project=.")

@everywhere using JLD2, FileIO, Serialization

@everywhere function calculate(x)
    return x^2
end

@everywhere function save_results!(fn::String, idx::String, results::Tuple)::Nothing
    jldopen(fn, "a+") do file
        # g = JLD2.Group(file, idx)  # create group
        file["$(idx)/results"] = results[2]  # zone_results
    end

    return nothing
end

function run_calc(x)
    n_ele = length(x)
    results = @sync @distributed (hcat) for i in 1:n_ele
        b = IOBuffer()
        res = calculate(x[i])
        serialize(b, res)
        b.data
    end

    @sync for i in 1:size(results, 2)
        res = deserialize(IOBuffer(@view results[:, i]))
        @async save_results!("dist_res.jld2", string(i), (i, res))
    end
end

arr = randn((100, 1))

run_calc(arr)

imported_res = load("dist_res.jld2")

@info imported_res

