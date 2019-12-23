
abstract type AgComponent end

function create(cls::Type{T}, data::Dict{Any, Any},
                override=Nothing) where T <: AgComponent
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


# @dataclass
# class Component:

#     def __getattribute__(self, attr):
#         v = object.__getattribute__(self, attr)
#         if isinstance(v, (CategoricalParameter, Constant, RealParameter)):
#             try:
#                 val = v.value
#             except AttributeError:
#                 val = v.default
#             # End try

#             return val

#         return v
#     # End __getattribute__()

#     def get_nominal(self, item):
#         if isinstance(item, (CategoricalParameter, Constant, RealParameter)):
#             try:
#                 val = item.value
#             except AttributeError:
#                 val = item.default
#             # End try

#             return val

#         return item
#     # End get_nominal()

#     @classmethod
#     def load_data(cls, name, data, override=None):
#         prefix = f"Irrigation___{name}"
#         props = generate_params(prefix, data['properties'], override)

#         return {
#             'name': name,
#             'properties': props
#         }
#     # End load_data()

#     @classmethod
#     def collate_data(cls, data: Dict):
#         """Produce flat lists of crop-specific parameters.

#         Parameters
#         ----------
#         * crop_data : Dict, of crop_data

#         Returns
#         -------
#         * tuple[List] : (uncertainties, categoricals, and constants)
#         """
#         unc, cats, consts = sort_param_types(data['properties'], unc=[], cats=[], consts=[])

#         return unc, cats, consts
#     # End collate_data()

#     @classmethod
#     def create(cls, data, override=None):
#         cls_name = cls.__class__.__name__

#         tmp = data.copy()
#         name = tmp['name']
#         prop = tmp.pop('properties')

#         prefix = f"{cls_name}___{name}"
#         props = generate_params(prefix, prop, override)

#         return cls(**tmp, **props)
#     # End create()

# # End Component()
