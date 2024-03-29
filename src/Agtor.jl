__precompile__()

module Agtor

using Parameters
using DataFrames, Dates, YAML, CSV
using Distributed

import OrderedCollections: LittleDict
import DataStructures: OrderedDict, DefaultDict

include("AgBase/Units.jl")
include("AgBase/Component.jl")
include("AgBase/Parameter.jl")
include("AgBase/io.jl")
include("AgBase/properties.jl")
include("AgBase/ResultsHandler.jl")
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
include("Model.jl")


AgUnion = Union{Int64, Float64, Agtor.AgParameter}

const component_sep = "└──"
const component_name_sep = "-"
const component_field_sep = "~"


export @def, AgUnion

export load_yaml, load_spec, load_climate, create
export generate_agparams, create, reset!
export AgComponent, AgParameter, Infrastructure, Irrigation, Pump
export WaterSource, Crop, FarmField, CropField, FarmZone
export Manager, EconManager, RigidManager, associate_managers
export Climate, Basin, run_timestep!, subtotal_costs, total_costs, update_available_water!
export collect_results, min_max, extract_values, param_info, extract_spec, add_prefix!
export set_params!, extract_agparams, collect_agparams!, collect_agparams, update_model!
export water_used_by_source
export get_data_for_timestep, aggregate_field_logs, run_model
export run_scenarios!, save_results!, save_state!
export collate_results, collate_results!, component_relationship
export select_results, scenario_stats, results_df

end # module
