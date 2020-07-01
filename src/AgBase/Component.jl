
abstract type AgComponent end

function create(cls::Type{T}, data::Dict{Any, Any},
                override=nothing) where T <: AgComponent
    cls_name = Base.typename(cls)
    tmp = copy(data)
    name = tmp["name"]
    prop = pop!(tmp, "properties")

    tmp = Dict(Symbol(s) => v for (s, v) in tmp)

    prefix = "$(cls_name)___$name"
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
