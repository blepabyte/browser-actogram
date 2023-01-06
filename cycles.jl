using FFTW
using LombScargle
using Dates
using TimeZones
using Statistics


"""
Assumes first element of FFT output has been deleted. Probably better to encode that in a struct-type later. 
"""
fft_bucket_hour_period(num_hours::Int, bucket) = Minute(round(Int, 60 * num_hours / bucket)) |> Dates.canonicalize


# TODO: Possible off-by-one errors... Check return size of rfft
fft_periods(num_hours::Int) = fft_bucket_hour_period.(num_hours, 1:floor(Int, num_hours // 2 - 1))


"""
Frequency components of input vector (as TimePeriods), assuming uniform samples at every hour
"""
function date_frequencies_in(hours; top_k::Union{Int, Nothing}=nothing)::Vector{Tuple{Float64, Dates.CompoundPeriod}}
    X = hours .- mean(hours)
    freqs = abs.(rfft(X))

    # mean ends up in first element of FFT output, is irrelevant
    ranking = map(enumerate(freqs[2:end])) do (i, f)
        hour_period = length(hours) / i
        p = Minute(round(Int, hour_period * 60)) |> Dates.canonicalize
        (f, p)
    end
    
    return if isnothing(top_k)
        sort!(ranking, rev=true)
    else
        partialsort!(ranking, 1:top_k, rev=true)
    end
end


function isolate_frequencies(hours, low, high)
    # Will have mean zero
    T = fft_periods(length(hours))
    I = findall(t -> (low <= t <= high), T)
    F = rfft(hours)[2:end]
    F[setdiff(eachindex(F), I)] .= 0
    
    zip(T[I], abs.(F[I])) |> collect |> display
    irfft(vcat([0], F), length(hours))
end


# TODO: WIP


struct MovingFreqs
end


struct FitSleepCycle{T}
end


# Runs prediction at a single frequency to try model underlying circadian rhythm (can that have multiple frequencies?)
function FitSleepCycle{:fft}(e::N24.SleepIntervalSequence)

end


struct TimeFitCurves
    start_time
    end_time
end


function interpolate(tc::TimeFitCurves)
end


function extrapolate(tc::TimeFitCurves)
end

