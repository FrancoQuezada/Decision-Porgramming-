"""Non-probing Markov maintenance chain, with optional noisy passive reports.
Chance kernels depend on actions. Information arcs are specified independently.
"""
function generate_maintenance_chain(stages::Int,seed::Int;information=:remember_action,
        repeated=true,deterministic=false)
    stages>=2 || throw(ArgumentError("at least two decisions required"))
    information in (:remember_action,:open_loop,:observed,:noisy) || throw(ArgumentError("information pattern"))
    rng=Xoshiro(seed)
    nodes=AbstractIDNode[]; utilities=UtilityFactor[]
    decisions=Int[]; states=Int[]; reports=Int[]
    first_probs=[rand(rng,35:75)//100,rand(rng,5:25)//100]
    transition=zeros(Exact,2,2,2)
    for x in 1:2,a in 1:2
        fail=a==2 ? rand(rng,5:25)//100 : (x==1 ? rand(rng,10:35)//100 : rand(rng,65:90)//100)
        transition[x,a,:]=[1-fail,fail]
    end
    for t in 1:stages
        info=Int[]
        if t>1
            information!=:open_loop && push!(info,decisions[end])
            information==:observed && push!(info,states[end])
            information==:noisy && push!(info,reports[end])
        end
        push!(nodes,DecisionNode(Symbol("D$t"),2,info));push!(decisions,length(nodes))
        if t==stages
            push!(utilities,UtilityFactor([states[end],decisions[end]],[30 3;-70 3]))
            break
        end
        cost=repeated ? 8 : rand(rng,4:14)
        push!(utilities,UtilityFactor([decisions[end]],[0,-cost]))
        if t==1
            kernel=Exact[1-first_probs[1] first_probs[1];1-first_probs[2] first_probs[2]]
            deterministic && (kernel=Exact[1 0;0 1])
            parents=[decisions[end]]
        else
            kernel=copy(transition)
            if !repeated
                for x in 1:2,a in 1:2
                    f=rand(rng,1:99)//100;kernel[x,a,:]=[1-f,f]
                end
            end
            if deterministic
                for x in 1:2,a in 1:2;kernel[x,a,:]=a==2 ? [1,0] : (x==1 ? [1,0] : [0,1]);end
            end
            parents=[states[end],decisions[end]]
        end
        push!(nodes,ChanceNode(Symbol("X$t"),2,parents,kernel));push!(states,length(nodes))
        if information==:noisy
            push!(nodes,ChanceNode(Symbol("Y$t"),2,[states[end]],Exact[4//5 1//5;1//5 4//5]))
            push!(reports,length(nodes))
        end
    end
    InfluenceDiagramInstance(nodes,utilities)
end

"""Reveal the last physical state, all past chance states, or no additional data."""
function chain_relaxation(id::InfluenceDiagramInstance;information=:state)
    information in (:none,:state,:all_past) || throw(ArgumentError("relaxation pattern"))
    extra=Dict{Int,Vector{Int}}()
    for (d,node) in enumerate(id.nodes)
        node isa DecisionNode || continue
        past=[j for j in 1:d-1 if id.nodes[j] isa ChanceNode]
        physical=[j for j in past if startswith(string(id.nodes[j].name),"X")]
        information==:none && continue
        extra[d]=information==:all_past ? past : (isempty(physical) ? Int[] : [physical[end]])
    end
    InformationRelaxation(id,extra)
end
export generate_maintenance_chain, chain_relaxation

function diagram_payload(id::InfluenceDiagramInstance)
    nodes=Dict{String,Any}[]
    for node in id.nodes
        row=Dict{String,Any}("name"=>string(node.name),"states"=>node.states)
        if node isa ChanceNode
            merge!(row,Dict("kind"=>"chance","parents"=>node.parents,
                "dimensions"=>collect(size(node.kernel)),"values"=>string.(vec(node.kernel))))
        else
            merge!(row,Dict("kind"=>"decision","information"=>node.information))
        end
        push!(nodes,row)
    end
    utilities=[Dict("scope"=>u.scope,"dimensions"=>collect(size(u.values)),
        "values"=>string.(vec(u.values))) for u in id.utilities]
    Dict("format"=>"finite-id-exact-v1","nodes"=>nodes,"utilities"=>utilities)
end
function diagram_hash(id::InfluenceDiagramInstance)
    io=IOBuffer();TOML.print(io,diagram_payload(id);sorted=true)
    bytes2hex(sha256(take!(io)))
end
function save_diagram(path,id::InfluenceDiagramInstance;metadata=Dict{String,Any}())
    payload=diagram_payload(id);payload["metadata"]=metadata
    mkpath(dirname(path));open(io->TOML.print(io,payload;sorted=true),path,"w")
    path
end
function load_diagram(path)
    d=TOML.parsefile(path)
    d["format"]=="finite-id-exact-v1" || throw(ArgumentError("diagram format"))
    function values(row)
        parseq(s)=let parts=split(s,"//");parse(BigInt,parts[1])//parse(BigInt,parts[2]);end
        Array(reshape(parseq.(row["values"]),Tuple(Int.(row["dimensions"]))))
    end
    nodes=AbstractIDNode[]
    for row in d["nodes"]
        if row["kind"]=="chance"
            push!(nodes,ChanceNode(Symbol(row["name"]),Int(row["states"]),Int.(row["parents"]),values(row)))
        elseif row["kind"]=="decision"
            push!(nodes,DecisionNode(Symbol(row["name"]),Int(row["states"]),Int.(row["information"])))
        else
            throw(ArgumentError("node kind"))
        end
    end
    InfluenceDiagramInstance(nodes,[UtilityFactor(Int.(row["scope"]),values(row)) for row in d["utilities"]])
end
export diagram_hash, save_diagram, load_diagram
