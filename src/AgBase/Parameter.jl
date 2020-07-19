using Mixers
import Flatten
import Dates


abstract type AgParameter end


AgUnion = Union{Date, Int64, Float64, AgParameter}

@with_kw mutable struct ConstantParameter <: AgParameter
    name::String
    default_val::Any
    value::Any

    ConstantParameter(name, default_val) = new(name, default_val, default_val)
end

@with_kw mutable struct RealParameter <: AgParameter
    name::String
    min_val::Float64
    max_val::Float64
    default_val::Float64
    value::Float64

    RealParameter(name, min_val, max_val, value) = new(name, min_val, max_val, value, value)
    RealParameter(name, range_vals::Array, value) = new(name, range_vals..., value, value)
end

@with_kw mutable struct CategoricalParameter <: AgParameter
    name::String
    cat_val::CategoricalArray
    min_val::Int64
    max_val::Int64
    default_val::Any
    value::Any

    function CategoricalParameter(name::String, cat_val::CategoricalArray, value::Any)::CategoricalValue
        min_val = 1
        max_val = length(cat_val)

        return new(name, cat_val, min_val, max_val, value, value)
    end

    function CategoricalParameter(name::String, cat_val::CategoricalArray, default_value::Any, value::Any)::CategoricalValue
        min_val = 1
        max_val = length(cat_val)

        return new(name, cat_val, min_val, max_val, value, value)
    end
end


# Below is equivalent to defining methods for each operation, e.g:
#    function Base.:+(x::AgParameter, y::AgParameter) x.value + y.value end
for op = (:+, :-, :/, :*, :^)
    @eval Base.$op(x::AgParameter, y::AgParameter) = Base.$op(x.value, y.value)
end

for op = (:+, :-, :/, :*, :^)
    @eval Base.$op(x::Union{Int, Real}, y::AgParameter) = Base.$op(x, y.value)
end

for op = (:+, :-, :/, :*, :^)
    @eval Base.$op(x::AgParameter, y::Union{Int, Real}) = Base.$op(x.value, y)
end


function Base.:*(x::String, y::Union{ConstantParameter, CategoricalParameter}) x * y.value end

# function Base.convert(x::Type{Any}, y::Agtor.AgParameter) convert(x, y.value) end
function Base.convert(x::Type{Any}, y::Agtor.ConstantParameter) convert(x, y.value) end


for op = (:Year, :Month, :Day)
    @eval Dates.$op(x::AgParameter) = Dates.$op(x.value)
end


"""Returns min/max values"""
function min_max(p::AgParameter)
    if is_const(p)
        return p.value
    end

    return p.min_val, p.max_val
end


"""Returns min/max values"""
function min_max(dataset::Dict)::Dict
    mm::Dict{Union{Dict, Symbol}, Union{Dict, Any}} = Dict()
    for (k, v) in dataset
        if v isa AgParameter
            mm[k] = min_max(v)
        else
            mm[k] = v
        end
    end

    return mm
end


function param_info(p::AgParameter)
    return (name=p.name, ptype=typeof(p), param_values(p)...)
end


"""Extract parameter values from AgParameter"""
function param_values(p::AgParameter)
    if is_const(p)
        return (default=p.value, min_val=p.value, max_val=p.value)
    end

    return (default=p.default_val, min_val=p.min_val, max_val=p.max_val)
end


"""Extract parameter values from Dict specification."""
function param_values(dataset::Dict)::Dict
    mm::Dict{Symbol, Any} = Dict()
    for (k, v) in dataset
        if v isa AgParameter && !is_const(v)
            mm[Symbol(v.name)] = param_values(v)
        end
    end

    return mm
end


"""Extract parameter values from Dict specification and store in a common Dict."""
function param_values!(dataset::Dict, mainset::Dict)::Nothing
    for (k, v) in dataset
        if Symbol(v.name) in mainset
            error("$(v.name) is already set!")
        end

        if v isa AgParameter && !is_const(v)
            mainset[Symbol(v.name)] = param_values(v)
        end
    end
end


"""Checks if parameter is constant."""
function is_const(p::AgParameter)::Bool
    if (p isa ConstantParameter) || (value_range(p) == 0.0)
        return true
    end

    return false
end


"""Returns max - min, or 0.0 if no min value defined"""
function value_range(p::AgParameter)::Float64
    if hasproperty(p, :min_val) == false
        return 0.0
    end

    return p.max_val - p.min_val
end


"""Modify AgParameter name in place by adding a prefix."""
function add_prefix!(prefix, component)
    params = Flatten.flatten(component, AgParameter)
    for pr in params
        pr.name = prefix*pr.name
    end
end



# function collate_agparams(spec::Dict, real, consts, cats)

# end
