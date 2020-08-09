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
        basin.zones = Dict(k => create(v, climate) for (k, v) in zone_specs)

        return basin
    end
end
