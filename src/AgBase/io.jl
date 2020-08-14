using YAML, JLD, HDF5
using Glob
using Base.Threads
import Agtor: generate_agparams


function load_yaml(data_dir::String, ext::String=".yml")::Dict{String, Dict}

    if !endswith(data_dir, ext)
        if startswith(ext, ".") == false
            error("Extension must include period, e.g. '.yml'")
        end

        if endswith(data_dir, "/") == false || endswith(data_dir, "\\") == false
            data_dir *= '/'
        end

        data_files = glob("$(data_dir)" * "*$ext")
    else
        data_files = [data_dir]
    end

    return load_yaml(data_files)
end


function load_yaml(file_list::Array{String})::Dict{String, Dict}
    loaded_dataset::Dict{String, Dict} = Dict{String, Dict}()
    Threads.@threads for fn in file_list
        data = YAML.load(open(fn))
        loaded_dataset[data["name"]] = data
    end

    return loaded_dataset
end


function load_spec(data_dir::String)::Dict{Symbol, Dict}
    specs::Dict{String, Dict} = load_yaml(data_dir)
    return Dict(Symbol(k) => generate_agparams("", v) for (k,v) in specs)
end


"""
Save model run results to JLD.
"""
function save_results(fn, results)
    jldopen(fn, "w") do file
        for (i, res) in enumerate(results)
            g = HDF5.g_create(file, string(i))  # create a group
            g["zone_results"] = res[1]  # zone_results
            g["field_results"] = res[2]  # field_results
        end
    end
end
