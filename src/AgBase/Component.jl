
abstract type AgComponent end

function create(cls::Type{T}, data::Dict{Any, Any},
                override=nothing) where T <: AgComponent
    cls_name = typeof(cls)
    tmp = copy(data)
    name = tmp["name"]
    prop = pop!(tmp, "properties")

    tmp = Dict(Symbol(s) => v for (s, v) in tmp)
    # prop = Dict(Symbol(s) => v for (s, v) in prop)

    prefix = "$(cls_name)___$name"
    props = generate_params(prefix, prop, override)

    return cls(; tmp..., props...)
end
