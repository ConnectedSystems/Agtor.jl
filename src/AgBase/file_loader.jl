using Glob

function load_yaml(data_dir, ext::String=".yml")
    if !startswith(ext, ".")
        error("Extension must include period, e.g. '.yml'")
    end

    if !endswith(data_dir, "/") || !endswith(data_dir, "\\")
        data_dir *= '/'
    end

    data_files = readdir(glob"$(data_dir)")

    loaded_dataset = Dict()
    for fn in data_files
        data = ingest_data(fn)
        loaded_dataset[data["name"]] = data
    end

    return loaded_dataset
end