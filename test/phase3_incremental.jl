@testset "Incremental bounds, backtracking and identical exact searches" begin
    for seed in (7,19),pattern in (:remember_action,:open_loop)
        id=generate_maintenance_chain(3,seed;information=pattern)
        r=chain_relaxation(id);b=StructuredOracle(r);c=cached_oracle(r);d=incremental_oracle(r)
        ks=policy_keys(id)
        parent=nothing
        # Consecutive queries include additions, removals, changed actions and siblings.
        for choices in Iterators.product((0:id.nodes[k[1]].states for k in ks)...)
            p=PartialPolicy(Dict(ks[i]=>a for (i,a) in enumerate(choices) if a!=0))
            a=evaluate_bound!(d,p;parent)
            @test a.value==upper_bound(b,p)==upper_bound(c,p)==upper_bound(r,p)
            parent=a.snapshot
        end
        @test d.stats.reused_messages>0
        @test d.stats.invalidated_messages>0
        outcomes=[solve_reuse_irbb(r;variant,trace=true) for variant in (:B,:C,:D)]
        expected=enumerate_policies(id).value
        original=solve_irbb(r)
        @test all(out.result.value==expected==evaluate_policy(id,out.result.policy) for out in outcomes)
        @test all(out.result.stats.visited==original.stats.visited for out in outcomes)
        @test all(out.result.stats.pruned==original.stats.pruned for out in outcomes)
        @test outcomes[1].trace==outcomes[2].trace==outcomes[3].trace
        @test outcomes[2].oracle.stats.subproblems_solved<outcomes[1].oracle.stats.subproblems_solved
        @test outcomes[3].oracle.stats.reused_messages>0
        @test outcomes[3].oracle.stats.key_builds<outcomes[2].oracle.stats.key_builds
        for row in outcomes[3].trace
            p=PartialPolicy(Dict(ks[i]=>a for (i,a) in enumerate(row.fixings) if a!=0))
            @test row.bound==upper_bound(r,p)>=enumerate_policies(id,p).value
            @test row.pruned==(row.bound<=row.incumbent)
        end
        inherited=solve_reuse_irbb(r;variant=:D,inherit_bounds=true,trace=true)
        @test inherited.result.value==expected
        for row in inherited.trace
            p=PartialPolicy(Dict(ks[i]=>a for (i,a) in enumerate(row.fixings) if a!=0))
            @test row.bound>=upper_bound(r,p)
        end
    end
    r=chain_relaxation(generate_maintenance_chain(3,7));d=incremental_oracle(r)
    initial=evaluate_bound!(d)
    old=Dict(pos=>s.value for (pos,s) in initial.snapshot.messages)
    child=PartialPolicy(Dict((3,(1,))=>2))
    new=evaluate_bound!(d,child;parent=initial.snapshot)
    @test new.value==upper_bound(r,child)
    @test Dict(pos=>s.value for (pos,s) in initial.snapshot.messages)==old
    # Snapshots cannot cross physical or information boundaries.
    other=incremental_oracle(chain_relaxation(generate_maintenance_chain(3,19)))
    @test_throws ArgumentError evaluate_bound!(other,PartialPolicy();parent=initial.snapshot)
    other=incremental_oracle(chain_relaxation(r.original;information=:all_past))
    @test_throws ArgumentError evaluate_bound!(other,PartialPolicy();parent=initial.snapshot)
    # Clearing ordinary memoization does not invalidate exact unchanged messages.
    clear_cache!(d.reuse.memo.cache)
    @test evaluate_bound!(d,child;parent=new.snapshot).value==new.value
end
