import Dates


###


"""
    uncanonicalize(duration, unit)
Converts any duration into a floating point value with unit (default: hours) given by the second parameter
Calculations are performed at millisecond resolution. 
"""
uncanonicalize_period(C::Union{Dates.Period, Dates.CompoundPeriod}, unit=Dates.Hour; exact=false) = if exact
    # type instability - probably shouldn't be used in hot loop
    # would like, but can't guarantee that `toms` returns an integer
    Int(Int(Dates.toms(C)) // Int(Dates.toms(unit(1))))
else
    Dates.toms(C) / Dates.toms(unit(1))
end


###


vec_along(x::AbstractArray; dim) = reshape(x, Tuple(vcat(fill(1, dim-1), [:])))
vec_along(x::Tuple; dim) = vec_along(collect(x); dim)
vec_along(x::Integer; dim) = vec_along(1:x; dim)

elementwise(f::Function, axes) = f.((vec_along(x; dim) for (dim, x) in enumerate(axes))...)

fromfunction = elementwise # numpy-like alias

export fromfunction, elementwise


###


