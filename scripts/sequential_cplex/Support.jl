module SequentialCPLEXSupport
using DecisionProgrammingAlgorithms, JuMP, CPLEX, TOML, SHA, LinearAlgebra
import MathOptInterface as MOI
const ROOT=normpath(joinpath(@__DIR__,"..",".."))
const CATALOG=joinpath(ROOT,"experiments","table3_sequential","frozen_julia1103")
const SOLVER_CONFIG=joinpath(ROOT,"experiments","phase4_extended","cplex.toml")

# Reuse the original Phase-4 parameter and atomic-record functions without
# including its top-level worker main() or launching an older campaign.
let tree=Meta.parseall(read(joinpath(ROOT,"scripts","phase4_extended","worker.jl"),String))
    for name in (:configured_optimizer,:atomic_toml,:putfinite!)
        f=only(e for e in tree.args if e isa Expr && e.head==:function &&
            e.args[1] isa Expr && e.args[1].head==:call && e.args[1].args[1]==name)
        Core.eval(@__MODULE__,f)
    end
end

# Existing exact sequential-policy serialization; the runner guard prevents
# execution of that script's separate synthetic benchmark.
include(joinpath(ROOT,"scripts","benchmark_sequential_oil.jl"))

function frozen_input(id;catalog=CATALOG)
    manifest=TOML.parsefile(joinpath(catalog,"manifest.toml"))
    item=only(r for r in manifest["records"] if r["id"]==id)
    path=joinpath(catalog,item["instance_file"])
    bytes2hex(sha256(read(path)))==item["file_sha256"] || error("frozen file checksum changed")
    x=load_oil(path)
    instance_hash(x)==item["instance_sha256"] || error("frozen physical input changed")
    x,item
end

function solve_method(method,x,seconds,config=SOLVER_CONFIG)
    method=="irbb_fi" && return solve_sequential_probing(x;bound=:full_information)
    method=="irbb_legacy" && return solve_sequential_probing(x;bound=:legacy_nonsequential)
    factory,_=configured_optimizer(config,"CPLEX-Default",seconds)
    method=="rdp" && return solve_sequential_rdp(x;optimizer=factory,dense=true,
        time_limit=seconds,total_time_limit=seconds)
    method=="rjt" && return solve_sequential_rjt(x;optimizer=factory,
        time_limit=seconds,total_time_limit=seconds)
    error("unsupported sequential method: $method")
end

function warm_method(method,m,config=SOLVER_CONFIG)
    if startswith(method,"irbb")
        reports=reshape([1,0,0,1],1,2,2)
        witness=OilInstance([1//2,1//2],[1 0;0 1],reports,[-1,1],[1//10])
        solve_method(method,witness,30.,config)
    end
    for k in unique([1,m])
        cheap=OilInstance([1.],ones(1,1),ones(k,1,1),[1.],ones(k))
        solve_method(method,cheap,30.,config)
    end
end

function save_policy(path,policy)
    sequential_benchmark_policy(path*".tmp",policy)
    mv(path*".tmp",path;force=true)
end
load_policy(path)=sequential_benchmark_load_policy(path)

export ROOT,CATALOG,SOLVER_CONFIG,configured_optimizer,atomic_toml,putfinite!,
    frozen_input,solve_method,warm_method,save_policy,load_policy
end
