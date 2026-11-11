include("Common.jl")
using .Table3Common
using TOML, Dates, DecisionProgrammingAlgorithms

function memory_status(pid)
    file="/proc/$pid/status"
    isfile(file) || return (rss=0,peak=0)
    s=try read(file,String) catch; return (rss=0,peak=0); end
    value(label)=let match=Base.match(Regex(label*":\\s+(\\d+)"),s)
        match===nothing ? 0 : parse(Int,match[1])*1024
    end
    (rss=value("VmRSS"),peak=value("VmHWM"))
end

function completed_attempt(job)
    isdir(job) || return nothing
    files=[joinpath(job,name,"result.toml") for name in sort(readdir(job))
        if isfile(joinpath(job,name,"result.toml"))]
    isempty(files) ? nothing : last(files)
end

function validate_completed(file,config)
    r=TOML.parsefile(file)
    r["protocol_sha256"]==sha(joinpath(dirname(dirname(dirname(dirname(file)))),"protocol.toml")) ||
        error("result/protocol mismatch")
    x,source=frozen_record(config["catalog"],r["id"])
    r["instance_sha256"]==source["instance_sha256"] || error("result/input mismatch")
    if get(r,"feasible_found",false)
        policy=joinpath(dirname(file),"policy.toml")
        sha(policy)==r["policy_sha256"] || error("modified saved policy")
        string(evaluate_policy(x,load_policy(policy)))==r["policy_physical_exact"] || error("saved physical value mismatch")
    end
    r
end

function stop_process(proc)
    process_running(proc) || return
    kill(proc,Base.SIGTERM); start=time()
    while process_running(proc) && time()-start<2.; sleep(0.05); end
    process_running(proc) && kill(proc,Base.SIGKILL)
end

function watchdog_limit(phase,config)
    phase=="model_and_solve" ? config["budget_seconds"] :
        phase=="root_lp" ? config["root_lp_budget_seconds"] : config["startup_limit_seconds"]
end
watchdog_reason(phase,elapsed,rss,config)=rss>config["memory_limit_gib"]*2.0^30 ? "MEMORY_LIMIT" :
    elapsed>watchdog_limit(phase,config) ? "TIME_LIMIT" : ""

function launch_job(campaign,config,source,method)
    id=source["id"]; job=joinpath(campaign,"jobs",id*"_"*method)
    old=completed_attempt(job)
    if old!==nothing
        validate_completed(old,config)
        println("Resume: preserving ",id," ",method)
        return
    end
    mkpath(job)
    attempt=joinpath(job,"attempt_"*lpad(length(readdir(job))+1,4,'0')); mkdir(attempt)
    logpath=joinpath(attempt,"worker.log")
    workerfile=joinpath(@__DIR__,"worker.jl")
    cmd=`$(Base.julia_cmd()) --startup-file=no --project=$ROOT $workerfile $campaign $id $method $attempt`
    record=Dict{String,Any}("id"=>id,"M"=>source["M"],"seed_id"=>source["seed_id"],
        "method"=>method,"solver"=>config["solver"],"instance_sha256"=>source["instance_sha256"],
        "protocol_sha256"=>sha(joinpath(campaign,"protocol.toml")),"feasible_found"=>false,
        "optimal_certified"=>false,"status"=>"OTHER_ERROR")
    beginwall=time(); reason=""; root_failure=false; peak=0
    open(logpath,"w") do log
        proc=run(pipeline(cmd;stdout=log,stderr=log);wait=false)
        while process_running(proc)
            mem=memory_status(getpid(proc)); peak=max(peak,mem.rss,mem.peak)
            statefile=joinpath(attempt,"state.toml")
            state=isfile(statefile) ? TOML.parsefile(statefile) : Dict{String,Any}()
            phase=get(state,"phase","startup")
            elapsed=time()-get(state,"wall_start",beginwall)
            cap=watchdog_limit(phase,config)
            reason=watchdog_reason(phase,elapsed,mem.rss,config)
            if !isempty(reason)
                root_failure=phase=="root_lp"
                record["failure_phase"]=phase
                record["watchdog_limit_seconds"]=cap
                stop_process(proc); break
            end
            sleep(0.1)
        end
        wait(proc)
        record["process_exit_code"]=proc.exitcode
    end
    final=joinpath(attempt,"result.toml")
    if !isfile(final)
        checkpoint=joinpath(attempt,"mip-result.toml")
        if isfile(checkpoint)
            saved=TOML.parsefile(checkpoint)
            merge!(record,saved)
        end
        if root_failure
            record["root_lp_error"]="auxiliary pure-LP watchdog: $reason"
        else
            record["status"]=isempty(reason) ? "BUILD_FAILURE" : reason
            record["optimal_certified"]=false
            record["error"]=isempty(reason) ? "worker exited before final result; inspect log" : "external watchdog: $reason"
            record["native_feasible_solution_unknown"]=!isfile(checkpoint)
        end
        record["worker_wall_runtime"]=time()-beginwall
        atomic_toml(final,record)
    end
    result=TOML.parsefile(final); result["peak_rss_bytes"]=peak
    result["process_exit_code"]=record["process_exit_code"]
    result["worker_wall_runtime"]=time()-beginwall
    atomic_toml(final,result)
    println(id," ",method,": ",result["status"],"; feasible policy=",result["feasible_found"])
end

function execute(campaign;methods=["rdp","rjt"],sizes=[1,2,3],ids=collect(1:50),allow_large=false)
    config=verify_campaign(campaign)
    all(in(METHODS),methods) || error("unknown method")
    all(m -> 1<=m<=8,sizes) && all(i -> 1<=i<=50,ids) || error("invalid cohort")
    any(>(3),sizes) && !allow_large && error("M>3 needs --allow-large and explicit budgets in protocol")
    any(startswith(m,"irbb") for m in methods) && any(>(2),sizes) && !allow_large &&
        error("IRBB M>2 needs --allow-large")
    if any(startswith(m,"irbb") for m in methods)
        # Validate earlier phases on these exact inputs before the extension.
        for m in sizes, id in ids, baseline in ("rdp","rjt")
            job=joinpath(campaign,"jobs","j$(lpad(id,2,'0'))_m$(m)_"*baseline)
            file=completed_attempt(job)
            file!==nothing && get(TOML.parsefile(file),"optimal_certified",false) ||
                error("validate paired RDP/RJT first: M=$m seed_id=$id")
        end
    end
    probe=preflight(config["solver"])
    path=joinpath(campaign,"probes",Dates.format(now(UTC),"yyyymmddTHHMMSSsss")*".toml")
    atomic_toml(path,probe)
    if !probe["available"]
        println("Campaign blocked: ",get(probe,"error","solver unavailable"),". No optimization jobs launched.")
        return false
    end
    manifest=TOML.parsefile(joinpath(config["catalog"],"manifest.toml"))
    for method in methods, m in sizes, id in ids
        source=only(r for r in manifest["records"] if r["M"]==m && r["seed_id"]==id)
        launch_job(campaign,config,source,method)
    end
    true
end

function options(args)
    Dict(split(arg[3:end],"=";limit=2)[1]=>
        (occursin('=',arg) ? split(arg,"=";limit=2)[2] : "true") for arg in args)
end

if abspath(PROGRAM_FILE)==@__FILE__
    isempty(ARGS) && error("commands: freeze HISTORICAL NATIVE NEW_CATALOG | prepare CATALOG NEW_CAMPAIGN [options] | run CAMPAIGN --sizes=1,2,3 [options] | preflight CAMPAIGN")
    command=ARGS[1]
    if command=="freeze"
        length(ARGS)==4 || error("freeze HISTORICAL NATIVE NEW_CATALOG")
        freeze(abspath(ARGS[2]),abspath(ARGS[3]),abspath(ARGS[4]))
    elseif command=="prepare"
        opts=options(ARGS[4:end])
        prepare(abspath(ARGS[2]),abspath(ARGS[3]);solver=get(opts,"solver","gurobi"),
            budget=parse(Float64,get(opts,"budget","3600")),memory_gib=parse(Float64,get(opts,"memory-gib","14")),
            numerical_mode=get(opts,"numerical-mode","corrected_same_input"))
    elseif command=="run"
        opts=options(ARGS[3:end]); haskey(opts,"sizes") || error("supply explicit --sizes")
        execute(abspath(ARGS[2]);methods=split(get(opts,"methods","rdp,rjt"),","),
            sizes=parse.(Int,split(opts["sizes"],",")),ids=parse.(Int,split(get(opts,"ids",join(1:50,",")),",")),
            allow_large=get(opts,"allow-large","false")=="true")
    elseif command=="preflight"
        config=verify_campaign(abspath(ARGS[2])); probe=preflight(config["solver"])
        atomic_toml(joinpath(abspath(ARGS[2]),"probes",Dates.format(now(UTC),"yyyymmddTHHMMSSsss")*".toml"),probe)
        println(probe)
    else
        error("unknown command")
    end
end
