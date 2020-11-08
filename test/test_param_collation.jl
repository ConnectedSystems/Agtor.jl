using Agtor, Dates, CSV
using Test

import Flatten

using Infiltrator


function setup_zone(data_dir::String="test/data/")
    zone_spec_dir::String = "$(data_dir)zones/"
    zone_specs::Dict{Symbol, Dict} = load_spec(zone_spec_dir)

    return [create(z_spec) for (z_name, z_spec) in zone_specs]
end
