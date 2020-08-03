using Mixers
using Agtor
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

    function CategoricalParameter(name::Symbol, cat_val::CategoricalArray, value::Any)::CategoricalValue
        min_val = 1
        max_val = length(cat_val)

        return new(name, cat_val, min_val, max_val, value, value)
    end

    function CategoricalParameter(name::Symbol, cat_val::CategoricalArray, default_value::Any, value::Any)::CategoricalValue
        min_val = 1
        max_val = length(cat_val)

        return new(name, cat_val, min_val, max_val, default_value, value)
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


"""
Generate AgParameter definitions.

Parameters
----------
prefix : str

dataset : Dict, of parameters for given component

override : Dict{str, object}, 
    values to override nominals with keys based on prefix + name

Returns
----------
* Dict matching structure of dataset
"""
function generate_agparams(prefix::Union{String, Symbol}, dataset::Dict, override::Union{Dict, Nothing}=nothing)::Dict{Symbol, Any}
    if "component" in keys(dataset)
        comp = dataset["component"]
        comp_name = dataset["name"]
        prefix *= "$(comp)___$(comp_name)"
    end

    if isnothing(override)
        override = Dict()
    end

    created::Dict{Union{String, Symbol}, Any} = copy(dataset)
    for (n, vals) in dataset
        var_id = prefix * "__$n"

        s = Symbol(n)
        pop!(created, n)

        if isa(vals, Dict)
            created[s] = generate_agparams(prefix*"__", vals, override)
            continue
        elseif endswith(String(n), "_spec")
            # Recurse into other defined specifications
            tmp = load_yaml(vals)
            created[s] = generate_agparams(prefix*"__", tmp, override)
            continue
        end
        
        # Replace nominal value with override value if specified
        if Symbol(var_id) in keys(override)
            vals = pop!(override, Symbol(var_id))
            created[s] = vals
            continue
        end

        if !in(vals[1], ["CategoricalParameter", "RealParameter", "ConstantParameter"])
            created[s] = vals
            continue
        end

        if isa(vals, Array)
            val_type, param_vals = vals[1], vals[2:end]

            def_val = param_vals[1]

            if length(unique(param_vals)) == 1
                created[s] = ConstantParameter(var_id, def_val)
                continue
            end

            valid_vals = param_vals[2:end]
            if val_type == "CategoricalParameter"
                valid_vals = categorical(valid_vals, ordered=true)
            end

            created[s] = eval(Symbol(val_type))(var_id, valid_vals, def_val)
        else
            created[s] = vals
        end
    end

    return created
end


function sample_params(dataset::Dict)
end


"""Extract parameter values from AgParameter"""
function extract_values(p::AgParameter; prefix::Union{String, Nothing}=nothing)::NamedTuple
    if !isnothing(prefix)
        name = prefix * p.name
    else
        name = p.name
    end

    if is_const(p)
        return (name=name, ptype=typeof(p), default=p.value, min_val=p.value, max_val=p.value)
    end

    return (name=name, ptype=typeof(p), default=p.default_val, min_val=p.min_val, max_val=p.max_val)
end


function collect_agparams!(dataset::Dict, store::Array; ignore::Union{Array, Nothing}=nothing)
    for (k, v) in dataset
        if !isnothing(ignore) && (k in ignore)
            continue
        end
        if v isa AgParameter && !is_const(v)
            push!(store, extract_values(v))
        elseif v isa Dict
            collect_agparams!(v, store; ignore=ignore)
        end
    end
end


"""Extract parameter values from Dict specification."""
function collect_agparams(dataset::Dict; prefix::Union{String, Nothing}=nothing)::Dict
    mm::Dict{Symbol, Any} = Dict()
    for (k, v) in dataset
        if v isa AgParameter && !is_const(v)
            if !isnothing(prefix)
                name = prefix * v.name
            else
                name = v.name
            end
            mm[Symbol(name)] = extract_values(v; prefix=prefix)
        end
    end

    return mm
end


# """Extract parameter values from Dict specification and store in a common Dict."""
function collect_agparams!(dataset::Dict, mainset::Dict)::Nothing
    for (k, v) in dataset
        if Symbol(v.name) in mainset
            error("$(v.name) is already set!")
        end

        if v isa AgParameter && !is_const(v)
            mainset[Symbol(v.name)] = extract_values(v)
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


function get_subtypes()
    return subtypes(DataFrame)
end


"""
Usage:
    zone_dir = "data_dir/zones/"
    zone_specs = load_yaml(zone_dir)
    zone_params = generate_agparams("", zone_specs["Zone_1"])
    
    collated_specs = []
    collect_agparams!(zone_params, collated_specs; ignore=["crop_spec"])

    z1 = create(FarmZone, zone_params)

    param_info = DataFrame(collated_specs)

    # Generate dataframe of samples
    samples = sample(param_info, 1000, sampler)  # where sampler is some function

    # Update z1 components with values found in first row
    @update z1 samples[1]
"""
function update_params(comp, sample)
    # entries = map(ap -> param_info(ap), Flatten.flatten(test_irrig, Agtor.AgParameter))

    tgt_params = names(sample)
    collated = []
    for f_name in fieldnames(typeof(comp))
        tmp_f = getfield(comp, f_name)
        if tmp_f isa Array
            arr_type = eltype(tmp_f)
            tmp_flat = reduce(vcat, Flatten.flatten(tmp_f, Array{arr_type}))
            for i in tmp_flat
                # tmp = Flatten.flatten(i, Agtor.AgParameter)
                update_params!(i, sample)
            end
        elseif isa(tmp_f, AgComponent) || isa(tmp_f, Dict)
            update_params!(tmp_f, sample)
        elseif tmp_f isa AgParameter
            update_params!(tmp_f, sample)
        end
    end
end

function update_params!(comp::Dict, sample)
    for (k,v) in comp
        if v isa AgParameter
            update_params!(v, sample)
        end
    end
end

function update_params!(p::AgParameter, sample)
    if p.name in names(sample)
        p.value = sample[Symbol(p.name)]
    end
end

# collated = []
# for f_name in fieldnames(typeof(z1))
#     tmp_f = getfield(z1, f_name)
#     f_type = typeof(tmp_f)
#     if tmp_f isa Array
#         arr_type = eltype(tmp_f)
#         tmp_flat = reduce(vcat, Flatten.flatten(tmp_f, Array{arr_type}))
#         for i in tmp_flat
#             tmp = map(ap -> param_info(ap), Flatten.flatten(i, Agtor.AgParameter))
#             append!(collated, tmp)
#         end
#     elseif f_type in all_comps
#         tmp = map(ap -> param_info(ap), Flatten.flatten(tmp_f, Agtor.AgParameter))
#         append!(collated, tmp)
#     end
# end
