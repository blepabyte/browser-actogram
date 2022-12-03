using Dates


# T will typically be `DateTime` or `ZonedDateTime`
mutable struct Awake{T}
	from::T
	to::T
end


mutable struct Asleep{T}
	from::T
	to::T
end


duration(i::Union{Awake, Asleep}) = i.to - i.from


struct SleepIntervalSequence{T}
    intervals::Vector{Union{Asleep{T}, Awake{T}}}
end


"""
	contains_hour(si::SleepIntervalSequence, type=Awake)
Returns a callable `T -> Bool` that checks whether a time (rounded/floored to an exact hour) is approximately contained in an interval of given `type`.
"""
function contains_hour(si::SleepIntervalSequence, type=Awake)
	hours = Set()
	
	for i in si.intervals
		i isa type || continue
		h = floor(i.from, Hour)
		while h < i.to
			push!(hours, h)
			h += Hour(1)
		end
	end
	
	h -> (h in hours)
end


function infer_sleep_intervals(activity_stream; 
	KEEP_AWAKE_DIFF = Hour(5), 
	MAX_SLEEP = Hour(24))
    
	it = Iterators.Stateful(activity_stream)

	last_t = popfirst!(it)
	T = typeof(last_t) # some dynamic type "inference"
	intervals::Vector{Union{Awake{T}, Asleep{T}}} = [Awake(last_t, last_t)]
	while !isempty(it)
		cur_t = popfirst!(it)
		last_t > cur_t && error("Expected events to be sorted")
		cur_t == last_t && continue  # ignore duplicate events
		if (cur_t - last_t) < KEEP_AWAKE_DIFF
			# continue same "wake" session
			last(intervals).to = cur_t
		elseif (cur_t - last_t) > MAX_SLEEP
			# no browsing data. cannot infer end of last interval
			last(intervals).to = last_t + Minute(1)
			push!(intervals, Awake(cur_t, cur_t + Minute(1)))
		else
			# add a sleep session
			push!(intervals, Asleep(last_t, cur_t))
			push!(intervals, Awake(cur_t, cur_t + Minute(1)))
		end
		last_t = cur_t
	end
	@assert all(duration.(intervals) .> Minute(0))
	SleepIntervalSequence(intervals)
end


# Abuse of "<" to mean containment of intervals because I can't be bothered implementing a binary search
search_first_interval_lt(int::Union{Asleep, Awake}, t) = int.to < t
search_last_interval_lt(t, int::Union{Asleep, Awake}) = t < int.from


function slice_intervals_within(wi::SleepIntervalSequence, t,  within::TimePeriod, cut=true)
    wake_intervals = wi.intervals
    # Find all intervals intersecting [t - within, t + within]
    I = searchsortedfirst(wake_intervals, t - within, lt=search_first_interval_lt):searchsortedlast(wake_intervals, t + within, lt=search_last_interval_lt)
	ints = wake_intervals[I] |> deepcopy

	if cut && !isempty(ints)
		first(ints).from = max(first(ints).from, t - within)
		last(ints).to = min(last(ints).to, t + within)
	end
	return SleepIntervalSequence(ints)
end


function sleep_density(wi::SleepIntervalSequence)
	awakes = filter(wi.intervals) do x x isa Awake end
	asleeps = filter(wi.intervals) do x x isa Asleep end

	wake_time = floor(sum(duration, awakes, init=Millisecond(0)), Minute) |> Dates.value
	sleep_time = floor(sum(duration, asleeps, init=Millisecond(0)), Minute) |> Dates.value
	total_time = wake_time + sleep_time

	return if total_time == 0
		missing
	else
		sleep_time / (sleep_time + wake_time)
	end
end


sleep_density_at(wi::SleepIntervalSequence, t, within=Minute(60 * 3)) = slice_intervals_within(wi, t, within) |> sleep_density


export SleepIntervalSequence, infer_sleep_intervals

