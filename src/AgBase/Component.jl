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

        climate::Climate = load_climate(cd_fn)

        return create(dt, climate)
    end

    return cls(; dt...)
end


function create(spec::Dict, climate_data::String)
    dt = deepcopy(spec)
    cls_name = pop!(dt, :component)
    cls = eval(Symbol(cls_name))

    if cls_name == "Basin"
        return cls(; name=dt[:name], zone_specs=dt[:zone_spec], 
                   climate_data=dt[:climate_data])
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
