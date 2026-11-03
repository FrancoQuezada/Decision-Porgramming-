"""B/C/D share the original deterministic branching and action-1 incumbent rule.
The original `solve_irbb` and its enumerative oracle remain unchanged as A.
"""
function solve_reuse_irbb(r::InformationRelaxation;variant=:C,cache_limit=nothing,
        inherit_bounds=false,trace=false,max_policies=1_000_000,fallback=:enumeration)
    variant in (:B,:C,:D) || throw(ArgumentError("variant must be :B, :C or :D"))
    start=time_ns()
    oracle=variant==:B ? StructuredOracle(r;fallback,max_policies) :
        (variant==:C ? cached_oracle(r;fallback,max_policies,cache=SubproblemCache(max_entries=cache_limit)) :
            incremental_oracle(r;fallback,max_policies,cache=SubproblemCache(max_entries=cache_limit)))
    id=oracle.plan.relaxation.original;ks=policy_keys(id);stats=SearchStats()
    best=nothing;policy=nothing;root_bound=nothing;inherited_prunes=0
    peak_snapshot_messages=0;last_snapshot=nothing
    # A child carries the parent's exact snapshot and its valid inherited bound.
    stack=Tuple{PartialPolicy,Union{Nothing,BoundSnapshot},Union{Nothing,Exact}}[(PartialPolicy(),nothing,nothing)]
    history=NamedTuple[]
    while !isempty(stack)
        p,parent,parent_bound=pop!(stack);stats.visited+=1
        feasible=Policy(Dict(key=>get(p.actions,key,1) for key in ks))
        t=time_ns();v=evaluate_policy(id,feasible);stats.evaluation_time+=(time_ns()-t)/1e9
        stats.evaluations+=1
        if isnothing(best) || v>best;best=v;policy=feasible;end
        if inherit_bounds && !isnothing(parent_bound) && parent_bound<=best
            inherited_prunes+=1;stats.pruned+=1
            trace && push!(history,(fixings=Tuple(get(p.actions,key,0) for key in ks),bound=parent_bound,incumbent=best,pruned=true,kind=:inherited))
            continue
        end
        t=time_ns();bound=evaluate_bound!(oracle,p;parent=variant==:D ? parent : nothing)
        stats.bound_time+=(time_ns()-t)/1e9
        ub=bound.value;snapshot=bound.snapshot
        isnothing(root_bound) && (root_bound=ub)
        if !isnothing(snapshot)
            peak_snapshot_messages=max(peak_snapshot_messages,length(snapshot.messages));last_snapshot=snapshot
        end
        prune=ub<=best
        trace && push!(history,(fixings=Tuple(get(p.actions,key,0) for key in ks),bound=ub,incumbent=best,pruned=prune,kind=:exact))
        if prune;stats.pruned+=1;continue;end
        free=findfirst(key->!haskey(p.actions,key),ks)
        isnothing(free) && error("invalid structured leaf bound")
        key=ks[free];stats.expanded+=1
        for a in reverse(1:id.nodes[key[1]].states)
            fixed=copy(p.actions);fixed[key]=a
            push!(stack,(PartialPolicy(fixed),snapshot,ub))
        end
    end
    stats.bound_policy_evaluations=oracle.stats.full_policy_evaluations
    stats.cache_hits=oracle.stats.cache_hits
    result=SearchResult(best,policy,best,best,:optimal_exact,0.0,(time_ns()-start)/1e9,stats)
    (result=result,oracle=oracle,root_bound=root_bound,trace=history,
        inherited_prunes=inherited_prunes,peak_snapshot_messages=peak_snapshot_messages,
        final_snapshot=last_snapshot)
end
export solve_reuse_irbb
