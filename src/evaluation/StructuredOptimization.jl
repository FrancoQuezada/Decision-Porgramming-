"""A sufficient graphical/informational test, not an unrestricted ID optimizer."""
struct StructuredSupport
    supported::Bool
    missing::Dict{Int,Vector{Int}}
end
struct UnsupportedStructuredModel <: Exception
    support::StructuredSupport
end
Base.showerror(io::IO,e::UnsupportedStructuredModel)=print(io,"structured oracle requires observed continuation/fixing dependencies; missing ",e.support.missing)

struct FixedPolicyRow
    decision::Int
    information::Tuple
    history::Tuple
    action::Int
end

"""Private snapshot and precomputed factor separators for chronological DP."""
struct StructuredPlan
    relaxation::InformationRelaxation
    utilities::Vector{Vector{UtilityFactor}}
    constant::Exact
    separators::Vector{Vector{Int}}
    original_rows::Vector{PolicyKey}
    support::StructuredSupport
end
function StructuredPlan(r::InformationRelaxation)
    r=deepcopy(InformationRelaxation(
        InfluenceDiagramInstance(r.original.nodes,r.original.utilities),
        InfluenceDiagramInstance(r.relaxed.nodes,r.relaxed.utilities)))
    id=r.relaxed; n=length(id.nodes)
    closing=[UtilityFactor[] for _ in 1:n]
    constant=zero(Exact)
    for u in id.utilities
        isempty(u.scope) ? (constant+=u.values[]) : push!(closing[maximum(u.scope)],u)
    end
    separators=[Int[] for _ in 1:n]
    for k in 1:n
        live=Int[]
        for j in k:n
            node=id.nodes[j]
            node isa ChanceNode && append!(live,filter(<(k),node.parents))
            for u in closing[j];append!(live,filter(<(k),u.scope));end
        end
        separators[k]=sort(unique(live))
    end
    missing=Dict{Int,Vector{Int}}()
    for (d,node) in enumerate(id.nodes)
        node isa DecisionNode || continue
        required=copy(separators[d])
        for j in d:n
            original=r.original.nodes[j]
            original isa DecisionNode && append!(required,filter(<(d),original.information))
        end
        absent=sort(setdiff(unique(required),node.information))
        isempty(absent) || (missing[d]=absent)
    end
    StructuredPlan(r,closing,constant,separators,policy_keys(r.original),StructuredSupport(isempty(missing),missing))
end
structured_support(r::InformationRelaxation)=StructuredPlan(r).support

Base.@kwdef mutable struct StructuredStats
    oracle_calls::Int=0
    subproblems_solved::Int=0
    decision_messages::Int=0
    chance_messages::Int=0
    cache_hits::Int=0
    cache_misses::Int=0
    key_builds::Int=0
    key_time::Float64=0.0
    compute_time::Float64=0.0 # exclusive recurrence time, child calls excluded
    fallback_calls::Int=0
    full_policy_evaluations::Int=0
    reused_messages::Int=0   # incremental reuse, separate from dictionary hits
    invalidated_messages::Int=0
    recomputed_messages::Int=0
    invalidation_time::Float64=0.0
end
struct MessageSolution
    value::Exact
    action::Int # smallest maximizing action; 0 for chance messages
end
struct NoReuse end

struct StructuredOracle{R} <: AbstractUpperBoundOracle
    plan::StructuredPlan
    reuse::R
    stats::StructuredStats
    fallback::Symbol
    max_policies::Int
end
function StructuredOracle(r::InformationRelaxation;fallback=:enumeration,max_policies=1_000_000)
    fallback in (:enumeration,:error) || throw(ArgumentError("fallback must be :enumeration or :error"))
    StructuredOracle(StructuredPlan(r),NoReuse(),StructuredStats(),fallback,max_policies)
end

struct StructuredWorkspace{R}
    plan::StructuredPlan
    fixings::Vector{FixedPolicyRow}
    stats::StructuredStats
    reuse::R
end
function fixed_rows(plan,p)
    validate_policy(plan.relaxation.original,p)
    [FixedPolicyRow(d,Tuple(plan.relaxation.original.nodes[d].information),h,a)
        for ((d,h),a) in sort(collect(p.actions);by=first)]
end
_prepare_reuse(::NoReuse,plan,p,parent,stats)=NoReuse()
_read_message!(::NoReuse,w,k,assignment)=nothing
_save_message!(::NoReuse,w,k,assignment,solution)=nothing
_snapshot(::NoReuse,plan,p)=nothing

function _continuation(w::StructuredWorkspace,k::Int,assignment::Vector{Int})
    id=w.plan.relaxation.relaxed
    k>length(id.nodes) && return MessageSolution(zero(Exact),0)
    cached=_read_message!(w.reuse,w,k,assignment)
    isnothing(cached) || return cached
    start=time_ns(); child_time=UInt64(0)
    node=id.nodes[k]; w.stats.subproblems_solved+=1
    if node isa ChanceNode
        w.stats.chance_messages+=1
        value=zero(Exact)
        for a in 1:node.states
            q=node.kernel[assignment[node.parents]...,a]
            q==0 && continue
            assignment[k]=a
            immediate=sum((u.values[assignment[u.scope]...] for u in w.plan.utilities[k]);init=zero(Exact))
            t=time_ns(); future=_continuation(w,k+1,assignment);child_time+=time_ns()-t
            value+=q*(immediate+future.value)
        end
        solution=MessageSolution(value,0)
    else
        w.stats.decision_messages+=1
        original=w.plan.relaxation.original.nodes[k]
        history=Tuple(assignment[original.information])
        action=0
        for row in w.fixings
            if row.decision==k && row.history==history;action=row.action;break;end
        end
        allowed=action==0 ? (1:node.states) : (action:action)
        best=nothing; best_action=0
        for a in allowed
            assignment[k]=a
            immediate=sum((u.values[assignment[u.scope]...] for u in w.plan.utilities[k]);init=zero(Exact))
            t=time_ns(); future=_continuation(w,k+1,assignment);child_time+=time_ns()-t
            v=immediate+future.value
            if isnothing(best) || v>best;best=v;best_action=a;end
        end
        solution=MessageSolution(best,best_action)
    end
    w.stats.compute_time+=(time_ns()-start-child_time)/1e9
    _save_message!(w.reuse,w,k,assignment,solution)
    solution
end

function evaluate_bound!(o::StructuredOracle,p::PartialPolicy=PartialPolicy();parent=nothing)
    o.stats.oracle_calls+=1
    validate_policy(o.plan.relaxation.original,p)
    if !o.plan.support.supported
        o.fallback==:error && throw(UnsupportedStructuredModel(o.plan.support))
        o.stats.fallback_calls+=1
        r=o.plan.relaxation
        result=enumerate_policies(r.relaxed,lift_fixings(r,p);max_policies=o.max_policies)
        o.stats.full_policy_evaluations+=result.evaluations
        return (value=result.value,snapshot=nothing,status=:enumeration_fallback)
    end
    reuse=_prepare_reuse(o.reuse,o.plan,p,parent,o.stats)
    w=StructuredWorkspace(o.plan,fixed_rows(o.plan,p),o.stats,reuse)
    result=_continuation(w,1,zeros(Int,length(o.plan.relaxation.relaxed.nodes)))
    (value=o.plan.constant+result.value,snapshot=_snapshot(reuse,o.plan,p),status=:structured_exact)
end
upper_bound(o::StructuredOracle,p::PartialPolicy=PartialPolicy())=evaluate_bound!(o,p).value

"""Recover one admissible relaxed policy, without enumerating complete policies."""
function optimize_relaxed(o::StructuredOracle,p::PartialPolicy=PartialPolicy())
    r=o.plan.relaxation
    if !o.plan.support.supported
        o.fallback==:error && throw(UnsupportedStructuredModel(o.plan.support))
        e=enumerate_policies(r.relaxed,lift_fixings(r,p);max_policies=o.max_policies)
        o.stats.oracle_calls+=1;o.stats.fallback_calls+=1
        o.stats.full_policy_evaluations+=e.evaluations
        return (value=e.value,policy=e.policy,status=:enumeration_fallback)
    end
    result=evaluate_bound!(o,p)
    actions=Dict(key=>1 for key in policy_keys(r.relaxed))
    merge!(actions,lift_fixings(r,p).actions)
    w=StructuredWorkspace(o.plan,fixed_rows(o.plan,p),o.stats,
        _prepare_reuse(o.reuse,o.plan,p,nothing,o.stats))
    assignment=zeros(Int,length(r.relaxed.nodes))
    reached=Dict{PolicyKey,Int}()
    function visit(k)
        k>length(assignment) && return
        node=r.relaxed.nodes[k]
        if node isa ChanceNode
            for a in 1:node.states
                node.kernel[assignment[node.parents]...,a]==0 && continue
                assignment[k]=a;visit(k+1)
            end
        else
            solution=_continuation(w,k,assignment)
            key=(k,Tuple(assignment[node.information]))
            haskey(reached,key) && reached[key]!=solution.action && error("inconsistent DP policy history")
            reached[key]=solution.action;actions[key]=solution.action
            assignment[k]=solution.action;visit(k+1)
        end
    end
    visit(1)
    policy=Policy(actions)
    evaluate_policy(r.relaxed,policy)==result.value || error("recovered policy does not attain bound")
    (value=result.value,policy=policy,status=:structured_exact)
end

export StructuredSupport, UnsupportedStructuredModel, StructuredPlan, StructuredStats
export StructuredOracle, structured_support, evaluate_bound!, optimize_relaxed
