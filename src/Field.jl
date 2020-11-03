abstract type FarmField <: AgComponent end

@with_kw mutable struct CropField <: FarmField
    name::String
    total_area_ha::Union{Float64, AgParameter}
    irrigation::Irrigation
    crop::Crop  # Initial value can just be the first item in crop_rotation
    # crop_choices::Array{Crop}  # This can be the unique values in crop_rotation
    crop_rotation::Array{Crop}
    soil_TAW::Union{Float64, AgParameter}
    soil_SWD::Union{Float64, AgParameter}  # soil water deficit
    ssm::Union{Float64, AgParameter} = 0.0
    irrigated_area::Union{Nothing, Float64} = nothing
    sowed::Bool = false
    _irrigated_volume::DefaultDict = DefaultDict{String, Float64}(0.0)
    _num_irrigation_events::Int64 = 0
    _irrigation_cost::Float64 = 0.0

    # next crop will be 2nd item in crop_rotation and this
    # counter will increment and reset as the seasons go by
    _next_crop_idx::Int64 = 2
    _fname::String = replace("$(name)-", " " => "_")

    _seasonal_log::DataFrame = DataFrame([Date, Float64, Float64, Float64, Float64, Float64, Float64, Float64], 
                                         [:Date, :income, :irrigated_volume, :irrigated_yield, :dryland_yield, :growing_season_rainfall, :irrigated_area, :dryland_area])
end

"""Getter for Field"""
function Base.getproperty(f::FarmField, v::Symbol)
    if v == :irrigated_volume
        return sum(values(f._irrigated_volume))

    elseif v == :irrigation_from_source
        return f._irrigated_volume

    elseif v == :irrigated_vol_mm
        irrig_area = f.irrigated_area
        if irrig_area == 0.0
            @assert f.irrigated_volume == 0.0 "Irrigation occured but irrigated area is 0!"
            return 0.0
        end

        val::Float64 = (f.irrigated_volume / irrig_area) * ML_to_mm

        return val

    elseif v == :irrigation_cost
        return f._irrigation_cost

    elseif v == :dryland_area
        return f.total_area_ha - f.irrigated_area

    elseif v == :plant_date
        return f.crop.plant_date

    elseif v == :harvest_date
        return f.crop.harvest_date
    elseif v == :num_crops
        return length(f.crop_rotation)
    else
        return getfield(f, v)

    end
end

"""Setter for Field"""
function Base.setproperty!(f::FarmField, v::Symbol, value)::Nothing
    if v == :irrigated_volume
        if isnothing(value) || length(value) == 1
            for (k, _v) in f._irrigated_volume
                f._irrigated_volume[k] = value
            end
        elseif length(value) == 2
            f._irrigated_volume[value[1]] += value[2]
        end
    elseif v == :plant_date
        f.crop.plant_date = value
    elseif v == :harvest_date
        f.crop.harvest_date = value
    else
        setfield!(f, Symbol(v), value)
    end

    return nothing
end

"""Volume used from a water source in ML"""
function volume_used_by_source(f::FarmField, ws_name::String)::Float64
    if haskey(f._irrigated_volume, Symbol(ws_name))
        return f._irrigated_volume[Symbol(ws_name)] / mm_to_ML
    end
    
    return 0.0
end


"""Log the (total) cost of irrigation."""
function log_irrigation_cost(f::FarmField, costs::Float64)::Nothing
    f._irrigation_cost += costs
    return nothing
end


"""
Log seasonal results.

* 
"""
function seasonal_field_log!(f::FarmField, dt::Date, income::Float64, 
                             irrig_vol::Float64, irrig_yield::Float64, 
                             dry_yield::Float64, seasonal_rainfall::Float64)::Nothing
    push!(f._seasonal_log, [dt, income, irrig_vol, irrig_yield, dry_yield, seasonal_rainfall, f.irrigated_area, f.dryland_area])
    return nothing
end


"""
Calculate soil water deficit.

Water deficit is represented as positive values.

Parameters
----------
    * rainfall : Amount of rainfall across timestep in mm
    * ET : Amount of evapotranspiration across timestep in mm
"""
function update_SWD!(f::FarmField, rainfall::Float64, ET::Float64)::Nothing
    tmp::Float64 = f.soil_SWD::Float64 - (rainfall - ET)::Float64
    tmp = max(0.0, min(tmp, f.soil_TAW::Float64))
    f.soil_SWD = round(tmp, digits=4)

    return nothing
end


"""
Calculate net irrigation depth in mm, 0.0 or above.

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
    * float : net irrigation depth
"""
function nid(f::FarmField, dt::Date)::Float64
    crop::Crop = f.crop
    coefs::NamedTuple = get_stage_coefs(crop, dt)

    e_rootzone_m::Float64 = crop.root_depth_m::Float64 * crop.effective_root_zone::Float64
    soil_RAW::Float64 = f.soil_TAW::Float64 * coefs.depletion_fraction::Float64

    return (e_rootzone_m * soil_RAW)
end


"""
Volume of water to maintain moisture at net irrigation depth.

Factors in irrigation efficiency.
Values are given in mm.
"""
function calc_required_water(f::FarmField, dt::Date)::Float64
    soil_SWD::Float64 = f.soil_SWD
    to_nid::Float64 = soil_SWD - nid(f, dt)
    if to_nid < 0.0
        return 0.0
    end

    return (soil_SWD / f.irrigation.efficiency)
end


"""Possible irrigation area in hectares."""
function possible_irrigation_area(f::FarmField, vol_ML::Float64, req_ML::Float64)::Float64
    if vol_ML == 0.0
        return 0.0
    end

    area::Float64 = isnothing(f.irrigated_area) ? f.total_area_ha : f.irrigated_area
    if area == 0.0
        return 0.0
    end

    if req_ML == 0.0
        return area
    end

    perc_area::Float64 = vol_ML / (req_ML * area)
    
    return min(perc_area * area, area)
end


function set_next_crop!(f::FarmField)::Nothing
    crop_id::Int64 = f._next_crop_idx > f.num_crops ? 1 : f._next_crop_idx

    # Update crop and next crop id
    f.crop, f._next_crop_idx = iterate(f.crop_rotation, crop_id)

    return nothing
end


function reset_state!(f::FarmField)::Nothing
    f.sowed = false

    if f.irrigation.name != "dryland"
        f.irrigated_area = f.total_area_ha
    end

    f.irrigated_volume = 0.0  # This clears the underlying log as well.
    f.irrigated_area = 0.0
    f._irrigation_cost = 0.0
    f._num_irrigation_events = 0
    f.soil_SWD = 0.0

    return nothing
end


"""
Potential crop yield calculation based on a modified French-Schultz equation.
The implemented method is the farmer-friendly version as described by 
Oliver et al., (2008) (see [1]).

``YP = (SSM + GSR - E) * WUE``

where

* ``YP`` is yield potential in tonnes per hectare
* ``SSM`` is Stored Soil Moisture (at start of season) in mm, assumed to be 30% of summer rainfall
* ``GSR`` is Growing Season Rainfall in mm
* ``E`` is Crop Evaporation coefficient in mm, the amount of rainfall required before the crop will start
    to grow, commonly 110mm, but can range from 30-170mm (see [2]),
* ``WUE`` is Water Use Efficiency coefficient in kg/mm


References
----------
.. [1] [Oliver et al. 2008 (Equation 1)](http://www.regional.org.au/au/asa/2008/concurrent/assessing-yield-potential/5827_oliverym.htm)

.. [2] [Whitbread and Hancock 2008](http://www.regional.org.au/au/asa/2008/concurrent/assessing-yield-potential/5803_whitbreadhancock.htm)


Parameters
----------
* ssm_mm : float, Stored Soil Moisture (mm) at start of season.
* gsr_mm : float, Growing Season Rainfall (mm)
* crop : object, Crop component object

Returns
-----------
* Potential yield in tonnes/Ha
"""
function calc_potential_crop_yield(ssm_mm::Float64, gsr_mm::Float64, 
                                   crop::AgComponent)::Float64
    
    evap_coef_mm::Float64 = crop.et_coef  # Crop evapotranspiration coefficient (mm)
    wue_coef_mm::Float64 = crop.wue_coef  # Water Use Efficiency coefficient (kg/mm)

    # maximum rainfall threshold in mm
    # water above this amount does not contribute to crop yield
    max_thres::Float64 = crop.rainfall_threshold  

    gsr_mm::Float64 = min(gsr_mm, max_thres)
    return max(0.0, ((ssm_mm + gsr_mm - evap_coef_mm) * wue_coef_mm) / 1000.0)
end


"""Calculate net income considering crop yield and costs incurred.

Parameters
----------
    yield_func : function, used to calculate crop yield.
    ssm : float, stored soil moisture at season start (in mm)
    gsr : float, growing season rainfall (in mm)
    irrig : float, volume (in mm) of irrigation water applied
    comps : list-like : (current datetime, water sources considered)

Returns
-------
    Tuple:
        * float : net income
        * float : irrigated crop yield, tonnes/Ha
        * float : dryland crop yield, tonnes/Ha
"""
function total_income(f::FarmField, ssm::Float64, gsr::Float64, 
                      irrig::Float64, comps)::Tuple
    inc::Float64, irrigated::Float64, dryland::Float64 = gross_income(f, ssm, gsr, irrig)
    return inc - total_costs(f, comps...), irrigated, dryland
end 


function gross_income(f::FarmField, ssm::Float64, gsr::Float64, 
                      irrig::Float64)::Tuple
    crop::Crop = f.crop
    irrigated_yield::Float64 = calc_potential_crop_yield(ssm, gsr+irrig, crop)
    dryland_yield::Float64 = calc_potential_crop_yield(ssm, gsr, crop)

    total_irrig_yield::Float64 = irrigated_yield * f.irrigated_area
    total_dry_yield::Float64 = dryland_yield * f.dryland_area

    inc::Float64 = irrigated_yield * f.irrigated_area * crop.price_per_yield
    inc += dryland_yield * f.dryland_area * crop.price_per_yield

    return inc, total_irrig_yield, total_dry_yield
end


"""Calculate total costs for a field.

Maintenance costs can be spread out across a number of fields if desired.
"""
function total_costs(f::FarmField, dt::Date, water_sources::Array{WaterSource}, num_fields::Int64=1)::Float64
    year_val::Int64 = year(dt)
    irrig_area::Float64 = f.irrigated_area
    h20_usage_cost::Float64 = 0.0
    maint_cost::Float64 = 0.0
    for w::WaterSource in water_sources
        water_used::Float64 = volume_used_by_source(f, w.name)
        ws_cost::Float64 = subtotal_costs(w, irrig_area, water_used)
        h20_usage_cost = h20_usage_cost + ws_cost

        pump_cost::Float64 = subtotal_costs(w.pump, year_val) / num_fields
        maint_cost = maint_cost + pump_cost
    end

    irrig_app_cost::Float64 = f._irrigation_cost

    if irrig_app_cost > 0.0
        @assert f.irrigated_volume > 0.0 "Irrigation had to occur for costs to be incurred!"
    elseif f.irrigated_volume > 0.0
        @assert irrig_app_cost > 0.0 "If irrigation occured, costs have to be incurred!"
    end

    h20_usage_cost = h20_usage_cost + irrig_app_cost
    
    maint_cost = maint_cost + subtotal_costs(f.irrigation, year_val)
    crop_costs::Float64 = subtotal_costs(f.crop, year_val)
    total_costs::Float64 = h20_usage_cost + maint_cost + crop_costs

    return total_costs
end
