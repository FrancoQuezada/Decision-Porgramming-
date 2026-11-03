struct InformationRelaxation <: AbstractUpperBoundOracle
    original::InfluenceDiagramInstance
    relaxed::InfluenceDiagramInstance
    function InformationRelaxation(original::InfluenceDiagramInstance,relaxed::InfluenceDiagramInstance)
        length(original.nodes)==length(relaxed.nodes) || throw(ArgumentError("relaxation changes nodes"))
        length(original.utilities)==length(relaxed.utilities) || throw(ArgumentError("relaxation changes utility"))
        for (u,v) in zip(original.utilities,relaxed.utilities)
            u.scope==v.scope && u.values==v.values || throw(ArgumentError("relaxation changes utility"))
        end
        for (i,(a,b)) in enumerate(zip(original.nodes,relaxed.nodes))
            typeof(a)==typeof(b) && a.name==b.name && a.states==b.states || throw(ArgumentError("relaxation changes node"))
            if a isa ChanceNode
                a.parents==b.parents && a.kernel==b.kernel || throw(ArgumentError("relaxation changes physical kernel"))
            else
                all(j -> j in b.information,a.information) || throw(ArgumentError("relaxation removes original information"))
                all(j -> j<i && original.nodes[j] isa ChanceNode,setdiff(b.information,a.information)) || throw(ArgumentError("relaxation adds future or decision information"))
            end
        end
        new(original,relaxed)
    end
end
function InformationRelaxation(id::InfluenceDiagramInstance,extra::Dict{Int,Vector{Int}})
    all(i -> 1<=i<=length(id.nodes) && id.nodes[i] isa DecisionNode,keys(extra)) || throw(ArgumentError("relaxation target is not a decision"))
    ns=copy(id.nodes)
    for (i,added) in extra
        all(j -> 1<=j<i && id.nodes[j] isa ChanceNode,added) || throw(ArgumentError("only already realized chance nodes can be revealed"))
        d=id.nodes[i]
        ns[i]=DecisionNode(d.name,d.states,vcat(d.information,sort(setdiff(added,d.information))))
    end
    InformationRelaxation(id,InfluenceDiagramInstance(ns,id.utilities))
end
function lift_fixings(r::InformationRelaxation,p::PartialPolicy)
    validate_policy(r.original,p)
    fixed=Dict{PolicyKey,Int}()
    for (i,h) in policy_keys(r.relaxed)
        original=r.original.nodes[i].information
        augmented=r.relaxed.nodes[i].information
        oldh=Tuple(h[findfirst(==(j),augmented)] for j in original)
        haskey(p.actions,(i,oldh)) && (fixed[(i,h)]=p.actions[(i,oldh)])
    end
    PartialPolicy(fixed)
end
function upper_bound(r::InformationRelaxation,p::PartialPolicy; max_policies=1_000_000)
    enumerate_policies(r.relaxed,lift_fixings(r,p); max_policies).value
end
export InformationRelaxation, lift_fixings
