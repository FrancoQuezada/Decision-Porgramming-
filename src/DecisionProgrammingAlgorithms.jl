module DecisionProgrammingAlgorithms

using Random, SHA, TOML, DelimitedFiles
using JuMP, HiGHS
import MathOptInterface as MOI
import DecisionProgramming

include("core/Interfaces.jl")
include("instances/OilWildcatter.jl")
include("evaluation/OilEvaluation.jl")
include("instances/SequentialOilPolicies.jl")
include("evaluation/SequentialOilEvaluation.jl")
include("algorithms/ProbingIRBB.jl")
include("algorithms/SequentialProbingIRBB.jl")
include("formulations/OilRDP.jl")
include("formulations/OilMILPDiagnostics.jl")
include("formulations/SequentialOilRDP.jl")
include("formulations/OilRJT.jl")
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
