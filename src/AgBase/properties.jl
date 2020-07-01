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
function generate_params(prefix::String, dataset::Dict, override::Union{Dict, Nothing}=nothing)::Dict{Symbol, Union{Dict, Union{AgParameter, Any}}}
    prefix *= "__"
    if isnothing(override)
        override = Dict()
    end

    created::Dict{Union{String, Symbol}, Union{AgParameter, Any}} = copy(dataset)
    for (n, vals) in dataset
        var_id = prefix * n

        s = Symbol(n)
        pop!(created, n)

        if isa(vals, Dict)
            created[s] = generate_params(prefix, vals, override)
            continue
        end
        
        # Replace nominal value with override value if specified
        if var_id in keys(override)
            vals = pop!(override, var_id)
            created[s] = ConstantParameter(var_id, vals)
            continue
        end

        if length(vals) == 1
            created[s] = ConstantParameter(var_id, vals)
            continue
        end 

        val_type, param_vals = vals[1], vals[2:end]

        if length(unique(param_vals)) == 1
            created[s] = ConstantParameter(var_id, param_vals[1])
            continue
        end

        ptype = Symbol(val_type)
        created[s] = eval(ptype)(var_id, param_vals[2:end]..., param_vals[1])
    end

    return created
end


function sample_params(dataset::Dict)
end


# def sort_param_types(element, unc, cats, consts):
#     if not isinstance(element, dict):
#         return unc, cats, consts

#     for el in element.values():
#         if isinstance(el, dict):
#             unc, cats, consts = sort_param_types(el, unc, cats, consts)
#         elif isinstance(el, Constant):
#             consts += [el]
#         elif isinstance(el, CategoricalParameter):
#             cats += [el]
#         elif isinstance(el, RealParameter):
#             unc += [el]
#         # End if
#     # End for

#     return unc, cats, consts
# # End sort_param_types()


# def get_samples(params, num_samples, sampler):
#     uncerts, cats, consts = params

#     design = sampler.generate_designs(uncerts+cats, num_samples)
#     const_params = (consts, ) * num_samples

#     consts_arr = [[p.value for p in i_row] for i_row in const_params]

#     uc_arr = np.array(design.designs)

#     combined = np.column_stack(
#         [arr for arr in [uc_arr, consts_arr] if len(arr) > 0]
#     )

#     labels = design.params + [str(i.name) for i in const_params[0]]

#     matrix = pd.DataFrame(combined, columns=labels)

#     return matrix
# # End get_samples()
