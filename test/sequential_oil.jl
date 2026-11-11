import JuMP
const SO=DecisionProgrammingAlgorithms

function adaptive_oil_witness()
    reports=Array{Rational{Int}}(undef,2,2,2)
    reports[1,:,:]=[4//5 1//5;1//5 4//5]
    reports[2,:,:]=[19//20 1//20;1//20 19//20]
    OilInstance([7//10,3//10],[1 0;0 1],reports,[-100,100],[1,8];
        metadata=Dict("kind"=>"adaptive-validation-witness-v1"))
end

function all_testing_completions(x)
    rows=sequential_policy_rows(x)
    [optimize_sequential_drilling(x,Dict{SequentialOilKey,Bool}(rows[j]=>a[j]
        for j in eachindex(rows))) for a in
        Iterators.product(ntuple(_ -> (false,true),length(rows))...)]
end

@testset "Sequential policies, conditional fixings and independent physical evaluation" begin
    x=adaptive_oil_witness(); rows=sequential_policy_rows(x)
    @test rows==[(1,()),(2,(0,)),(2,(1,)),(2,(2,))]
    p=PartialSequentialOilPolicy(Dict((2,(2,))=>1))
    completion=complete_sequential_testing(x,p)
    @test completion[(2,(2,))]
    @test !completion[(1,())] && !completion[(2,(1,))]
    @test sequential_global_sets(x,p)==(required=UInt64(0),forbidden=UInt64(0))
    for a in (false,true)
        q=PartialSequentialOilPolicy(Dict((2,h)=>a for h in ((0,),(1,),(2,))))
        sets=sequential_global_sets(x,q)
        @test (a ? sets.required : sets.forbidden)==2
    end
    @test_throws ArgumentError PartialSequentialOilPolicy(Dict((1,())=>2))
    @test_throws ArgumentError complete_sequential_testing(x,PartialSequentialOilPolicy(Dict((2,(3,))=>1)))
    @test_throws ArgumentError complete_sequential_testing(x,PartialSequentialOilPolicy(Dict((2,())=>1)))
    @test_throws ArgumentError optimize_sequential_drilling(x,Dict((1,())=>false))
    @test_throws ArgumentError solve_sequential_probing(x;bound=:dp)
    @test_throws ArgumentError solve_sequential_probing(x;max_rows=3)
    @test_throws ArgumentError solve_sequential_dp(x;max_histories=4)
    @test_throws ArgumentError build_sequential_rdp(x;max_segments=3)
    @test_throws ArgumentError solve_rjt(x;max_tests=1)
    @test_throws ArgumentError solve_rjt(x;max_policy_rows=2)
    for c in all_testing_completions(x)
        @test evaluate_policy(x,c.policy)==c.value
        # Exhaust every drilling action on every structurally reachable leaf.
        # Off-policy rows remain defined. This does not use the drilling max formula.
        histories=[h for h in keys(c.policy.drill) if all(
            c.policy.testing[(i,h[1:i-1])]==(h[i]>0) for i in 1:ntests(x))]
        best=maximum(begin
            rule=copy(c.policy.drill)
            for (k,h) in enumerate(histories); rule[h]=a[k]; end
            evaluate_policy(x,SequentialOilPolicy(c.policy.testing,rule))
        end for a in Iterators.product(ntuple(_ -> (false,true),length(histories))...))
        @test best==c.value
    end
    d=solve_sequential_dp(x)
    @test d.value==903//50
    @test solve_probing(x).value==17
    @test d.value>solve_probing(x).value
    @test d.policy.testing[(1,())]
    @test !d.policy.testing[(2,(1,))] && d.policy.testing[(2,(2,))]
    # A complete policy with no tests has a genuinely loose FI leaf bound.
    leaf=PartialSequentialOilPolicy(Dict(k=>false for k in rows))
    @test upper_bound(SequentialProbingBound(OilEvaluator(x),:full_information),leaf)>
        optimize_sequential_drilling(x,leaf.actions).value
end

@testset "Every partial testing policy: exhaustive completions and both bounds" begin
    cases=vec([generate_oil(m,seed;states=nr,report_states=nr)
        for m in 1:2,seed in (7,26),nr in (2,3)])
    append!(cases,[adaptive_oil_witness(),generate_oil(2,9;states=2,kind=:redundant),
        generate_oil(2,9;states=2,kind=:uninformative)])
    reports=zeros(Int,2,2,3); reports[:,1,1].=1; reports[:,2,2].=1
    push!(cases,OilInstance([0,1],[1 0;0 1],reports,[-100,150],[0,7]))
    push!(cases,OilInstance([1//2,1//2],[1 0;0 1],reports,[-100,150],[1000,1000]))
    for x in cases
        rows=sequential_policy_rows(x); completions=all_testing_completions(x)
        fi=SequentialProbingBound(OilEvaluator(x),:full_information)
        legacy=SequentialProbingBound(OilEvaluator(x),:legacy_nonsequential)
        for assignment in Iterators.product(ntuple(_ -> -1:1,length(rows))...)
            p=PartialSequentialOilPolicy(Dict(rows[j]=>assignment[j]
                for j in eachindex(rows) if assignment[j]>=0))
            compatible=[c for c in completions if all(c.policy.testing[k]==a for (k,a) in p.actions)]
            target=maximum(c.value for c in compatible)
            dp=solve_sequential_dp(x,p)
            @test dp.value==target==evaluate_policy(x,dp.policy)
            @test all(dp.policy.testing[k]==a for (k,a) in p.actions)
            completed=complete_sequential_testing(x,p)
            @test all(completed[k]==a for (k,a) in p.actions)
            @test upper_bound(fi,p)>=upper_bound(legacy,p)>=target
        end
    end
end

@testset "Sequential dense RDP dimensions, reduced equivalence and package kernels" begin
    for (m,nv,nc) in ((1,26,19),(2,170,79),(3,1194,319))
        x=generate_oil(m,7)
        b=build_sequential_rdp(x;dense=true)
        @test JuMP.num_variables(b.model)==nv
        @test JuMP.num_constraints(b.model;count_variable_in_set_constraints=false)==nc
        if isfile(SO.paper_oil_path())
            paper=solve_paper_rdp(x;optimizer=JuMP.optimizer_with_attributes(SO.HiGHS.Optimizer,"threads"=>1))
            @test (paper.variables,paper.constraints)==((26,19),(164,70),(1158,265))[m]
        end
        seq=solve_sequential_rdp(x;dense=true)
        reduced=solve_sequential_rdp(x)
        @test seq.status==reduced.status==MOI.OPTIMAL
        @test seq.policy_value==reduced.policy_value==solve_sequential_dp(x).value
        @test isapprox(seq.value,Float64(seq.policy_value);atol=1e-7,rtol=1e-9)
        @test reduced.variables<seq.variables
        a=oil_diagram(x); b=oil_diagram(x;sequential=true)
        @test a.X==b.X
        @test a.Y==b.Y
        for i in 1:m
            @test isempty(a.I_j["T$i"])
            @test b.I_j["T$i"]==["Tr$j" for j in 1:i-1]
        end
    end
end

@testset "Identical physical instances: nonseq/seq RDP, RJT, IRBB and exact DP" begin
    cases=OilInstance[adaptive_oil_witness()]
    for m in 0:2, seed in (7,26), kind in (:informative,:uninformative,:redundant,:heterogeneous)
        push!(cases,generate_oil(m,seed;states=2,kind))
    end
    # Three-stage binary-report B&B, with the intentionally loose FI bound.
    push!(cases,generate_oil(3,7;states=2))
    # Deterministic reports, unused report states, zero-probability oil, high/zero costs,
    # non-square state spaces, and always-negative drilling gain.
    reports=zeros(Int,2,2,3); reports[:,1,1].=1; reports[:,2,2].=1
    for prior in ([0,1],[1//2,1//2]), costs in ([0,0],[0,3],[1000,1000]),
            payoff in ([-100,150],[-5,-1])
        push!(cases,OilInstance(prior,[1 0;0 1],reports,payoff,costs))
    end
    for x in cases
        nonseq=solve_probing(x); dp=solve_sequential_dp(x)
        @test dp.value>=nonseq.value
        ntests(x)<=1 && @test dp.value==nonseq.value
        @test evaluate_policy(x,dp.policy)==dp.value
        for option in (:full_information,:legacy_nonsequential)
            b=solve_sequential_probing(x;bound=option)
            @test b.status==:optimal_exact
            @test b.value==b.lower_bound==b.upper_bound==dp.value==evaluate_policy(x,b.policy)
            @test b.stats.visited==2*b.stats.expanded+1
            @test b.stats.evaluations==b.stats.visited
            @test b.stats.pruned<=b.stats.visited-b.stats.expanded
            @test b.stats.cache_hits+b.stats.bound_policy_evaluations==b.stats.visited
        end
        for (solve,target) in ((solve_rdp,nonseq.value),(solve_rjt,nonseq.value),
                (solve_sequential_rdp,dp.value),(solve_sequential_rjt,dp.value))
            r=solve(x)
            @test r.status==MOI.OPTIMAL
            @test r.policy_value==target==evaluate_policy(x,r.policy)
            @test isapprox(r.value,Float64(target);atol=1e-7,rtol=1e-9)
        end
    end
end

@testset "Portable MILP diagnostics and optional full-procedure time limits" begin
    x=generate_oil(3,7;states=2)
    for method in (solve_sequential_rdp,solve_sequential_rjt)
        r=method(x;time_limit=60.,total_time_limit=1e-9)
        @test r.status in (MOI.TIME_LIMIT,MOI.OPTIMAL)
        @test hasproperty(r,:primal_status) && hasproperty(r,:raw_status)
        @test hasproperty(r,:mip_gap) && hasproperty(r,:shifted_upper_bound)
        if !r.has_solution
            @test r.policy===nothing && r.policy_value===nothing
            @test r.value===nothing && r.lower_bound===nothing
        else
            @test isapprox(r.value,Float64(evaluate_policy(x,r.policy));atol=1e-7,rtol=1e-9)
        end
    end
    @test_throws ArgumentError solve_sequential_rdp(x;total_time_limit=-1.)
    @test_throws ArgumentError solve_sequential_rjt(x;total_time_limit=Inf)
end
