using Agtor
using JuMP, CSV, DataFrames, GLPK, Dates
using Statistics

gs_start = (5, 1)
# # calc_potential_crop_yield(ssm_mm::Float64, gsr_mm::Float64, crop::AgComponent)

data_dir = "test/data/"
calib_zone = load_spec("$(data_dir)zones/CalibZone.yml")
tgt_spec = calib_zone[:CalibZone]
agparams = collect_agparams!(tgt_spec, []; ignore=[:crop_spec])

# Loading climate data
climate_data = "$(data_dir)climate/calib_climate_data.csv"
use_threads = Threads.nthreads() > 1
climate_seq = DataFrame!(CSV.File(climate_data, threaded=use_threads, dateformat="dd-mm-YYYY"))

climate = Climate(climate_seq)
farmer = Manager("Calibration")

wheat_zone = create(tgt_spec, climate)

# @info agparams

function run_model(farmer, zone)
    time_sequence = zone.climate.time_steps
    @inbounds for dt_i in time_sequence
        run_timestep(farmer, zone, dt_i)

        # Resetting allocations for test run
        if monthday(dt_i) == gs_start
            for ws in zone.water_sources
                if ws.name == "surface_water"
                    ws.allocation = 150.0
                elseif ws.name == "groundwater"
                    ws.allocation = 40.0
                end
            end
        end
    end

    zone_results, field_results = collect_results(zone)

    return zone_results, field_results
end


function obj_func(farmer, zone, obs_data, params=nothing)
    if !isnothing(params)
        tmp_zone = update_model(zone, params)
    else
        tmp_zone = zone
    end

    zone_results, field_results = run_model(farmer, tmp_zone)

    f1 = field_results["field1"]

    mod_years = map(x -> Year(x), f1.Date)
    avail_years = (mod_years .>= Dates.Year(1991))

    subset = f1[avail_years, :]
    avg_yield = (subset[!, :irrigated_yield] + subset[!, :dryland_yield]) ./ (subset[!, :irrigated_area] + subset[!, :dryland_area])

    # RMSE
    return sqrt(mean((avg_yield .- obs_data.Average).^2))
end

hist_wheat_prod = "test/data/crops/Vic_NC_wheat_production.csv"
obs_wheat = DataFrame!(CSV.File(hist_wheat_prod, threaded=use_threads, dateformat="YYYY", comment="#", types=Dict(1=>Dates.Date)))
obs_wheat[!, :Year] = obs_wheat[!, :Year] .+ Dates.Year(1)

obs_wheat = obs_wheat[obs_wheat[!, :Year] .<= Dates.Date("2016-01-01"), :]
obs_wheat[!, :Average] = (obs_wheat[!, Symbol(" Wheat produced (t)")] ./ obs_wheat[!, Symbol(" Wheat area sown (ha)")])

obj_func(farmer, wheat_zone, obs_wheat)



