__precompile__()

module Agtor

using Parameters
using DataFrames, Dates, YAML, CSV

import DataStructures: OrderedDict, DefaultDict

include("AgBase/Units.jl")
include("AgBase/Parameter.jl")
include("AgBase/io.jl")
include("AgBase/properties.jl")
include("AgBase/Component.jl")
include("Infrastructure/Infrastructure.jl")
include("Infrastructure/Irrigation.jl")
include("Infrastructure/Pump.jl")
include("Climate.jl")
include("WaterSource.jl")
include("Crop.jl")
include("Field.jl")
include("Zone.jl")
include("Manager.jl")
include("RigidManager.jl")
include("Basin.jl")


AgUnion = Union{Int64, Float64, Agtor.AgParameter}

export load_yaml, generate_agparams, load_spec, create, AgUnion
export AgComponent, AgParameter, Infrastructure, Irrigation, Pump
export WaterSource, Crop, FarmField, CropField, FarmZone
export Manager, BaseManager, RigidManager
export Climate, Basin, run_timestep, subtotal_costs, total_costs, update_available_water!
export collect_results, min_max, extract_values, param_info, extract_spec, add_prefix!, @def
export set_params!, extract_agparams, collect_agparams!, collect_agparams, update_model!
export aggregate_field_logs, save_results!, collate_results!

end # module
