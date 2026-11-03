using Test, DecisionProgrammingAlgorithms
import MathOptInterface as MOI
using Random

@testset "Input validation and exact instance persistence" begin
    x=generate_oil(3,26)
    @test instance_hash(x)==instance_hash(generate_oil(3,26))
    @test instance_hash(x)!=instance_hash(generate_oil(3,25))
    @test all(sum(x.geology;dims=2).==1)
    @test all(sum(x.reports;dims=3).==1)
    @test length(unique(x.geology[o,:] for o in axes(x.geology,1)))>1
    for i in 1:ntests(x)
        # Effective report distributions given O, not just conditional on S.
        effective=x.geology*x.reports[i,:,:]
        @test effective[1,:]!=effective[2,:]
    end
    mktempdir() do dir
        file=save_oil(joinpath(dir,"instance.toml"),x)
        @test instance_hash(load_oil(file))==instance_hash(x)
        z=generate_oil(0,1)
        @test instance_hash(load_oil(save_oil(joinpath(dir,"zero.toml"),z)))==instance_hash(z)
    end
    @test_throws ArgumentError OilInstance([0.5,0.5],[1.0 0;0 1.0],ones(1,2,1),[-1,1],[-1])
    @test_throws ArgumentError OilInstance([-0.1,1.1],[1.0 0;0 1.0],ones(1,2,1),[-1,1],[0])
    @test_throws ArgumentError OilInstance([0.4,0.4],[1.0 0;0 1.0],ones(1,2,1),[-1,1],[0])
    @test_throws DimensionMismatch OilInstance([0.5,0.5],ones(2,1),ones(1,2,1),[-1,1],[0])
    @test_throws ArgumentError generate_oil(2,1;accuracy=1.1)
    @test_throws ArgumentError ProbingNode(UInt64(1),UInt64(1))
    @test_throws ArgumentError operating_value(OilEvaluator(x),UInt64(8))
end

include("phase3_structured.jl")
include("phase3_cache.jl")
include("phase3_incremental.jl")
include("phase3_edgecases.jl")

@testset "Enumeration = probing IRBB = RDP on identical instances" begin
    for m in 0:4,seed in (1,11,26),kind in (:informative,:uninformative,:heterogeneous,:redundant)
        x=generate_oil(m,seed;kind)
        enumeration=enumerate_oil(x)
        bb=solve_probing(x)
        milp=solve_rdp(x)
        @test bb.status==:optimal_exact
        @test bb.value==enumeration.result.value==evaluate_policy(x,bb.policy)
        @test bb.upper_bound==bb.lower_bound
        @test milp.status==MOI.OPTIMAL
        @test isapprox(milp.value,Float64(bb.value);atol=1e-7,rtol=1e-9)
        @test isapprox(milp.value,Float64(milp.policy_value);atol=1e-7,rtol=1e-9)
        @test milp.policy_value==bb.value
        audit=validate_probing_bounds(x)
        @test audit.nodes==3^m
        e=OilEvaluator(x)
        for (mask,v) in enumeration.values
            @test portfolio_value(e,mask)==v
            @test evaluate_policy(x,optimal_oil_policy(e,mask))==v
        end
        if kind==:uninformative
            @test bb.policy.tests==0
            @test all(operating_value(e,mask)==operating_value(e,UInt64(0)) for mask in keys(enumeration.values))
        elseif kind==:redundant && m>1
            @test operating_value(e,UInt64(1))==operating_value(e,full_mask(x))
        end
    end
    for seed in (25,26)
        x=generate_oil(5,seed)
        @test enumerate_oil(x).result.value==solve_probing(x).value
        @test isapprox(solve_rdp(x).value,Float64(solve_probing(x).value);atol=1e-7)
        @test validate_probing_bounds(x).nodes==243
    end
end

@testset "All drilling policies, degenerate probabilities, cost and utility cases" begin
    for m in 0:2,seed in 1:3
        x=generate_oil(m,seed;states=2)
        e=OilEvaluator(x)
        for mask in UInt64(0):full_mask(x)
            histories=collect(DecisionProgrammingAlgorithms.outcomes(2,count_ones(mask)))[:]
            best=maximum(evaluate_policy(x,OilPolicy(mask,Dict(histories[k]=>actions[k] for k in eachindex(histories))))
                for actions in Iterators.product(ntuple(_ -> (false,true),length(histories))...))
            @test best==portfolio_value(e,mask)
        end
    end
    for costs in ([0,0],[0,1000],[1000,1000]), payoff in ([-1,-2],[-100,150])
        reports=zeros(2,2,2)
        reports[:,1,1].=1; reports[:,2,2].=1
        x=OilInstance([0.5,0.5],[1 0;0 1],reports,payoff,costs)
        a=solve_probing(x)
        @test a.value==enumerate_oil(x).result.value
        @test isapprox(solve_rdp(x).value,Float64(a.value);atol=1e-7)
        @test validate_probing_bounds(x).nodes==9
    end
    reports=zeros(1,2,3); reports[1,1,:]=[1-1e-14,1e-14,0];reports[1,2,:]=[0,1,0]
    x=OilInstance([0,1],[1 0;0 1],reports,[-100,100],[0])
    @test solve_probing(x).value==100
    @test solve_rdp(x).policy_value==100
    x=generate_oil(2,8;states=4,report_states=2,accuracy=[0.4,0.95])
    @test solve_probing(x).value==enumerate_oil(x).result.value==solve_rdp(x).policy_value
end

@testset "Non-probing partial policies, causal bounds and exact inference" begin
    for seed in 0:9
        id=maintenance_instance(;seed)
        relaxation=InformationRelaxation(id,Dict(3=>[2]))
        enum=enumerate_policies(id)
        bb=solve_irbb(relaxation)
        @test enum.evaluations==8
        @test bb.value==enum.value==evaluate_policy(id,bb.policy)
        @test validate_policy_bounds(relaxation).nodes==27
        @test upper_bound(relaxation,PartialPolicy())>=enum.value
        for z in let zs=Policy[]; foreach_policy(z -> push!(zs,z),id); zs end
            @test evaluate_policy(id,z)==evaluate_policy(id,z,VariableEliminationEvaluator([1,2,3]))
            @test evaluate_policy(id,z)==evaluate_policy(id,z,VariableEliminationEvaluator([3,2,1]))
            # Every complete original policy embeds with the same value.
            lifted=lift_fixings(relaxation,PartialPolicy(z.actions))
            @test enumerate_policies(relaxation.relaxed,lifted).value==evaluate_policy(id,z)
        end
        p=PartialPolicy(Dict((3,(1,))=>2))
        lifted=lift_fixings(relaxation,p)
        @test lifted.actions[(3,(1,1))]==2
        @test lifted.actions[(3,(1,2))]==2
        @test_throws ArgumentError InformationRelaxation(id,Dict(1=>[2]))
        @test_throws ArgumentError InformationRelaxation(id,Dict(2=>[1]))
        @test_throws ArgumentError enumerate_policies(id,PartialPolicy(Dict((3,(9,))=>1)))
        @test_throws ArgumentError evaluate_policy(id,Policy(Dict((1,())=>1)))
        @test_throws ArgumentError evaluate_policy(id,bb.policy,VariableEliminationEvaluator([1,1,3]))
        modified=maintenance_instance(;seed=100+seed)
        if modified.nodes[2].kernel!=id.nodes[2].kernel
            @test_throws ArgumentError InformationRelaxation(id,modified)
        end
    end
end

if isfile(DecisionProgrammingAlgorithms.paper_oil_path())
@testset "Pinned upstream source audit and independent package formulations" begin
    include(joinpath(@__DIR__,"..","scripts","OriginalSources.jl"))
    for m in 1:3
        d=OriginalSources.original_data(m,2025)
        @test all(d.S[o,:]==d.S[1,:] for o in 1:3)
        @test all(d.T[i,1,s,:]==d.T[1,1,1,:] for i in 1:m,s in 1:3)
        @test all(d.V[1,i]==d.V[1,1] for i in 1:m)
        x=OriginalSources.as_oil(d); e=OilEvaluator(x)
        @test all(operating_value(e,mask)==operating_value(e,UInt64(0)) for mask in UInt64(0):full_mask(x))
        @test solve_probing(x).policy.tests==0
    end
    for m in 1:2,seed in (11,26)
        x=generate_oil(m,seed)
        target=solve_probing(x).value
        for method in (:DP,:RJT)
            r=OriginalSources.package_solve(x,method)
            @test r.status==MOI.OPTIMAL
            @test r.policy_value==target
            @test abs(r.value-Float64(target))<=r.utility_rounding_bound+1e-7
        end
    end
    @test OriginalSources.original_rdp(OriginalSources.original_data(1,2025)).status==MOI.OPTIMAL
    # Agreement on degenerate upstream inputs must not mask source defects.
    informative=generate_oil(1,26)
    defective=OriginalSources.original_rdp(OriginalSources.original_layout(informative))
    @test !isapprox(defective.value,Float64(solve_probing(informative).value);atol=1e-7)
end
else
    @info "Optional upstream audit/package checks require scripts/setup_external.jl"
end

if all(isfile(joinpath(@__DIR__,"..","experiments","instances","prototype_m$(m)_s$(seed).toml"))
       for (m,seed) in ((4,26),(5,25)))
@testset "Supplied synthetic Python pilot inputs independently solved in Julia" begin
    for (m,seed,value,mask) in ((4,26,57.61204042999587,8),(5,25,39.179926121263264,2))
        x=load_oil(joinpath(@__DIR__,"..","experiments","instances","prototype_m$(m)_s$(seed).toml"))
        a=enumerate_oil(x).result;b=solve_probing(x);c=solve_rdp(x)
        @test a.value==b.value==c.policy_value
        @test isapprox(Float64(b.value),value;atol=1e-7)
        @test isapprox(c.value,value;atol=1e-7)
        @test b.policy.tests==mask
        @test validate_probing_bounds(x).nodes==3^m
    end
end
else
    @info "Optional historical pilot snapshots are local research inputs and are not bundled"
end

if isfile(DecisionProgrammingAlgorithms.paper_oil_path())
    include("phase4_paper.jl")
else
    @info "Source-derived Phase 4 tests require scripts/setup_external.jl (existing tests still run)"
end
