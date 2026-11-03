@testset "Structured optimization: exact recurrence and support" begin
    for seed in 0:3
        id=maintenance_instance(;seed)
        r=InformationRelaxation(id,Dict(3=>[2]));o=StructuredOracle(r)
        @test o.plan.support.supported
        for choices in Iterators.product(ntuple(_->0:2,3)...)
            ks=policy_keys(id);p=PartialPolicy(Dict(ks[i]=>a for (i,a) in enumerate(choices) if a!=0))
            @test upper_bound(o,p)==upper_bound(r,p)
            z=optimize_relaxed(o,p)
            @test z.value==evaluate_policy(r.relaxed,z.policy)
            @test all(z.policy.actions[k]==a for (k,a) in lift_fixings(r,p).actions)
        end
        hidden=InformationRelaxation(id,Dict{Int,Vector{Int}}())
        @test !structured_support(hidden).supported
        fallback=StructuredOracle(hidden)
        @test evaluate_bound!(fallback).status==:enumeration_fallback
        @test upper_bound(fallback)==enumerate_policies(id).value
        @test_throws UnsupportedStructuredModel upper_bound(StructuredOracle(hidden;fallback=:error))
    end
    for pattern in (:remember_action,:open_loop),seed in (7,19)
        id=generate_maintenance_chain(3,seed;information=pattern)
        r=chain_relaxation(id);o=StructuredOracle(r)
        @test o.plan.support.supported
        ks=policy_keys(id)
        for choices in Iterators.product((0:id.nodes[k[1]].states for k in ks)...)
            p=PartialPolicy(Dict(ks[i]=>a for (i,a) in enumerate(choices) if a!=0))
            @test upper_bound(o,p)==upper_bound(r,p)
        end
        z=optimize_relaxed(o)
        @test evaluate_policy(r.relaxed,z.policy)==z.value
        @test o.stats.full_policy_evaluations==0
    end
end
