abstract type FarmField end

@with_kw mutable struct CropField <: FarmField
    name::String
    total_area_ha::Quantity{ha}
    crop::Crop
    crop_choices::Array{Crop}
    crop_rotation::Array{Crop}
    soil_TAW::Float64
    soil_SWD::Float64
    ssm::Quantity{mm} = 0.0
    _irrigated_volume::Dict = Dict{String, Float64}()
    _num_irrigation_events::Int64 = 0

end

"""Getter for Field"""
function Base.getproperty(f::FarmField, v::Symbol)
    if v == :irrigated_volume
        return sum(values(f._irrigated_volume))

    elseif v == :irrigation_from_source
        return copy(f._irrigated_volume)

    elseif v == :irrigated_vol_mm
        if f.irrigated_area == 0.0
            @assert f.irrigated_volume > 0.0 "Irrigation occured but irrigated area is 0!"
            return 0.0
        end
        return uconvert(mm, (f.irrigated_volume / f.irrigated_area))

    elseif v == :irrigation_cost
        return f._irrigation_cost

    elseif v == :dryland_area
        return f.total_area_ha - f.irrigated_area

    else
        return getfield(f, v)
    end
end

"""Setter for Field"""
function Base.setproperty!(f::FarmField, v::Symbol, value)
    if v == :irrigated_volume
        @assert typeof(value) <: Tuple || typeof(value) <: Array

        if length(value) == 2
            f._irrigated_volume[value[1]] = value[2]
            return
        end

        # Otherwise, update or create new water source
        key, val = value
        if haskey(f._irrigated_volume, key) == false
            f._irrigated_volume[key] = 0.0
        end
        f._irrigated_volume[key] += val

    else
        setproperty!(f, v, value)
    end
end


function volume_used_by_source(f::FarmField, ws_name::String)
    if haskey(f._irrigated_volume, ws_name)
        return f._irrigated_volume[ws_name]
    end
    
    return 0.0
end

"""Log the cost of irrigation."""
function log_irrigation_cost(f::FarmField, costs::Float64)
    f._irrigation_cost += costs
    return
end

"""Calculate soil water deficit.

Water deficit is represented as positive values.

Parameters
==========
* rainfall : Amount of rainfall across timestep in mm
* ET : Amount of evapotranspiration across timestep in mm
"""
function update_SWD(f::FarmField, rainfall::Float64, ET::Float64)
    tmp = f.soil_SWD - (rainfall - ET)
    tmp = max(0.0, min(tmp, f.soil_TAW))
    f.soil_SWD = round(tmp, digits=4)
end

"""Calculate net irrigation depth in mm, 0.0 or above.

Equation taken from [Agriculture Victoria](http://agriculture.vic.gov.au/agriculture/horticulture/vegetables/vegetable-growing-and-management/estimating-vegetable-crop-water-use)

See also:
* http://www.fao.org/docrep/x5560e/x5560e03.htm
* https://www.bae.ncsu.edu/programs/extension/evans/ag452-1.html
* http://dpipwe.tas.gov.au/Documents/Soil-water_factsheet_14_12_2011a.pdf
* https://www.agric.wa.gov.au/water-management/calculating-readily-available-water?nopaging=1

:math:`NID` = Effective root depth (:math:`D_{rz}`) :math:`*` Readily Available Water (:math:`RAW`)

where:

* :math:`D_{rz}` = :math:`Crop_{root_depth} * Crop_{e_rz}`, where :math:`Crop_{root_depth}` is the estimated root depth for current stage of crop (initial, late, etc.) and :math:`Crop_{e_rz}` is the effective root zone coefficient for the crop. \\
* :math:`Crop_{e_rz}` is said to be between 1 and 2/3rds of total root depth \\
* :math:`RAW = p * TAW`, :math:`p` is depletion fraction of crop, :math:`TAW` is Total Available Water in Soil

As an example, if a crop has a root depth (:math:`RD_{r}`) of 1m, an effective root zone (:math:`RD_{erz}`) coefficient of 0.55, a depletion fraction (p) of 0.4 and the soil has a TAW of 180mm: \\
:math:`(RD_{r} * RD_{erz}) * (p * TAW)`
:math:`(1 * 0.55) * (0.4 * 180)`

Returns
-------
* float : net irrigation depth as negative value
"""
function nid(f::FarmField, dt::DateTime)::Float64
    crop = f.crop
    coefs = crop.get_stage_coefs(dt)

    depl_frac = get_nominal(coefs["depletion_fraction"])
    e_rootzone_m = (crop.root_depth_m * crop.effective_root_zone)

    soil_RAW = f.soil_TAW * depl_frac
    return (e_rootzone_m * soil_RAW)
end
        
function calc_required_water(f::FarmField, dt::DateTime)::Quantity{mm}
    """Volume of water to maintain moisture at net irrigation depth.

    Factors in irrigation efficiency.
    Values are given in mm.
    """
    to_nid = f.soil_SWD - nid(f, dt)
    if to_nid < 0.0
        return 0.0
    end
    
    tmp = f.soil_SWD / f.irrigation.efficiency
    return round(tmp, digits=4)mm
end

"""Possible irrigation area in hectares.
"""
function calc_possible_area(f::FarmField, vol_ML::Quantity{ML})::Quantity{ha}
    if vol_ML == 0.0ML
        return 0.0ha
    end

    area = f.irrigated_area == Nothing ? f.total_area_ha : f.irrigated_area
    if area == 0.0ha
        return 0.0ha
    end

    req_water_mm = calc_required_water(f)
    if req_water_mm == 0.0mm
        return area
    end
    
    ML_per_ha = uconvert(ML/ha, req_water_mm)
    perc_area = (vol_ML / (ML_per_ha * area))
    
    return min(perc_area * area, area)
end

function set_next_crop(f::FarmField)
    f.crop = next(f.crop_rotation)
    ini_state(f)
end

function ini_state(f::FarmField)
    reset_state(f)
    f.plant_date = f.crop.plant_date
end

function reset_state(f::FarmField)
    f.sowed = false
    f.harvested = false
    f.irrigated_area = Nothing
    f.irrigated_volume = 0.0
    f.water_used = Dict()

    f._irrigation_cost = 0.0
    f._num_irrigation_events = 0

    f.harvest_date = Nothing
end

"""Calculate net income considering crop yield and costs incurred.

Parameters
----------
yield_func : function, used to calculate crop yield.
ssm : float, stored soil moisture at season start
gsr : float, growing season rainfall.
irrig : float, volume (in mm) of irrigation water applied
comps : list-like : (current datetime, water sources considered)

Returns
----------
* float : net income
"""
function total_income(f::FarmField, yield_func::Function, 
                      ssm::Quantity{mm}, gsr::Quantity{mm}, 
                      irrig::Quantity{mm}, comps)::Float64
    inc = gross_income(f, yield_func, ssm, gsr, irrig)
    return inc - total_costs(f, comps...)
end

function gross_income(f::FarmField, yield_func::Function, ssm::Quantity{mm}, 
                      gsr::Quantity{mm}, irrig::Quantity{mm})::Float64
    crop = f.crop
    irrigated_yield = yield_func(ssm, gsr+irrig, crop)
    dryland_yield = yield_func(ssm, gsr, crop)

    inc = irrigated_yield * f.irrigated_area * crop.price_per_yield
    inc += dryland_yield * f.dryland_area * crop.price_per_yield

    return inc
end

function total_costs(f::FarmField, dt::DateTime, water_sources::Array, num_fields::Int64=1)::Float64
    """Calculate total costs for a field.

    Maintenance costs can be spread out across a number of fields if desired.
    """
    irrig_area = f.irrigated_area

    h20_usage_cost = 0.0
    maint_cost = 0.0
    for (ws_name, w) in water_sources
        water_used = volume_used_by_source(f, ws_name)

        ws_cost = total_costs(w.source, irrig_area, water_used)
        h20_usage_cost += ws_cost

        pump_cost = total_costs(w.source.pump, dt.year) / num_fields
        maint_cost += pump_cost

    end

    irrig_app_cost = f.irrigation_costs

    if irrig_app_cost > 0
        @assert f.irrigated_volume > 0 "Irrigation had to occur for costs to be incurred!"
    elseif f.irrigated_volume > 0
        @assert irrig_app_cost > 0 "If irrigation occured, costs have to be incurred!"
    end

    h20_usage_cost += irrig_app_cost
    maint_cost += total_costs(f.irrigation, dt.year)

    crop_costs = total_costs(f.crop, dt.year)
    total_costs = h20_usage_cost + maint_cost + crop_costs

    return total_costs
end

function create(cls::AgComponent, data)
    Nothing
end

#     @classmethod
#     function create(cls, data, override=None):
#         cls_name = cls.__class__.__name__

#         tmp = data.copy()
#         name = tmp['name']
#         prop = tmp.pop('properties')

#         # crop_rot = prop.pop('crop_rotation')

#         prefix = f"{cls_name}___{name}"
#         props = generate_params(prefix, prop, override)

#         # TODO: 
#         # Need to generate irrigation object and crop rotation
#         # as given in specification

#         return cls(**tmp, **props)
#     # End create()

# # End FarmField()


# if __name__ == '__main__':
#     from agtor.Irrigation import Irrigation
#     from agtor.Crop import Crop

#     irrig = Irrigation('Gravity', 2000.0, 1, 5, 0.05, 0.2, efficiency=0.5, flow_ML_day=12, head_pressure=12)
#     crop_rotation = [Crop('Wheat', crop_type='irrigated', plant_date='05-15'), 
#                      Crop('Barley', crop_type='irrigated', plant_date='05-15'), 
#                      Crop('Canola', crop_type='irrigated', plant_date='05-15')]

#     Field = CropField(100.0, irrig, crop_rotation)
