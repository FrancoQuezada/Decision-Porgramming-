# Source-derived model tests use the existing free solver in the root environment;
# the separate CPLEX integration test/campaign exercises the primary solver.
using HiGHS, JuMP
@testset "Pinned source transformation and minimally corrected RDP" begin
    original=derive_paper_model(:original);corrected=derive_paper_model(:corrected)
    @test original.mathematical_fingerprint==original.source_mathematical_fingerprint
    @test corrected.mathematical_fingerprint!=original.mathematical_fingerprint
    @test corrected.source_sha256==original.source_sha256
    @test corrected.counts==Dict(:report_axis=>1,:coefficient_shape=>1,:drilling_axes=>1,:fixed_coordinates=>6)
    DPA=DecisionProgrammingAlgorithms
    @test collect(DPA.paper_actual_indices([2,1:3,2]))==collect(CartesianIndices((2:2,1:3,2:2)))
    optimizer=optimizer_with_attributes(HiGHS.Optimizer,"threads"=>1,"mip_rel_gap"=>0.,"mip_abs_gap"=>1e-9)
    for m in 1:3,seed in (7,19),nr in (2,3)
        x=generate_oil(m,seed;report_states=nr)
        exact=enumerate_oil(x).result
        r=solve_paper_rdp(x;version=:corrected,optimizer,time_limit=30.)
        @test r.status==MOI.OPTIMAL
        @test r.policy!==nothing
        @test evaluate_policy(x,r.policy)==exact.value
        @test isapprox(r.nominal_value,Float64(exact.value);atol=1e-7,rtol=1e-9)
        @test r.variables==paper_model_size(x,:corrected).variables
        @test r.policy_diagnostics.raw_invalid_drilling_rows==0
    end
    x=generate_oil(1,7)
    a=solve_paper_rdp(x;version=:original,optimizer)
    @test !isapprox(a.nominal_value,Float64(solve_probing(x).value);atol=1e-7)
    @test a.policy===nothing || !isapprox(a.nominal_value,Float64(evaluate_policy(x,a.policy));atol=1e-7)
    # Every correction is needed: missing final result state, tensor allocation,
    # fixed integer coordinates, and correct ordering of test/report axes.
    @test original.counts==Dict(k=>0 for k in keys(corrected.counts))
    @test size(paper_layout(x).T,4)==size(x.reports,3)+1
    @test paper_model_size(x,:original).y==12
    @test paper_model_size(x,:corrected).y==16
    # Non-square state/report dimensions, exact zeros and utility accounting.
    x=generate_oil(2,7;states=4,report_states=2,kind=:redundant,
        costs=[1000.,1000.],drilling_cost=500.,rewards=[0.,100.,200.,300.])
    r=solve_paper_rdp(x;optimizer)
    @test isapprox(r.nominal_value,0.;atol=1e-7)
    @test evaluate_policy(x,r.policy)==0
end

@testset "Each source correction is necessary" begin
    DPA=DecisionProgrammingAlgorithms
    DPA.prepare_paper_models!()
    saved=DPA.PAPER_FUNCTIONS[:corrected]
    optimizer=optimizer_with_attributes(HiGHS.Optimizer,"threads"=>1,"mip_rel_gap"=>0.)
    x=generate_oil(1,7)
    target=Float64(solve_probing(x).value)
    try
        for omitted in (:report_axis,:coefficient_shape,:drilling_axes,:fixed_coordinates)
            _,raw=DPA.paper_oil_source()
            counts=Dict(k=>0 for k in (:report_axis,:coefficient_shape,:drilling_axes,:fixed_coordinates))
            partial=DPA.correct_paper_expression(Base.remove_linenums!(deepcopy(raw)),counts;omit=omitted)
            adapted=DPA.adapt_paper_solver(partial)
            adapted.args[1].args[1]=Symbol("ablation_",omitted);push!(adapted.args[1].args,:runtime)
            Core.eval(DPA,adapted)
            DPA.PAPER_FUNCTIONS[:corrected]=getfield(DPA,Symbol("ablation_",omitted))
            # Omitting shape/order corrections makes construction fail. Omitting
            # the report-axis/fixed-coordinate corrections loses physical EU.
            if omitted in (:coefficient_shape,:drilling_axes)
                @test_throws BoundsError solve_paper_rdp(x;optimizer)
            else
                r=solve_paper_rdp(x;optimizer)
                @test r.status!=MOI.OPTIMAL || !isapprox(r.nominal_value,target;atol=1e-7)
            end
        end
    finally
        DPA.PAPER_FUNCTIONS[:corrected]=saved
    end
end
