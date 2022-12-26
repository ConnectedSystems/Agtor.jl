using YAML, JLD2, HDF5, FileIO
using DataFrames
using Glob
using Base.Threads
import Agtor: generate_agparams


function load_yaml(data_dir::String, ext::String=".yml")::Dict{String, Dict}

    if !endswith(data_dir, ext)
        if startswith(ext, ".") == false
            throw(ArgumentError("Extension must include period, e.g. '.yml'"))
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


function load_climate(data_fn::String)::Climate
    # Expect only CSV for now...
    if endswith(data_fn, ".csv")
        use_threads = Threads.nthreads() > 1
        climate_seq = CSV.read(data_fn, DataFrame; dateformat="YYYY-mm-dd")
    else
        throw(ArgumentError("Currently, climate data can only be provided in CSV format"))
    end

    return Climate(climate_seq)
end


function determine_file_mode(fn::String)::String
    if isfile(fn)
        return "a+"
    end

    return "w"
end


"""Save state to JLD"""
function save_state!(fn::String, obj::Any, group::String)::Nothing
    mode = determine_file_mode(fn)
    jldopen(fn, mode) do file
        file[group] = obj
    end

    return nothing
end

"""Save arbitrary results to JLD."""
function save_results!(fn::String, results::Any, group::Tuple{String, String})::Nothing
    mode = determine_file_mode(fn)
    jldopen(fn, mode) do file
        idx, name = group
        file["$(idx)/$(name)"] = results
    end

    return nothing
end


"""Save arbitrary results to JLD."""
function save_results!(fn::String, results::NamedTuple)::Nothing
    mode = determine_file_mode(fn)
    jldopen(fn, mode) do file
        file["results"] = results
    end

    return nothing
end


"""Save results to JLD2.

# Example

```julia
output_fn = "example.jld2"
results = run_scenarios!(samples, z1, run_timestep!; post=allocation_callback!)
save_results!(output_fn, results)
```
"""
function save_results!(fn::String, results::Dict)::Nothing
    mode = determine_file_mode(fn)
    jldopen(fn, mode; compress=true) do f
        for (i, res) in results
            f[i] = res
        end
    end

    return nothing
end


# """Save results to JLD2."""
# function save_results!(fn::String, results::Dict)::Nothing
#     mode = determine_file_mode(fn)
#     jldopen(fn, mode) do file
#         for (i, res) in results
#             if res isa NamedTuple
#                 # Handle Zone level results
#                 file["$(i)/zone_results"] = res.zone_results
#                 file["$(i)/field_results"] = res.field_results
#             elseif res isa Dict
#                 # handle Basin level results
#                 for (k, v) in res
#                     file["$(i)/$(k)/zone_results"] = v.zone_results
#                     file["$(i)/$(k)/field_results"] = v.field_results
#                 end
#             end
#         end
#     end

#     return nothing
# end


"""Save results for a single zone to JLD."""
function save_results!(fn::String, idx::Union{String, Int64}, results::NamedTuple)::Nothing
    mode = determine_file_mode(fn)

    try
        jldopen(fn, mode) do file
            file["$(idx)/zone_results"] = results.zone_results  # zone_results
            file["$(idx)/field_results"] = results.field_results  # field_results
        end
    catch e
        if isa(e, TaskFailedException)
            jldopen(fn, "a+") do file
                file["$(idx)/zone_results"] = results.zone_results  # zone_results
                file["$(idx)/field_results"] = results.field_results  # field_results
            end
        else
            println("Could not save results ($(idx)) to $(fn)!")
        end
    end

    return nothing
end


"""Save results for a scenario, basin, and zone combination"""
function save_results!(fn, sid, bid, zid, results; mode="w")::Nothing
    jldopen(fn, mode) do file
        prefix = "Scenario_$(sid)/$(bid)/$(zid)"
        file["$(prefix)/zone_results"] = results.zone_results  # zone_results
        file["$(prefix)/field_results"] = results.field_results  # field_results
    end

    return nothing
end
