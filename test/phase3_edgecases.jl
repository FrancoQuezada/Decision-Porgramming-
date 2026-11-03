@testset "Noisy observations, zero histories and unsupported consistency" begin
    for pattern in (:remember_action,:open_loop,:observed,:noisy),seed in (7,19)
        id=generate_maintenance_chain(2,seed;information=pattern,deterministic=true)
        r=chain_relaxation(id)
        @test structured_support(r).supported
        @test diagram_hash(id)==diagram_hash(generate_maintenance_chain(2,seed;information=pattern,deterministic=true))
        mktempdir() do dir
            @test diagram_hash(load_diagram(save_diagram(joinpath(dir,"id.toml"),id)))==diagram_hash(id)
        end
        ks=policy_keys(id);d=incremental_oracle(r);parent=nothing
        for choices in Iterators.product((0:id.nodes[k[1]].states for k in ks)...)
            p=PartialPolicy(Dict(ks[i]=>a for (i,a) in enumerate(choices) if a!=0))
            bound=evaluate_bound!(d,p;parent);parent=bound.snapshot
            @test bound.value==upper_bound(r,p)
            @test bound.value>=enumerate_policies(id,p).value
        end
        z=optimize_relaxed(d)
        @test evaluate_policy(r.relaxed,z.policy)==z.value
        @test all(z.policy.actions[k]==a for (k,a) in lift_fixings(r,PartialPolicy()).actions)
    end
    # A hidden variable matters through future policy fixings, although it is
    # absent from every future physical utility/kernel scope at D2.
    DPA=DecisionProgrammingAlgorithms
    nodes=DPA.AbstractIDNode[ChanceNode(:hidden,2,Int[],Exact[1//2,1//2]),
        DecisionNode(:first,2,Int[]),DecisionNode(:last,2,[1,2])]
    id=InfluenceDiagramInstance(nodes,[UtilityFactor([2,3],[1 0;0 1])])
    r=InformationRelaxation(id,Dict{Int,Vector{Int}}())
    p=PartialPolicy(Dict((3,(h,a))=>h for h in 1:2,a in 1:2))
    @test StructuredPlan(r).separators[2]==Int[]
    @test structured_support(r).missing[2]==[1]
    @test upper_bound(StructuredOracle(r),p)==1//2
    @test upper_bound(cached_oracle(r),p)==1//2
    @test upper_bound(incremental_oracle(r),p)==1//2
    visible=InformationRelaxation(id,Dict(2=>[1]))
    @test upper_bound(cached_oracle(visible),p)==1
    fixed=PartialPolicy(merge(p.actions,Dict((2,())=>1)))
    @test upper_bound(cached_oracle(visible),fixed)==1//2
    @test optimize_relaxed(cached_oracle(visible),fixed).value==1//2
    # Ordered information tuples, rather than unordered sets, index policy rows.
    id=maintenance_instance();ns=copy(id.nodes);ns[3]=DecisionNode(:operate,2,[2,1])
    r=InformationRelaxation(id,InfluenceDiagramInstance(ns,id.utilities))
    for a in 1:2
        p=PartialPolicy(Dict((3,(1,))=>a))
        @test optimize_relaxed(cached_oracle(r),p).value==upper_bound(r,p)
    end
    # Constant utilities, negative values and a final decision-dependent chance.
    id=InfluenceDiagramInstance(DPA.AbstractIDNode[DecisionNode(:d,2,Int[]),
        ChanceNode(:x,2,[1],Exact[1//3 2//3;3//4 1//4])],
        [UtilityFactor(Int[],fill(Exact(1//7),())),UtilityFactor([1,2],[-5 -1;-9 -4])])
    r=InformationRelaxation(id,Dict{Int,Vector{Int}}())
    @test upper_bound(cached_oracle(r))==upper_bound(r,PartialPolicy())<0
    @test optimize_relaxed(incremental_oracle(r)).value==enumerate_policies(id).value
    # A change in utilities alone must have a different exact model identity.
    base=chain_relaxation(generate_maintenance_chain(3,7))
    changed=InfluenceDiagramInstance(base.original.nodes,
        vcat(base.original.utilities,[UtilityFactor(Int[],fill(Exact(1),()))]))
    c=cached_oracle(base);upper_bound(c)
    z=cached_oracle(chain_relaxation(changed);cache=c.reuse.cache)
    @test context_key(c,PartialPolicy(),1,())!=context_key(z,PartialPolicy(),1,())
    @test upper_bound(z)==upper_bound(c)+1
    # Unsupported models retain the reference path and do not report cache reuse.
    hidden=chain_relaxation(generate_maintenance_chain(3,7);information=:none)
    for variant in (:B,:C,:D)
        z=solve_reuse_irbb(hidden;variant)
        @test z.result.value==solve_irbb(hidden).value
        @test z.oracle.stats.fallback_calls>0
        @test z.oracle.stats.cache_hits==z.oracle.stats.reused_messages==0
    end
    # Inherited pruning is exercised explicitly and never counted as an exact hit.
    id=InfluenceDiagramInstance([DecisionNode(:choose,3,Int[])],[UtilityFactor([1],[0,5,1])])
    r=InformationRelaxation(id,Dict{Int,Vector{Int}}())
    inherited=solve_reuse_irbb(r;variant=:D,inherit_bounds=true,trace=true)
    @test inherited.result.value==5
    @test inherited.inherited_prunes==2
    @test count(row->row.kind==:inherited,inherited.trace)==2
    @test inherited.oracle.stats.oracle_calls==2
end
