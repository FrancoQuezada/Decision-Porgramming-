struct OilPolicy
    tests::UInt64
    drill::Dict{Tuple,Bool} # report states of selected tests, in ascending test order
end

mutable struct OilEvaluator <: AbstractPolicyEvaluator
    instance::OilInstance
    alpha::Vector{Exact}
    cache::Dict{UInt64,Tuple{Exact,OilPolicy}}
    stats::SearchStats
end
function OilEvaluator(x::OilInstance, stats=SearchStats())
    alpha = [sum(x.prior[o]*x.geology[o,s]*x.payoff[o] for o in eachindex(x.prior)) for s in axes(x.geology,2)]
    OilEvaluator(x,alpha,Dict{UInt64,Tuple{Exact,OilPolicy}}(),stats)
end

"""Exact sum over report assignments; hidden O is eliminated once into alpha(S)."""
function operating_value(e::OilEvaluator, mask::UInt64)
    check_mask(e.instance, mask)
    if haskey(e.cache,mask)
        e.stats.cache_hits += 1
        return e.cache[mask][1]
    end
    start = time_ns()
    x = e.instance
    ids = selected_tests(x,mask)
    value = zero(Exact)
    rule = Dict{Tuple,Bool}()
    for r in outcomes(size(x.reports,3),length(ids))
        gain = sum(e.alpha[s]*prod((x.reports[i,s,r[k]] for (k,i) in enumerate(ids)); init=one(Exact)) for s in eachindex(e.alpha))
        rule[r] = gain > 0
        value += max(zero(Exact),gain)
    end
    e.cache[mask] = (value,OilPolicy(mask,rule))
    e.stats.evaluations += 1
    e.stats.evaluation_time += (time_ns()-start)/1e9
    value
end
portfolio_value(e::OilEvaluator, mask::UInt64) = operating_value(e,mask)-test_cost(e.instance,mask)
function optimal_oil_policy(e::OilEvaluator, mask::UInt64)
    operating_value(e,mask)
    e.cache[mask][2]
end

"""Independent evaluation over O,S and reports, without precomputed alpha or oracle cache."""
function evaluate_policy(x::OilInstance, policy::OilPolicy)
    ids = selected_tests(x,check_mask(x,policy.tests))
    val = -test_cost(x,policy.tests)
    for r in outcomes(size(x.reports,3),length(ids))
        haskey(policy.drill,r) || throw(ArgumentError("incomplete drilling rule"))
        if policy.drill[r]
            for o in eachindex(x.prior), s in axes(x.geology,2)
                probability = x.prior[o]*x.geology[o,s]
                for (k,i) in enumerate(ids); probability *= x.reports[i,s,r[k]]; end
                val += probability*x.payoff[o]
            end
        end
    end
    val
end

"""Enumerate portfolios and optimize every report action by direct joint summation.
This implementation never calls the optimized OilEvaluator.
"""
function enumerate_oil(x::OilInstance; max_tests=16)
    ntests(x) <= max_tests || throw(ArgumentError("enumeration size guard"))
    start = time_ns()
    vals = Dict{UInt64,Exact}()
    best = nothing; bestpolicy = nothing
    for mask in UInt64(0):full_mask(x)
        ids = selected_tests(x,mask)
        rule = Dict{Tuple,Bool}()
        v = -test_cost(x,mask)
        for r in outcomes(size(x.reports,3),length(ids))
            gain = zero(Exact)
            for o in eachindex(x.prior), s in axes(x.geology,2)
                prob = x.prior[o]*x.geology[o,s]
                for k in eachindex(ids); prob *= x.reports[ids[k],s,r[k]]; end
                gain += prob*x.payoff[o]
            end
            rule[r] = gain > 0
            v += max(zero(Exact),gain)
        end
        vals[mask] = v
        if isnothing(best) || v > best
            best = v; bestpolicy = OilPolicy(mask,rule)
        end
    end
    stats = SearchStats(evaluations=length(vals),evaluation_time=(time_ns()-start)/1e9)
    (result=SearchResult(best,bestpolicy,best,best,:optimal_exact,0.0,(time_ns()-start)/1e9,stats), values=vals)
end

export OilPolicy, OilEvaluator, operating_value, portfolio_value, optimal_oil_policy
export evaluate_policy, enumerate_oil
