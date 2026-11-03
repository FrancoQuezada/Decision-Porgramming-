module DecisionProgrammingAlgorithms

using Random, SHA, TOML, DelimitedFiles
using JuMP, HiGHS
import MathOptInterface as MOI

include("core/Interfaces.jl")
include("instances/OilWildcatter.jl")
include("evaluation/OilEvaluation.jl")
include("algorithms/ProbingIRBB.jl")
include("formulations/OilRDP.jl")
include("formulations/PaperOilRDP.jl")
include("core/InfluenceDiagrams.jl")
include("evaluation/PolicyEvaluation.jl")
include("relaxations/InformationRelaxation.jl")
include("algorithms/IRBB.jl")
include("evaluation/StructuredOptimization.jl")
include("instances/GeneralDPInstances.jl")
include("caching/ContextKeys.jl")
include("caching/SubproblemCache.jl")
include("caching/IncrementalUpdates.jl")
include("algorithms/CachedIRBB.jl")
include("utilities/Experiments.jl")

end
