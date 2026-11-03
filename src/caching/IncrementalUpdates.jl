struct MessagePosition
    stage::Int
    prefix::Tuple
end
Base.isequal(a::MessagePosition,b::MessagePosition)=a.stage==b.stage && isequal(a.prefix,b.prefix)
Base.:(==)(a::MessagePosition,b::MessagePosition)=isequal(a,b)
Base.hash(p::MessagePosition,h::UInt)=hash((p.stage,p.prefix),h)

struct BoundSnapshot
    identity::ModelIdentity
    information::Tuple
    actions::Dict{PolicyKey,Int}
    messages::Dict{MessagePosition,MessageSolution}
    dependents::Dict{PolicyKey,Set{MessagePosition}}
end
struct IncrementalReuse
    memo::MemoizedReuse
end
struct IncrementalWorkspace
    cached::CachedWorkspace
    messages::Dict{MessagePosition,MessageSolution}
    dependents::Dict{PolicyKey,Set{MessagePosition}}
    invalidated::Set{MessagePosition}
end
function incremental_oracle(r::InformationRelaxation;cache=SubproblemCache(),fallback=:enumeration,max_policies=1_000_000)
    fallback in (:enumeration,:error) || throw(ArgumentError("fallback"))
    plan=StructuredPlan(r)
    memo=MemoizedReuse(cache,model_identity(plan),relaxation_identity(plan))
    StructuredOracle(plan,IncrementalReuse(memo),StructuredStats(),fallback,max_policies)
end
function _prepare_reuse(reuse::IncrementalReuse,plan,p,parent,stats)
    t=time_ns()
    cached=_prepare_reuse(reuse.memo,plan,p,nothing,stats)
    invalid=Set{MessagePosition}()
    messages=Dict{MessagePosition,MessageSolution}()
    dependents=Dict{PolicyKey,Set{MessagePosition}}()
    if !isnothing(parent)
        parent isa BoundSnapshot || throw(ArgumentError("invalid bound snapshot"))
        parent.identity==reuse.memo.identity && parent.information==reuse.memo.information || throw(ArgumentError("snapshot model/information mismatch"))
        for key in union(keys(parent.actions),keys(p.actions))
            get(parent.actions,key,0)==get(p.actions,key,0) && continue
            union!(invalid,get(parent.dependents,key,Set{MessagePosition}()))
        end
        for (pos,solution) in parent.messages
            pos in invalid || (messages[pos]=solution)
        end
        for (key,positions) in parent.dependents
            retained=setdiff(positions,invalid)
            isempty(retained) || (dependents[key]=retained)
        end
    end
    stats.invalidated_messages+=length(invalid)
    stats.invalidation_time+=(time_ns()-t)/1e9
    IncrementalWorkspace(cached,messages,dependents,invalid)
end
message_position(k,assignment)=MessagePosition(k,Tuple(assignment[j] for j in 1:k-1))

function record_message!(inc::IncrementalWorkspace,w,k,assignment,solution)
    pos=message_position(k,assignment)
    inc.messages[pos]=solution
    for key in w.plan.original_rows
        d,h=key;d<k && continue
        info=w.plan.relaxation.original.nodes[d].information
        all(v>=k || assignment[v]==h[j] for (j,v) in enumerate(info)) || continue
        push!(get!(inc.dependents,key,Set{MessagePosition}()),pos)
    end
    nothing
end
function _read_message!(inc::IncrementalWorkspace,w,k,assignment)
    pos=message_position(k,assignment)
    if haskey(inc.messages,pos)
        w.stats.reused_messages+=1
        return inc.messages[pos]
    end
    result=_read_message!(inc.cached,w,k,assignment)
    isnothing(result) || record_message!(inc,w,k,assignment,result)
    result
end
function _save_message!(inc::IncrementalWorkspace,w,k,assignment,solution)
    _save_message!(inc.cached,w,k,assignment,solution)
    pos=message_position(k,assignment)
    pos in inc.invalidated && (w.stats.recomputed_messages+=1)
    record_message!(inc,w,k,assignment,solution)
end
function _snapshot(inc::IncrementalWorkspace,plan,p)
    memo=inc.cached.reuse
    BoundSnapshot(memo.identity,memo.information,copy(p.actions),inc.messages,inc.dependents)
end
export BoundSnapshot, incremental_oracle
