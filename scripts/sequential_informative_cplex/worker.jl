# Fresh process per run; all scientific work is performed after the scheduler launches this file.
include("Support.jl")
using .SequentialInformativeCPLEXSupport
using DecisionProgrammingAlgorithms, TOML, SHA, JuMP, LinearAlgebra

const THREAD_KEYS = ("JULIA_NUM_THREADS", "OPENBLAS_NUM_THREADS", "OMP_NUM_THREADS",
    "MKL_NUM_THREADS", "VECLIB_MAXIMUM_THREADS", "BLIS_NUM_THREADS")

function worker(folder)
    job = TOML.parsefile(joinpath(folder, "job.toml"))
    method = job["method"]
    seconds = job["time_seconds"]
    config = job["solver_config"]
    Threads.nthreads() == 1 || error("one Julia computation thread required")
    BLAS.set_num_threads(1)
    all(get(ENV, key, "") == "1" for key in THREAD_KEYS) || error("Phase-4 thread environment mismatch")
    row = Dict{String,Any}(
        "algorithm" => job["algorithm"], "method" => method,
        "status" => "ERROR", "certified_optimal" => false,
        "feasibility_status" => "UNAVAILABLE", "julia_version" => string(VERSION),
        "julia_threads" => Threads.nthreads(), "blas_threads" => BLAS.get_num_threads(),
        "computation_threads" => 1,
        "thread_environment" => Dict(key => get(ENV, key, "") for key in THREAD_KEYS),
        "solver" => startswith(method, "irbb") ? "none" : "CPLEX",
        "solver_configuration" => startswith(method, "irbb") ? "none" : "CPLEX-Default",
        "configuration_label" => "sequential informative benchmark; CPLEX-Default",
    )
    try
        x = campaign_input(job)
        row["instance_hash"] = instance_hash(x)
        row["instance_file_sha256"] = job["file_sha256"]
        warm_start = time_ns()
        warm_method(method, config)
        row["warmup_seconds"] = (time_ns() - warm_start) / 1e9
        if !startswith(method, "irbb")
            _, parameters = configured_optimizer(config, "CPLEX-Default", seconds)
            row["cplex_parameters"] = parameters
            row["optimization_threads"] = 1
            row["cplex_jl_version"] = string(pkgversion(SequentialInformativeCPLEXSupport.CPLEX))
        end
        GC.gc()
        atomic_toml(joinpath(folder, "started.toml"),
            Dict("monotonic_seconds" => time_ns()/1e9, "unix_seconds" => time()))
        timed = @timed solve_method(method, x, seconds, config)
        result = timed.value
        row["elapsed"] = timed.time
        row["allocated_bytes"] = timed.bytes
        row["gc_seconds"] = timed.gctime
        row["compilation_seconds"] = timed.compile_time
        row["recompilation_seconds"] = timed.recompile_time
        row["self_high_water_bytes"] = Sys.maxrss()
        row["termination_reason"] = string(result.status)
        row["optimality_status"] = string(result.status)
        is_irbb = result isa SearchResult
        row["status"] = is_irbb ? (result.status == :optimal_exact ? "OPTIMAL" : uppercase(string(result.status))) : string(result.status)
        if is_irbb
            row["bound_scope"] = "physical_exact_rational"
            row["best_feasible_objective"] = Float64(result.lower_bound)
            row["best_upper_bound"] = Float64(result.upper_bound)
            row["objective_exact"] = string(result.value)
            row["exact_optimality_certificate"] = true
            for (key, value) in (("irbb_nodes", result.stats.visited),
                    ("expanded_nodes", result.stats.expanded), ("pruned_nodes", result.stats.pruned),
                    ("policy_evaluations", result.stats.evaluations), ("cache_hits", result.stats.cache_hits),
                    ("cache_misses", result.stats.bound_policy_evaluations),
                    ("evaluation_seconds", result.stats.evaluation_time), ("bound_seconds", result.stats.bound_time))
                row[key] = value
            end
            row["tau_p"] = timed.time
        else
            row["bound_scope"] = "physical_float64_model"
            row["solver_primal_status"] = string(result.primal_status)
            row["raw_status"] = result.raw_status
            row["feasibility_status"] = result.has_solution ? "POLICY_UNVALIDATED" : "NO_SOLUTION"
            for (key, value) in (("nominal_objective", result.value),
                    ("nominal_shifted_objective", result.shifted_value), ("best_upper_bound", result.upper_bound),
                    ("nominal_upper_bound", result.upper_bound), ("shift", result.shift),
                    ("native_mip_gap", result.mip_gap), ("preprocessing_seconds", result.preprocessing_time),
                    ("construction_seconds", result.build_time), ("optimization_seconds", result.solve_time),
                    ("solver_seconds", result.solver_time), ("variables", result.variables),
                    ("constraints", result.constraints), ("milp_nodes", result.nodes),
                    ("solver_version", result.solver_version))
                putfinite!(row, key, value)
            end
            row["tau_s"] = result.solver_time
            row["tau_p"] = timed.time - result.solver_time
        end
        atomic_toml(joinpath(folder, "solved.toml"), row)
        if result.policy !== nothing
            validation_start = time_ns()
            physical = evaluate_policy(x, result.policy)
            row["validation_seconds"] = (time_ns() - validation_start) / 1e9
            save_policy(joinpath(folder, "policy.toml"), result.policy)
            evaluate_policy(x, load_policy(joinpath(folder, "policy.toml"))) == physical || error("saved policy mismatch")
            row["policy_sha256"] = bytes2hex(sha256(read(joinpath(folder, "policy.toml"))))
            row["policy_file"] = "policy.toml"
            row["policy_value_exact"] = string(physical)
            row["policy_value"] = Float64(physical)
            row["best_feasible_objective"] = Float64(physical)
            row["policy_complete"] = true
            row["feasibility_status"] = "FEASIBLE_EXACT_POLICY"
            objective = is_irbb ? Float64(result.value) : result.value
            row["objective_policy_consistent"] = objective !== nothing &&
                isapprox(objective, Float64(physical); atol=1e-7, rtol=1e-9)
            reference_start = time_ns()
            reference = solve_sequential_dp(x)
            row["reference_seconds"] = (time_ns() - reference_start) / 1e9
            row["exact_reference_value"] = string(reference.value)
            row["exact_reference_agreement"] = physical == reference.value
            row["certified_optimal"] = row["status"] == "OPTIMAL" &&
                row["objective_policy_consistent"] && row["exact_reference_agreement"]
            if row["status"] == "OPTIMAL" && !row["exact_reference_agreement"]
                row["termination_reason"] = "NATIVE_OPTIMAL_TOLERANCE_DIFFERS_FROM_EXACT_REFERENCE"
            end
            if !row["objective_policy_consistent"]
                row["status"] = "ERROR"
                row["termination_reason"] = "OBJECTIVE_POLICY_MISMATCH"
            end
        else
            row["policy_complete"] = false
        end
    catch err
        row["status"] = err isa OutOfMemoryError ? "OUT_OF_MEMORY" : "ERROR"
        row["termination_reason"] = row["status"]
        row["error"] = sprint(showerror, err, catch_backtrace())
        row["certified_optimal"] = false
    end
    row["self_high_water_bytes"] = Sys.maxrss()
    atomic_toml(joinpath(folder, "result.toml"), row)
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) == 1 || error("worker.jl ATTEMPT_DIRECTORY")
    worker(abspath(only(ARGS)))
end
