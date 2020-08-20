using Agtor
using Optim, CSV, DataFrames, Dates
using Statistics
using Infiltrator

gs_start = (5, 1)
# # calc_potential_crop_yield(ssm_mm::Float64, gsr_mm::Float64, crop::AgComponent)

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


function create_obj_func(tgt_spec, pars)
    
    # Loading climate data
    climate_data = "$(data_dir)climate/calib_climate_data.csv"
    use_threads = Threads.nthreads() > 1
    climate_seq = DataFrame!(CSV.File(climate_data, threaded=use_threads, dateformat="dd-mm-YYYY"))

    # Create example zone
    climate = Climate(climate_seq)
    farmer = Manager("Calibration")
    zone = create(tgt_spec, climate)

    # Load observed wheat production
    hist_wheat_prod = "$(data_dir)crops/Vic_NC_wheat_production.csv"
    obs_wheat = DataFrame!(CSV.File(hist_wheat_prod, threaded=use_threads, dateformat="YYYY", comment="#", types=Dict(1=>Dates.Date)))
    obs_wheat[!, :Year] = obs_wheat[!, :Year] .+ Dates.Year(1)

    obs_wheat = obs_wheat[obs_wheat[!, :Year] .<= Dates.Date("2016-01-01"), :]
    obs_wheat[!, :Average] = (obs_wheat[!, Symbol(" Wheat produced (t)")] ./ obs_wheat[!, Symbol(" Wheat area sown (ha)")])

    function run_func(params=nothing)
        if !isnothing(params)
            tmp = (; zip(map(Symbol, pars[!, :name]), params)...)
            tmp_zone = update_model(zone, tmp)
        else
            tmp_zone = zone
        end
    
        zone_results, field_results = run_model(farmer, tmp_zone)
    
        f1 = field_results["field1"]
    
        mod_years = map(x -> Year(x), f1.Date)
        avail_years = (mod_years .>= Dates.Year(1991))
    
        subset = f1[avail_years, :]
        avg_yield = (subset[!, :irrigated_yield] + subset[!, :dryland_yield]) ./ (subset[!, :irrigated_area] + subset[!, :dryland_area])

        rmse = sqrt(mean((avg_yield .- obs_wheat.Average).^2))
        
        return rmse
    end

    return run_func
end

# run_func(farmer, wheat_zone, obs_wheat)

data_dir = "test/data/"
calib_zone = load_spec("$(data_dir)zones/CalibZone.yml")
tgt_spec = calib_zone[:CalibZone]
agparams = collect_agparams!(tgt_spec, [])


# Find relevant crop parameters for French-Schultz calibration
crop_params = agparams[occursin.("_uncalibrated_wheat", agparams[!, "name"]) .&
                       (occursin.("wue_coef", agparams[!, "name"]) .|
                        occursin.("et_coef", agparams[!, "name"]) .|
                        occursin.("ssm_coef", agparams[!, "name"]) .|
                        occursin.("rainfall_threshold", agparams[!, "name"])), :]

lower = crop_params.min_val
upper = crop_params.max_val
initial_x = crop_params.default

obj_func = create_obj_func(tgt_spec, crop_params)

res = optimize(obj_func, lower, upper, initial_x)
# 8.770169e-01 (0.877) w/ SAMIN(), no convergence - took 3055 seconds (~51 mins)


@info res
summary(res)

@info Optim.minimizer(res)
@info (; zip(map(Symbol, crop_params[!, :name]), Optim.minimizer(res))...)

# ┌ Info:  * Status: success
# │
# │  * Candidate solution
# │     Final objective value:     8.896884e-01
# │
# │  * Found with
# │     Algorithm:     Fminbox with L-BFGS
# │
# │  * Convergence measures
# │     |x - x'|               = 0.00e+00 ≤ 0.0e+00
# │     |x - x'|/|x'|          = 0.00e+00 ≤ 0.0e+00
# │     |f(x) - f(x')|         = 0.00e+00 ≤ 0.0e+00
# │     |f(x) - f(x')|/|f(x')| = 0.00e+00 ≤ 0.0e+00
# │     |g(x)|                 = 2.09e-04 ≰ 1.0e-08
# │
# │  * Work counters
# │     Seconds run:   8549  (vs limit Inf)
# │     Iterations:    7
# │     f(x) calls:    1957
# └     ∇f(x) calls:   1957
# [ Info: [379.7167523959479, 100.00000000000001, 7.755910986915787]
# [ Info: (Zone__CalibZone___CropField__field1___Crop__uncalibrated_wheat~rainfall_threshold = 379.7167523959479, Zone__CalibZone___CropField__field1___Crop__uncalibrated_wheat~et_coef = 100.00000000000001, Zone__CalibZone___CropField__field1___Crop__uncalibrated_wheat~wue_coef = 7.755910986915787)