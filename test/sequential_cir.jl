using Test, DecisionProgrammingAlgorithms, Random

function cir_witness(;zero_reports=false,costs=[1,3],payoff=[-10,12])
    r=Array{Exact}(undef,2,2,2)
    for i in 1:2
        r[i,:,:]=zero_reports ? [1 0;0 1] : [3//4 1//4;1//4 3//4]
    end
    OilInstance([1//2,1//2],[1 0;0 1],r,payoff,costs)
end

@testset "CIR exhaustive partial policies and bounds" begin
    for x in (cir_witness(),cir_witness(zero_reports=true),
            cir_witness(costs=[0,0]),cir_witness(payoff=[-3,-1]))
        rows=sequential_policy_rows(x)
        complete=[optimize_sequential_drilling(x,Dict(rows[j]=>a[j] for j in eachindex(rows)))
            for a in Iterators.product(ntuple(_->(false,true),length(rows))...)]
        for a in Iterators.product(ntuple(_->(-1,0,1),length(rows))...)
            p=PartialSequentialOilPolicy(Dict(rows[j]=>Bool(a[j]) for j in eachindex(rows) if a[j]>=0))
            ref=sequential_cir_reference(x,p)
            compatible=filter(c->all(c.policy.testing[k]==v for (k,v) in p.actions),complete)
            @test ref.upper>=maximum(c.value for c in compatible)
            @test ref.lower==optimize_sequential_drilling(x,complete_sequential_testing(x,p)).value
            @test ref.cost==minimum_sequential_testing_cost(x,p)
            @test ref.upper==sequential_cir_reference(x,canonical_sequential_policy(x,p)).upper
            for bound in (:full_information,:legacy_nonsequential)
                old=sequential_cost_aware_bound(SequentialProbingBound(OilEvaluator(x),bound),p)
                @test min(old.value,ref.upper)<=old.value
                @test min(old.value,ref.upper)>=maximum(c.value for c in compatible)
            end
            for key in rows
                haskey(p.actions,key) && continue
                for action in (false,true)
                    child=PartialSequentialOilPolicy(merge(p.actions,Dict(key=>action)))
                    @test sequential_cir_reference(x,child).upper<=ref.upper
                end
            end
            length(p.actions)==length(rows) && @test ref.upper==only(compatible).value
        end
    end
end

@testset "Incremental messages, siblings, removals, unions and rollback" begin
    rng=Xoshiro(491)
    for x in (cir_witness(),cir_witness(zero_reports=true),generate_oil(3,109;states=2)),
            mode in (:reference,:incremental,:cached)
        s=SequentialCIRState(x;mode)
        rows=sequential_policy_rows(x); actions=Dict{SequentialOilKey,Bool}()
        function check()
            ref=sequential_cir_reference(x,PartialSequentialOilPolicy(actions))
            @test all(s.messages[j]==ref.messages[s.keys[j]] for j in eachindex(s.keys))
        end
        check()
        for _ in 1:40
            checkpoint=cir_checkpoint(s); original=copy(actions)
            changes=Dict{SequentialOilKey,Union{Nothing,Bool}}()
            for key in rand(rng,rows,3)
                changes[key]=rand(rng,(nothing,false,true))
            end
            for (key,value) in changes
                value===nothing ? delete!(actions,key) : (actions[key]=value)
            end
            cir_update!(s,changes); check()
            canonical=canonical_sequential_policy(x,PartialSequentialOilPolicy(actions))
            removed=Dict(key=>nothing for key in keys(actions) if !haskey(canonical.actions,key))
            cir_update!(s,removed); actions=canonical.actions; check()
            cir_rollback!(s,checkpoint); actions=original; check()
        end
        # Every single row changes at most M message positions (three types).
        before=s.stats.messages_recomputed
        cir_update!(s,Dict((2,(1,))=>true))
        @test s.stats.messages_recomputed-before<=3*ntests(x)
        cir_rollback!(s,0)
        before=s.stats.cache_hits
        cir_update!(s,Dict((2,(1,))=>true))
        mode==:cached && @test s.stats.cache_hits>before
    end
end

@testset "Exact context equality, isolation and forced collisions" begin
    x=cir_witness()
    for collisions in (false,true)
        s=SequentialCIRState(x;force_cache_collisions=collisions)
        cir_update!(s,Dict((1,())=>false))
        root=s.messages[1]; signature=s.signature[1]
        hits=s.stats.cache_hits
        # Incompatible real-report restrictions do not affect root context.
        cir_update!(s,Dict((2,(1,))=>true))
        @test s.messages[1]==root && s.signature[1]==signature
        @test s.stats.cache_hits>=hits+3
        cir_update!(s,Dict((2,(0,))=>true))
        @test s.signature[1]!=signature
        @test s.messages[1][3]>root[3]
        ref=sequential_cir_reference(x,PartialSequentialOilPolicy(Dict(
            (1,())=>false,(2,(1,))=>true,(2,(0,))=>true)))
        @test s.messages[1]==(ref.upper,ref.lower,ref.cost)
        collisions && @test length(unique(k.digest for k in keys(s.cache)))==1
    end
    for changed in (cir_witness(zero_reports=true),cir_witness(costs=[7,8]),
            cir_witness(payoff=[-30,50]))
        a=SequentialCIRState(x); b=SequentialCIRState(changed)
        @test a.cache!==b.cache && a.intern!==b.intern
        ref=sequential_cir_reference(changed)
        @test b.messages[1]==(ref.upper,ref.lower,ref.cost)
    end
    s=SequentialCIRState(x); empty!(x.costs) # private snapshot survives caller mutation
    @test length(s.instance.costs)==2
    @test_throws ArgumentError SequentialCIRState(cir_witness();semantics=:other)
    @test_throws ArgumentError cir_update!(s,Dict((3,(0,0))=>true))
    @test_throws ArgumentError cir_update!(s,Dict((1,())=>2))
    # An unselected FREE alternative remains relevant to the exact context key.
    s=SequentialCIRState(cir_witness(costs=[0,100],payoff=[-3,-1]))
    signature=s.signature[1]; original=s.messages[1]
    cir_update!(s,Dict((2,(1,))=>true))
    @test s.messages[1]==original
    @test s.signature[1]!=signature
    for capacity in (0,1)
        s=SequentialCIRState(cir_witness();max_cache_entries=capacity)
        cir_update!(s,Dict((1,())=>true,(2,(1,))=>false))
        ref=sequential_cir_reference(s.instance,PartialSequentialOilPolicy(Dict((1,())=>true,(2,(1,))=>false)))
        @test s.messages[1]==(ref.upper,ref.lower,ref.cost)
        @test length(s.cache)<=capacity
    end
    # Regression: FREE TEST may activate a mandatory expensive downstream test.
    x=cir_witness(costs=[0,100]); p=PartialSequentialOilPolicy(Dict((2,(1,))=>true,(2,(2,))=>true))
    @test sequential_cir_reference(x,p).upper==13//4
    @test sequential_cir_reference(x,p).upper>
        sequential_cir_reference(x,PartialSequentialOilPolicy(merge(p.actions,Dict((1,())=>true)))).upper
end

@testset "CIR search equals independent exact DP" begin
    for x in (cir_witness(),cir_witness(zero_reports=true),generate_oil(3,71;states=2),
            generate_oil(0,2;states=2)), bound in (:full_information,:legacy_nonsequential),
            mode in (:reference,:incremental,:cached)
        result=solve_sequential_cir(x;bound,mode,max_rows=100)
        @test result.status==:optimal_exact
        @test result.value==solve_sequential_dp(x).value==evaluate_policy(x,result.policy)
        @test result.lower_bound==result.upper_bound
    end
    x=cir_witness()
    @test solve_sequential_probing(x;variant=:combined_cir).value==solve_sequential_dp(x).value
    @test_throws ArgumentError solve_sequential_cir(x;time_limit=0)
    interrupted=solve_sequential_cir(x;time_limit=eps(Float64))
    @test interrupted.status==:time_limit
    @test interrupted.lower_bound<=solve_sequential_dp(x).value<=interrupted.upper_bound
    @test interrupted.value==evaluate_policy(x,interrupted.policy)
end
