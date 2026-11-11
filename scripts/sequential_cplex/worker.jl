# Fresh process, original Phase-4 markers, timing and record conventions.
include("Support.jl")
using .SequentialCPLEXSupport
using DecisionProgrammingAlgorithms, TOML, SHA, JuMP, LinearAlgebra
import MathOptInterface as MOI

function worker(folder)
    job=TOML.parsefile(joinpath(folder,"job.toml"))
    method=job["method"]; seconds=job["time_seconds"]; config=job["solver_config"]
    Threads.nthreads()==1 || error("one Julia computation thread required")
    BLAS.set_num_threads(1)
    all(get(ENV,k,"")=="1" for k in ("JULIA_NUM_THREADS","OPENBLAS_NUM_THREADS","OMP_NUM_THREADS","MKL_NUM_THREADS")) || error("Phase-4 thread environment mismatch")
    row=Dict{String,Any}("algorithm"=>job["algorithm"],"method"=>method,
        "status"=>"ERROR","certified_optimal"=>false,"feasibility_status"=>"UNAVAILABLE",
        "julia_version"=>string(VERSION),"julia_threads"=>Threads.nthreads(),
        "blas_threads"=>BLAS.get_num_threads(),"computation_threads"=>1,
        "solver"=>startswith(method,"irbb") ? "none" : "CPLEX",
        "solver_configuration"=>startswith(method,"irbb") ? "none" : "CPLEX-Default",
        "configuration_label"=>"our sequential baseline; not published Gurobi timings")
    try
        x,item=frozen_input(job["instance_id"])
        instance_hash(x)==job["instance_hash"] || error("job/input hash mismatch")
        row["instance_hash"]=instance_hash(x)
        row["instance_file_sha256"]=item["file_sha256"]
        init=time_ns(); warm_method(method,ntests(x),config)
        row["warmup_seconds"]=(time_ns()-init)/1e9
        if !startswith(method,"irbb")
            _,parameters=configured_optimizer(config,"CPLEX-Default",seconds)
            row["cplex_parameters"]=parameters
            row["optimization_threads"]=1
            row["cplex_jl_version"]=string(pkgversion(SequentialCPLEXSupport.CPLEX))
        end
        GC.gc()
        atomic_toml(joinpath(folder,"started.toml"),Dict("monotonic_seconds"=>time_ns()/1e9,"unix_seconds"=>time()))
        timed=@timed solve_method(method,x,seconds,config)
        r=timed.value
        row["elapsed"]=timed.time
        row["allocated_bytes"]=timed.bytes
        row["gc_seconds"]=timed.gctime
        row["compilation_seconds"]=timed.compile_time
        row["recompilation_seconds"]=timed.recompile_time
        row["self_high_water_bytes"]=Sys.maxrss()
        row["termination_reason"]=string(r.status)
        row["optimality_status"]=string(r.status)
        isbb=r isa SearchResult
        row["status"]=isbb ? (r.status==:optimal_exact ? "OPTIMAL" : uppercase(string(r.status))) : string(r.status)
        if isbb
            row["bound_scope"]="physical_exact_rational"
            row["best_feasible_objective"]=Float64(r.lower_bound)
            row["best_upper_bound"]=Float64(r.upper_bound)
            row["objective_exact"]=string(r.value)
            row["exact_optimality_certificate"]=true
            for (key,v) in (("irbb_nodes",r.stats.visited),("expanded_nodes",r.stats.expanded),
                    ("pruned_nodes",r.stats.pruned),("policy_evaluations",r.stats.evaluations),
                    ("cache_hits",r.stats.cache_hits),("cache_misses",r.stats.bound_policy_evaluations),
                    ("evaluation_seconds",r.stats.evaluation_time),("bound_seconds",r.stats.bound_time))
                row[key]=v
            end
            row["tau_p"]=timed.time
        else
            row["bound_scope"]="physical_float64_model"
            row["solver_primal_status"]=string(r.primal_status)
            row["raw_status"]=r.raw_status
            row["feasibility_status"]=r.has_solution ? "POLICY_UNVALIDATED" : "NO_SOLUTION"
            for (key,v) in (("nominal_objective",r.value),("nominal_shifted_objective",r.shifted_value),
                    ("best_upper_bound",r.upper_bound),("nominal_upper_bound",r.upper_bound),
                    ("shift",r.shift),("native_mip_gap",r.mip_gap),
                    ("preprocessing_seconds",r.preprocessing_time),("construction_seconds",r.build_time),
                    ("optimization_seconds",r.solve_time),("solver_seconds",r.solver_time),
                    ("variables",r.variables),("constraints",r.constraints),("milp_nodes",r.nodes),
                    ("solver_version",r.solver_version))
                putfinite!(row,key,v)
            end
            row["tau_s"]=r.solver_time
            row["tau_p"]=timed.time-r.solver_time
        end
        atomic_toml(joinpath(folder,"solved.toml"),row)
        if r.policy!==nothing
            validation=time_ns(); physical=evaluate_policy(x,r.policy)
            row["validation_seconds"]=(time_ns()-validation)/1e9
            save_policy(joinpath(folder,"policy.toml"),r.policy)
            evaluate_policy(x,load_policy(joinpath(folder,"policy.toml")))==physical || error("saved policy mismatch")
            row["policy_sha256"]=bytes2hex(sha256(read(joinpath(folder,"policy.toml"))))
            row["policy_file"]="policy.toml"
            row["policy_value_exact"]=string(physical)
            row["policy_value"]=Float64(physical)
            row["best_feasible_objective"]=Float64(physical)
            row["policy_complete"]=true
            row["feasibility_status"]="FEASIBLE_EXACT_POLICY"
            objective=isbb ? Float64(r.value) : r.value
            row["objective_policy_consistent"]=objective!==nothing && isapprox(objective,Float64(physical);atol=1e-7,rtol=1e-9)
            reference_start=time_ns(); reference=solve_sequential_dp(x)
            row["reference_seconds"]=(time_ns()-reference_start)/1e9
            row["exact_reference_value"]=string(reference.value)
            row["exact_reference_agreement"]=physical==reference.value
            row["certified_optimal"]=row["status"]=="OPTIMAL" && row["objective_policy_consistent"] && row["exact_reference_agreement"]
            if row["status"]=="OPTIMAL" && !row["exact_reference_agreement"]
                row["termination_reason"]="NATIVE_OPTIMAL_TOLERANCE_DIFFERS_FROM_EXACT_REFERENCE"
            end
            !row["objective_policy_consistent"] && (row["status"]="ERROR";row["termination_reason"]="OBJECTIVE_POLICY_MISMATCH")
        else
            row["policy_complete"]=false
        end
    catch err
        row["status"]=err isa OutOfMemoryError ? "OUT_OF_MEMORY" : "ERROR"
        row["termination_reason"]=row["status"]
        row["error"]=sprint(showerror,err,catch_backtrace())
        row["certified_optimal"]=false
    end
    row["self_high_water_bytes"]=Sys.maxrss()
    atomic_toml(joinpath(folder,"result.toml"),row)
end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==1 || error("worker.jl ATTEMPT_DIRECTORY")
    worker(abspath(only(ARGS)))
end
