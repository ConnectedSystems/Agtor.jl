import Agtor: set_next_crop!, update_stages!, in_season, load_yaml, Basin


function setup_basin(data_dir::String="test/data/")
    basin_spec_dir::String = "$(data_dir)basins/"
    basin_specs::Dict{String, Dict} = load_yaml(basin_spec_dir)

    return [Basin(b) for (k, b) in basin_specs]
end

test = setup_basin()