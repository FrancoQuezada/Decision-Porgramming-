include("Common.jl")
using .Table3Common
using DecisionProgrammingAlgorithms, JuMP, TOML
import MathOptInterface as MOI

function optional_metric!(record,key,query)
    try
        value=query()
        value isa AbstractFloat && !isfinite(value) && return
        record[key]=value isa Enum ? string(value) : value
    catch
        # Missing metrics remain missing; final MIP bounds are never root LPs.
    end
end

function run_method(x,method,factory,budget,mode)
    if method=="rdp"
        if mode=="publication_offsets"
            start=time_ns(); b=source_rdp_model(x,factory,budget)
            set_time_limit_sec(b.model,max(0.001,budget-(time_ns()-start)/1e9))
            optstart=time_ns(); optimize!(b.model); opt=(time_ns()-optstart)/1e9
            has_values(b.model) || error("no feasible source RDP solution")
            testing=Dict{SequentialOilKey,Bool}((i,h)=>
                DecisionProgrammingAlgorithms.oil_binary_action(b.ztest[i][(h .+ 1)...,:])==1
                for (i,h) in sequential_policy_rows(x))
            drill=Dict{Tuple,Bool}(h=>DecisionProgrammingAlgorithms.oil_binary_action(b.z[(h .+ 1)...,:])==1
                for h in Iterators.product(ntuple(_ -> 0:3,ntests(x))...))
            policy=SequentialOilPolicy(testing,drill)
            return (value=objective_value(b.model)-b.shift,shift=b.shift,policy=policy,
                policy_value=evaluate_policy(x,policy),status=termination_status(b.model),
                elapsed=(time_ns()-start)/1e9,preprocessing_time=b.preprocessing_time,
                build_time=b.build_time,solve_time=opt,solver_time=solve_time(b.model),
                variables=num_variables(b.model),constraints=num_constraints(b.model;count_variable_in_set_constraints=false))
        end
        return solve_sequential_rdp(x;dense=true,optimizer=factory,time_limit=budget,
            max_segments=Int(2*big(8)^ntests(x)))
    elseif method=="rjt" && mode=="corrected_same_input"
        return solve_sequential_rjt(x;optimizer=factory,time_limit=budget,max_tests=8,max_policy_rows=100_000)
    elseif method in ("rjt","dp_milp")
        start=time_ns(); b=package_model(x,method,factory;publication_offsets=mode=="publication_offsets")
        set_time_limit_sec(b.model,max(0.001,budget-(time_ns()-start)/1e9))
        optstart=time_ns(); optimize!(b.model); opt=(time_ns()-optstart)/1e9
        has_values(b.model) || error("no feasible package solution: $(termination_status(b.model))")
        policy=decode_package(x,b.z); physical=evaluate_policy(x,policy)
        return (value=objective_value(b.model)-b.shift,shift=b.shift,policy=policy,policy_value=physical,
            status=termination_status(b.model),elapsed=(time_ns()-start)/1e9,
            preprocessing_time=0.,build_time=b.build_time,solve_time=opt,solver_time=solve_time(b.model),
            variables=num_variables(b.model),constraints=num_constraints(b.model;count_variable_in_set_constraints=false))
    elseif method in ("irbb_fi","irbb_legacy")
        return solve_sequential_probing(x;bound=method=="irbb_fi" ? :full_information : :legacy_nonsequential,
            max_rows=Int(sum(big(4)^(i-1) for i in 1:ntests(x))))
    end
    error("unknown method $method")
end

function worker(campaign,id,method,attempt)
    config=verify_campaign(campaign); x,source=frozen_record(config["catalog"],id)
    statefile=joinpath(attempt,"state.toml"); resultfile=joinpath(attempt,"result.toml")
    record=Dict{String,Any}("id"=>id,"M"=>ntests(x),"seed_id"=>source["seed_id"],
        "archived_seed"=>source["archived_seed"],"method"=>method,"solver"=>config["solver"],
        "label"=>config["label"],"numerical_mode"=>config["numerical_mode"],
        "instance_sha256"=>instance_hash(x),"protocol_sha256"=>sha(joinpath(campaign,"protocol.toml")),
        "status"=>"OTHER_ERROR","feasible_found"=>false,"optimal_certified"=>false,
        "original_utility_offset"=>source["original_utility_offset"],"within_pinned_loop"=>source["within_pinned_loop"],
        "root_node_after_cuts_available"=>false)
    record["shift"]=if method=="rjt"
        config["numerical_mode"]=="publication_offsets" ? Float64(source["original_utility_offset"]) : 0.
    elseif method in ("rdp","dp_milp")
        config["numerical_mode"]=="publication_offsets" ? Float64(source["original_utility_offset"]) :
            Float64(1-min(0,minimum(x.payoff))+sum(x.costs))
    else
        0.
    end
    captured=Ref{Any}(nothing)
    base=solver_factory(config["solver"])
    factory=() -> begin
        optimizer=MOI.instantiate(base)
        captured[]=optimizer
        optimizer
    end
    # One discarded M=1 solve per process. It does not consume the instance RNG.
    # Data differ from the source's first M=1, but parameter types/shapes agree.
    warm,_=frozen_record(config["catalog"],"j$(lpad(source["seed_id"],2,'0'))_m1")
    atomic_toml(statefile,Dict("phase"=>"warmup","wall_start"=>time()))
    warmstart=time_ns()
    run_method(warm,method,factory,min(60.,config["budget_seconds"]),config["numerical_mode"])
    atomic_toml(joinpath(attempt,"warmup.toml"),Dict("elapsed"=>(time_ns()-warmstart)/1e9,
        "instance_sha256"=>instance_hash(warm),"included_in_measured_total"=>false))
    captured[]=nothing
    atomic_toml(statefile,Dict("phase"=>"model_and_solve","wall_start"=>time()))
    wallstart=time_ns()
    try
        r=run_method(x,method,factory,config["budget_seconds"],config["numerical_mode"])
        record["total_runtime"]=(time_ns()-wallstart)/1e9
        record["method_elapsed"]=r.elapsed
        record["status"]=r isa SearchResult ? "OPTIMAL" : string(r.status)
        record["policy_physical_exact"]=string(evaluate_policy(x,r.policy))
        record["policy_physical_objective"]=Float64(evaluate_policy(x,r.policy))
        record["feasible_found"]=true
        save_policy(joinpath(attempt,"policy.toml"),r.policy)
        saved=load_policy(joinpath(attempt,"policy.toml"))
        evaluate_policy(x,saved)==(r isa SearchResult ? r.value : r.policy_value) || error("policy round-trip mismatch")
        record["policy_sha256"]=sha(joinpath(attempt,"policy.toml"))
        if r isa SearchResult
            record["primal_status"]="FEASIBLE_POINT"; record["best_feasible_objective"]=Float64(r.value)
            record["best_bound"]=Float64(r.value); record["final_mip_gap"]=0.
            for key in (:visited,:expanded,:pruned,:evaluations,:cache_hits,:bound_policy_evaluations,:bound_time,:evaluation_time)
                record[string(key)]=getproperty(r.stats,key)
            end
            record["exact_optimality_certificate"]=true
            record["nominal_physical_agreement"]=true
        else
            for key in (:preprocessing_time,:build_time,:solve_time,:solver_time,:variables,:constraints,:shift)
                record[string(key)]=getproperty(r,key)
            end
            record["best_feasible_objective"]=r.value
            record["publication_scope_total"]=r.preprocessing_time+r.build_time+r.solve_time
            record["nominal_physical_agreement"]=isapprox(r.value,record["policy_physical_objective"];atol=1e-7,rtol=1e-9)
            record["shifted_objective"]=r.value+r.shift
        end
        record["publication_utility_of_policy"]=record["policy_physical_objective"]+source["original_utility_offset"]
        if ntests(x)<=3
            ref=solve_sequential_dp(x)
            record["exact_reference_value"]=string(ref.value)
            record["exact_reference_agreement"]=record["policy_physical_exact"]==string(ref.value)
        end
        record["optimal_certified"]=record["status"]=="OPTIMAL" && record["nominal_physical_agreement"] &&
            get(record,"exact_reference_agreement",true)
    catch err
        record["total_runtime"]=(time_ns()-wallstart)/1e9
        record["error"]=sprint(showerror,err)
    end
    raw=captured[]
    if raw!==nothing
        optional_metric!(record,"native_status",() -> string(MOI.get(raw,MOI.TerminationStatus())))
        optional_metric!(record,"primal_status",() -> string(MOI.get(raw,MOI.PrimalStatus())))
        optional_metric!(record,"native_objective_shifted",() -> MOI.get(raw,MOI.ObjectiveValue()))
        optional_metric!(record,"native_bound_shifted",() -> MOI.get(raw,MOI.ObjectiveBound()))
        optional_metric!(record,"final_mip_gap",() -> MOI.get(raw,MOI.RelativeGap()))
        optional_metric!(record,"native_solver_time",() -> MOI.get(raw,MOI.SolveTimeSec()))
        optional_metric!(record,"solver_version",() -> MOI.get(raw,MOI.SolverVersion()))
        optional_metric!(record,"milp_nodes",() -> MOI.get(raw,MOI.NodeCount()))
        optional_metric!(record,"native_variable_count",() -> MOI.get(raw,MOI.NumberOfVariables()))
        if haskey(record,"shift") && haskey(record,"native_bound_shifted")
            record["best_bound"]=record["native_bound_shifted"]-record["shift"]
        end
        if !record["feasible_found"]
            native=get(record,"native_status","OTHER_ERROR")
            record["status"]=native=="TIME_LIMIT" ? "TIME_LIMIT" :
                native=="OPTIMIZE_NOT_CALLED" ? "BUILD_FAILURE" :
                occursin("MEMORY",native) ? "MEMORY_LIMIT" : "OTHER_ERROR"
        end
    end
    if !haskey(record,"preprocessing_time") && !(method in ("irbb_fi","irbb_legacy"))
        record["preparation_timing_missing_reason"]="existing solver returned no result; partial phase timings are unavailable, not estimated from final bounds"
    end
    atomic_toml(joinpath(attempt,"mip-result.toml"),record)
    if raw!==nothing && record["feasible_found"]
        atomic_toml(statefile,Dict("phase"=>"root_lp","wall_start"=>time()))
        try
            merge!(record,root_lp(raw,base,record["shift"];budget=config["root_lp_budget_seconds"]))
        catch err
            record["root_lp_error"]=sprint(showerror,err)
        end
    end
    atomic_toml(resultfile,record)
    atomic_toml(statefile,Dict("phase"=>"complete","wall_start"=>time()))
end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==4 || error("worker CAMPAIGN INSTANCE_ID METHOD NEW_ATTEMPT_DIRECTORY")
    worker(abspath(ARGS[1]),ARGS[2],ARGS[3],abspath(ARGS[4]))
end
