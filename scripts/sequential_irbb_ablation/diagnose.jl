using DecisionProgrammingAlgorithms, TOML

const ROOT=normpath(joinpath(@__DIR__,"..",".."))
const VARIANTS=(:baseline,:reachability,:cost_aware,:combined)
const BOUNDS=(:full_information,:legacy_nonsequential)

function atomic_toml(path,value)
    mkpath(dirname(path)); temporary=path*".$(getpid()).tmp"
    open(io->TOML.print(io,value;sorted=true),temporary,"w")
    mv(temporary,path;force=true)
end

function diagnose(destination,seconds)
    seconds>0 || error("positive diagnostic time limit required")
    for id in ("j03_m4","j01_m5")
        x=load_oil(joinpath(ROOT,"experiments","table3_sequential","frozen_julia1103","instances",id*".toml"))
        reference=solve_sequential_dp(x)
        for variant in VARIANTS, bound in BOUNDS
            file=joinpath(destination,"$(id)__$(variant)__$(bound).toml")
            isfile(file) && continue
            GC.gc(); timed=@timed solve_sequential_probing(x;variant,bound,
                max_rows=typemax(Int),time_limit=seconds,progress_every=10_000)
            result=timed.value
            row=Dict{String,Any}("instance_id"=>id,"instance_hash"=>instance_hash(x),
                "seed"=>x.metadata["seed"],"variant"=>string(variant),"bound"=>string(bound),
                "diagnostic_time_limit"=>seconds,"status"=>string(result.status),
                "elapsed"=>timed.time,"allocated_bytes"=>timed.bytes,"gc_seconds"=>timed.gctime,
                "value_exact"=>string(result.value),"lower_bound_exact"=>string(result.lower_bound),
                "upper_bound_exact"=>string(result.upper_bound),
                "reference_exact"=>string(reference.value),"reference_agreement"=>result.value==reference.value)
            for name in fieldnames(SearchStats)
                value=getfield(result.stats,name)
                value===nothing || (row[string(name)]=value isa Rational ? string(value) : value)
            end
            atomic_toml(file,row); println(basename(file)," ",row["status"]," nodes=",result.stats.visited)
        end
    end
end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==2 || error("diagnose.jl OUTPUT_DIRECTORY SECONDS")
    diagnose(abspath(ARGS[1]),parse(Float64,ARGS[2]))
end
