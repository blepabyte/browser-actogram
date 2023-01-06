module N24
include("./N24.jl")
end
using .N24

module Loader
import ..N24
if "places.sqlite" in readdir()
    function recent_timestamps(x)
        N24.Sources.read_timestamps_file("./places.sqlite")
    end
else
    include("../custom_loader.jl")
end
end

using Dates, TimeZones
using DataFrames, GLM

function output(x)
    haskey(ENV, "HIDE_OUTPUT") || (x isa AbstractString ? println(x) : display(x))
    x
end

function cycle_to_time_offset(p::Real)
    proportion = mod(p, 1.)
    round(Int, proportion * 24 * 60) |> Minute
end

"""
Using a default wake-up time of 6am as a reference point, gets the current "circadian time", as estimated by the last 21 days of activity data
"""
function circadian_time(num_days_for_estimate::Int=21, reference_wake_time=Time(6, 0))
    after_date = Date(now()) - Day(num_days_for_estimate)

    # Find and load activity timestamp data for sleep estimation
    ts = filter(
        t -> Date(t) >= after_date,
        Loader.recent_timestamps(2)
    )
    # Construct estimated sequence of Awake and Asleep intervals
    si = Sleep.infer_sleep_intervals(ts)
    # Run estimation algorithm that tries to align intervals into complete sleep cycles
    et = Phases.PhaseEst(
        Sleep.contains_hour(si),
        extrema(ts)...
    )
    # Results of estimation as a DataFrame
    df = N24.frame(et) |> output

    hours_ago(t) = Dates.value(round(now(localzone()) - t, Minute)) / 60

    # Construct linear regression model: cycles start/end at integer values of :cycle
    df_vars = select(df,
        :cycle,
        :starts => ByRow(hours_ago) => :offset_now
    )

    linear_model = lm(@formula(cycle ~ offset_now), df_vars) |> output

    sleep_period = coef(linear_model) |> last |> abs |> inv

    linear_pred = predict(
        linear_model, 
        DataFrame(Dict(:offset_now => [0])),
        interval=:prediction
    ) |> output

    pred, lower_confidence, upper_confidence = reference_wake_time .+ (linear_pred |> eachrow |> only |> collect .|> cycle_to_time_offset)

    output("\nEstimated sleep cycle period: $(round(sleep_period, digits=3)) hours")

    let fmt(t) = Dates.format(t, "HH:MM")
        println("Actual time: ", fmt(now()))
        println("Circadian time: $(fmt(pred)) in 95% CI [$(fmt(lower_confidence)), $(fmt(upper_confidence))] estimate")
        println("Offset: ", round(Time(now()) - pred, Hour))
    end
    pred
end

circadian_time()

