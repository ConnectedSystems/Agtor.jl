# Getting Started

## A note on terminology

Agtor is a zonal agricultural cropping model

Specific terms are used within Agtor:

- Field : An area used for cropping, e.g., farm or farm-level
- Zone  : An arbitrary collection of fields, e.g., sub-catchment
- Basin : An arbitrary collection of zones, e.g., a catchment


# Defining Components

All components for Agtor are defined through YAML files.




```yaml
name: Campaspe
component: Basin

# Paths to zone specs
zone_spec: [
  "examples/campaspe/basin/Zone_1.yml", 
  "examples/campaspe/basin/Zone_2.yml",
  "examples/campaspe/basin/Zone_3.yml",
  "examples/campaspe/basin/Zone_4.yml",
  "examples/campaspe/basin/Zone_5.yml",
  "examples/campaspe/basin/Zone_6.yml",
  "examples/campaspe/basin/Zone_7.yml",
  "examples/campaspe/basin/Zone_8.yml",
  "examples/campaspe/basin/Zone_9.yml",
  "examples/campaspe/basin/Zone_10.yml",
  "examples/campaspe/basin/Zone_11.yml",
  "examples/campaspe/basin/Zone_12.yml"
]
```

```yaml
name: Zone_1
component: FarmZone

# Paths to data, relative to where project is run
climate_data: "examples/campaspe/climate/basin_historic_climate_data.csv"

fields:
  field1:
    name: field1
    component: CropField

    total_area_ha: 20966.53801
    irrigation_spec: "test/data/irrigations/gravity.yml"

    # Initial crop is the first one in this list
    crop_rotation_spec: ["test/data/crops/irrigated_wheat.yml", "test/data/crops/irrigated_barley.yml", "test/data/crops/irrigated_canola.yml"]

    # average soil total available water (mm)
    soil_TAW: ["RealParameter", 165.0, 145.0, 185.0]

    # Initial Soil Water Deficit
    soil_SWD: 20.0
```


```julia
using Agtor




```