import DataStructures: counter


mutable struct Basin <: AgComponent
    name::String
    zones::Tuple
    climate::Climate
    managers::Tuple
    current_ts::NamedTuple{(:idx, :dt)}

    function Basin(; name, zone_spec, climate_data, managers)
        basin = new()
        basin.name = name

        climate::Climate = load_climate(climate_data)
        basin.climate = climate
        basin.current_ts = (idx=1, dt=climate.time_steps[1])

        basin.managers = Tuple(mg for (mg, _) in managers)

        basin.zones = Tuple(create(v, climate) for (k, v) in zone_spec)
        assign_managers!(managers, basin.zones)

        return basin
    end
end


"""
# Example

```julia
# Load zone specifications
zone_specs = load_spec("test/data/zones")

# Define managers of interest
Manager_A = BaseManager("optimizing")
Manager_B = RigidManager("rigid", 0.05)

# Create tuple-based relation between managers and zones (by name)
manage_zones = ((Manager_A, ("Zone_1", )), (Manager_B, ("Zone_2", "Zone_3")))

# Attach managers to their associated zones
assign_managers!(manage_zones, values(zone_specs))
```

Raises `ArgumentError` if duplicate zone names are found.
"""
function assign_managers!(rel::Tuple, zones)
    all_names = []
    for (mg, zone_names) in rel
        for tgt_name in zone_names
            for zone in zones
                if string(tgt_name) == zone.name
                    push!(all_names, tgt_name)
                    zone.manager = mg
                end
            end
        end
    end

    dups::Array{String} = String[k for (k, v) in counter(all_names) if v > 1]
    if length(dups) > 0
        throw(ArgumentError("Cannot co-manage a zone!\nDuplicates found: $(dups)"))
    end

    if length(all_names) != length(zones)
        throw(ArgumentError("One or more zones are missing a manager"))
    end
end


function reset!(b::Basin)::Nothing
    for z in b.zones
        reset!(z)
    end

    b.current_ts = (idx=1, dt=b.climate.time_steps[1])

    return nothing
end


"""Collect model run results for a Basin"""
function collect_results(basin::Basin; last=false)::Dict
    results = Dict()
    sizehint!(results, length(basin.zones))

    for z in basin.zones
        results[z.name] = collect_results(z)
    end

    return results
end
