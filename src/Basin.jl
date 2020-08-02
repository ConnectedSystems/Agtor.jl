import Agtor: Climate, FarmZone

mutable struct Basin <: AgComponent
    climate_options::CategoricalParameter
    climate_data_paths::String
    zone_data_path::String
    zone_names::Array
    zones::Array{FarmZone}

    function Basin(spec::Dict)

        props = generate_agparams(spec["name"], spec["properties"])

        basin = new()
        basin.climate_options = props[:climate_options]
        basin.zone_names = props[:zones]

        basin.climate_data_paths = spec["climate_data"]
        basin.zone_data_path = spec["zone_data"]

        basin.zones = setup_zones(basin.zone_data_path, basin.zone_names)

        return basin
    end
end


function setup_zones(data_path::String, zone_names::Array)
    zone_spec_dir::String = data_path
    zone_specs::Dict{String, Dict} = load_yaml(zone_spec_dir)

    return [create(FarmZone, z_spec) for (z_name, z_spec) in zone_specs if z_name in zone_names]
end