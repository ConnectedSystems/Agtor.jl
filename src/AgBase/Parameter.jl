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
    min_val::Real
    max_val::Real
    default_val::Real
    value::Real

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


"""Returns min/max values"""
function value_range(p::AgParameter)
    if hasproperty(p, :min_val) == false
        return p.value, p.value
    end
    return p.min, p.max
end

"""Returns max - min, or 0.0 if no min value defined"""
function value_dist(p::AgParameter)
    if hasproperty(p, :min_val) == false
        return 0.0
    end
    return p.max - p.min
end

function is_const(p::AgParameter)
    if value_dist(p) == 0.0
        return true
    end
    return false
end
