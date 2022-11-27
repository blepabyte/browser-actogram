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


function hour_by_day_view(first_day, last_day, time_zone=localzone())::Matrix{ZonedDateTime}
    # times are accepted and converted to their corresponding date
    first_day, last_day = Date(first_day), Date(last_day)
    n_1 = Dates.value(Day(last_day - first_day))
    start_zoned = ZonedDateTime(first_day, time_zone)
    elementwise(
        (h, d) -> start_zoned + Day(d) + Hour(h),
        (0:23, 0:n_1)
    )
end


function day_by_week_view(start_date, end_date)::Matrix{Date}

end


module TestCases
    using Test
    
    function runtests()
    
    end
end

