
mutable struct Basin <: AgComponent
    name::String
    zones::Dict{Symbol, FarmZone}
    managers::Dict{Symbol, Manager}

    function Basin(; name, zone_spec, climate_data)
        basin = new()
        basin.name = name

        climate::Climate = load_climate(climate_data)
        basin.zones = Dict(k => create(v, climate) for (k, v) in zone_spec)
        managers = nothing

        return basin
    end
end
