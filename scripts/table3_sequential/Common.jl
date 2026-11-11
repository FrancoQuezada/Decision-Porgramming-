module Table3Common
using DecisionProgrammingAlgorithms, JuMP, HiGHS, TOML, SHA, Dates, DelimitedFiles
using Base.Iterators: product
import DecisionProgramming as DP
import MathOptInterface as MOI
if Base.find_package("Gurobi")!==nothing
    try
        import Gurobi
    catch
        # Preflight reports unavailable optional installations without a fallback.
    end
end
include("SourceGenerator.jl")
using .Table3SourceGenerator
const ROOT=Table3SourceGenerator.ROOT
const METHODS=("rdp","rjt","dp_milp","irbb_fi","irbb_legacy")
const IMPLEMENTATION_FILES=[relpath(joinpath(dir,file),ROOT)
    for (dir,_,files) in walkdir(joinpath(ROOT,"src")) for file in files if endswith(file,".jl")]
const PIPELINE_FILES=["scripts/table3_sequential/"*file for file in
    ("Common.jl","SourceGenerator.jl","SourceModels.jl","worker.jl","campaign.jl","report.jl","validate.jl","PublishedTable3.csv")]
sha(path)=bytes2hex(sha256(read(path)))
function available_memory()
    if isfile("/proc/meminfo")
        match=Base.match(r"MemAvailable:\s+(\d+)",read("/proc/meminfo",String))
        match!==nothing && return parse(Int,match[1])*1024
    end
    Sys.free_memory()
end

function atomic_toml(path,data)
    mkpath(dirname(path)); temp=path*".tmp.$(getpid())"
    open(io -> TOML.print(io,data;sorted=true),temp,"w")
    mv(temp,path;force=true); path
end

function freeze(historical,native,dest)
    ispath(dest) && error("frozen destination already exists; no overwrite")
    h=TOML.parsefile(joinpath(historical,"manifest.toml"))
    n=TOML.parsefile(joinpath(native,"manifest.toml"))
    h["julia"]=="1.10.3" || error("historical-compatible mode must use Julia 1.10.3")
    nmap=Dict(r["id"]=>r for r in n["records"])
    length(h["records"])==450==length(nmap) || error("incomplete 50-seed, M=1..8 replay")
    equal=0; records=Dict{String,Any}[]
    mkpath(joinpath(dest,"instances")); mkpath(joinpath(dest,"raw"))
    for r in h["records"]
        equal += r["array_sha256"]==nmap[r["id"]]["array_sha256"]
        rawfile=joinpath(historical,r["file"])
        sha(rawfile)==r["file_sha256"] || error("modified replay file")
        raw,meta=Table3SourceGenerator.read_raw(rawfile)
        r["warmup"] && continue
        m=r["M"]; id=r["id"]
        all(raw.U[:,2].==100) && all(raw.V[2,:].==50*m) || error("unexpected utility baseline")
        offset=100+50*m*m
        metadata=Dict{String,Any}("generator"=>"pinned-source-shared-stream-v1",
            "generation_mode"=>"julia-1.10.3-source-replay","seed"=>r["archived_seed"],
            "seed_id"=>r["seed_id"],"source_commit"=>r["source_commit"],
            "generator_implementation_sha256"=>r["generator_implementation_sha256"],
            "generator_expression_sha256"=>r["generator_expression_sha256"],
            "raw_array_sha256"=>r["array_sha256"],"source_iteration"=>r["iteration"],
            "within_pinned_loop"=>r["within_pinned_loop"],"original_utility_offset"=>offset)
        x=OilInstance(raw.O,raw.S,raw.T[:,1,:,2:4],raw.U[:,1]-raw.U[:,2],raw.V[2,:]-raw.V[1,:];metadata)
        file=joinpath("instances",id*".toml"); save_oil(joinpath(dest,file),x)
        instance_hash(load_oil(joinpath(dest,file)))==instance_hash(x) || error("snapshot round-trip")
        copied=joinpath("raw",id*".toml"); cp(rawfile,joinpath(dest,copied))
        normalization=max(maximum(abs.(Float64.(x.prior)-raw.O)),
            maximum(abs.(Float64.(x.geology)-raw.S)),maximum(abs.(Float64.(x.reports)-raw.T[:,1,:,2:4])))
        push!(records,Dict{String,Any}("id"=>id,"M"=>m,"seed_id"=>r["seed_id"],
            "archived_seed"=>r["archived_seed"],"instance_file"=>file,"raw_file"=>copied,
            "instance_sha256"=>instance_hash(x),"file_sha256"=>sha(joinpath(dest,file)),
            "raw_file_sha256"=>sha(joinpath(dest,copied)),"raw_array_sha256"=>r["array_sha256"],
            "original_utility_offset"=>offset,"within_pinned_loop"=>r["within_pinned_loop"],
            "max_float64_normalization_delta"=>normalization))
    end
    length(records)==400 || error("expected 400 instances")
    audit=Dict{String,Any}("historical_julia"=>h["julia"],"native_julia"=>n["julia"],
        "equal_raw_array_sets"=>equal,"compared_raw_array_sets"=>450,
        "all_bits_equal"=>equal==450,"retained_instances"=>400,"discarded_warmups"=>50,
        "source_scripts_max_M"=>7,"M8_status"=>"explicit continuation of the source stream beyond literal No=7",
        "historical_identity_limit"=>"No historical raw-array archive supplied; agreement is against source replay in Julia 1.10.3.",
        "canonical_input_semantics"=>"OilInstance converts and exactly normalizes supplied Float64 probability rows. Original Float64 arrays retained separately.",
        "historical_manifest_sha256"=>sha(joinpath(historical,"manifest.toml")),
        "native_manifest_sha256"=>sha(joinpath(native,"manifest.toml")))
    atomic_toml(joinpath(dest,"generation_audit.toml"),audit)
    manifest=Dict("format"=>"table3-frozen-v1","source_commit"=>h["source_commit"],
        "records"=>records,"source_hashes"=>h["source_hashes"],"audit"=>audit)
    atomic_toml(joinpath(dest,"manifest.toml"),manifest)
    write_records(joinpath(dest,"instances.csv"),records)
    println("Frozen 400 exact snapshots; bitwise raw agreement: ",equal,"/450")
    dest
end

function frozen_record(catalog,id)
    manifest=TOML.parsefile(joinpath(catalog,"manifest.toml"))
    r=only(r for r in manifest["records"] if r["id"]==id)
    file=joinpath(catalog,r["instance_file"])
    sha(file)==r["file_sha256"] || error("modified frozen snapshot")
    sha(joinpath(catalog,r["raw_file"]))==r["raw_file_sha256"] || error("modified raw snapshot")
    x=load_oil(file)
    instance_hash(x)==r["instance_sha256"] || error("modified canonical instance")
    x,r
end

rdp_size(m)=(variables=2*big(8)^m+2*big(4)^m+2*sum(big(4)^(i-1) for i in 1:m),
    constraints=4*big(4)^m+3*sum(big(4)^(i-1) for i in 1:m))

function source_hashes()
    Dict(file=>sha(joinpath(ROOT,file)) for file in vcat(IMPLEMENTATION_FILES,PIPELINE_FILES,
        ["Project.toml","Manifest.toml","external.lock.toml"]))
end

function published_reference()
    data,header=readdlm(joinpath(@__DIR__,"PublishedTable3.csv"),',',String,'\n';header=true)
    names=vec(header); rows=Dict{String,Any}[]
    for i in axes(data,1)
        r=Dict{String,Any}(names[j]=>data[i,j] for j in eachindex(names))
        for key in ("M","published_optimal","published_feasible"); r[key]=parse(Int,r[key]); end
        for (original,numeric) in (("published_total_text","published_mean_total"),("published_solver_text","published_mean_solver"),
                ("published_RR_text","published_RR_percent"))
            v=tryparse(Float64,r[original]); v!==nothing && (r[numeric]=v)
        end
        for key in ("constraints","variables")
            text=r["published_"*key*"_text"]
            all(isdigit,text) && (r["published_"*key]=parse(Int,text))
        end
        r["reference_source"]="Supplementary_material_rev3.pdf, Table 3, page 3; visually checked"
        push!(rows,r)
    end
    rows
end

function prepare(catalog,dest; solver="gurobi",budget=3600.,memory_gib=14., numerical_mode="corrected_same_input")
    ispath(dest) && error("campaign already exists; use resume")
    solver in ("gurobi","highs") || error("unknown solver")
    numerical_mode in ("corrected_same_input","publication_offsets") || error("unknown numerical mode")
    budget>0 && memory_gib>0 || error("positive resource limits required")
    manifest=TOML.parsefile(joinpath(catalog,"manifest.toml"))
    length(manifest["records"])==400 || error("freeze all cohorts first")
    mkpath(dest); mkpath(joinpath(dest,"jobs"))
    config=Dict{String,Any}("format"=>"table3-campaign-v1","catalog"=>abspath(catalog),
        "catalog_manifest_sha256"=>sha(joinpath(catalog,"manifest.toml")),"solver"=>solver,
        "label"=>solver=="gurobi" ? "Gurobi default parameters; environment differs from publication" : "HiGHS mathematical sanity comparison, not Gurobi timing reproduction",
        "numerical_mode"=>numerical_mode,"budget_seconds"=>Float64(budget),
        "available_memory_bytes_at_preparation"=>available_memory(),
        "memory_limit_gib"=>Float64(memory_gib),"startup_limit_seconds"=>120.,
        "root_lp_budget_seconds"=>60.,"source_hashes"=>source_hashes(),
        "root_relaxation_kind"=>"separately solved pure LP relaxation, not post-cut root-node bound",
        "RR_percentage_normalization"=>"UNVERIFIED: supplement needed; RR% stays missing",
        "created_utc"=>string(now(UTC)),"environment"=>environment_record(),
        "publication_environment"=>Dict("julia"=>"1.10.3","JuMP"=>"1.23.0",
            "DecisionProgramming"=>"2.0.1","Gurobi"=>"11.0.2","cpu"=>"Intel E5-2680 2.5GHz","ram_gb"=>16))
    atomic_toml(joinpath(dest,"protocol.toml"),config)
    reference=published_reference()
    write_records(joinpath(dest,"published_reference.csv"),reference)
    atomic_toml(joinpath(dest,"published_reference.toml"),Dict("rows"=>reference))
    atomic_toml(joinpath(dest,"reference_provenance.toml"),Dict("sha256"=>sha(joinpath(dest,"published_reference.csv")),
        "toml_sha256"=>sha(joinpath(dest,"published_reference.toml")),
        "complete_table_transcription"=>true,"source_pdf"=>"Docs/Supplementary_material_rev3.pdf",
        "source_pdf_sha256"=>"c1e5139e6f4bb87c0a8d538b167c2da6b99a34a37cdd19c1e4445b569578b6fc",
        "page"=>3,"RR_normalization_verified"=>false,
        "note"=>"Printed rounded sizes, T/N/A and the DP M=5 0/0 with positive times are preserved literally; no correction inferred."))
    println("Prepared resumable ",solver," campaign at ",dest)
end

function verify_campaign(dest)
    config=TOML.parsefile(joinpath(dest,"protocol.toml"))
    sha(joinpath(config["catalog"],"manifest.toml"))==config["catalog_manifest_sha256"] || error("catalog manifest changed")
    for (file,hash) in config["source_hashes"]
        sha(joinpath(ROOT,file))==hash || error("source changed since preparation: $file; start a new campaign")
    end
    provenance=TOML.parsefile(joinpath(dest,"reference_provenance.toml"))
    sha(joinpath(dest,"published_reference.csv"))==provenance["sha256"] || error("published reference changed")
    sha(joinpath(dest,"published_reference.toml"))==provenance["toml_sha256"] || error("published reference changed")
    config
end

function solver_factory(name)
    if name=="highs"
        return optimizer_with_attributes(HiGHS.Optimizer,"threads"=>1,"mip_rel_gap"=>0.,"mip_abs_gap"=>1e-9)
    end
    # Gurobi is optional, via an installed stacked/isolated environment.
    isdefined(@__MODULE__,:Gurobi) || error("Gurobi.jl is unavailable in the active/stacked environment")
    getfield(@__MODULE__,:Gurobi).Optimizer # no modified research parameters
end

function preflight(name)
    record=Dict{String,Any}("solver"=>name,"available"=>false,"environment"=>environment_record(),
        "julia"=>string(VERSION),"JuMP"=>string(pkgversion(JuMP)),
        "available_memory_bytes"=>available_memory(),"load_path"=>copy(LOAD_PATH),
        "DecisionProgramming"=>string(pkgversion(DP)),"MathOptInterface"=>string(pkgversion(MOI)))
    try
        factory=solver_factory(name)
        if name=="gurobi"
            record["Gurobi_jl"]=string(pkgversion(getfield(@__MODULE__,:Gurobi)))
            record["available_Gurobi_runtime"]=string(getfield(@__MODULE__,:Gurobi)._GUROBI_VERSION)
        end
        model=Model(factory); set_silent(model)
        @variable(model,0<=v<=1); @objective(model,Max,v); optimize!(model)
        record["solver_version"]=MOI.get(backend(model),MOI.SolverVersion())
        record["status"]=string(termination_status(model))
        record["available"]=termination_status(model)==MOI.OPTIMAL
        if name=="gurobi"
            record["Gurobi_jl"]=string(pkgversion(getfield(@__MODULE__,:Gurobi)))
            record["Threads"]=get_optimizer_attribute(model,"Threads")
            record["MIPGap"]=get_optimizer_attribute(model,"MIPGap")
        end
    catch err
        record["error"]=sprint(showerror,err)
    end
    record
end

function save_policy(path,p::SequentialOilPolicy)
    atomic_toml(path,Dict("format"=>"oil-sequential-policy-v1",
        "testing"=>[Dict("stage"=>i,"history"=>collect(h),"action"=>a) for ((i,h),a) in sort!(collect(p.testing))],
        "drill"=>[Dict("history"=>collect(h),"action"=>a) for (h,a) in sort!(collect(p.drill))]))
end
function load_policy(path)
    d=TOML.parsefile(path)
    SequentialOilPolicy(Dict{SequentialOilKey,Bool}((r["stage"],Tuple(r["history"]))=>r["action"] for r in d["testing"]),
        Dict{Tuple,Bool}(Tuple(r["history"])=>r["action"] for r in d["drill"]))
end

function package_model(x,method,optimizer; publication_offsets=false)
    start=time_ns(); diagram=oil_diagram(x;sequential=true)
    if publication_offsets
        m=ntests(x)
        for i in 1:m
            diagram.Y["C$i"].data[:]=Float32[-Float64(x.costs[i])+50*m,50*m]
        end
        diagram.Y["P"].data[:,1]=Float32.(x.payoff).+100
        diagram.Y["P"].data[:,2].=100
        DP.generate_diagram!(diagram) # original positive utilities, no extra translation
    end
    model=Model(optimizer); set_silent(model)
    z=DP.DecisionVariables(model,diagram;names=false)
    variables=method=="rjt" ? DP.RJTVariables(model,diagram,z;names=false) :
        DP.PathCompatibilityVariables(model,diagram,z;names=false,probability_cut=false)
    ev=if method=="rjt" && !publication_offsets
        first(DecisionProgrammingAlgorithms.physical_rjt_expectation(model,diagram,variables,x))
    else
        DP.expected_value(model,diagram,variables)
    end
    @objective(model,Max,ev)
    offset=publication_offsets ? 100+50*ntests(x)^2 : 0
    shift=offset+(method=="dp_milp" ? diagram.translation : 0)
    (model=model,z=z,diagram=diagram,shift=Float64(shift),build_time=(time_ns()-start)/1e9)
end

function decode_package(x,z)
    nr=size(x.reports,3); m=ntests(x)
    testing=Dict{SequentialOilKey,Bool}((i,h)=>DecisionProgrammingAlgorithms.oil_binary_action(z["T$i"].z[(h .+ 1)...,:])==1
        for (i,h) in sequential_policy_rows(x))
    drill=Dict{Tuple,Bool}(h=>DecisionProgrammingAlgorithms.oil_binary_action(z["D"].z[(h .+ 1)...,:])==1
        for h in Iterators.product(ntuple(_ -> 0:nr,m)...))
    SequentialOilPolicy(testing,drill)
end

function root_lp(raw,optimizer,shift; budget=60.)
    start=time_ns()
    # Copy the unpresolved input model, never final MIP cuts/bounds.
    cache=MOI.Utilities.Model{Float64}(); MOI.copy_to(cache,raw)
    for (F,S) in MOI.get(cache,MOI.ListOfConstraintTypesPresent())
        S in (MOI.ZeroOne,MOI.Integer) || continue
        for ci in MOI.get(cache,MOI.ListOfConstraintIndices{F,S}())
            vi=MOI.get(cache,MOI.ConstraintFunction(),ci); MOI.delete(cache,ci)
            if S==MOI.ZeroOne
                # Existing explicit bounds may already be present. Affine rows
                # preserve those bounds without duplicate VariableIndex bounds.
                affine=MOI.ScalarAffineFunction([MOI.ScalarAffineTerm(1.,vi)],0.)
                MOI.add_constraint(cache,affine,MOI.GreaterThan(0.))
                MOI.add_constraint(cache,affine,MOI.LessThan(1.))
            end
        end
    end
    lp=MOI.instantiate(optimizer)
    MOI.set(lp,MOI.Silent(),true); MOI.set(lp,MOI.TimeLimitSec(),budget)
    MOI.copy_to(lp,cache); MOI.optimize!(lp)
    result=Dict{String,Any}("root_lp_status"=>string(MOI.get(lp,MOI.TerminationStatus())),
        "root_lp_time"=>(time_ns()-start)/1e9,"root_lp_kind"=>"pure LP, no MIP cuts")
    if MOI.get(lp,MOI.TerminationStatus())==MOI.OPTIMAL
        result["root_lp_shifted"]=MOI.get(lp,MOI.ObjectiveValue())
        result["root_lp_physical"]=result["root_lp_shifted"]-shift
    end
    result
end

include("SourceModels.jl")

export ROOT, METHODS, sha, atomic_toml, freeze, frozen_record, rdp_size, prepare,
    verify_campaign, solver_factory, preflight, save_policy, load_policy,
    package_model, decode_package, root_lp, source_rdp_model, source_hashes, published_reference
end
