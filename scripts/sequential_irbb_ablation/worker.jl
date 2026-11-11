include(joinpath(@__DIR__,"..","sequential_informative_cplex","Support.jl"))
using .SequentialInformativeCPLEXSupport
using DecisionProgrammingAlgorithms, TOML, SHA, LinearAlgebra

const THREAD_KEYS=("JULIA_NUM_THREADS","OPENBLAS_NUM_THREADS","OMP_NUM_THREADS",
    "MKL_NUM_THREADS","VECLIB_MAXIMUM_THREADS","BLIS_NUM_THREADS")

function worker(folder)
    job=TOML.parsefile(joinpath(folder,"job.toml")); seconds=job["time_seconds"]
    Threads.nthreads()==1 || error("one Julia computation thread required")
    BLAS.set_num_threads(1)
    all(get(ENV,key,"")=="1" for key in THREAD_KEYS) || error("thread environment mismatch")
    row=Dict{String,Any}("algorithm"=>"irbb","method"=>job["method"],
        "variant"=>job["variant"],"bound"=>job["bound"],"status"=>"ERROR",
        "certified_optimal"=>false,"feasibility_status"=>"UNAVAILABLE",
        "solver"=>"none","solver_configuration"=>"none","julia_version"=>string(VERSION),
        "julia_threads"=>Threads.nthreads(),"blas_threads"=>BLAS.get_num_threads(),
        "computation_threads"=>1,
        "thread_environment"=>Dict(key=>get(ENV,key,"") for key in THREAD_KEYS))
    try
        x=campaign_input(job)
        variant=Symbol(job["variant"]); bound=Symbol(job["bound"])
        warm=OilInstance([1.],ones(1,1),ones(1,1,1),[1.],[10.])
        warmstart=time_ns()
        solve_sequential_probing(warm;variant,bound,max_rows=typemax(Int),time_limit=30.)
        row["warmup_seconds"]=(time_ns()-warmstart)/1e9
        GC.gc()
        atomic_toml(joinpath(folder,"started.toml"),
            Dict("monotonic_seconds"=>time_ns()/1e9,"unix_seconds"=>time()))
        # Leave a small margin for a cooperative timeout record before the
        # scheduler's independent hard wall-clock watchdog.
        internal_limit=max(0.001,seconds-2.)
        timed=@timed solve_sequential_probing(x;variant,bound,max_rows=typemax(Int),
            time_limit=internal_limit,progress_every=job["progress_every"])
        result=timed.value; stats=result.stats
        row["elapsed"]=timed.time; row["allocated_bytes"]=timed.bytes
        row["gc_seconds"]=timed.gctime; row["compilation_seconds"]=timed.compile_time
        row["recompilation_seconds"]=timed.recompile_time
        row["self_high_water_bytes"]=Sys.maxrss()
        row["status"]=result.status==:optimal_exact ? "OPTIMAL" : uppercase(string(result.status))
        row["termination_reason"]=string(result.status)
        row["objective_exact"]=string(result.value)
        row["best_feasible_objective"]=Float64(result.lower_bound)
        row["best_upper_bound"]=Float64(result.upper_bound)
        for name in fieldnames(SearchStats)
            value=getfield(stats,name)
            value===nothing || (row[string(name)]=value isa Rational ? string(value) : value)
        end
        row["irbb_nodes"]=stats.visited
        atomic_toml(joinpath(folder,"solved.toml"),row)
        if result.policy!==nothing
            validation=time_ns(); physical=evaluate_policy(x,result.policy)
            row["validation_seconds"]=(time_ns()-validation)/1e9
            save_policy(joinpath(folder,"policy.toml"),result.policy)
            row["policy_sha256"]=bytes2hex(sha256(read(joinpath(folder,"policy.toml"))))
            row["policy_file"]="policy.toml"; row["policy_value_exact"]=string(physical)
            row["policy_value"]=Float64(physical); row["policy_complete"]=true
            row["feasibility_status"]="FEASIBLE_EXACT_POLICY"
            row["objective_policy_consistent"]=physical==result.value
            reference_start=time_ns(); reference=solve_sequential_dp(x)
            row["reference_seconds"]=(time_ns()-reference_start)/1e9
            row["exact_reference_value"]=string(reference.value)
            row["exact_reference_agreement"]=physical==reference.value
            row["certified_optimal"]=row["status"]=="OPTIMAL" &&
                row["objective_policy_consistent"] && row["exact_reference_agreement"]
        else
            row["policy_complete"]=false
        end
    catch err
        row["status"]=err isa OutOfMemoryError ? "OUT_OF_MEMORY" : "ERROR"
        row["termination_reason"]=row["status"]
        row["error"]=sprint(showerror,err,catch_backtrace())
    end
    row["self_high_water_bytes"]=Sys.maxrss()
    atomic_toml(joinpath(folder,"result.toml"),row)
end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==1 || error("worker.jl ATTEMPT_DIRECTORY")
    worker(abspath(only(ARGS)))
end
