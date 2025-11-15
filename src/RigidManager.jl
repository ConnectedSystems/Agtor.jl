using OrderedCollections


"""A rigid farm manager.

Water is applied by a pre-determined quantity rather than optimal
profitability. Uses surface water first, then groundwater.
"""
struct RigidManager <: Manager
    name::String
    application_amount::Float64
end


function run_timestep!(farmer::RigidManager, zone::FarmZone, idx::Int64, dt::Date)::Nothing
    for f::FarmField in zone.fields
        s_start::Date = f.plant_date
        s_end::Date = f.harvest_date

        within_season::Bool = in_season(dt, s_start, s_end)
        season_start::Bool = matching_dates(dt, s_start)
        season_end::Bool = matching_dates(dt, s_end)

        f_name::String = f.name

        if within_season
            apply_rainfall!(zone, dt)

            if f.irrigated_area == 0.0 || f.irrigation.name == "dryland"
                # no irrigation occurred!
                continue
            end

            req_water_mm::Float64 = farmer.application_amount * ML_to_mm
            area_to_apply::Float64 = f.total_area_ha
            for ws in zone.water_sources
                avail_water_mm::Float64 = (ws.allocation / area_to_apply) * ML_to_mm
                water_to_apply_mm::Float64 = 0.0

                if avail_water_mm > 0.0
                    if (req_water_mm <= avail_water_mm) && (req_water_mm != 0.0)
                        water_to_apply_mm = req_water_mm
                        req_water_mm = 0.0
                    else
                        water_to_apply_mm = avail_water_mm
                        req_water_mm -= avail_water_mm
                    end
                end

                if water_to_apply_mm > 0.0
                    vol_to_apply_ML_ha::Float64 = (water_to_apply_mm / mm_to_ML)
                    apply_irrigation!(f, ws, water_to_apply_mm, area_to_apply)

                    app_cost_per_ML::NamedTuple = ML_water_application_cost(farmer, zone, f, vol_to_apply_ML_ha)
                    application_cost::Float64 = app_cost_per_ML[Symbol(ws.name)]
                    log_irrigation_cost(f, (application_cost * vol_to_apply_ML_ha * area_to_apply))
                else
                    log_irrigation_cost(f, 0.0)
                end
            end
        elseif season_start
            f.sowed = true
            apply_rainfall!(zone, dt)

            # Rigid farmer attempts to use total field area
            f.irrigated_area = f.total_area_ha

        elseif season_end
            # End of season

            # growing season rainfall
            gsr_mm::Float64 = get_seasonal_rainfall(zone.climate, [s_start, s_end], f_name)

            if f.sowed
                # Account for irrigation efficiency
                irrig_mm::Float64 = f.irrigated_vol_mm * f.irrigation.efficiency

                # The French-Schultz method assumes 25-30% of previous 3 months
                # rainfall contributed towards crop growth
                # The SSM coefficient is set as a crop parameter.
                prev::Date = f.plant_date - Month(3)
                prev_mm::Float64 = get_seasonal_rainfall(zone.climate, [prev, s_start], f_name)
                ssm_mm::Float64 = prev_mm * f.crop.ssm_coef

                income::Float64, irrigated_yield::Float64, dryland_yield::Float64 =
                    total_income(
                        f, ssm_mm, gsr_mm, irrig_mm,
                        (dt, zone.water_sources)
                    )

                seasonal_field_log!(f, dt, income, f.irrigated_volume, irrigated_yield, dryland_yield, gsr_mm)
            else
                costs = total_costs(f, dt, zone.water_sources)
                seasonal_field_log!(f, dt, -costs, 0.0, 0.0, 0.0, gsr_mm)
            end

            log_irrigation_by_water_source(zone, f, dt)

            set_next_crop!(farmer, f, dt)
            reset_state!(f)
        end
    end

    return nothing
end
