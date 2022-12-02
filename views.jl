using Dates
using TimeZones
using DataFrames


"""
    map_into_df(
        df::DataFrame, 
        hour_col_name::Symbol, 
        value_fn,
        value_missing=missing
    )
Given a DataFrame with a key column consisting of `ZonedDateTime`s floored to an exact hour, 
returns a mapping function that can be broadcast over the output of `hour_by_day_view`
"""
map_into_df(
    df::DataFrame, 
    hour_col_name::Symbol, 
    value_fn,
    value_missing=missing
) = let gdf = groupby(df, hour_col_name)
    hd::ZonedDateTime -> let k = NamedTuple((hour_col_name => hd,))
        if haskey(gdf, k)
            value_fn(gdf[k] |> only |> NamedTuple)
        else
            value_missing
        end
    end
end


function hour_by_day_view(first_day::T, last_day::T, time_zone::TimeZone=localzone())::Matrix{ZonedDateTime} where T <: Union{Date, DateTime, ZonedDateTime}
    # times are accepted and converted to their corresponding date
    first_day, last_day = Date(first_day), Date(last_day)
    n_1 = Dates.value(Day(last_day - first_day))
    start_zoned = ZonedDateTime(first_day, time_zone)
    elementwise(
        (h, d) -> start_zoned + Day(d) + Hour(h),
        (0:23, 0:n_1)
    )
end

hour_by_day_view(contained_times::Vector, time_zone::TimeZone=localzone()) = hour_by_day_view(extrema(contained_times)..., time_zone)


function day_by_week_view(start_date, end_date)::Matrix{Date}

end


function hour_span_view(from::ZonedDateTime, to::ZonedDateTime)
    from, to = floor(from, Hour), ceil(to, Hour)
    @assert from < to
    t = from
    span = ZonedDateTime[]
    while t <= to
        push!(span, t)
        t += Hour(1)
    end
    span
end

struct HourSpan
    first::ZonedDateTime
    until_inclusive::ZonedDateTime
end

Base.length(hs::HourSpan) = (Dates.value ∘ Hour)(hs.until_inclusive - hs.first) + 1
Base.iterate(hs::HourSpan) = (hs.first, hs.first + Hour(1))
Base.iterate(hs::HourSpan, t::ZonedDateTime) = if t > hs.until_inclusive
    nothing
else
    (t, t + Hour(1))
end

"""
    hour_span(from::ZonedDateTime, to::ZonedDateTime)
Like `hour_span_view` but returns an iterator, avoiding frequently unnecessary allocations
"""
hour_span(from::ZonedDateTime, to::ZonedDateTime) = HourSpan(from, to)


