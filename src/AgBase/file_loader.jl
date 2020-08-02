using YAML
using Glob
using Base.Threads


function load_yaml(data_dir::String, ext::String=".yml")::Dict{String, Dict}
    if startswith(ext, ".") == false
        error("Extension must include period, e.g. '.yml'")
    end

    if endswith(data_dir, "/") == false || endswith(data_dir, "\\") == false
        data_dir *= '/'
    end

    data_files = glob("$(data_dir)" * "*$ext")

    loaded_dataset::Dict{String, Dict} = Dict{String, Dict}()
    Threads.@threads for fn in data_files
        data = YAML.load(open(fn))
        loaded_dataset[data["name"]] = data
    end

    return loaded_dataset
end

function load_yaml(file_list::Array{String})::Dict{String, Dict}
    loaded_dataset::Dict{String, Dict} = Dict{String, Dict}()
    Threads.@threads for fn in file_list
        data = YAML.load(open(fn))
        loaded_dataset[data["name"]] = data
    end

    return loaded_dataset
end