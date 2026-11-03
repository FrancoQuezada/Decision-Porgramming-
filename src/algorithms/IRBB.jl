"""Small-instance partial-policy B&B with an exact enumerative relaxed oracle.
This proves functionality beyond probing; no general efficiency claim is made.
"""
function solve_irbb(r::InformationRelaxation; max_policies=1_000_000)
    start=time_ns(); id=r.original; stats=SearchStats()
    keys=policy_keys(id)
    cache=Dict{Tuple,Exact}()
    best=nothing; policy=nothing
    stack=[PartialPolicy()]
    while !isempty(stack)
        p=pop!(stack); stats.visited+=1
        actions=Dict(key=>get(p.actions,key,1) for key in keys)
        feasible=Policy(actions)
        t=time_ns(); v=evaluate_policy(id,feasible); stats.evaluation_time+=(time_ns()-t)/1e9
        stats.evaluations+=1
        if isnothing(best) || v>best; best=v; policy=feasible; end
        code=Tuple(get(p.actions,key,0) for key in keys)
        t=time_ns()
        if haskey(cache,code)
            ub=cache[code]; stats.cache_hits+=1
        else
            relaxed=enumerate_policies(r.relaxed,lift_fixings(r,p); max_policies)
            ub=relaxed.value; cache[code]=ub
            stats.bound_policy_evaluations+=relaxed.evaluations
        end
        stats.bound_time+=(time_ns()-t)/1e9
        if ub<=best; stats.pruned+=1; continue; end
        free=findfirst(key -> !haskey(p.actions,key),keys)
        isnothing(free) && error("invalid relaxed leaf bound")
        key=keys[free]; stats.expanded+=1
        for a in reverse(1:id.nodes[key[1]].states)
            fixed=copy(p.actions); fixed[key]=a; push!(stack,PartialPolicy(fixed))
        end
    end
    SearchResult(best,policy,best,best,:optimal_exact,0.0,(time_ns()-start)/1e9,stats)
end

function validate_policy_bounds(r::InformationRelaxation; max_nodes=100_000)
    id=r.original; keys=policy_keys(id)
    prod((big(id.nodes[k[1]].states+1) for k in keys); init=big(1))<=max_nodes || throw(ArgumentError("partial policy audit size guard"))
    count=0; largest_slack=zero(Exact)
    for choices in Iterators.product((0:id.nodes[k[1]].states for k in keys)...)
        p=PartialPolicy(Dict(keys[i]=>a for (i,a) in enumerate(choices) if a!=0))
        truevalue=enumerate_policies(id,p).value
        bound=upper_bound(r,p)
        bound>=truevalue || error("invalid bound at $p")
        count+=1; largest_slack=max(largest_slack,bound-truevalue)
    end
    (nodes=count,largest_slack=largest_slack)
end
export solve_irbb, validate_policy_bounds
