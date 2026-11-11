struct SequentialProbingBound <: AbstractUpperBoundOracle
    evaluator::OilEvaluator
    option::Symbol
    function SequentialProbingBound(e::OilEvaluator, option::Symbol=:legacy_nonsequential)
        option in (:full_information,:legacy_nonsequential) || throw(ArgumentError("unknown sequential bound"))
        new(e,option)
    end
end

"""A test is global only if *every* information row is explicitly fixed alike."""
function sequential_global_sets(x::OilInstance, p::PartialSequentialOilPolicy)
    validate_sequential_testing(x,p.actions)
    yes=zeros(Int,ntests(x)); no=zeros(Int,ntests(x))
    for ((i,_),a) in p.actions
        a ? (yes[i]+=1) : (no[i]+=1)
    end
    required=UInt64(0); forbidden=UInt64(0)
    for i in 1:ntests(x)
        count=big(size(x.reports,3)+1)^(i-1)
        yes[i]==count && (required |= UInt64(1)<<(i-1))
        no[i]==count && (forbidden |= UInt64(1)<<(i-1))
    end
    (required=required,forbidden=forbidden)
end

function upper_bound(b::SequentialProbingBound, p::PartialSequentialOilPolicy)
    x=b.evaluator.instance
    validate_sequential_testing(x,p.actions)
    b.option==:full_information && return operating_value(b.evaluator,full_mask(x))
    sets=sequential_global_sets(x,p)
    operating_value(b.evaluator,full_mask(x) & ~sets.forbidden)-test_cost(x,sets.required)
end

const SEQUENTIAL_IRBB_VARIANTS=(:baseline,:reachability,:cost_aware,:combined)

function sequential_cost_aware_bound(b::SequentialProbingBound,
        p::PartialSequentialOilPolicy)
    primary=upper_bound(b,p)
    x=b.evaluator.instance
    cost_bound=operating_value(b.evaluator,full_mask(x))-
        minimum_sequential_testing_cost(x,p)
    (value=min(primary,cost_bound),primary=primary,cost_bound=cost_bound)
end

function report_sequential_progress(io,variant,stats,depth,best,ub,start)
    println(io,"sequential_irbb variant=",variant," nodes=",stats.visited,
        " depth=",depth," incumbent=",best," upper_bound=",ub,
        " elapsed=",(time_ns()-start)/1e9)
    flush(io)
end

"""Direct DFS baseline. First unfixed row; skip child before test child.

Both bounds can remain loose at complete leaves. Only exhaustive termination
certifies optimality. No reachability reduction, DP bounds or policy cache.
"""
function solve_sequential_probing_baseline(x::OilInstance; bound=:legacy_nonsequential,
        max_rows=24,progress_every=0,progress_io=stderr,time_limit=Inf)
    (time_limit>0 && !isnan(time_limit)) || throw(ArgumentError("positive time limit required"))
    start=time_ns(); rows=sequential_policy_rows(x;max_rows)
    stats=SearchStats(); e=OilEvaluator(x); oracle=SequentialProbingBound(e,bound)
    best=nothing; bestpolicy=nothing
    stack=[(PartialSequentialOilPolicy(),0)]
    while !isempty(stack)
        if !isnothing(best) && (time_ns()-start)/1e9>=time_limit
            stats.cache_hits=e.stats.cache_hits
            stats.bound_policy_evaluations=e.stats.evaluations
            return SearchResult(best,bestpolicy,best,stats.root_upper_bound,:time_limit,0.,
                (time_ns()-start)/1e9,stats)
        end
        p,depth=pop!(stack); stats.visited+=1
        stats.maximum_depth=max(stats.maximum_depth,depth)
        stats.maximum_stack_size=max(stats.maximum_stack_size,length(stack)+1)
        evalstart=time_ns()
        candidate=optimize_sequential_drilling(x,complete_sequential_testing(x,p;max_rows))
        stats.evaluations+=1; stats.evaluation_time+=(time_ns()-evalstart)/1e9
        if isnothing(best) || candidate.value>best
            best=candidate.value; bestpolicy=candidate.policy; stats.incumbent_updates+=1
        end
        depth==0 && (stats.root_lower_bound=best)
        boundstart=time_ns(); ub=upper_bound(oracle,p); stats.bound_evaluations+=1
        stats.bound_time+=(time_ns()-boundstart)/1e9
        depth==0 && (stats.root_upper_bound=ub)
        if progress_every>0 && stats.visited%progress_every==0
            report_sequential_progress(progress_io,:baseline,stats,depth,best,ub,start)
        end
        if ub<=best
            stats.pruned+=1; stats.pruned_by_primary_bound+=1; continue
        end
        k=findfirst(key -> !haskey(p.actions,key),rows)
        isnothing(k) && continue # exact candidate at leaf; the UB need not be tight
        stats.expanded+=1
        for a in (true,false) # LIFO: visit skip first
            actions=copy(p.actions); actions[rows[k]]=a
            push!(stack,(PartialSequentialOilPolicy(actions),depth+1))
        end
    end
    stats.cache_hits=e.stats.cache_hits
    stats.bound_policy_evaluations=e.stats.evaluations # portfolio oracle cache misses
    SearchResult(best,bestpolicy,best,best,:optimal_exact,0.,(time_ns()-start)/1e9,stats)
end

"""Reachability/cost/caching ablations with the baseline row order.

`:reachability` changes only the represented rows. `:cost_aware` changes only
the bound. `:combined` applies both and caches physical completions and bounds.
All comparisons use exact rationals.
"""
function solve_sequential_probing_improved(x::OilInstance; bound=:legacy_nonsequential,
        variant=:combined,max_rows=24,progress_every=0,progress_io=stderr,time_limit=Inf)
    variant in (:reachability,:cost_aware,:combined) ||
        throw(ArgumentError("unknown improved sequential IR-B&B variant: $variant"))
    (time_limit>0 && !isnan(time_limit)) || throw(ArgumentError("positive time limit required"))
    start=time_ns(); rows=sequential_policy_rows(x;max_rows); total_rows=length(rows)
    stats=SearchStats(); evaluator=OilEvaluator(x); oracle=SequentialProbingBound(evaluator,bound)
    use_reachability=variant in (:reachability,:combined)
    use_cost=variant in (:cost_aware,:combined)
    use_cache=variant==:combined
    evaluation_cache=Dict{Any,Any}(); bound_cache=Dict{Any,Any}()
    initial_candidate=nothing

    # Every nontrivial policy has a first commissioned test on the all-N/A
    # history and pays its cost with probability one.
    if use_cost
        no_testing=Dict{SequentialOilKey,Bool}(key=>false for key in rows)
        evalstart=time_ns(); candidate=optimize_sequential_drilling(x,no_testing)
        stats.evaluations+=1; stats.evaluation_cache_misses+=1
        stats.evaluation_time+=(time_ns()-evalstart)/1e9
        stats.incumbent_updates=1; initial_candidate=candidate
        use_cache && (evaluation_cache[physical_sequential_key(x,no_testing)]=candidate)
        full_information=operating_value(evaluator,full_mask(x))
        nontrivial_upper=ntests(x)==0 ? candidate.value :
            full_information-minimum(x.costs)
        stats.root_lower_bound=candidate.value
        stats.root_upper_bound=max(candidate.value,nontrivial_upper)
        stats.bound_evaluations=1
        if nontrivial_upper<=candidate.value
            stats.visited=1; stats.maximum_stack_size=1
            stats.pruned=1; stats.pruned_by_cost_bound=1; stats.root_certificates=1
            stats.cache_hits=evaluator.stats.cache_hits
            stats.bound_policy_evaluations=evaluator.stats.evaluations
            return SearchResult(candidate.value,candidate.policy,candidate.value,candidate.value,
                :optimal_exact,0.,(time_ns()-start)/1e9,stats)
        end
    end

    best=isnothing(initial_candidate) ? nothing : initial_candidate.value
    bestpolicy=isnothing(initial_candidate) ? nothing : initial_candidate.policy
    stack=[(PartialSequentialOilPolicy(),0)]
    while !isempty(stack)
        if !isnothing(best) && (time_ns()-start)/1e9>=time_limit
            stats.cache_hits=evaluator.stats.cache_hits+stats.evaluation_cache_hits+stats.bound_cache_hits
            stats.bound_policy_evaluations=evaluator.stats.evaluations
            return SearchResult(best,bestpolicy,best,stats.root_upper_bound,:time_limit,0.,
                (time_ns()-start)/1e9,stats)
        end
        p,depth=pop!(stack)
        use_reachability && (p=canonical_sequential_policy(x,p))
        stats.visited+=1; stats.maximum_depth=max(stats.maximum_depth,depth)
        stats.maximum_stack_size=max(stats.maximum_stack_size,length(stack)+1)
        reachable=use_reachability ? reachable_sequential_rows(x,p) : rows
        use_reachability && (stats.unreachable_decisions_eliminated+=total_rows-length(reachable))

        evalstart=time_ns()
        testing=complete_sequential_testing(x,p;max_rows,
            rows=use_cache ? rows : nothing)
        evaluation_was_computed=false
        candidate=if use_cache
            key=physical_sequential_key(x,testing)
            if haskey(evaluation_cache,key)
                stats.evaluation_cache_hits+=1; evaluation_cache[key]
            else
                stats.evaluation_cache_misses+=1
                evaluation_was_computed=true
                value=optimize_sequential_drilling(x,testing)
                evaluation_cache[key]=value
            end
        else
            stats.evaluation_cache_misses+=1
            evaluation_was_computed=true
            optimize_sequential_drilling(x,testing)
        end
        stats.evaluations+=evaluation_was_computed
        stats.evaluation_time+=(time_ns()-evalstart)/1e9
        if isnothing(best) || candidate.value>best
            best=candidate.value; bestpolicy=candidate.policy; stats.incumbent_updates+=1
        end
        depth==0 && (stats.root_lower_bound=best)

        k=findfirst(key -> !haskey(p.actions,key),reachable)
        isnothing(k) && continue # Explicit exact evaluation of a complete canonical policy.

        boundstart=time_ns()
        bound_result=if use_cache
            key=canonical_sequential_key(x,p)
            if haskey(bound_cache,key)
                stats.bound_cache_hits+=1; bound_cache[key]
            else
                stats.bound_cache_misses+=1
                value=use_cost ? sequential_cost_aware_bound(oracle,p) :
                    (value=upper_bound(oracle,p),primary=nothing,cost_bound=nothing)
                bound_cache[key]=value
            end
        else
            stats.bound_cache_misses+=1
            use_cost ? sequential_cost_aware_bound(oracle,p) :
                (value=upper_bound(oracle,p),primary=nothing,cost_bound=nothing)
        end
        stats.bound_evaluations+=1; stats.bound_time+=(time_ns()-boundstart)/1e9
        ub=bound_result.value; depth==0 && (stats.root_upper_bound=ub)
        if progress_every>0 && stats.visited%progress_every==0
            report_sequential_progress(progress_io,variant,stats,depth,best,ub,start)
        end
        if ub<=best
            stats.pruned+=1
            if use_cost && bound_result.cost_bound<bound_result.primary
                stats.pruned_by_cost_bound+=1
            else
                stats.pruned_by_primary_bound+=1
            end
            continue
        end
        stats.expanded+=1
        branch=reachable[k]
        for action in (true,false) # Same LIFO skip-first order as the baseline.
            actions=copy(p.actions); actions[branch]=action
            child=PartialSequentialOilPolicy(actions)
            use_reachability && (child=canonical_sequential_policy(x,child))
            push!(stack,(child,depth+1))
        end
    end
    stats.cache_hits=evaluator.stats.cache_hits+stats.evaluation_cache_hits+stats.bound_cache_hits
    stats.bound_policy_evaluations=evaluator.stats.evaluations
    SearchResult(best,bestpolicy,best,best,:optimal_exact,0.,(time_ns()-start)/1e9,stats)
end

function solve_sequential_probing(x::OilInstance; bound=:legacy_nonsequential,
        variant=:baseline,max_rows=24,progress_every=0,progress_io=stderr,time_limit=Inf)
    variant in SEQUENTIAL_IRBB_VARIANTS ||
        throw(ArgumentError("unknown sequential IR-B&B variant: $variant"))
    variant==:baseline && return solve_sequential_probing_baseline(x;bound,max_rows,
        progress_every,progress_io,time_limit)
    solve_sequential_probing_improved(x;bound,variant,max_rows,progress_every,progress_io,time_limit)
end

export SequentialProbingBound, sequential_global_sets, sequential_cost_aware_bound
export SEQUENTIAL_IRBB_VARIANTS, solve_sequential_probing_baseline
export solve_sequential_probing_improved, solve_sequential_probing
