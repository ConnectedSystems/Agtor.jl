import Agtor: Climate, FarmZone


mutable struct Basin <: AgComponent
    name::String
    zones::Dict{Symbol, FarmZone}

    function Basin(name, zone_specs; climate_data)
        basin = new()
        basin.name = name

        # Expect only CSV for now...
        if endswith(climate_data, ".csv")
            use_threads = Threads.nthreads() > 1
            climate_seq = DataFrame!(CSV.File(climate_data, threaded=use_threads, dateformat="dd-mm-YYYY"))
        else
            error("Currently, climate data can only be provided in CSV format")
        end

        climate::Climate = Climate(climate_seq)
        basin.zones = Dict(k => create(FarmZone, v, climate) for (k, v) in zone_specs)

        return basin
    end
end


function setup_zones(data_path::String, zone_names::Array)
    zone_spec_dir::String = data_path
    zone_specs::Dict{String, Dict} = load_yaml(zone_spec_dir)

    return [create(FarmZone, z_spec) for (z_name, z_spec) in zone_specs if z_name in zone_names]
end

function create(cls::Type{Basin}, spec::Dict; climate_data::String)
    cls_name = pop!(spec, :component)
    return cls(spec[:name], spec[:zone_spec]; climate_data)
end
