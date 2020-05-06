using Mixers

abstract type AgParameter end

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
end

@with_kw mutable struct CategoricalParameter <: AgParameter
    name::String
    cat_val::Array{Any}
    default_val::Any
    value::Any
    
end

function Base.:+(x::AgParameter, y::AgParameter) x.value + y.value end
function Base.:-(x::AgParameter, y::AgParameter) x.value - y.value end
function Base.:/(x::AgParameter, y::AgParameter) x.value / y.value end
function Base.:*(x::AgParameter, y::AgParameter) x.value * y.value end
function Base.:^(x::AgParameter, y::AgParameter) x.value^y.value end

function Base.:*(x::String, y::ConstantParameter) x * y.value end

function Base.convert(x::Type{Any}, y::Agtor.AgParameter) convert(x, y.value) end


"""Returns min/max values"""
function value_range(p::AgParameter)::Tuple
    if hasproperty(p, :min_val) == false
        return p.value, p.value
    end
    return p.min, p.max
end


"""Returns max - min, or 0.0 if no min value defined"""
function value_dist(p::AgParameter)::Float64
    if hasproperty(p, :min_val) == false
        return 0.0
    end
    return p.max - p.min
end


function is_const(p::AgParameter)::Bool
    if (p isa ConstantParameter) || (value_dist(p) == 0.0)
        return true
    end
    return false
end
