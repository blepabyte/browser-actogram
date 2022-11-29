# module N24

include("./utils.jl")

module Sources
using ..N24
include("./sources.jl")
end
using .Sources

module Views
using ..N24
include("./views.jl")
end
using .Views

module Events
using ..N24
include("./events.jl")
end
using .Events

module Sleep
using ..N24
include("./sleep.jl")
end
using .Sleep

module Cycles
using ..N24
include("./cycles.jl")
end
using .Cycles


module Phases
using ..N24
include("./phases.jl")
end
using .Phases


# end

