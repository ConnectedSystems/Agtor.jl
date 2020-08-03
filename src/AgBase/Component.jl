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


# macro create(cls, comp_spec, id_prefix, collated=nothing, other=nothing)

#     return :(begin
#         local cls_name = Base.typename($cls) 
#         local spec = copy($(esc(comp_spec)))
#         local name = spec["name"]
#         local prefix = String($id_prefix)
#         prefix = prefix * "$(cls_name)___$name"
#         local props = generate_agparams(prefix, pop!(spec, "properties"))

#         local tmp = extract_spec(props)

#         if !isnothing($(esc(collated)))
#             append!($(esc(collated)), tmp)
#         end

#         spec = Dict(Symbol(s) => v for (s, v) in spec)

#         local op = $(esc(other))
#         if !isnothing(op)
#             return create($cls, spec, props; id_prefix=prefix, op...)
#         else
#             return create($cls, spec, props; id_prefix=prefix)
#         end
#     end)
# end


function create(spec::Dict)
    dt = copy(spec)

    cls_name = pop!(dt, :component)
    cls = eval(Symbol(cls_name))
    return cls(; dt...)
end


function Base.getproperty(A::AgComponent, v::Symbol)
    field = getfield(A, v)
    if field isa AgParameter
        return field.value
    end

    return field
end
