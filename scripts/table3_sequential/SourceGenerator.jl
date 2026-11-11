module Table3SourceGenerator
using Random, SHA, TOML
const ROOT=normpath(joinpath(@__DIR__,"..",".."))
const COMMIT="c8af1afc111f7f2c7ec81105225fa3854d5edf9a"
const REF=joinpath(ROOT,"external","Decision-Programming-new-formulation-sequential")
const FILES=("oil_new_seq_Gurobi.jl","oil_rjt_seq_Gurobi.jl","oil_dp_seq_Gurobi.jl")
const SOURCE=joinpath(REF,"Final codes")

function verify_source()
    readchomp(`git -C $REF rev-parse HEAD`)==COMMIT || error("incorrect source pin")
    isempty(readchomp(`git -C $REF status --porcelain`)) || error("modified external source")
end

function assigns(e,name)
    e isa Expr || return false
    if e.head==:(=)
        lhs=e.args[1]
        (lhs==name || (lhs isa Expr && lhs.head==:ref && lhs.args[1]==name)) && return true
    end
    any(a -> assigns(a,name),e.args)
end

"""Extract the original operations, never the solver or top-level file writes."""
function generator_body(file)
    tree=Meta.parseall(read(file,String))
    loop=only(e for e in tree.args if e isa Expr && e.head==:for)
    loop.args[1]==:(No_tests = [1, [i for i = 1:No]...]) ||
        error("source experiment-loop expression changed")
    statements=filter(e -> !(e isa LineNumberNode),loop.args[2].args)
    first=findfirst(e -> e isa Expr && e.head==:(=) && e.args[1]==:O,statements)
    last=findlast(e -> assigns(e,:U),statements)
    first!==nothing && last!==nothing && first<last || error("generator boundaries not found")
    body=Base.remove_linenums!(Expr(:block,deepcopy(statements[first:last])...))
    body
end

function source_functions()
    verify_source()
    bodies=[generator_body(joinpath(SOURCE,file)) for file in FILES]
    all(==(first(bodies)),bodies) || error("the three source generators disagree")
    body=first(bodies)
    f=Core.eval(@__MODULE__,:(function (No_tests)
        No_states=3
        $body
        (O=O,S=S,T=T,V=V,U=U)
    end))
    (function_object=f,expression_sha256=bytes2hex(sha256(string(body))),
        source_hashes=Dict(file=>bytes2hex(sha256(read(joinpath(SOURCE,file)))) for file in FILES))
end

function archived_seeds()
    verify_source()
    [begin
        file=joinpath(SOURCE,"Data","oil_seed_gurobi_$(j).csv")
        (id=j,seed=parse(Int,strip(read(file,String))),file=relpath(file,REF),
            sha256=bytes2hex(sha256(read(file))))
    end for j in 1:50]
end

function array_hash(data)
    io=IOBuffer()
    for name in (:O,:S,:T,:V,:U)
        a=getproperty(data,name)
        write(io,string(name),'\0',string(size(a)),'\0')
        for v in a; write(io,reinterpret(UInt64,Float64(v))); end
    end
    bytes2hex(sha256(take!(io)))
end

function raw_payload(d,meta)
    merge(Dict{String,Any}("O"=>d.O,"S"=>[collect(d.S[o,:]) for o in 1:3],
        "T"=>[[[collect(d.T[i,a,s,:]) for s in 1:3] for a in 1:2] for i in axes(d.T,1)],
        "V"=>[collect(d.V[a,:]) for a in 1:2],"U"=>[collect(d.U[o,:]) for o in 1:3],
        "array_sha256"=>array_hash(d)),meta)
end

function read_raw(path)
    d=TOML.parsefile(path); m=d["M"]
    s=reduce(vcat,permutedims.(d["S"]))
    t=zeros(m,2,3,4)
    for i in 1:m,a in 1:2,k in 1:3; t[i,a,k,:]=d["T"][i][a][k]; end
    v=reduce(vcat,permutedims.(d["V"])); u=reduce(vcat,permutedims.(d["U"]))
    data=(O=d["O"],S=s,T=t,V=v,U=u)
    array_hash(data)==d["array_sha256"] || error("raw-array checksum mismatch: $path")
    data,d
end

"""Replay one shared default-RNG stream per archived seed, including warm-up M=1.
M=8 extends the pinned scripts' literal No=7 loop and is labeled accordingly.
"""
function replay_seed(seed; max_m=8, retain_warmup=true)
    sf=source_functions(); result=Any[]
    task=Task() do
        Random.seed!(seed)
        for (iteration,m) in enumerate([1;collect(1:max_m)])
            d=Base.invokelatest(sf.function_object,m)
            (retain_warmup || iteration>1) && push!(result,(iteration=iteration,M=m,data=d))
        end
    end
    schedule(task); fetch(task)
    result
end

function emit(dest; max_m=8)
    ispath(dest) && error("output exists; no overwrite: $dest")
    sf=source_functions(); seeds=archived_seeds()
    mkpath(dest); mkpath(joinpath(dest,"raw"))
    records=Dict{String,Any}[]
    for seed in seeds
        # No optimization or diagram construction intervenes between draws.
        for item in replay_seed(seed.seed;max_m)
            warmup=item.iteration==1
            id=warmup ? "j$(lpad(seed.id,2,'0'))_warmup_m1" : "j$(lpad(seed.id,2,'0'))_m$(item.M)"
            meta=Dict{String,Any}("id"=>id,"seed_id"=>seed.id,"archived_seed"=>seed.seed,
                "seed_file"=>seed.file,"seed_file_sha256"=>seed.sha256,"M"=>item.M,
                "iteration"=>item.iteration,"warmup"=>warmup,"source_commit"=>COMMIT,
                "source_loop_max_M"=>7,"within_pinned_loop"=>item.M<=7,
                "generation_julia"=>string(VERSION),"rng"=>string(typeof(Random.default_rng())),
                "generator_expression_sha256"=>sf.expression_sha256,
                "generator_implementation_sha256"=>bytes2hex(sha256(read(@__FILE__))))
            payload=raw_payload(item.data,meta)
            file=joinpath("raw",id*".toml")
            open(io -> TOML.print(io,payload;sorted=true),joinpath(dest,file),"w")
            push!(records,merge(meta,Dict("file"=>file,"array_sha256"=>payload["array_sha256"],
                "file_sha256"=>bytes2hex(sha256(read(joinpath(dest,file)))))))
        end
    end
    manifest=Dict("format"=>"table3-source-replay-v1","julia"=>string(VERSION),
        "source_commit"=>COMMIT,"source_hashes"=>sf.source_hashes,"records"=>records,
        "note"=>"M=1 is the second iteration; M=8 is an explicit extension of literal No=7. No historical raw-array archive is supplied.")
    open(io -> TOML.print(io,manifest;sorted=true),joinpath(dest,"manifest.toml"),"w")
    println("Generated ",length(records)," source-replayed arrays under Julia ",VERSION," at ",dest)
end
end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==1 || error("usage: julia SourceGenerator.jl NEW_OUTPUT_DIRECTORY")
    Table3SourceGenerator.emit(abspath(only(ARGS)))
end
