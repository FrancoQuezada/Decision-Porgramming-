"""Independent nonincremental CIR recurrence, including all history messages.

Uses joint (O,S) propagation rather than the incremental sufficient statistics.
FREE tests have zero cost, but retain both SKIP and TEST alternatives.
"""
function sequential_cir_reference(x::OilInstance, p=PartialSequentialOilPolicy())
    validate_sequential_testing(x,p.actions)
    messages=Dict{SequentialOilKey,NTuple{3,Exact}}()
    function visit(i,h,q)
        if i>ntests(x)
            v=max(zero(Exact),sum(q[o,s]*x.payoff[o]
                for o in eachindex(x.prior),s in axes(x.geology,2)))
            messages[(i,h)]=(v,v,zero(Exact))
        else
            skip=visit(i+1,(h...,0),q)
            tests=[visit(i+1,(h...,r),q .* permutedims(x.reports[i,:,r]))
                for r in axes(x.reports,3)]
            u=sum(t[1] for t in tests); l=sum(t[2] for t in tests)
            c=sum(t[3] for t in tests); fee=x.costs[i]*sum(q)
            a=get(p.actions,(i,h),nothing)
            messages[(i,h)]=a===false ? skip : a===true ? (u-fee,l-fee,c+fee) :
                (max(skip[1],u),skip[2],min(skip[3],c+fee))
        end
        messages[(i,h)]
    end
    q=[x.prior[o]*x.geology[o,s] for o in eachindex(x.prior),s in axes(x.geology,2)]
    root=visit(1,(),q)
    (upper=root[1],lower=root[2],cost=root[3],messages=messages)
end

Base.@kwdef mutable struct CIRStats
    bound_evaluations::Int=0
    messages_recomputed::Int=0
    messages_reused::Int=0
    cache_hits::Int=0
    cache_misses::Int=0
    peak_cache_entries::Int=0
    cache_bytes::Int=0
    arithmetic_operations::Int=0
    update_time::Float64=0.0
    lookup_time::Float64=0.0
    rollback_time::Float64=0.0
    key_time::Float64=0.0
    physical_evaluations_avoided::Int=0
    pruned_by_cir::Int=0
end

struct CIRMessageKey
    content::Tuple{Symbol,Int,Int,Symbol}
    digest::UInt
end
Base.hash(k::CIRMessageKey,h::UInt)=hash(k.digest,h)
Base.isequal(a::CIRMessageKey,b::CIRMessageKey)=a.digest==b.digest && isequal(a.content,b.content)
Base.:(==)(a::CIRMessageKey,b::CIRMessageKey)=isequal(a,b)

"""Solve-local exact continuation cache. Immutable integer signatures are interned
by full tuple equality, never by hash alone. A state owns a private model copy.
"""
mutable struct SequentialCIRState
    instance::OilInstance
    keys::Vector{SequentialOilKey}
    index::Dict{SequentialOilKey,Int}
    parent::Vector{Int}
    children::Vector{Vector{Int}}
    fee::Vector{Exact}
    terminal::Vector{Exact}
    status::Vector{Int8}
    messages::Vector{NTuple{3,Exact}}
    signature::Vector{Int}
    intern::Dict{Any,Int}
    cache::Dict{CIRMessageKey,Exact}
    undo::Vector{Any}
    mode::Symbol
    semantics::Symbol
    max_cache_entries::Int
    force_cache_collisions::Bool
    stats::CIRStats
end

function cir_recompute!(s::SequentialCIRState,j)
    ch=s.children[j]
    isempty(ch) && return
    t=time_ns(); a=s.status[j]
    # Fixed actions exclude only structurally incompatible continuations.
    relevant=a==0 ? (s.signature[ch[1]],) : a==1 ? Tuple(s.signature[k] for k in ch[2:end]) :
        Tuple(s.signature[k] for k in ch)
    description=(j,a,relevant)
    sig=get!(s.intern,description) do; length(s.intern)+1; end
    s.signature[j]=sig
    s.stats.key_time+=(time_ns()-t)/1e9
    values=Exact[]
    for (v,kind) in enumerate((:U,:L,:C))
        kt=time_ns(); content=(s.semantics,j,sig,kind)
        key=CIRMessageKey(content,s.force_cache_collisions ? UInt(0) : hash(content))
        s.stats.key_time+=(time_ns()-kt)/1e9
        t=time_ns(); hit=s.mode==:cached && haskey(s.cache,key)
        value=hit ? s.cache[key] : nothing
        s.stats.lookup_time+=(time_ns()-t)/1e9
        if hit
            s.stats.cache_hits+=1
        else
            s.stats.cache_misses+=(s.mode==:cached)
            skip=s.messages[ch[1]][v]
            test=sum(s.messages[k][v] for k in ch[2:end])
            s.stats.arithmetic_operations+=length(ch)-2
            value=if v==1
                a==0 ? skip : a==1 ? test-s.fee[j] : max(skip,test)
            elseif v==2
                a==1 ? test-s.fee[j] : skip
            else
                a==0 ? skip : a==1 ? test+s.fee[j] : min(skip,test+s.fee[j])
            end
            s.stats.arithmetic_operations+=2
            s.stats.messages_recomputed+=1
            if s.mode==:cached && s.max_cache_entries>0
                # Bounded dictionary; clearing affects speed only. Interned keys
                # remain valid and are accounted for in retained memory.
                length(s.cache)>=s.max_cache_entries && empty!(s.cache)
                s.cache[key]=value
                s.stats.peak_cache_entries=max(s.stats.peak_cache_entries,length(s.cache))
            end
        end
        push!(values,value)
    end
    s.messages[j]=(values...,)
end

function SequentialCIRState(x::OilInstance;mode=:cached,semantics=:cir_v1,
        max_cache_entries=100_000,force_cache_collisions=false)
    mode in (:reference,:incremental,:cached) || throw(ArgumentError("CIR mode"))
    semantics==:cir_v1 || throw(ArgumentError("unsupported CIR semantics"))
    max_cache_entries>=0 || throw(ArgumentError("negative cache capacity"))
    x=deepcopy(x) # No foreign model can read or mutate this solve's cache.
    keys=SequentialOilKey[]; parent=Int[]; children=Vector{Int}[]
    fee=Exact[]; terminal=Exact[]
    alpha=[sum(x.prior[o]*x.geology[o,k]*x.payoff[o] for o in eachindex(x.prior))
        for k in axes(x.geology,2)]
    beta=[sum(x.prior[o]*x.geology[o,k] for o in eachindex(x.prior))
        for k in axes(x.geology,2)]
    function build(i,h,likelihood,par)
        push!(keys,(i,h)); j=length(keys); push!(parent,par); push!(children,Int[])
        push!(fee,i<=ntests(x) ? x.costs[i]*sum(beta .* likelihood) : zero(Exact))
        push!(terminal,max(zero(Exact),sum(alpha .* likelihood)))
        if i<=ntests(x)
            push!(children[j],build(i+1,(h...,0),likelihood,j))
            for r in axes(x.reports,3)
                push!(children[j],build(i+1,(h...,r),likelihood .* x.reports[i,:,r],j))
            end
        end
        j
    end
    build(1,(),ones(Exact,length(beta)),0)
    n=length(keys)
    s=SequentialCIRState(x,keys,Dict(k=>j for (j,k) in enumerate(keys)),parent,children,
        fee,terminal,fill(Int8(-1),n),[(v,v,zero(Exact)) for v in terminal],zeros(Int,n),
        Dict{Any,Int}(),Dict{CIRMessageKey,Exact}(),Any[],mode,semantics,
        max_cache_entries,force_cache_collisions,CIRStats())
    for j in n:-1:1; cir_recompute!(s,j); end
    s
end

cir_checkpoint(s::SequentialCIRState)=length(s.undo)

"""Apply simultaneous row additions/removals/changes; nothing denotes FREE.
Only the union of changed rows' ancestor paths is recomputed.
"""
function cir_update!(s::SequentialCIRState,changes::AbstractDict)
    for (key,a) in changes
        haskey(s.index,key) && key[1]<=ntests(s.instance) || throw(ArgumentError("invalid CIR row"))
        (a===nothing || a isa Bool) || throw(ArgumentError("CIR action must be Bool or nothing"))
    end
    t=time_ns(); affected=Set{Int}()
    for (key,a) in changes
        j=s.index[key]; status=a===nothing ? Int8(-1) : Int8(a)
        s.status[j]==status && continue
        push!(s.undo,(:status,j,s.status[j])); s.status[j]=status
        while j!=0; push!(affected,j); j=s.parent[j]; end
    end
    for j in sort!(collect(affected);rev=true)
        push!(s.undo,(:message,j,s.messages[j],s.signature[j]))
        cir_recompute!(s,j)
    end
    # Counts preserved positions, not dictionary lookups. Terminals included.
    s.stats.messages_reused+=3*(length(s.keys)-length(affected))
    s.stats.update_time+=(time_ns()-t)/1e9
    if s.mode==:reference
        p=PartialSequentialOilPolicy(Dict(s.keys[j]=>Bool(a) for (j,a) in enumerate(s.status)
            if a>=0))
        ref=sequential_cir_reference(s.instance,p)
        for j in eachindex(s.keys); s.messages[j]=ref.messages[s.keys[j]]; end
    end
    s.messages[1]
end

function cir_rollback!(s::SequentialCIRState,checkpoint::Int)
    0<=checkpoint<=length(s.undo) || throw(ArgumentError("invalid CIR checkpoint"))
    t=time_ns()
    while length(s.undo)>checkpoint
        entry=pop!(s.undo); j=entry[2]
        if entry[1]==:status
            s.status[j]=entry[3]
        else
            s.messages[j]=entry[3]; s.signature[j]=entry[4]
        end
    end
    s.stats.rollback_time+=(time_ns()-t)/1e9
    s.messages[1]
end

function solve_sequential_cir(x::OilInstance;bound=:full_information,max_rows=24,
        progress_every=0,progress_io=stderr,time_limit=Inf,mode=:cached)
    (time_limit>0 && !isnan(time_limit)) || throw(ArgumentError("positive time limit required"))
    start=time_ns(); rows=sequential_policy_rows(x;max_rows)
    stats=SearchStats(cir=CIRStats()); e=OilEvaluator(x); primary=SequentialProbingBound(e,bound)
    candidate=optimize_sequential_drilling(x,Dict(k=>false for k in rows))
    best=candidate.value; bestpolicy=candidate.policy; stats.evaluations=1; stats.incumbent_updates=1
    full=operating_value(e,full_mask(x))
    nontrivial=ntests(x)==0 ? best : full-minimum(x.costs)
    stats.root_lower_bound=best; stats.root_upper_bound=max(best,nontrivial)
    if nontrivial<=best
        stats.visited=1; stats.pruned=1; stats.root_certificates=1; stats.pruned_by_cost_bound=1
        return SearchResult(best,bestpolicy,best,best,:optimal_exact,0.,(time_ns()-start)/1e9,stats)
    end
    t=time_ns(); s=SequentialCIRState(x;mode); stats.cir=s.stats
    stats.bound_time+=(time_ns()-t)/1e9
    interrupted=false
    function dfs(depth)
        if (time_ns()-start)/1e9>=time_limit; interrupted=true; return; end
        stats.visited+=1; stats.maximum_depth=max(stats.maximum_depth,depth)
        stats.maximum_stack_size=max(stats.maximum_stack_size,depth+1)
        p=PartialSequentialOilPolicy(Dict(s.keys[j]=>Bool(a) for (j,a) in enumerate(s.status) if a>=0))
        p=canonical_sequential_policy(x,p)
        reachable=reachable_sequential_rows(x,p)
        stats.unreachable_decisions_eliminated+=length(rows)-length(reachable)
        lower=s.messages[1][2]
        if lower>best
            t=time_ns(); testing=complete_sequential_testing(x,p;rows)
            c=optimize_sequential_drilling(x,testing)
            physical=evaluate_policy(x,c.policy)
            physical==c.value==lower || error("CIR incremental incumbent mismatch")
            best=lower; bestpolicy=c.policy; stats.incumbent_updates+=1; stats.evaluations+=1
            stats.evaluation_time+=(time_ns()-t)/1e9
        else
            s.stats.physical_evaluations_avoided+=1
        end
        t=time_ns(); ubprimary=upper_bound(primary,p); ubcost=full-s.messages[1][3]
        ubcir=s.messages[1][1]; ub=min(ubprimary,ubcost,ubcir)
        stats.bound_evaluations+=1; s.stats.bound_evaluations+=1
        stats.bound_time+=(time_ns()-t)/1e9
        depth==0 && (stats.root_upper_bound=ub)
        progress_every>0 && stats.visited%progress_every==0 &&
            report_sequential_progress(progress_io,:combined_cir,stats,depth,best,ub,start)
        if ub<=best
            stats.pruned+=1
            if ubprimary<=best; stats.pruned_by_primary_bound+=1
            elseif ubcost<=best; stats.pruned_by_cost_bound+=1
            else; s.stats.pruned_by_cir+=1; end
            return
        end
        k=findfirst(key->!haskey(p.actions,key),reachable)
        isnothing(k) && return
        stats.expanded+=1; key=reachable[k]
        for action in (false,true)
            checkpoint=cir_checkpoint(s)
            t=time_ns(); cir_update!(s,Dict(key=>action)); stats.bound_time+=(time_ns()-t)/1e9
            dfs(depth+1)
            cir_rollback!(s,checkpoint)
            interrupted && return
        end
    end
    dfs(0)
    stats.cir.cache_bytes=Base.summarysize(s.cache)+Base.summarysize(s.intern)
    stats.cache_hits=e.stats.cache_hits+s.stats.cache_hits
    stats.bound_policy_evaluations=e.stats.evaluations
    SearchResult(best,bestpolicy,best,interrupted ? stats.root_upper_bound : best,
        interrupted ? :time_limit : :optimal_exact,0.,(time_ns()-start)/1e9,stats)
end

export sequential_cir_reference, CIRStats, SequentialCIRState
export cir_checkpoint, cir_update!, cir_rollback!, solve_sequential_cir
