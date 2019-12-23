using YAML
using Glob


function load_yaml(data_dir::String, ext::String=".yml")::Dict{String, Dict}
    if !startswith(ext, ".")
        error("Extension must include period, e.g. '.yml'")
    end

    if !endswith(data_dir, "/") || !endswith(data_dir, "\\")
        data_dir *= '/'
    end

    data_files = glob("$(data_dir)" * "*$ext")

    loaded_dataset = Dict{String, Dict}()
    for fn in data_files
        data = YAML.load(open(fn))
        loaded_dataset[data["name"]] = data
    end

    return loaded_dataset
end