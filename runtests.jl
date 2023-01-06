using Test
# using BenchmarkTools

using Dates, TimeZones

module N24
    include("./N24.jl")
end
using .N24

@testset "phase conversions" begin
    s1 = Phases.Advance(3)
    s2 = Phases.Delay(3)
    t = floor(now(localzone()), Hour)
    @test N24.PhaseShift(s1(t), t) == s1
    @test N24.PhaseShift(s2(t), t) == s2
end

@testset "views" begin
    a = ZonedDateTime(2022, 1, 1, tz"UTC")
    b = a + Hour(3)
    @test collect(Views.hour_span(a, b)) == Views.hour_span_view(a, b) == [a, a + Hour(1), a + Hour(2), b]
end

@testset "test functionality on sample data" begin
    tol = 0.1 # 10% tolerance

    # Generate sample activity data with given parameters
    days = 60
    SAMPLE_TIMES = N24.Sources.mock_data(days)

    
    SI = N24.infer_sleep_intervals(SAMPLE_TIMES)
    # Should identify most sleep intervals. Test within tolerance% of expected days. 
    @test days * (1 - tol) < length(SI.intervals)/2 < days * (1 + tol)
    
    # b = @benchmark N24.PhaseEst(
    #     N24.Sleep.contains_hour($SI),
    #     extrema($SAMPLE_TIMES)...,
    # )   
    # display(b)
    
    PE = N24.PhaseEst(
            N24.Sleep.contains_hour(SI),
            extrema(SAMPLE_TIMES)...,
        )
    
    df_phase = N24.frame(PE)
    @test ["cycle", "starts", "ends", "duration", "phase_shift"] ⊆ names(df_phase)

    # Checks sanity of sleep phase duration (sample data has obvious 24h rhythm)
    @test 24 * (1 - tol) < N24.uncanonicalize_period(sum(df_phase.duration)) / size(df_phase, 1) < 24 * (1 + tol)

    # @infiltrate
end

