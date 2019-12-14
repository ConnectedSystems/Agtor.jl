using Mixers

abstract type AgParameter end

mutable struct ConstantParameter <: AgParameter
    name::String
    default_val::Any
    value::Any

    ConstantParameter(name, default_val) = new(name, default_val, default_val)
end

mutable struct RealParameter <: AgParameter
    name::String
    min_val::Real
    max_val::Real
    default_val::Real
    value::Real
end

mutable struct CategoricalParameter <: AgParameter
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
    if !hasproperty(p, :min_val)
        return p.value, p.value
    end
    return p.min, p.max
end

"""Returns max - min, or 0.0 if no min/max values defined"""
function value_dist(p::AgParameter)
    if !hasproperty(p, :min_val)
        return 0.0
    end
    return p.max - p.min
end

function is_const(p::AgParameter)
    if value_dist(p::AgParameter) == 0.0
        return true
    end
    return false
end
