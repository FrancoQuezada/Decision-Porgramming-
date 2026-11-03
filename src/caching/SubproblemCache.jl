Base.@kwdef mutable struct CacheStats
    hits::Int=0
    misses::Int=0
    insertions::Int=0
    evictions::Int=0
    peak_entries::Int=0
end
mutable struct SubproblemCache
    data::Dict{ContextKey,MessageSolution}
    seen::Union{Nothing,Set{ContextKey}}
    order::Vector{ContextKey}
    max_entries::Union{Nothing,Int}
    stats::CacheStats
end
function SubproblemCache(;max_entries=nothing,track_unique=true)
    isnothing(max_entries) || max_entries>=0 || throw(ArgumentError("negative cache capacity"))
    SubproblemCache(Dict{ContextKey,MessageSolution}(),track_unique ? Set{ContextKey}() : nothing,
        ContextKey[],max_entries,CacheStats())
end
function cache_lookup!(cache::SubproblemCache,key::ContextKey)
    isnothing(cache.seen) || push!(cache.seen,key)
    if haskey(cache.data,key)
        cache.stats.hits+=1
        return cache.data[key]
    end
    cache.stats.misses+=1
    nothing
end
function cache_insert!(cache::SubproblemCache,key::ContextKey,solution::MessageSolution)
    cache.max_entries===0 && return
    if haskey(cache.data,key);cache.data[key]=solution;return;end
    if !isnothing(cache.max_entries)
        if length(cache.data)>=cache.max_entries
            delete!(cache.data,popfirst!(cache.order));cache.stats.evictions+=1
        end
        push!(cache.order,key)
    end
    cache.data[key]=solution;cache.stats.insertions+=1
    cache.stats.peak_entries=max(cache.stats.peak_entries,length(cache.data))
    nothing
end
function clear_cache!(cache::SubproblemCache)
    empty!(cache.data);empty!(cache.order)
    isnothing(cache.seen) || empty!(cache.seen)
    cache.stats=CacheStats()
    cache
end
function cache_metrics(cache::SubproblemCache)
    calls=cache.stats.hits+cache.stats.misses
    (hits=cache.stats.hits,misses=cache.stats.misses,
        hit_ratio=calls==0 ? 0.0 : cache.stats.hits/calls,
        entries=length(cache.data),unique_keys=isnothing(cache.seen) ? nothing : length(cache.seen),
        peak_entries=cache.stats.peak_entries,evictions=cache.stats.evictions,
        memory_bytes=Base.summarysize(cache),entry_memory_bytes=Base.summarysize(cache.data))
end

struct MemoizedReuse
    cache::SubproblemCache
    identity::ModelIdentity
    information::Tuple
end
struct CachedWorkspace
    reuse::MemoizedReuse
    pending::Vector{Union{Nothing,ContextKey}}
end
function cached_oracle(r::InformationRelaxation;cache=SubproblemCache(),fallback=:enumeration,max_policies=1_000_000)
    fallback in (:enumeration,:error) || throw(ArgumentError("fallback"))
    plan=StructuredPlan(r)
    reuse=MemoizedReuse(cache,model_identity(plan),relaxation_identity(plan))
    StructuredOracle(plan,reuse,StructuredStats(),fallback,max_policies)
end
function _prepare_reuse(reuse::MemoizedReuse,plan,p,parent,stats)
    CachedWorkspace(reuse,Union{Nothing,ContextKey}[nothing for _ in plan.separators])
end
function _read_message!(c::CachedWorkspace,w,k,assignment)
    t=time_ns()
    key=make_context_key(w.plan,c.reuse.identity,c.reuse.information,w.fixings,k,assignment)
    w.stats.key_time+=(time_ns()-t)/1e9;w.stats.key_builds+=1
    solution=cache_lookup!(c.reuse.cache,key)
    if isnothing(solution)
        w.stats.cache_misses+=1;c.pending[k]=key
    else
        w.stats.cache_hits+=1
    end
    solution
end
function _save_message!(c::CachedWorkspace,w,k,assignment,solution)
    key=c.pending[k]
    isnothing(key) && error("missing pending cache key")
    cache_insert!(c.reuse.cache,key,solution);c.pending[k]=nothing
    nothing
end
_snapshot(::CachedWorkspace,plan,p)=nothing

export CacheStats, SubproblemCache, clear_cache!, cache_metrics, cached_oracle
