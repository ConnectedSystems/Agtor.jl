using YAML, JLD2, HDF5, FileIO
using DataFrames
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


function load_climate(data_fn::String)
    # Expect only CSV for now...
    if endswith(data_fn, ".csv")
        use_threads = Threads.nthreads() > 1
        climate_seq = DataFrame!(CSV.File(data_fn, threaded=use_threads, dateformat="dd-mm-YYYY"))
    else
        error("Currently, climate data can only be provided in CSV format")
    end

    return Climate(climate_seq)
end

"""Save results for a single zone to JLD."""
function save_results!(fn, results::Dict)::Nothing
    jldopen(fn, "w") do file
        for (i, res) in results
            file["$(i)/zone_results"] = results[1]  # zone_results
            file["$(i)/field_results"] = results[2]  # field_results
        end
    end

    return
end

"""Save results for a single zone to JLD."""
function save_results!(fn::String, idx::String, results::Tuple)::Nothing
    jldopen(fn, "w") do file
        file["$(idx)/zone_results"] = results[1]  # zone_results
        file["$(idx)/field_results"] = results[2]  # field_results
    end

    return
end


"""Save results for a scenario, basin, and zone combination"""
function save_results!(fn, sid, bid, zid, results)::Nothing
    jldopen(fn, "w") do file
        prefix = "Scenario_$(sid)/Basin_$(bid)/Zone_$(zid)"
        file["$(prefix)/zone_results"] = results[1]  # zone_results
        file["$(prefix)/field_results"] = results[2]  # field_results
    end

    return
end


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

    return
end
