using DataFrames
using Dates
using TimeZones
using Chain

struct EventsAsHourBuckets
    # NOTE: groupby column to get efficient indexing for a specific hour boundary
    df::DataFrame
    start_date
    end_date
end

into_hour_buckets(times::Vector{ZonedDateTime}) = DataFrame(:t => times) |> into_hour_buckets

"""
Takes either:

    Vector{ZonedDateTime}
    df::(DataFrame{t::ZonedDateTime})
and returns:

    dfh::(DataFrame{date::DateTime, hour_num_events::Int, tz_hour::ZonedDateTime})
"""
function into_hour_buckets(
    df::DataFrame;
    _smooth_fn = identity, # TODO: deprecate, because applying smoothing only within 24-hour windows is bad
    HOUR_EVENT_TH = 1,
    WITH_TIME_ZONE = localzone()
    )

    # dfb = @chain df begin
    # 	# split DateTime to Date and Hour (zero-indexed hour offset from 00:00 of that day) columns, discarding timezone information
    # 	transform(:t => ByRow(Date) => :date, :t => ByRow(hour) => :hour_idx)
    # 	groupby(_, Cols(:date, :hour_idx))
    # 	# count the number of "activity" events each hour
    # 	combine(:hour_idx => length => :hour_num_events)
    # 	# and use as threshold to only keep rows corresponding to hours with activity
    # 	subset(:hour_num_events => ByRow(>=(HOUR_EVENT_TH)))
    # 	groupby(:date)
    # 	# so that after grouping by day, we get a length 24 bitvector corresponding to the hours of each day
    # 	combine(:hour_idx => (x -> let
    # 		hencode = zeros(24)
    # 		hencode[x .+ 1] .= 1
    # 		[_smooth_fn(hencode)]
    # 	end) => :hour_active)
    #     # subtlety: not all days have 24 hours (daylight savings)
    # 	transform(Cols() => ByRow(() -> collect(0:23)) => :hour_idxes)
    #     # but for the purposes of plotting, the output shall be timezone-naive
    #     transform(Cols(:date, :hour_idxes) => ByRow((date, idx) -> DateTime(date) .+ Hour.(idx)) => :hour_times)
    # end
    
    dfb = @chain df begin
    	# normalise all to single canonical timezone
    	select(:t => (t -> astimezone.(t, localzone())) => :tz)
    	transform!(:tz => (t -> floor.(t, Hour)) => :tz_hour)
    	groupby(:tz_hour)
    	combine(:tz_hour => length => :hour_num_events)
    	transform!(:tz_hour => ByRow(Date) => :date)
    end    

    EventsAsHourBuckets(dfb, minimum(dfb.date), maximum(dfb.date))
end


export into_hour_buckets

