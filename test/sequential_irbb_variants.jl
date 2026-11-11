const DPA=DecisionProgrammingAlgorithms

function sequential_test_completions(x)
    rows=sequential_policy_rows(x)
    [optimize_sequential_drilling(x,Dict{SequentialOilKey,Bool}(rows[j]=>actions[j]
        for j in eachindex(rows))) for actions in
        Iterators.product(ntuple(_ -> (false,true),length(rows))...)]
end

@testset "Sequential IR-B&B reachability canonicalization" begin
    x=adaptive_oil_witness()
    rows=sequential_policy_rows(x)
    p=PartialSequentialOilPolicy(Dict((1,())=>false,(2,(1,))=>true))
    @test reachable_sequential_rows(x,p)==[(1,()),(2,(0,))]
    q=canonical_sequential_policy(x,p)
    @test q.actions==Dict{SequentialOilKey,Bool}((1,())=>false)
    a=complete_sequential_testing(x,p;rows)
    b=copy(a); b[(2,(1,))]=false; b[(2,(2,))]=true
    @test physical_sequential_key(x,a)==physical_sequential_key(x,b)
    @test optimize_sequential_drilling(x,a).value==optimize_sequential_drilling(x,b).value

    completions=sequential_test_completions(x)
    classes=Dict{Any,Set{Exact}}()
    for completion in completions
        key=physical_sequential_key(x,completion.policy.testing)
        push!(get!(classes,key,Set{Exact}()),completion.value)
    end
    @test all(length(values)==1 for values in values(classes))
    @test length(classes)<length(completions)
    @test maximum(only(values) for values in values(classes))==solve_sequential_dp(x).value
end

@testset "Cost-aware sequential bounds on every small partial policy" begin
    cases=OilInstance[adaptive_oil_witness(),generate_oil(2,7;states=2),
        generate_oil(2,9;states=2,kind=:uninformative)]
    for x in cases
        rows=sequential_policy_rows(x); completions=sequential_test_completions(x)
        for assignment in Iterators.product(ntuple(_ -> -1:1,length(rows))...)
            p=PartialSequentialOilPolicy(Dict(rows[j]=>assignment[j]
                for j in eachindex(rows) if assignment[j]>=0))
            compatible=[c for c in completions if all(c.policy.testing[k]==a for (k,a) in p.actions)]
            target=maximum(c.value for c in compatible)
            for option in (:full_information,:legacy_nonsequential)
                result=sequential_cost_aware_bound(SequentialProbingBound(OilEvaluator(x),option),p)
                @test result.value>=target
                @test result.value<=result.primary
            end
            minimum_cost=minimum_sequential_testing_cost(x,p)
            @test minimum_cost>=0
        end
    end
end

@testset "Four sequential IR-B&B variants agree with exact DP" begin
    cases=OilInstance[adaptive_oil_witness(),generate_oil(1,4;states=2),
        generate_oil(2,7;states=2),generate_oil(2,9;states=2,kind=:redundant),
        generate_oil(2,9;states=2,kind=:uninformative)]
    for x in cases
        reference=solve_sequential_dp(x)
        for variant in SEQUENTIAL_IRBB_VARIANTS, option in (:full_information,:legacy_nonsequential)
            result=solve_sequential_probing(x;variant,bound=option,max_rows=100)
            @test result.status==:optimal_exact
            @test result.value==reference.value==evaluate_policy(x,result.policy)
            @test result.lower_bound==result.upper_bound
            @test result.stats.visited>=1
            @test result.stats.maximum_depth>=0
            @test result.stats.incumbent_updates>=1
            variant==:combined && @test result.stats.evaluation_cache_hits>=0
        end
    end
    @test_throws ArgumentError solve_sequential_probing(first(cases);variant=:unknown)
    @test_throws ArgumentError solve_sequential_probing(first(cases);variant=:combined,time_limit=0)
end

@testset "Exact root cost certificate" begin
    x=generate_oil(3,11;states=2,costs=fill(10_000,3))
    reference=solve_sequential_dp(x)
    for variant in (:cost_aware,:combined), option in (:full_information,:legacy_nonsequential)
        result=solve_sequential_probing(x;variant,bound=option,max_rows=100)
        @test result.status==:optimal_exact
        @test result.value==reference.value
        @test result.stats.visited==1
        @test result.stats.root_certificates==1
        @test result.stats.root_upper_bound==result.stats.root_lower_bound==result.value
    end
end
