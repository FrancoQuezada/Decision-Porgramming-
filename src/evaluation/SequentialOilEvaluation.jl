"""Evaluate a complete testing policy and optimize terminal drilling exactly.

Forward likelihood propagation eliminates O into alpha(S). Testing costs are
charged against the probability of reaching each testing history, not ex ante.
No caching or aggregation of testing policies is used.
"""
function optimize_sequential_drilling(x::OilInstance, testing::AbstractDict)
    validate_sequential_testing(x,testing;complete=true)
    alpha=[sum(x.prior[o]*x.geology[o,s]*x.payoff[o] for o in eachindex(x.prior))
        for s in axes(x.geology,2)]
    beta=[sum(x.prior[o]*x.geology[o,s] for o in eachindex(x.prior))
        for s in axes(x.geology,2)]
    rule=Dict{Tuple,Bool}()
    function forward(i,h,likelihood)
        if i>ntests(x)
            gain=sum(alpha .* likelihood)
            rule[h]=gain>0
            return max(zero(Exact),gain)
        end
        if !testing[(i,h)]
            return forward(i+1,(h...,0),likelihood)
        end
        result=-x.costs[i]*sum(beta .* likelihood)
        for r in axes(x.reports,3)
            result+=forward(i+1,(h...,r),likelihood .* x.reports[i,:,r])
        end
        result
    end
    v=forward(1,(),ones(Exact,size(x.geology,2)))
    # Off-policy drilling rows remain explicit and deterministic.
    for h in Iterators.product(ntuple(_ -> 0:size(x.reports,3),ntests(x))...)
        get!(rule,h,false)
    end
    (value=v,policy=SequentialOilPolicy(Dict{SequentialOilKey,Bool}(testing),rule))
end

"""Minimum exact expected testing cost over all completions of a partial policy.

The recursion retains the original information structure. At an unfixed row it
chooses `skip` or `test` using only that row's observed history. Consequently the
result is the minimum testing cost of an original feasible completion, not an
information-relaxed surrogate.
"""
function minimum_sequential_testing_cost(x::OilInstance, p::PartialSequentialOilPolicy)
    validate_sequential_testing(x,p.actions)
    beta=[sum(x.prior[o]*x.geology[o,s] for o in eachindex(x.prior))
        for s in axes(x.geology,2)]
    function backward(i,h,likelihood)
        i>ntests(x) && return zero(Exact)
        key=(i,h)
        choices=haskey(p.actions,key) ? (p.actions[key],) : (false,true)
        best=nothing
        for action in choices
            value=if action
                x.costs[i]*sum(beta .* likelihood)+sum(backward(i+1,(h...,r),
                    likelihood .* x.reports[i,:,r]) for r in axes(x.reports,3))
            else
                backward(i+1,(h...,0),likelihood)
            end
            (isnothing(best) || value<best) && (best=value)
        end
        best
    end
    backward(1,(),ones(Exact,size(x.geology,2)))
end

"""Independent physical evaluation: traverse the causal process for each O,S.
Does not use alpha, the drilling optimizer, portfolio values or the DP reference.
"""
function evaluate_policy(x::OilInstance, p::SequentialOilPolicy)
    validate_sequential_testing(x,p.testing;complete=true)
    nr=size(x.reports,3); m=ntests(x)
    all(h -> length(h)==m && all(r -> r isa Integer && 0<=r<=nr,h),keys(p.drill)) ||
        throw(ArgumentError("invalid drilling history"))
    length(p.drill)==big(nr+1)^m || throw(ArgumentError("incomplete sequential drilling policy"))
    function physical(i,h,o,s)
        i>m && return p.drill[h] ? x.payoff[o] : zero(Exact)
        !p.testing[(i,h)] && return physical(i+1,(h...,0),o,s)
        -x.costs[i]+sum(x.reports[i,s,r]*physical(i+1,(h...,r),o,s) for r in 1:nr)
    end
    sum(x.prior[o]*x.geology[o,s]*physical(1,(),o,s)
        for o in eachindex(x.prior), s in axes(x.geology,2))
end

"""Independent exact backward DP over joint unnormalized beliefs on (O,S).

Only a validation reference: this function is never used as a B&B bound oracle.
All supplied fixings are retained, also in rows unreachable from the root policy.
"""
function solve_sequential_dp(x::OilInstance, p::PartialSequentialOilPolicy=PartialSequentialOilPolicy();
        max_histories=100_000)
    start=time_ns(); stats=SearchStats()
    total=sum((big(size(x.reports,3)+1)^i for i in 0:ntests(x)); init=big(0))
    total<=max_histories || throw(ArgumentError("sequential DP history size guard"))
    testing=complete_sequential_testing(x,p;max_rows=max_histories)
    drill=Dict{Tuple,Bool}(h=>false for h in
        Iterators.product(ntuple(_ -> 0:size(x.reports,3),ntests(x))...))
    function backward(i,h,joint)
        stats.visited+=1
        if i>ntests(x)
            gain=sum(joint[o,s]*x.payoff[o] for o in eachindex(x.prior),s in axes(x.geology,2))
            drill[h]=gain>0
            return max(zero(Exact),gain)
        end
        choices=haskey(p.actions,(i,h)) ? (p.actions[(i,h)],) : (false,true)
        best=nothing; action=false
        for a in choices
            v=if a
                -sum(joint)*x.costs[i]+sum(backward(i+1,(h...,r),
                    joint .* permutedims(x.reports[i,:,r])) for r in axes(x.reports,3))
            else
                backward(i+1,(h...,0),joint)
            end
            if isnothing(best) || v>best; best=v; action=a; end
        end
        testing[(i,h)]=action
        best
    end
    joint=[x.prior[o]*x.geology[o,s] for o in eachindex(x.prior),s in axes(x.geology,2)]
    v=backward(1,(),joint)
    policy=SequentialOilPolicy(testing,drill)
    evalstart=time_ns(); physical=evaluate_policy(x,policy)
    stats.evaluations=1; stats.evaluation_time=(time_ns()-evalstart)/1e9
    v==physical || error("sequential DP policy recovery mismatch")
    SearchResult(v,policy,v,v,:optimal_exact,0.,(time_ns()-start)/1e9,stats)
end

export optimize_sequential_drilling, minimum_sequential_testing_cost, solve_sequential_dp
