
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
