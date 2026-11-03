struct ProbingNode
    required::UInt64
    forbidden::UInt64
    function ProbingNode(a::UInt64,b::UInt64)
        a & b == 0 || throw(ArgumentError("overlapping node fixings"))
        new(a,b)
    end
end
struct ProbingBound <: AbstractUpperBoundOracle
    evaluator::OilEvaluator
end
function upper_bound(b::ProbingBound, p::ProbingNode)
    e = b.evaluator
    check_mask(e.instance,p.required); check_mask(e.instance,p.forbidden)
    start = time_ns()
    ub = operating_value(e,full_mask(e.instance) & ~p.forbidden) - test_cost(e.instance,p.required)
    e.stats.bound_time += (time_ns()-start)/1e9
    ub
end

"""Depth-first exact probing B&B, branching on the largest marginal information loss.
Pruning uses Rational{BigInt}; there is no tolerance-based loss of optimality.
"""
function solve_probing(x::OilInstance; max_tests=16)
    ntests(x) <= max_tests || throw(ArgumentError("exact oracle size guard"))
    start = time_ns()
    e = OilEvaluator(x)
    b = ProbingBound(e)
    bestmask = UInt64(0); best = portfolio_value(e,bestmask)
    stack = [ProbingNode(UInt64(0),UInt64(0))]
    while !isempty(stack)
        p = pop!(stack); e.stats.visited += 1
        candidate = portfolio_value(e,p.required)
        if candidate > best; best = candidate; bestmask = p.required; end
        ub = upper_bound(b,p)
        if ub <= best; e.stats.pruned += 1; continue; end
        allowed = full_mask(x) & ~p.forbidden
        free = selected_tests(x,allowed & ~p.required)
        isempty(free) && error("inconsistent leaf bound")
        losses = [operating_value(e,allowed)-operating_value(e,allowed & ~(UInt64(1) << (i-1))) for i in free]
        bit = UInt64(1) << (free[argmax(losses)]-1)
        e.stats.expanded += 1
        push!(stack,ProbingNode(p.required,p.forbidden|bit))
        push!(stack,ProbingNode(p.required|bit,p.forbidden))
    end
    policy = optimal_oil_policy(e,bestmask)
    SearchResult(best,policy,best,best,:optimal_exact,0.0,(time_ns()-start)/1e9,e.stats)
end

function validate_probing_bounds(x::OilInstance; max_tests=8)
    ntests(x) <= max_tests || throw(ArgumentError("bound audit size guard"))
    enum = enumerate_oil(x).values
    e = OilEvaluator(x); b = ProbingBound(e)
    count = 0; largest_slack = zero(Exact)
    for states in Iterators.product(ntuple(_ -> 0:2,ntests(x))...)
        a=UInt64(0); f=UInt64(0)
        for i in 1:ntests(x)
            states[i] == 1 && (a |= UInt64(1) << (i-1))
            states[i] == 2 && (f |= UInt64(1) << (i-1))
        end
        ub = upper_bound(b,ProbingNode(a,f))
        subtree = maximum(v for (mask,v) in enum if mask & a == a && mask & f == 0)
        ub >= subtree || error("invalid bound at ($a,$f)")
        largest_slack = max(largest_slack,ub-subtree); count += 1
    end
    (nodes=count,largest_slack=largest_slack)
end

export ProbingNode, ProbingBound, upper_bound, solve_probing, validate_probing_bounds
