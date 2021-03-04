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
    irrigated_area::Union{Nothing, Float64} = 0.0
    sowed::Bool = false
    _irrigated_volume::DefaultDict = DefaultDict{String, Float64}(0.0)
    _num_irrigation_events::Int64 = 0
    _irrigation_cost::Float64 = 0.0

    # next crop will be 2nd item in crop_rotation and this
    # counter will increment and reset as the seasons go by
    _next_crop_idx::Int64 = 2
    _fname::String = replace("$(name)-", " " => "_")
    _seasonal_log::DataFrame = setup_log()

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


@doc """
    update_SWD!(f::FarmField, rainfall::Float64, ET::Float64)

Calculate soil water deficit, and update `f.soil_SWD`

Water deficit is represented as positive values.

`rainfall` and `ET` parameters are expected in mm.
"""
function update_SWD!(f::FarmField, rainfall::Float64, ET::Float64)::Nothing
    tmp::Float64 = f.soil_SWD::Float64 - (rainfall - ET)::Float64

    tmp = max(0.0, min(tmp, f.soil_TAW))
    f.soil_SWD = round(tmp, digits=4)

    return nothing
end


@doc """
    nid(f::FarmField, dt::Date)

Calculate net irrigation depth in mm, 0.0 or above.

Equation taken from [Agriculture Victoria](http://agriculture.vic.gov.au/agriculture/horticulture/vegetables/vegetable-growing-and-management/estimating-vegetable-crop-water-use)

See also:
* http://www.fao.org/docrep/x5560e/x5560e03.htm
* https://www.bae.ncsu.edu/programs/extension/evans/ag452-1.html
* http://dpipwe.tas.gov.au/Documents/Soil-water_factsheet_14_12_2011a.pdf
* https://www.agric.wa.gov.au/water-management/calculating-readily-available-water?nopaging=1

``NID`` = Effective root depth (``D_{rz}``) ``*`` Readily Available Water (``RAW``)

where:

* ``D_{rz}`` = ``Crop_{root depth} * Crop_{e_rz}``, where ``Crop_{root depth}`` 
  is the estimated root depth for current stage of crop (initial, late, etc.) 
  and ``Crop_{e rz}`` is the effective root zone coefficient for the crop.
* ``Crop_{e rz}`` is said to be between 1 and 2/3rds of total root depth
* ``RAW = p * TAW``, ``p`` is depletion fraction of crop, ``TAW`` is 
  Total Available Water in Soil

As an example, if a crop has a root depth (``RD_{r}``) of 1m, an effective 
root zone (``RD_{erz}``) coefficient of 0.55, a depletion fraction (`p`) of 0.4 
and the soil has a ``TAW`` of 180mm:

``(RD_{r} * RD_{erz}) * (p * TAW)``

Works out to be:

``(1 * 0.55) * (0.4 * 180)``

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


@doc """
    calc_required_water(f::FarmField, dt::Date)

Volume of water to maintain moisture above net irrigation depth (`nid`).

Calculates volume of water needed to replenish soil water deficit (`swd`)
when SWD falls below `nid`, considering irrigation efficiency.

Values are given in mm.

- link to [`nid(f::FarmField, dt::Date)`](@ref)
"""
function calc_required_water(f::FarmField, dt::Date)::Float64
    swd::Float64 = f.soil_SWD::Float64
    to_nid::Float64 = swd - nid(f, dt)
    if to_nid < 0.0
        return 0.0
    end

    return (swd / f.irrigation.efficiency)
end


@doc """Possible irrigation area in hectares."""
function possible_irrigation_area(f::FarmField, vol_ML::Float64, req_ML::Float64)::Float64
    if vol_ML == 0.0
        return 0.0
    end

    area::Float64 = 0.0
    if f.irrigation.name != "dryland"
        area = f.irrigated_area == 0.0 ? f.total_area_ha : f.irrigated_area
    end

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

    f.irrigated_volume = 0.0  # This clears the underlying log as well.
    f.irrigated_area = 0.0
    f._irrigation_cost = 0.0
    f._num_irrigation_events = 0
    f.soil_SWD = 0.0

    return nothing
end


@doc """
    french_schultz_cy(; ssm_mm::Float64, gsr_mm::Float64, crop::AgComponent)

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
1. [Oliver et al. (2008) (see Equation 1)](http://www.regional.org.au/au/asa/2008/concurrent/assessing-yield-potential/5827_oliverym.htm)
2. [Whitbread and Hancock (2008)](http://www.regional.org.au/au/asa/2008/concurrent/assessing-yield-potential/5803_whitbreadhancock.htm)


Parameters
----------
* ssm_mm : float, Stored Soil Moisture (mm) at start of season.
* gsr_mm : float, Growing Season Rainfall (mm)
* crop : object, Crop component object

Returns
-----------
* Potential yield in tonnes/Ha
"""
function french_schultz_cy(; ssm_mm::Float64, gsr_mm::Float64, 
                             crop::AgComponent)::Float64
    evap_coef_mm::Float64 = crop.et_coef  # Crop evapotranspiration coefficient (mm)
    wue_coef_mm::Float64 = crop.wue_coef  # Water Use Efficiency coefficient (kg/mm)

    # maximum rainfall threshold in mm
    # water above this amount does not contribute to crop yield
    max_thres::Float64 = crop.rainfall_threshold  

    gsr_mm::Float64 = min(gsr_mm, max_thres)
    return max(0.0, ((ssm_mm + gsr_mm - evap_coef_mm) * wue_coef_mm) / 1000.0)
end


"""
    calc_potential_crop_yield(method::Function; kwargs...)

Calculate potential crop yield using an arbitrary function.
This function enables a consistent interface to be provided.

Function must return a Tuple of results or a Float64
"""
function calc_potential_crop_yield(method::Function; kwargs...)::Union{Tuple, Float64}
    return method(; kwargs...)
end


"""
    total_income(f::FarmField, ssm::Float64, gsr::Float64, irrig::Float64, comps)::Tuple

Calculate net income considering crop yield and costs incurred.


Returns
-------
    Tuple:
        * float : net income
        * float : irrigated crop yield [t/ha]
        * float : dryland crop yield [t/ha]
"""
function total_income(f::FarmField, ssm::Float64, gsr::Float64, 
                      irrig::Float64, comps)::Tuple
    inc::Float64, irrigated::Float64, dryland::Float64 = gross_income(f, ssm, gsr, irrig)
    return inc - total_costs(f, comps...), irrigated, dryland
end 


"""
    gross_income(f::FarmField, ssm::Float64, gsr::Float64, 
        irrig::Float64, func::Function=french_schultz_cy)::Tuple

Calculate gross income, potential irrigated yield, and potential dryland yield.

Returns
-------
Tuple{Float64} : income, irrigated yield [t], dryland yield [t]
"""
function gross_income(f::FarmField, ssm_mm::Float64, gsr_mm::Float64, 
                      irrig::Float64, func::Function=french_schultz_cy)::Tuple
    crop::Crop = f.crop

    income::Float64 = 0.0
    total_irrig_yield::Float64 = 0.0
    if f.irrigated_area > 0.0
        irrigated_yield::Float64 = calc_potential_crop_yield(func; ssm_mm, gsr_mm=gsr_mm+irrig, crop)
        total_irrig_yield = irrigated_yield * f.irrigated_area
        income = irrigated_yield * f.irrigated_area * crop.price_per_yield
    end

    dryland_yield::Float64 = calc_potential_crop_yield(func; ssm_mm, gsr_mm, crop)
    total_dry_yield::Float64 = dryland_yield * f.dryland_area

    income += dryland_yield * f.dryland_area * crop.price_per_yield

    return income, total_irrig_yield, total_dry_yield
end


"""
    gross_income(f::FarmField, area::Float64, func::Function=french_schultz_cy; kwargs...)::Tuple

Calculate gross income and crop yield using an arbitrary crop yield function.

Returns
-------
Tuple{Float64} : income [\$/yield], total_yield [t]
"""
function gross_income(f::FarmField, area::Float64, func::Function=french_schultz_cy; kwargs...)::Tuple
    crop::Crop = f.crop
    crop_yield_per_area::Float64 = calc_potential_crop_yield(func; kwargs...)

    total_yield::Float64 = crop_yield_per_area * area
    income::Float64 = total_yield * crop.price_per_yield

    return income, total_yield
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


function setup_log()::DataFrame
    return DataFrame([Date, Float64, Float64, Float64, Float64, Float64, Float64, Float64], 
                     [:Date, :income, :irrigated_volume, :irrigated_yield, :dryland_yield, 
                      :growing_season_rainfall, :irrigated_area, :dryland_area])
end


function reset!(f::FarmField)::Nothing
    f._seasonal_log = setup_log()

    reset_state!(f)

    return
end

