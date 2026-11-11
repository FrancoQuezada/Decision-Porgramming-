using DecisionProgrammingAlgorithms, TOML

function run_diagnostics(destination,seconds)
    0<seconds<=30 || error("diagnostics require a limit in (0,30] seconds")
    root=normpath(joinpath(@__DIR__,"..",".."))
    # Warm both implementations on small inputs before recording allocations.
    warm=generate_oil(2,71;states=2,costs=[0,0])
    for variant in (:combined,:combined_cir), bound in (:full_information,:legacy_nonsequential)
        solve_sequential_probing(warm;variant,bound,max_rows=100,time_limit=seconds)
    end
    mkpath(destination)
    for id in ("j03_m4","j01_m5")
        x=load_oil(joinpath(root,"experiments","table3_sequential","frozen_julia1103",
            "instances",id*".toml"))
        reference=solve_sequential_dp(x)
        for variant in (:combined,:combined_cir), bound in (:full_information,:legacy_nonsequential)
            file=joinpath(destination,"$(id)__$(variant)__$(bound).toml")
            isfile(file) && error("refusing to overwrite $file")
            GC.gc()
            timed=@timed solve_sequential_probing(x;variant,bound,max_rows=typemax(Int),time_limit=seconds)
            result=timed.value
            @assert result.value==evaluate_policy(x,result.policy)
            @assert result.lower_bound<=reference.value<=result.upper_bound
            result.status==:optimal_exact && @assert result.value==reference.value
            row=Dict{String,Any}("instance_id"=>id,"seed"=>x.metadata["seed"],
                "instance_hash"=>instance_hash(x),"variant"=>string(variant),"bound"=>string(bound),
                "julia_version"=>string(VERSION),"time_limit"=>seconds,"status"=>string(result.status),
                "elapsed"=>timed.time,"allocated_bytes"=>timed.bytes,"gc_seconds"=>timed.gctime,
                "objective_exact"=>string(result.value),"reference_exact"=>string(reference.value),
                "reference_agreement"=>result.value==reference.value,
                "lower_bound_exact"=>string(result.lower_bound),"upper_bound_exact"=>string(result.upper_bound))
            for name in fieldnames(SearchStats)
                value=getfield(result.stats,name)
                value===nothing && continue
                name==:cir && continue
                row[string(name)]=value isa Rational ? string(value) : value
            end
            if result.stats.cir!==nothing
                row["cir"]=Dict(string(k)=>getfield(result.stats.cir,k) for k in fieldnames(CIRStats))
            end
            temp=file*".$(getpid()).tmp"
            open(io->TOML.print(io,row;sorted=true),temp,"w"); mv(temp,file;force=false)
            println(id," ",variant," ",bound," ",result.status," nodes=",result.stats.visited,
                " seconds=",round(timed.time;digits=6)," bytes=",timed.bytes)
        end
    end
end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==2 || error("usage: diagnose.jl NEW_OUTPUT_DIRECTORY SECONDS")
    run_diagnostics(abspath(ARGS[1]),parse(Float64,ARGS[2]))
end
