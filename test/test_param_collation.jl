import Agtor: set_next_crop!, update_stages!, in_season, load_yaml
using Agtor, Dates, CSV
using Test

import Flatten

using Infiltrator


function setup_zone(data_dir::String="test/data/")
    zone_spec_dir::String = "$(data_dir)zones/"
    zone_specs::Dict{String, Dict} = load_yaml(zone_spec_dir)

    return [create(FarmZone, z_spec) for (z_name, z_spec) in zone_specs]
end


function collect_params(data::Array)
    a = []
    for i in data
        if i isa AgComponent
            append!(a, param_info(i))
        elseif i isa Dict
            append!(a, collect_params(i))
        end
    end

    return a
end


function collate_params(data_dir::String="test/data/")
    z1 = setup_zone(data_dir)[1]

    components = subtypes(AgComponent)

    # Collect all subtypes of AgComponent
    all_ = Base.Iterators.flatten([subtypes(sc) for sc in components 
                                   if length(subtypes(sc)) > 0])
    all_comps = vcat(collect(all_), components)

    ignore = [Climate, FarmZone, Manager, Infrastructure]

    all_comps = [i for i in all_comps if !in(i, ignore)]

    @info components, all_comps

    collated = []
    for f_name in fieldnames(typeof(z1))
        tmp_f = getfield(z1, f_name)
        f_type = typeof(tmp_f)
        if tmp_f isa Array
            arr_type = eltype(tmp_f)
            tmp_flat = reduce(vcat, Flatten.flatten(tmp_f, Array{arr_type}))
            for i in tmp_flat
                tmp = map(ap -> param_info(ap), Flatten.flatten(i, Agtor.AgParameter))
                append!(collated, tmp)
            end
        elseif f_type in all_comps
            tmp = map(ap -> param_info(ap), Flatten.flatten(tmp_f, Agtor.AgParameter))
            append!(collated, tmp)
        end
    end

    @info length(collated) collated

    return collated
end


# @testset "Agtor.jl" begin
#     collate_params()
# end

all_agparams = collate_params()

