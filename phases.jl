using Dates, TimeZones
using DataFrames

const State = Tuple{Int, ZonedDateTime}

# All times are floored to an hour boundary (minute value is zero). This reduces the number of states; as further precision is likely unnecessary given the nature of estimation

struct PhaseShift
	shift::Int # signed hours
end

function PhaseShift(a::ZonedDateTime, b::ZonedDateTime)
	# negative sign 
	PhaseShift(-N24.uncanonicalize_period(b - a - Hour(24), exact=true))
end

# Advancement in circadian rhythm relative to a 24 hour day 
Advance(h::Int) = PhaseShift(h)
# Delay increases the period of the rhythm, so a "day"/cycle is longer
Delay(h::Int) = PhaseShift(-h)
"""
	(s::PhaseShift)(t::ZonedDateTime)
Goes backwards to compute time of cycle start, assuming `t` is cycle end/start of next cycle, and `s` was the shift.
Satisfies `PhaseShift(s(t), t) == s`.
"""
(s::PhaseShift)(t::ZonedDateTime) = t - Hour(24) + Hour(s.shift)

# arbitrary, subject to change
const DEFAULT_PHASE_SCORES = Dict(
	Advance(4) => 0.3,
	Advance(3) => 0.5,
	Advance(2) => 0.7,
	Advance(1) => 0.9,
	# Delay(0) == Advance(0)
	Delay(0) => 1.0,
	Delay(1) => 1.0,
	Delay(2) => 0.9,
	Delay(3) => 0.8,
	Delay(4) => 0.7,
	Delay(5) => 0.5,
	Delay(6) => 0.3,
	# Delay(7) => 0.3,
)


### Trying out different alignment objectives

# different scoring objectives for:
# a) underlying circadian rhythm
# b) actual sleep behaviour

abstract type AlignmentImpl end

struct HammingAlignment <: AlignmentImpl
	phase_scores::Dict
end

struct WakeAlignment <: AlignmentImpl
	phase_scores::Dict
end

function align(A::HammingAlignment, active::Function, base_score::Float64, t::ZonedDateTime, s::PhaseShift)
	# considers the interval [t1, t2] == [shift(t), t]
	# span is inclusive, so activity in last hour is irrelevant
	activity = N24.Views.hour_span_view(s(t), t - Hour(1)) .|> active
	num_hours = length(activity)

	# hamming distance against "typical". estimates a mix of (a) and (b)
	wake_lag = 2
	sample_sleep = vcat(
		fill(0, wake_lag), # probably not using laptop immediately after waking up
		fill(1, num_hours - (8 + wake_lag)),
		fill(0, 8)
	)
	
	ham_similarity = sum(activity .== sample_sleep) / length(activity) # in [0, 1]
	base_score + ham_similarity * A.phase_scores[s]
end

function align(A::WakeAlignment, active::Function, base_score::Float64, t::ZonedDateTime, s::PhaseShift)
	activity = N24.Views.hour_span_view(s(t), t - Hour(1)) .|> active
	num_hours = length(activity)

	wake_point = findfirst(activity)
	wake_score = if wake_point == 1
		# possibly woken up by alarm, so not predictive
		0.2
	elseif wake_point === nothing
		# probable missing activity data
		0
	else
		2 / (3 + abs(wake_point - 3))
	end

	sleep_point = findlast(!, activity)
	sleep_score = if sleep_point === nothing
		0
	else
		sleep_offset = sleep_point - (num_hours - 7)
		sleep_offset > 0 ? 4 / (2 + sleep_offset) : 1 / (2 - sleep_offset)
	end

	activity_contrib = activity[3:min(length(activity), 3 + 12)]
	activity_score = sum(activity_contrib) / length(activity_contrib)

	m = 0.5
	return base_score + A.phase_scores[s] * (2 + m * (wake_score + 0.5 * sleep_score + activity_score))
end


### Structs to keep track of and advance the dynamic programming state

mutable struct PhaseEstimation{A <: AlignmentImpl}
	states::Dict{State, Float64}
	paths::Dict{State, State}
	active::Function # returns 0 => inactive at time, 1 => active at time. assumes has been somewhat processed/smoothed from raw activity data
	cycle::Int
	considered_times::Vector{ZonedDateTime} # assume sorted
	alignment_algorithm::A
end


function consider(P::PhaseEstimation, t::ZonedDateTime)
	best_score, best_shift = findmax(Dict([
		s => alignment(P, t, s) for s in keys(P.alignment_algorithm.phase_scores)
	]))
	P.states[(P.cycle, t)] = best_score
	P.paths[(P.cycle, t)] = (P.cycle - 1, best_shift(t))
end


"
	alignment(P::PhaseEstimation, t::ZonedDateTime, s::PhaseShift)
Computes score for current cycle number, given the circadian cycle described by the parameters. `t` is typically an element of `P.considered_times`
"
function alignment(P::PhaseEstimation, t::ZonedDateTime, s::PhaseShift)
	prev_t = s(t)
	@assert prev_t < t

	prev_state = (P.cycle - 1, prev_t)
	base_score::Float64 = get(P.states, prev_state, -Inf)
	base_score === -Inf && return 0

	return align(
		P.alignment_algorithm,
		P.active,
		base_score,
		t,
		s
	)
end


function extract_path(P::PhaseEstimation, state::State)
    path = [state]
    # get cycle number of state and iterate backwards
	for c in first(state):-1:1
		push!(path, P.paths[last(path)])
	end
    reverse!(path)
    path
end


"""
Contains result of phase estimation over a given interval

Related functions: `frame(::PhaseEst)`
"""
struct PhaseEst
    path # consists of times of inferred "wake" events
    shifts
    mean_period
end # TODO: overload display

function next_cycle_range(left::ZonedDateTime, right::ZonedDateTime)
    N24.Views.hour_span_view(
        left + Hour(24) - Hour(4),
        right + Hour(24) + Hour(7)
    )
end


"""
    PhaseEst(active::Function, first_hour::ZonedDateTime, last_hour::ZonedDateTime, start_lag_hours::Int=28, end_lag_hours::Int=32)
Start lag defines the time period that the algorithm can choose the initial "wake time" from
"""
function PhaseEst(active::Function, first_hour::ZonedDateTime, last_hour::ZonedDateTime; start_lag_hours::Int=28, end_lag_hours::Int=36, POOL_SIZE::Int=48)
    # once a cycle has reached this point, it is finalised and will be part of the output
    end_cutoff = last_hour - Hour(end_lag_hours)

    P = PhaseEstimation{HammingAlignment}(
        Dict([
            (0, first_hour + Hour(h)) => 0
            for h in 0:start_lag_hours
        ]),
        Dict(),
        active,
        0,
        next_cycle_range(first_hour, first_hour + Hour(start_lag_hours)),
		HammingAlignment(DEFAULT_PHASE_SCORES)
    )
    
    terminating_states::Dict{State, Float64} = Dict()
    
    while !isempty(P.considered_times)
        foreach(t -> consider(P, t), P.considered_times)
    
        # assumes sorted
        if last(P.considered_times) >= end_cutoff
            # we do NOT want to reward for total number of cycles (that makes the algorithm "squish" things to try fit the given time period exactly over end_lag period, regardless of actual sleep activity)
            # solution: normalise by # cycles
            terminate = i -> let k = (P.cycle, P.considered_times[i])
                (k, P.states[k] / P.cycle)
            end
            # ideally end_lag_hours should be large enough that all consideration times will reach this point before exceeding last_hour        
            I = searchsortedfirst(P.considered_times, end_cutoff):length(P.considered_times)
            merge!(terminating_states, Dict(terminate.(I)))
            deleteat!(P.considered_times, I)
        end
        
        isempty(P.considered_times) && break
        
        # trim the fat; maybe keep constant instead of percentage?
        if P.cycle > 1 && P.cycle % 28 == 0 && length(P.considered_times) > POOL_SIZE
            score_time = t -> P.states[(P.cycle, t)]
            considered_scores = P.considered_times .|> score_time
            # drop_threshold = maximum(considered_scores) * 0.9
            # surely there's a better way to write this
			ordered_scores = sort(considered_scores)
			keep_threshold = ordered_scores[length(ordered_scores) - POOL_SIZE + 1]
			
			pre_drop_count = length(P.considered_times)
            P.considered_times = P.considered_times[considered_scores .>= keep_threshold]
			post_drop_count = length(P.considered_times)
			# @info "Pruned times: $pre_drop_count -> $post_drop_count"
        end

    	# generate considered times for next cycle
    	# NAIVE: uniformly expand shifted range
    	P.considered_times = next_cycle_range(extrema(P.considered_times)...)

    	P.cycle += 1
    end
    
    best_terminal_state = argmax(terminating_states)
    best_state_path = extract_path(P, best_terminal_state)
    best_path = last.(best_state_path)
    diffs = diff(best_path) .|> Dates.canonicalize

    PhaseEst(
        best_path,
        diffs,
        N24.uncanonicalize_period(sum(diffs)) / length(diffs)
    )
end


"""
	frame(P::PhaseEst)
Conversion to a DataFrame for more convenient analysis
"""
function N24.frame(PE::PhaseEst)
	transform!(
		DataFrame(
			# maximum(:cycle) gives total number of sleep-wake cycles
			:cycle => collect(1:length(PE.path)-1),
			:starts => PE.path[1:end-1],
			:ends => PE.path[2:end],
		),
		Cols(:starts, :ends) => ((a, b) -> hcat(
			Hour.(b .- a),
			N24.PhaseShift.(a, b)
		)) => [:duration, :phase_shift],
	)
end


struct PhaseResponse
	model
end


"""
Given disjoint activity streams, constructs a generalised linear model for phase response to light
"""
function phase_response(sources...)
	
end


export PhaseShift, Advance, Delay, PhaseEst

