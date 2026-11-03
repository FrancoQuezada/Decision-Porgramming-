struct CollidingContext
    value::Int
end
Base.hash(::CollidingContext,h::UInt)=hash(0,h)
Base.isequal(a::CollidingContext,b::CollidingContext)=a.value==b.value

@testset "Context keys, exact memoization and rejected reuse" begin
    for seed in (7,19),pattern in (:remember_action,:open_loop)
        id=generate_maintenance_chain(3,seed;information=pattern)
        r=chain_relaxation(id);b=StructuredOracle(r);c=cached_oracle(r)
        ks=policy_keys(id)
        for choices in Iterators.product((0:id.nodes[k[1]].states for k in ks)...)
            p=PartialPolicy(Dict(ks[i]=>a for (i,a) in enumerate(choices) if a!=0))
            @test upper_bound(c,p)==upper_bound(b,p)==upper_bound(r,p)
        end
        @test c.stats.cache_hits>0
        @test c.stats.subproblems_solved<b.stats.subproblems_solved
        z=optimize_relaxed(c)
        @test evaluate_policy(r.relaxed,z.policy)==upper_bound(r,PartialPolicy())
        @test cache_metrics(c.reuse.cache).unique_keys==c.stats.cache_misses
    end
    id=generate_maintenance_chain(3,7);r=chain_relaxation(id)
    c=cached_oracle(r)
    # After D1=2, a fixing of D2(D1=1) is irrelevant; after D1=1 it matters.
    p=PartialPolicy(Dict((3,(1,))=>2))
    @test context_key(c,PartialPolicy(),3,(2,1))==context_key(c,p,3,(2,1))
    @test context_key(c,PartialPolicy(),3,(1,1))!=context_key(c,p,3,(1,1))
    @test context_key(c,PartialPolicy(),2,(1,))!=context_key(c,PartialPolicy(),2,(2,))
    # A later separator has forgotten D1 and X1; a compatible old fixing drops out.
    old=PartialPolicy(Dict((1,())=>2))
    @test context_key(c,old,5,(2,1,1,1))==context_key(c,PartialPolicy(),5,(2,1,1,1))
    cache=c.reuse.cache
    original=upper_bound(c)
    count=length(cache.data)
    other=cached_oracle(chain_relaxation(generate_maintenance_chain(3,19));cache)
    @test upper_bound(other)==upper_bound(other.plan.relaxation,PartialPolicy())
    @test length(cache.data)>count
    count=length(cache.data)
    different=cached_oracle(chain_relaxation(id;information=:all_past);cache)
    @test upper_bound(different)==upper_bound(different.plan.relaxation,PartialPolicy())
    @test length(cache.data)>count
    @test context_key(c,PartialPolicy(),1,())!=context_key(different,PartialPolicy(),1,())
    # The oracle owns a private snapshot even if the caller mutates its arrays.
    id.nodes[2].kernel[1,:]=[1,0]
    @test upper_bound(c)==original
    # Equality must disambiguate real hash collisions.
    key=context_key(c,PartialPolicy(),1,())
    a=ContextKey(key.instance,key.relaxation,1,(CollidingContext(1),),())
    z=ContextKey(key.instance,key.relaxation,1,(CollidingContext(2),),())
    @test hash(a)==hash(z)
    @test !isequal(a,z)
    dict=Dict(a=>1,z=>2)
    @test length(dict)==2 && dict[a]==1 && dict[z]==2
    # Capacity affects work and storage, never the answer.
    for limit in (0,1,5)
        small=cached_oracle(r;cache=SubproblemCache(max_entries=limit))
        @test upper_bound(small)==upper_bound(r,PartialPolicy())
        @test cache_metrics(small.reuse.cache).peak_entries<=limit
        clear_cache!(small.reuse.cache)
        @test isempty(small.reuse.cache.data)
        @test upper_bound(small)==upper_bound(r,PartialPolicy())
    end
end
