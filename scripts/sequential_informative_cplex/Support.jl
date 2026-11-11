module SequentialInformativeCPLEXSupport
using DecisionProgrammingAlgorithms, JuMP, CPLEX, TOML, SHA, LinearAlgebra
import MathOptInterface as MOI

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const SOLVER_CONFIG = joinpath(ROOT, "experiments", "phase4_extended", "cplex.toml")

# Reuse the audited Phase-4 optimizer configuration and atomic record helpers.
let tree = Meta.parseall(read(joinpath(ROOT, "scripts", "phase4_extended", "worker.jl"), String))
    for name in (:configured_optimizer, :atomic_toml, :putfinite!)
        expression = only(e for e in tree.args if e isa Expr && e.head == :function &&
            e.args[1] isa Expr && e.args[1].head == :call && e.args[1].args[1] == name)
        Core.eval(@__MODULE__, expression)
    end
end

include(joinpath(ROOT, "scripts", "benchmark_sequential_oil.jl"))

function campaign_input(job)
    path = normpath(joinpath(ROOT, job["instance"]))
    bytes2hex(sha256(read(path))) == job["file_sha256"] || error("instance file checksum changed")
    x = load_oil(path)
    instance_hash(x) == job["instance_hash"] || error("physical instance hash changed")
    x
end

"""The caller's 3600-second and memory watchdogs remain the only resource guards."""
function solve_method(method, x, seconds, config=SOLVER_CONFIG)
    unlimited = typemax(Int)
    method == "irbb_fi" && return solve_sequential_probing(x;
        bound=:full_information, max_rows=unlimited)
    method == "irbb_legacy" && return solve_sequential_probing(x;
        bound=:legacy_nonsequential, max_rows=unlimited)
    factory, _ = configured_optimizer(config, "CPLEX-Default", seconds)
    method == "rdp" && return solve_sequential_rdp(x; optimizer=factory, dense=true,
        time_limit=seconds, total_time_limit=seconds, max_segments=unlimited)
    method == "rjt" && return solve_sequential_rjt(x; optimizer=factory,
        time_limit=seconds, total_time_limit=seconds, max_tests=unlimited,
        max_policy_rows=unlimited)
    error("unsupported sequential method: $(method)")
end

# Compile the code path on a one-test instance; the campaign model construction
# and all instance-dependent work remain inside the measured solve.
function warm_method(method, config=SOLVER_CONFIG)
    if startswith(method, "irbb")
        reports = reshape([1, 0, 0, 1], 1, 2, 2)
        witness = OilInstance([1//2, 1//2], [1 0; 0 1], reports, [-1, 1], [1//10])
        solve_method(method, witness, 30., config)
    else
        cheap = OilInstance([1.], ones(1,1), ones(1,1,1), [1.], ones(1))
        solve_method(method, cheap, 30., config)
    end
end

function save_policy(path, policy)
    sequential_benchmark_policy(path * ".tmp", policy)
    mv(path * ".tmp", path; force=true)
end
load_policy(path) = sequential_benchmark_load_policy(path)

export ROOT, SOLVER_CONFIG, configured_optimizer, atomic_toml, putfinite!, campaign_input,
    solve_method, warm_method, save_policy, load_policy
end
