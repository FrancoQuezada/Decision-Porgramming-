abstract type AbstractIDNode end
struct ChanceNode <: AbstractIDNode
    name::Symbol
    states::Int
    parents::Vector{Int}
    kernel::Array{Exact}
end
ChanceNode(name::Symbol,states::Integer,parents::AbstractVector{<:Integer},kernel::AbstractArray{<:Real}) = ChanceNode(name,Int(states),Int.(parents),exact.(kernel))
struct DecisionNode <: AbstractIDNode
    name::Symbol
    states::Int
    information::Vector{Int}
end
struct UtilityFactor
    scope::Vector{Int}
    values::Array{Exact}
end
UtilityFactor(scope::AbstractVector{<:Integer},values::AbstractArray{<:Real}) = UtilityFactor(Int.(scope),exact.(values))

"""Finite expected-additive-utility ID in explicit causal order.
Only deterministic unconstrained policies are supported in v0.1.
"""
struct InfluenceDiagramInstance
    nodes::Vector{AbstractIDNode}
    utilities::Vector{UtilityFactor}
    function InfluenceDiagramInstance(nodes,utilities)
        ns=AbstractIDNode[nodes...]
        length(unique(n.name for n in ns))==length(ns) || throw(ArgumentError("duplicate names"))
        for (i,n) in enumerate(ns)
            n.states>0 || throw(ArgumentError("empty state space"))
            pars=n isa ChanceNode ? n.parents : n.information
            all(j -> 1<=j<i,pars) && length(unique(pars))==length(pars) || throw(ArgumentError("parents/information must precede node"))
            if n isa ChanceNode
                size(n.kernel)==Tuple(vcat([ns[j].states for j in pars],n.states)) || throw(DimensionMismatch("chance kernel at $i"))
                for h in Iterators.product((1:ns[j].states for j in pars)...)
                    all(>=(0),n.kernel[h...,:]) && sum(n.kernel[h...,:])==1 || throw(ArgumentError("kernel must be exactly normalized"))
                end
            end
        end
        us=UtilityFactor[utilities...]
        for u in us
            all(j -> 1<=j<=length(ns),u.scope) && length(unique(u.scope))==length(u.scope) || throw(ArgumentError("utility scope"))
            size(u.values)==Tuple(ns[j].states for j in u.scope) || throw(DimensionMismatch("utility"))
        end
        new(ns,us)
    end
end

const PolicyKey=Tuple{Int,Tuple}
struct Policy
    actions::Dict{PolicyKey,Int}
end
struct PartialPolicy
    actions::Dict{PolicyKey,Int}
end
PartialPolicy()=PartialPolicy(Dict{PolicyKey,Int}())
function policy_keys(id::InfluenceDiagramInstance)
    keys=PolicyKey[]
    for (i,n) in enumerate(id.nodes)
        n isa DecisionNode || continue
        for h in Iterators.product((1:id.nodes[j].states for j in n.information)...)
            push!(keys,(i,h))
        end
    end
    keys
end
function validate_policy(id,p; complete=p isa Policy)
    ks=policy_keys(id)
    for (key,a) in p.actions
        key in ks || throw(ArgumentError("invalid policy history $key"))
        1<=a<=id.nodes[key[1]].states || throw(ArgumentError("invalid action"))
    end
    complete && length(ks)!=length(p.actions) && throw(ArgumentError("incomplete policy"))
    true
end

function foreach_policy(f,id,p::PartialPolicy=PartialPolicy(); max_policies=1_000_000)
    validate_policy(id,p)
    free=[key for key in policy_keys(id) if !haskey(p.actions,key)]
    prod((big(id.nodes[key[1]].states) for key in free); init=big(1))<=max_policies || throw(ArgumentError("policy enumeration size guard"))
    actions=copy(p.actions)
    function visit(k)
        if k>length(free); f(Policy(copy(actions))); return; end
        key=free[k]
        for a in 1:id.nodes[key[1]].states; actions[key]=a; visit(k+1); end
        delete!(actions,key)
    end
    visit(1)
end

"""Non-probing maintenance D1 → X, then D2. D2 observes D1 but not X."""
function maintenance_instance(; seed=0)
    rng=Xoshiro(seed)
    # Rational transition probabilities depend on the earlier maintenance action.
    failure_no=rand(rng,35:65)//100
    failure_yes=rand(rng,5:20)//100
    kernel=[1-failure_no failure_no; 1-failure_yes failure_yes]
    nodes=AbstractIDNode[DecisionNode(:maintain,2,Int[]),ChanceNode(:failure,2,[1],kernel),
        DecisionNode(:operate,2,[1])]
    InfluenceDiagramInstance(nodes,[UtilityFactor([1],[0,-8]),
        UtilityFactor([2,3],[30 3;-70 3])])
end

export ChanceNode, DecisionNode, UtilityFactor, InfluenceDiagramInstance, Policy, PartialPolicy
export policy_keys, validate_policy, foreach_policy, maintenance_instance
