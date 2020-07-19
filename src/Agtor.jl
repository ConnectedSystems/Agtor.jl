__precompile__()

module Agtor

using Parameters
using CSV, DataFrames, Dates, YAML

import DataStructures: OrderedDict, DefaultDict

include("AgBase/Units.jl")
include("AgBase/file_loader.jl")
include("AgBase/Parameter.jl")
include("AgBase/properties.jl")
include("AgBase/Component.jl")
include("Infrastructure/Infrastructure.jl")
include("Infrastructure/Irrigation.jl")
include("Infrastructure/Pump.jl")
include("WaterSource.jl")
include("Crop.jl")
include("Field.jl")
include("Zone.jl")
include("Manager.jl")
include("Climate.jl")
include("Basin.jl")

AgUnion = Union{Int64, Float64, Agtor.AgParameter}

export AgComponent, AgParameter, Infrastructure, Irrigation, Pump
export WaterSource, Crop, FarmField, CropField, FarmZone, Manager, Climate, Basin
export load_yaml, generate_params, create, run_timestep, subtotal_costs, total_costs
export collect_results, min_max, param_values, AgUnion, add_prefix!, @def

end # module
