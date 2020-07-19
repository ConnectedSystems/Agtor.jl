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


function create(cls::Type{T}, data::Dict;
                override::Union{Dict, Nothing}=nothing, 
                id_prefix::Union{String, Nothing}=nothing) where T <: AgComponent
    cls_name = Base.typename(cls)
    tmp = copy(data)
    name = tmp["name"]
    prop = pop!(tmp, "properties")

    tmp = Dict(Symbol(s) => v for (s, v) in tmp)

    prefix::String = "$(cls_name)___$name"
    @add_preprefix

    props::Dict{Symbol, Any} = generate_params(prefix, prop, override)

    return cls(; tmp..., props...)
end


function Base.getproperty(A::AgComponent, v::Symbol)
    field = getfield(A, v)
    if field isa AgParameter
        return field.value
    end

    return field
end
