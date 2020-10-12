using Flatten


abstract type AgComponent end


macro def(name, definition)
    return quote
        macro $(esc(name))()
            esc($(Expr(:quote, definition)))
        end
    end
end


@def add_preprefix begin
    if !isnothing(id_prefix)
        prefix = id_prefix * prefix
    end
end


function create(spec::Dict)
    dt = deepcopy(spec)
    cls_name = pop!(dt, :component)
    cls = eval(Symbol(cls_name))

    if cls_name == "FarmZone"
        cd_fn::Union{String, Nothing} = get(spec, :climate_data, nothing)
        if isnothing(cd_fn)
            error("Climate data not found in Zone spec.")
        end

        # Expect only CSV for now...
        if endswith(cd_fn, ".csv")
            use_threads = Threads.nthreads() > 1
            climate_seq = DataFrame!(CSV.File(cd_fn, threaded=use_threads, dateformat="dd-mm-YYYY"))
            climate_data = Climate(climate_seq)
        else
            error("Currently, climate data can only be provided in CSV format")
        end

        return create(dt, climate_data)
    end

    return cls(; dt...)
end


function create(spec::Dict, climate_data::String)
    dt = deepcopy(spec)
    cls_name = pop!(dt, :component)
    cls = eval(Symbol(cls_name))

    if cls_name == "Basin"
        return cls(dt[:name], dt[:zone_spec]; 
                   climate_data=climate_data)
    end

    error("Unknown component: $(cls_name), with additional parameter '$(climate_data)'")
end


function Base.getproperty(A::AgComponent, v::Symbol)
    field = getfield(A, v)
    if field isa AgParameter
        return field.value
    end

    return field
end
