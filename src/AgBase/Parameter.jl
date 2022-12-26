import DataFrames: DataFrame, DataFrameRow
import Flatten: flatten
import Dates

using CategoricalArrays
using Mixers
using Agtor


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

    RealParameter(name, min_val, max_val, d_val, value) = new(name, min_val, max_val, d_val, value)
    RealParameter(name, min_val, max_val, value) = new(name, min_val, max_val, value, value)
    RealParameter(name, range_vals::Array, value) = new(name, range_vals..., value, value)
end


@doc """
    CategoricalParameter

Min and max values will map to (integer) element position in an CategoricalArray.

Sampling between the min and max values will be mapped to their categorical value in the given array
using `floor()` of the Float value `x`.

Valid values for the CategoricalParameter will therefore be: 
`1 <= x < (n+1)`, where n is number of options.
"""
@with_kw mutable struct CategoricalParameter <: AgParameter
    name::String
    cat_val::CategoricalArray
    min_val::Int64
    max_val::Int64
    default_val::Any
    value::Any

    function CategoricalParameter(name::String, cat_val::CategoricalArray, value::Any)::CategoricalValue
        min_val = 1
        max_val = length(cat_val) + 1

        return new(name, cat_val, min_val, max_val, value, value)
    end

    function CategoricalParameter(name::String, cat_val::CategoricalArray, default_value::Any, value::Any)::CategoricalValue
        min_val = 1
        max_val = length(cat_val) + 1

        return new(name, cat_val, min_val, max_val, default_value, value)
    end
end

"""Setter for CategoricalParameter to handle float to categorical element position."""
function Base.setproperty!(cat::CategoricalParameter, v::Symbol, value)::Nothing
    if v == :value
        if value isa AbstractFloat || value isa Integer
            cat_pos = floor(Int, value)
            cat.value = cat.cat_val[cat_pos]
        elseif value isa String
            pos = cat.cat_val(findfirst(x-> x == value, cat.cat_val))
            if isnothing(pos)
                throw(ArgumentError("$(pos) is not a valid option for $(cat.name)"))
            end

            cat.value = cat.cat_val[pos]
        else
            throw(ArgumentError("Type $(typeof(value)) is not a valid type option for $(cat.name), has to be Integer, Float or String"))
        end
    else
        setfield!(f, Symbol(v), value)
    end

    return nothing
end


"""
    agin(p::AgParameter, store::Array)::Bool

Agtor specific `in` function.

Purposeful decision not to override Base.in() method as this
performs the check on any Array expecting NamedTuples.
"""
function agin(p::AgParameter, store::Array)::Bool
    for st in store
        if st.name == p.name
            return true
        end
    end

    return false
end


# Below is equivalent to defining methods for each operation, e.g:
#    function Base.:+(x::AgParameter, y::AgParameter) x.value + y.value end
for op = (:+, :-, :/, :*, :^, :<, :>, :%)
    @eval Base.$op(x::AgParameter, y::AgParameter) = Base.$op(x.value, y.value)
end

for op = (:+, :-, :/, :*, :^, :<, :>, :%)
    @eval Base.$op(x::Number, y::AgParameter) = Base.$op(x, y.value)
    @eval Base.$op(x::AgParameter, y::Number) = Base.$op(x.value, y)
end

for op = (:isless, :isgreater)
    @eval Base.$op(x::AgParameter, y::Number) = Base.$op(x.value, y)
end

Base.:*(x::String, y::Union{ConstantParameter, CategoricalParameter}) = x * y.value

Base.convert(::Type{T}, x::AgParameter) where {T<:Number} = T(x.value)
Base.convert(x::Type{Any}, y::Agtor.ConstantParameter) = convert(x, y.value)

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

# Arguments
- prefix : str
- dataset : Dict, of parameters for given component

# Returns
- Dict matching structure of dataset
"""
function generate_agparams(prefix::Union{String, Symbol}, dataset::Dict)::Dict{Symbol, Any}
    comp_sep = Agtor.component_sep
    name_sep = Agtor.component_name_sep
    field_sep = Agtor.component_field_sep

    if "component" in keys(dataset)
        comp = dataset["component"]
        comp_name = dataset["name"]

        if prefix === ""
            prefix *= "$(comp)$(name_sep)$(comp_name)"
        else
            prefix *= "$(comp_sep)$(comp)$(name_sep)$(comp_name)"
        end
    end

    created::Dict{Any, Any} = deepcopy(dataset)
    for (n, vals) in dataset
        var_id = "$(prefix)$(field_sep)$n"

        s = Symbol(n)
        pop!(created, n)

        if isa(vals, Dict)
            created[s] = generate_agparams(prefix, vals)
            continue
        elseif endswith(String(n), "_spec")
            # Recurse into other defined specifications
            tmp = load_yaml(vals)
            created[s] = generate_agparams(prefix, tmp)
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


function collect_agparams!(dataset::Dict, store::Array; ignore::Union{Array, Nothing}=nothing)::DataFrame
    for (k, v) in dataset
        if !isnothing(ignore) && (k in ignore)
            continue
        end

        if v isa AgParameter && !is_const(v)
            if !agin(v, store)
                push!(store, extract_values(v))
            end
        elseif v isa Dict || v isa Array
            collect_agparams!(v, store; ignore=ignore)
        end
    end

    return DataFrame(store)
end


"""Extract parameter values from Dict specification."""
function collect_agparams(dataset::Dict; ignore::Union{Array, Nothing}=nothing)::DataFrame
    return collect_agparams!(dataset, []; ignore=ignore)
end


function collect_agparams!(dataset::Union{Array, Tuple}, store::Array; ignore::Union{Array, Nothing}=nothing)::Nothing
    for v in dataset
        if v isa AgParameter && !is_const(v)
            if !agin(v, store)
                push!(store, extract_values(v))
            end
        elseif v isa Dict || v isa Array || v isa AgComponent || v isa Tuple
            collect_agparams!(v, store; ignore=ignore)
        end
    end

    return nothing
end


"""Extract parameter values from AgComponent."""
function collect_agparams!(dataset::Union{AgComponent, AgParameter}, store::Array; ignore=nothing)::DataFrame
    match = (Array, Tuple, Dict, AgComponent, AgParameter)

    for fn in fieldnames(typeof(dataset))

        fv = getfield(dataset, fn)
        if fv isa AgParameter && !is_const(fv)
            if !agin(fv, store)
                push!(store, extract_values(fv))
            end
        elseif any(map(x -> fv isa x, match))
            if fv isa Array{Date}
                continue
            end
            collect_agparams!(fv, store; ignore=ignore)
        end
    end

    return DataFrame(store)
end

function collect_agparams!(dataset::Union{AgComponent, AgParameter}; ignore=nothing)::DataFrame
    return collect_agparams!(dataset, []; ignore=nothing)
end


"""Extract parameter values from Dict specification and store in a common Dict."""
function collect_agparams!(dataset::Dict, mainset::Dict)::Nothing
    for (k, v) in dataset
        if Symbol(v.name) in mainset
            throw(ArgumentError("$(v.name) is already set!"))
        end

        if v isa AgParameter && !is_const(v)
            mainset[Symbol(v.name)] = extract_values(v)
        end
    end

    return
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
function add_prefix!(prefix::String, component)::Nothing
    params = flatten(component, AgParameter)
    for pr in params
        setfield!(pr, :name, prefix*pr.name)
    end

    return
end


"""
# Example

```julia
zone_dir = "data_dir/zones/"
zone_specs = load_yaml(zone_dir)
zone_params = generate_agparams("", zone_specs["Zone_1"])

collated_specs = []
collect_agparams!(zone_params, collated_specs; ignore=["crop_spec"])

# Expect only CSV for now...
climate_fn::String = "data/climate/farm_climate_data.csv"
climate::Climate = load_climate(climate_fn)
z1 = create(zone_params, climate)

param_info = DataFrame(collated_specs)

# Generate dataframe of samples
samples = sample(param_info, 1000, sampler)  # where sampler is some function

# Update z1 components with values found in first row
set_params!(z1, samples[1])
```
"""
function set_params!(comp, sample)::Nothing
    match = (Array, Tuple, Dict, AgComponent, AgParameter)
    for f_name in fieldnames(typeof(comp))
        tmp_f = getfield(comp, f_name)

        if any(map(x -> isa(tmp_f, x), match))
            set_params!(tmp_f, sample)
        end
    end

    return
end


function set_params!(comp::Array, sample)::Nothing
    arr_type = eltype(comp)
    tmp_flat = reduce(vcat, Flatten.flatten(comp, Array{arr_type}))
    for i in tmp_flat
        set_params!(i, sample)
    end

    return
end


function set_params!(comp::Dict, sample)::Nothing
    for (k,v) in comp
        set_params!(v, sample)
    end

    return
end

function set_params!(p::AgParameter, sample::Union{DataFrame, DataFrameRow})::Nothing
    p_name::Symbol = Symbol(p.name)
    if p_name in names(sample)
        setfield!(p, :value, sample[p_name])
    end

    return
end


function set_params!(p::AgParameter, sample::Union{Number, String})::Nothing
    setfield!(p, :value, sample)

    return
end


function set_params!(p::AgParameter, sample::Union{Dict, NamedTuple})::Nothing
    p_name::Symbol = Symbol(p.name)
    if p_name in keys(sample)
        setfield!(p, :value, sample)
    end

    return
end


function update_model!(comp, sample)::Nothing
    set_params!(comp, sample)

    return
end


"""
Create relational mapping between components and values.
"""
function component_relationship(agparams::DataFrame)::Dict
    comp_sep = Agtor.component_sep
    name_sep = Agtor.component_name_sep
    field_sep = Agtor.component_field_sep
    
    relation = Dict()
    names = agparams.name

    for n in names
        nstr = String(n)
        components = split(nstr, comp_sep)
        top_level = components[1]

        if !haskey(relation, top_level)
            relation[top_level] = Dict() 
        end
            
        upper = relation[top_level]
        
        for c in components[2:end]
            if contains(c, field_sep)
                comp, fld_name = Tuple(split(c, field_sep))

                field_values = agparams[in([n]).(names), [:default, :min_val, :max_val]]
                field_values = copy(field_values[1, :])

                if haskey(upper, comp)
                    upper[comp][fld_name] = field_values
                else
                    upper[comp] = Dict(fld_name=>field_values)
                end

                continue
            end

            if !haskey(upper, c)
                upper[c] = Dict()
            end
            
            upper = upper[c]
        end
    end

    return relation
end

