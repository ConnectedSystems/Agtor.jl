module agtor

using Unitful
import Unitful: ML, ha, m, mm
using Parameters
using Dates

import DataStructures: OrderedDict

include("AgBase/Parameter.jl")
include("AgBase/Component.jl")
include("Infrastructure/Infrastructure.jl")
include("Infrastructure/Pump.jl")
include("WaterSource.jl")
include("Crop.jl")
include("Field.jl")
include("Zone.jl")
include("Manager.jl")


export AgComponent, Infrastructure, Pump, WaterSource


end # module
