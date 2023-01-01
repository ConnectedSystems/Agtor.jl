# Example Component Specifications

See [this paper](https://doi.org/10.1016/j.ejrh.2020.100669) for details on parameters outlined in the specs below.


## Component Structure

```
                     ┌───────┐
          ┌──────────┤ Basin │
          │          └───────┘
has many  │
          │
          │
     ┌────▼───┐    shares a      ┌─────────┐
     │  Zone  ├──────────────────► Manager │
     └───┬────┘                  └─────────┘
         │
has many │ ┌───────┐
         └─► Field │
           └┬──────┘
            │
            │  Rotates many ┌───────┐
            ├────────────────► Crop │
            │               └───────┘
            │
            │      has a    ┌────────────┐
            ├───────────────► Irrigation │
            │               └────────────┘
            │
            │      has      ┌──────┐
            ├───────────────► Pump │
            │               └──────┘
            │
            │      has      ┌─────────────┐
            └───────────────► WaterSource │
                            └─────────────┘
```


## Crop

Defines economic and growth parameters (over four stages) for a given crop.

```yaml
name: irrigated_barley
component: Crop
crop_type: irrigated_cereal

# values below are given as list of
# nominal "best guess" values, min, and max 
# plant_dates are assumed to be static across all seasons.
# Identical values for all options are treated as constants
plant_date: ["CategoricalParameter", "05-31", "05-31", "05-31"]
yield_per_ha: ["RealParameter", 3.25, 2.5, 7.0]
price_per_yield: ["RealParameter", 200.0, 100.0, 250.0]
variable_cost_per_ha: ["RealParameter", 160.0, 120.0, 350.0]
water_use_ML_per_ha: ["RealParameter", 2.0, 1.5, 3.0]
root_depth_m: ["RealParameter", 1.0, 0.8, 1.5]
# values below were calibrated for North-Central Victoria
et_coef: ["RealParameter", 170.0, 170.0, 170.0]
wue_coef: ["RealParameter", 11.4552, 11.4552, 11.4552]
rainfall_threshold: ["RealParameter", 466.43204, 466.43204, 466.43204]
ssm_coef: ["RealParameter", 0.4, 0.4, 0.4]

# Effective root zone is roughly half to 2/3rds of root depth
# https://www.bae.ncsu.edu/programs/extension/evans/ag452-1.html
# http://dpipwe.tas.gov.au/Documents/Soil-water_factsheet_14_12_2011a.pdf
effective_root_zone: ["RealParameter", 0.55, 0.5, 0.66]
growth_stages:
  # growth stage length are given in days
  # harvest date is the sum of all stages
  initial: 
    stage_length: ["RealParameter", 20, 20, 20]
    crop_coefficient: 0.3
    depletion_fraction: 0.55
  development: 
    stage_length: ["RealParameter", 25, 25, 25]
    crop_coefficient: 0.3
    depletion_fraction: 0.55
  mid_season: 
    stage_length: ["RealParameter", 60, 60, 60]
    crop_coefficient: 1.15
    depletion_fraction: 0.55
  late:
    stage_length: ["RealParameter", 30, 30, 30]
    crop_coefficient: 0.25
    depletion_fraction: 0.55
```


## Irrigation

```yaml
name: gravity
component: Irrigation

# Cost to install/adopt ($ per ha)
capital_cost: ["RealParameter", 2000.0, 2000.0, 2500.0]

# water application efficiency
efficiency: ["RealParameter", 0.5, 0.5, 0.9]

# Assumed percentage of capital_cost 
minor_maintenance_rate: ["RealParameter", 0.05, 0.05, 0.05]
major_maintenance_rate: ["RealParameter", 0.10, 0.10, 0.10]

# Assumed maintenance schedule for minor/major maintenance
# in years, where 1 is every year, 5 is every 5 years, etc.
minor_maintenance_schedule: ["RealParameter", 1.0, 1.0, 1.0]
major_maintenance_schedule: ["RealParameter", 5.0, 5.0, 5.0]

# Assumed average flow rate in ML/day
flow_ML_day: ["RealParameter", 12.0, 12.0, 12.0]

# Range of required head pressure to operate irrigation
head_pressure: ["RealParameter", 10.0, 8.0, 15.0]
```


## Pump

Defines the operational costs of a pumping system for surface water and groundwater.
Specs for `surface_water` and `groundwater` must be defined.

```yaml
name: surface_water
component: Pump
# surface water pump representing an average mix of
# 60% diesel and 40% electric pumps

# https://publications.csiro.au/rpr/download?pid=csiro:EP1312979&dsid=DS5

capital_cost: ["RealParameter", 18000.0, 18000.0, 70000.0]
minor_maintenance_schedule: ["RealParameter", 1, 1, 1]
major_maintenance_schedule: ["RealParameter", 1, 1, 1]
minor_maintenance_rate: ["RealParameter", 0.005, 0.005, 0.005]
major_maintenance_rate: ["RealParameter", 0.005, 0.005, 0.005]
pump_efficiency: 0.7
cost_per_kW: ["RealParameter", 0.285, 0.285, 0.285]
derating: 0.75
```


## WaterSource

Defines the cost of accessing a given water source (`surface_water` and `groundwater` must be defined).

```yaml
name: groundwater
component: WaterSource

# Surface and Groundwater Account fees: http://www.g-mwater.com.au/downloads/gmw/Pricing_Table_June15.pdf
# Supply costs taken from East Loddon (North)

# Water Share/Entitlements:
# http://waterregister.vic.gov.au/water-entitlements/entitlement-statistics

# 4C Lower Campaspe, 52, 1633.5ML
# Pricing:
# http://www.g-mwater.com.au/customer-services/myaccount/pricingsimulator
# http://www.g-mwater.com.au/general-information/pricingsimulator

# http://www.g-mwater.com.au/downloads/gmw/Pricing_Table_June15.pdf

# Definitions:
# http://waterregister.vic.gov.au/about/water-dictionary

# access_fees are sum of the below
# in $ per service point
# service: 100.0
# infrastructure_access: 2714.0
# service_point: 300
# service_point_remote_read: 350
# service_point_remote_operate: 400
# surface_drainage_service: 100
yearly_cost: 3964.0

# area_fee ($/Ha): 7.95
cost_per_ha:  7.95  # ($/ha)

# access_fee: 2.04
# resource_management_fee: 4.47
# high_reliability_entitlement: 24.86
# low_reliability_entitlement: 15.35
# high_reliability_storage: 10.57
# low_reliability_storage: 5.18
# above_entitlement_storage: 15.35
cost_per_ML: 77.82  # ($/ML)

head: 25.0  # Initial head (in meters)
allocation: 50.0  # Initial allocation
```


## FarmZone

```yaml
name: Zone_1
component: FarmZone

# Paths to data, relative to where project is run
climate_data: "test/data/climate/farm_climate_data.csv"
pump_spec: "test/data/pumps/"

fields:
  field1:
    name: field1
    component: CropField

    total_area_ha: 100.0
    irrigation_spec: "test/data/irrigations/gravity.yml"

    # Initial crop is the first one in this list
    crop_rotation_spec: ["test/data/crops/irrigated_wheat.yml", "test/data/crops/irrigated_barley.yml"]

    # average soil total available water (mm)
    soil_TAW: 100.0

    # Initial Soil Water Deficit
    soil_SWD: 20.0

water_sources:
  surface_water:
    name: surface_water
    component: WaterSource
    # Surface and Groundwater Account fees: http://www.g-mwater.com.au/downloads/gmw/Pricing_Table_June15.pdf
    # Supply costs taken from East Loddon (North)

    # Average volume per licence for the lower Campaspe is ~407ML
    # (56.2GL / 138 Licences)
    # see http://www.g-mwater.com.au/downloads/gmw/Groundwater/Lower_Campaspe_Valley_WSPA/Nov_2013_-_Lower_Campaspe_Valley_WSPA_Plan_A4_FINAL-fixed_for_web.pdf
    # esp. Section 2.2 (Groundwater Use) page 8, 

    # Groundwater fees: http://www.g-mwater.com.au/downloads/gmw/Forms_Groundwater/2015/TATDOC-2264638-2015-16_Schedule_of_Fees_and_Charges_-_Groundwater_and_Bore_Construction.pdf

    # Entitlement statistics from http://waterregister.vic.gov.au/water-entitlements/entitlement-statistics

    # Other fees not considered:
    # Bore Construction fee: $1440
    # Replacement bore: $900
    # Each Additional bore: $170
    # licence amendment: $527 (alter number of bores, alter depth of bore, change bore site)
    # overuse cost: $2000 / ML (we assume that farmers never over use!)

    # Licence Renewal:
    # Licence renewal occurs every 5-15 years http://www.g-mwater.com.au/downloads/gmw/Forms_Surface_Water/2015/30_Nov_2015_-_2811974-v10-APPLICATION_TO_RENEW_A_LICENCE_TO_TAKE_AND_USE_SURFACEWATER_OPERATE_WORKS.pdf
    # Licence Renewal costs $681 (based on 2014-15 fees)
    # $681 / 5 years, which is $136.2 a year

    # In some cases, farmers may need a licence to perform on-farm MAR
    # See under section entitled "Managed Aquifer Recharge (MAR)"
    # http://www.srw.com.au/page/page.asp?page_Id=113#BM4730

    # Bore Operation Licence is said to be $1414
    # Could not find whether this is yearly or every 5 years.
    # Assuming every 5 years
    # $1414 / 5 is 282.8

    # http://www.g-mwater.com.au/customer-services/manage-my-account/feedescriptions
    # http://www.g-mwater.com.au/customer-services/manage-my-account/feesandcharges
    # http://www.g-mwater.com.au/customer-services/manage-my-account/feesandcharges/yourfeesexplained
    # yearly_cost is the sum of the below
    # in $ per service point
    # service,90
    # service_point,100
    # access_service_point,50
    # bore_operation_licence,282.8
    # licence_renewal,136.2
    yearly_cost: 659.0

    # No charge based on area
    cost_per_ha: 0.0

    # Total fees ($ / ML)
    # access: 3.96
    # resource_management: 4.33
    cost_per_ML: 8.29

    head: 0.0  # Initial head
    allocation: 225.0  # Initial allocation
    entitlement: 225.0  # Total entitlement

  groundwater:
    name: groundwater
    component: WaterSource

    # Surface and Groundwater Account fees: http://www.g-mwater.com.au/downloads/gmw/Pricing_Table_June15.pdf
    # Supply costs taken from East Loddon (North)

    # Water Share/Entitlements:
    # http://waterregister.vic.gov.au/water-entitlements/entitlement-statistics

    # 4C Lower Campaspe, 52, 1633.5ML
    # Pricing:
    # http://www.g-mwater.com.au/customer-services/myaccount/pricingsimulator
    # http://www.g-mwater.com.au/general-information/pricingsimulator

    # http://www.g-mwater.com.au/downloads/gmw/Pricing_Table_June15.pdf

    # Definitions:
    # http://waterregister.vic.gov.au/about/water-dictionary

    # access_fees are sum of the below
    # in $ per service point
    # service: 100.0
    # infrastructure_access: 2714.0
    # service_point: 300
    # service_point_remote_read: 350
    # service_point_remote_operate: 400
    # surface_drainage_service: 100
    yearly_cost: 3964.0

    # area_fee ($/Ha): 7.95
    cost_per_ha:  7.95  # ($/ha)

    # access_fee: 2.04
    # resource_management_fee: 4.47
    # high_reliability_entitlement: 24.86
    # low_reliability_entitlement: 15.35
    # high_reliability_storage: 10.57
    # low_reliability_storage: 5.18
    # above_entitlement_storage: 15.35
    cost_per_ML: 77.82  # ($/ML)

    head: 25.0  # Initial head (in meters)
    allocation: 50.0  # Initial allocation
    entitlement: 50.0  # Total entitlement
```

## Basin

```yaml
name: ExampleBasin
component: Basin

# Paths to zone specs
zone_spec: ["test/data/zones/Zone_1.yml", "test/data/zones/Zone_2.yml"]

```