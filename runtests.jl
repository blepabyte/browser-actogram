using Test, BenchmarkTools

using Dates, TimeZones

module N24
    include("./N24.jl")
end
using .N24

module MockData
	using Dates, TimeZones
	sleep_hours() = sort(rand(collect(rand(5:9):rand(21:23)), 40)) # ~prob 0.95 of hitting any given bucket

	function sample(days=60)
		reduce(vcat, [
			(ZonedDateTime(2022, tz"Pacific/Auckland") + Day(d)) .+ Hour.(sleep_hours())
			for d in 1:days
		])
	end
end

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
    # Generate sample activity data with given parameters
    days = 30
    SAMPLE_TIMES = MockData.sample(days)
    
    SI = N24.infer_sleep_intervals(SAMPLE_TIMES)
    # Should identify most sleep intervals. Test within 10% of expected days. 
    @test days * 0.9 < length(SI.intervals)/2 < days * 1.1
    
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
    @test ["cycle", "starts", "ends", "phase_shift"] ⊆ names(df_phase)
end

