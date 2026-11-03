"""Exact finite-state evaluation interface; implementations document their arithmetic."""
abstract type AbstractPolicyEvaluator end
abstract type AbstractUpperBoundOracle end

"""Times in seconds, measured with a monotonic clock. Counters are per solve."""
Base.@kwdef mutable struct SearchStats
    visited::Int = 0
    pruned::Int = 0
    expanded::Int = 0
    evaluations::Int = 0
    cache_hits::Int = 0
    bound_policy_evaluations::Int = 0
    evaluation_time::Float64 = 0.0
    bound_time::Float64 = 0.0
end

struct SearchResult{P,T<:Real}
    value::T
    policy::P
    lower_bound::T
    upper_bound::T
    status::Symbol
    tolerance::Float64
    elapsed::Float64
    stats::SearchStats
end

absolute_gap(r) = max(0.0, r.upper_bound - r.lower_bound)
relative_gap(r) = absolute_gap(r) / max(1.0, abs(r.lower_bound))
export AbstractPolicyEvaluator, AbstractUpperBoundOracle, SearchStats, SearchResult
export absolute_gap, relative_gap
