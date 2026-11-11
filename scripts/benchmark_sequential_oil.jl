#= Small common-input baseline only. Run after Pkg.test passes.

julia --project=. scripts/benchmark_sequential_oil.jl [new-output-directory]
No existing run is overwritten. Defaults to M=1,2,3, seeds 7,26, two real reports.
=#
using DecisionProgrammingAlgorithms, TOML, Dates, SHA
import MathOptInterface as MOI

const SEQUENTIAL_METHODS=(
    "nonseq_rdp"=>solve_rdp,
    "nonseq_rjt"=>solve_rjt,
    "nonseq_irbb"=>solve_probing,
    "seq_rdp"=>solve_sequential_rdp,
    "seq_rjt"=>solve_sequential_rjt,
    "seq_irbb_fi"=>(x -> solve_sequential_probing(x;bound=:full_information)),
    "seq_irbb_legacy"=>(x -> solve_sequential_probing(x;bound=:legacy_nonsequential)),
    "seq_dp"=>solve_sequential_dp)

function sequential_benchmark_policy(path,p)
    data=if p isa OilPolicy
        Dict("format"=>"oil-portfolio-policy-v1","tests"=>string(p.tests),
            "drill"=>[Dict("history"=>collect(h),"action"=>a) for (h,a) in sort!(collect(p.drill))])
    else
        Dict("format"=>"oil-sequential-policy-v1",
            "testing"=>[Dict("stage"=>i,"history"=>collect(h),"action"=>a)
                for ((i,h),a) in sort!(collect(p.testing))],
            "drill"=>[Dict("history"=>collect(h),"action"=>a) for (h,a) in sort!(collect(p.drill))])
    end
    open(io -> TOML.print(io,data;sorted=true),path,"w")
end

function sequential_benchmark_load_policy(path)
    data=TOML.parsefile(path)
    drill=Dict{Tuple,Bool}(Tuple(row["history"])=>row["action"] for row in data["drill"])
    if data["format"]=="oil-portfolio-policy-v1"
        return OilPolicy(parse(UInt64,data["tests"]),drill)
    end
    data["format"]=="oil-sequential-policy-v1" || error("unknown saved policy format")
    testing=Dict{SequentialOilKey,Bool}((row["stage"],Tuple(row["history"]))=>row["action"]
        for row in data["testing"])
    SequentialOilPolicy(testing,drill)
end

function benchmark_sequential_oil(dest)
    ispath(dest) && error("output directory already exists: $dest")
    mkpath(joinpath(dest,"instances")); mkpath(joinpath(dest,"policies"))
    env=environment_record()
    env["date_utc"]=string(now(UTC)); env["source_git_head"]=readchomp(`git rev-parse HEAD`)
    env["source_worktree_status"]=readchomp(`git status --porcelain`)
    env["root_manifest_sha256"]=bytes2hex(sha256(read(joinpath(@__DIR__,"..","Manifest.toml"))))
    env["highs_threads"]=1; env["solver_time_limit_seconds"]=60
    for file in ("Project.toml","external.lock.toml")
        env[file*"_sha256"]=bytes2hex(sha256(read(joinpath(@__DIR__,"..",file))))
    end
    env["sizes"]=[1,2,3]; env["seeds"]=[7,26]; env["states"]=2; env["report_states"]=2
    env["generator"]="independent-v1"; env["repetitions"]=1
    env["timing"]="one warm-up per method; total includes coefficient/model preparation, optimization, recovery and exact policy evaluation; MILP time limit 60s applies to optimize!"
    # Include the exact local code, including untracked new implementation files.
    paths=["src","test"]
    hashes=Dict{String,Any}()
    for folder in paths, (dir,_,files) in walkdir(joinpath(@__DIR__,"..",folder)), file in files
        endswith(file,".jl") || continue
        p=joinpath(dir,file); hashes[relpath(p,joinpath(@__DIR__,".."))]=bytes2hex(sha256(read(p)))
    end
    hashes["scripts/benchmark_sequential_oil.jl"]=bytes2hex(sha256(read(@__FILE__)))
    env["source_hashes"]=hashes
    open(io -> TOML.print(io,env;sorted=true),joinpath(dest,"environment.toml"),"w")
    warm=generate_oil(1,7;states=2)
    warmrecords=Dict{String,Any}[]
    for (name,f) in SEQUENTIAL_METHODS
        r=f(warm)
        push!(warmrecords,Dict("method"=>name,"elapsed"=>r.elapsed,"status"=>string(r.status)))
    end
    write_records(joinpath(dest,"warmups.csv"),warmrecords)
    records=Dict{String,Any}[]
    for m in 1:3, seed in (7,26)
        file=save_oil(joinpath(dest,"instances","m$(m)_s$(seed).toml"),generate_oil(m,seed;states=2))
        x=load_oil(file); ref=solve_sequential_dp(x); nonseq=solve_probing(x)
        for (name,f) in SEQUENTIAL_METHODS
            r=f(x)
            target=startswith(name,"nonseq") ? nonseq.value : ref.value
            physical=evaluate_policy(x,r.policy)
            statusok=r isa SearchResult ? r.status==:optimal_exact : r.status==MOI.OPTIMAL
            physical==target && statusok && isapprox(Float64(r.value),Float64(target);atol=1e-7,rtol=1e-9) ||
                error("common-input verification failed: $name M=$m seed=$seed")
            policyfile=joinpath("policies","m$(m)_s$(seed)_$(name).toml")
            sequential_benchmark_policy(joinpath(dest,policyfile),r.policy)
            evaluate_policy(x,sequential_benchmark_load_policy(joinpath(dest,policyfile)))==physical ||
                error("saved policy round-trip mismatch")
            row=Dict{String,Any}("M"=>m,"seed"=>seed,"method"=>name,
                "instance_hash"=>instance_hash(x),"instance_file"=>relpath(file,dest),
                "policy_file"=>policyfile,"policy_sha256"=>bytes2hex(sha256(read(joinpath(dest,policyfile)))),
                "objective"=>Float64(physical),"objective_exact"=>string(physical),
                "status"=>string(r.status),"elapsed"=>r.elapsed,
                "independent_policy_validated"=>true,"exact_reference_agreement"=>true)
            if name=="seq_dp"
                row["dp_histories"]=r.stats.visited
                row["policy_evaluations"]=r.stats.evaluations
                row["evaluation_time"]=r.stats.evaluation_time
            elseif r isa SearchResult
                row["visited"]=r.stats.visited; row["expanded"]=r.stats.expanded
                row["pruned"]=r.stats.pruned; row["policy_evaluations"]=r.stats.evaluations
                row["evaluation_time"]=r.stats.evaluation_time; row["bound_time"]=r.stats.bound_time
                row["cache_hits"]=r.stats.cache_hits
                row["portfolio_oracle_evaluations"]=r.stats.bound_policy_evaluations
                if name=="nonseq_irbb"
                    row["portfolio_oracle_evaluations"]=r.stats.evaluations
                    delete!(row,"policy_evaluations") # evaluations are F(T), not whole policies
                end
            else
                for key in (:preprocessing_time,:build_time,:solve_time,:solver_time,:variables,
                        :constraints,:solver,:solver_version,:nodes)
                    hasproperty(r,key) && (row[string(key)]=getproperty(r,key))
                end
            end
            push!(records,row)
            write_records(joinpath(dest,"comparison.csv"),records)
            println((M=m,seed=seed,method=name,value=Float64(physical),elapsed=r.elapsed))
        end
    end
    println("Saved ",length(records)," independently checked records to ",dest)
end

if abspath(PROGRAM_FILE)==@__FILE__
    dest=isempty(ARGS) ? joinpath(@__DIR__,"..","experiments","results","sequential_baseline",
        Dates.format(now(UTC),"yyyymmddTHHMMSSsss")) : only(ARGS)
    benchmark_sequential_oil(abspath(dest))
end
