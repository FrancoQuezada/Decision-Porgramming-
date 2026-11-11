"""Runtime access to pinned upstream sources. No upstream code is redistributed here."""
module OriginalSources
using Random, JuMP, HiGHS
using Base.Iterators: product
using DecisionProgrammingAlgorithms
import DecisionProgramming
using SHA, TOML

const ROOT=dirname(@__DIR__)
const REF=joinpath(ROOT,"external","Decision-Programming-new-formulation")
const MODEL=Ref{Model}()
const EXPECTED="47d4a32716e9642fb1a04d67cce48204446d597b"

function verify_reference()
    readchomp(`git -C $REF rev-parse HEAD`)==EXPECTED || error("unexpected upstream commit")
    isempty(readchomp(`git -C $REF status --porcelain`)) || error("modified upstream reference")
end

function source_tree(name)
    verify_reference()
    Meta.parseall(read(joinpath(REF,"oil",name),String))
end

function original_data(m::Int,seed::Int)
    # Select the exact source expressions from O=zeros(...) through scaler=...
    # inside the p loop. No hand-written reconstruction of its RNG calls.
    tree=source_tree("test_oil_DP.jl")
    outer=only(x for x in tree.args if x isa Expr && x.head==:for)
    inner=only(x for x in outer.args[2].args if x isa Expr && x.head==:for)
    statements=inner.args[2].args
    assignment_to(x,name)=x isa Expr && x.head==:(=) && x.args[1]==name
    first=findfirst(x -> assignment_to(x,:O),statements)
    last=findfirst(x -> assignment_to(x,:scaler),statements)
    body=Expr(:block,statements[first:last]...,
        :((O=O,S=S,T=T,V=V,U=U,scaler=scaler,seed=seed,tests=No_tests)))
    # The isolated closure has only the original loop's required local inputs.
    f=Core.eval(@__MODULE__, :(function (No_tests, seed)
        No_states=3
        $body
    end))
    Base.invokelatest(f,m,seed)
end

function as_oil(d)
    OilInstance(d.O,d.S,d.T[:,1,:,2:end],d.U[:,1],-d.V[1,:];
        metadata=Dict("generator"=>"upstream-extracted", "seed"=>d.seed,
            "kind"=>"original", "source_commit"=>EXPECTED))
end

function original_layout(x::OilInstance)
    length(x.prior)==size(x.geology,2)==size(x.reports,3)==3 || error("original function assumes three states")
    m=ntests(x)
    t=zeros(m,2,3,4)
    t[:,1,:,2:end]=Float64.(x.reports)
    t[:,2,:,1].=1
    v=zeros(2,m);v[1,:]=-Float64.(x.costs)
    u=zeros(3,2);u[:,1]=Float64.(x.payoff)
    shift=Float64(1-min(0,minimum(x.payoff))+sum(x.costs))
    (O=Float64.(x.prior),S=Float64.(x.geology),T=t,V=v,U=u,scaler=shift,
        seed=x.metadata["seed"],tests=m)
end

function capture_original!(model)
    MODEL[]=model
    set_silent(model)
    optimize!(model)
end

function adapt_solver(expr)
    expr isa Expr || return expr
    # Solver plumbing only. All variable, coefficient and constraint expressions
    # remain exactly as parsed from the pinned original function.
    if expr.head==:(=) && expr.args[1]==:optimizer
        return :(optimizer=optimizer_with_attributes(HiGHS.Optimizer,
            "mip_rel_gap"=>0.0,"mip_abs_gap"=>1e-9,"threads"=>1,
            "mip_feasibility_tolerance"=>1e-9,"random_seed"=>0))
    elseif expr.head==:call && expr.args[1]==:optimize!
        return Expr(:call,:capture_original!,expr.args[2])
    end
    Expr(expr.head,map(adapt_solver,expr.args)...)
end

function original_rdp(d)
    tree=source_tree("test_oil_DP.jl")
    f=only(x for x in tree.args if x isa Expr && x.head==:function)
    Core.eval(@__MODULE__,adapt_solver(f))
    result=Base.invokelatest(DP_model,1:3,1:3,1:2,3,d.tests,d.scaler,d.O,d.S,d.T,d.V,d.U)
    model=MODEL[]
    (value=result[6]-d.scaler,shifted=result[6],shift=d.scaler,
        preprocessing_time=result[1],build_time=result[2],elapsed=result[3],
        solve_time=solve_time(model),variables=num_variables(model),
        constraints=num_constraints(model;count_variable_in_set_constraints=false),
        lower_bound=objective_value(model)-d.scaler,
        upper_bound=objective_bound(model)-d.scaler,status=termination_status(model))
end

# Shared constructor; audit options retain their original behavior.
package_diagram(x::OilInstance; kwargs...) = oil_diagram(x; kwargs...)

function package_solve(x,method; upstream_costs=false,rewards_offset=0)
    start=time_ns()
    diagram=package_diagram(x;upstream_costs,rewards_offset)
    model=Model(optimizer_with_attributes(HiGHS.Optimizer,"threads"=>1,
        "mip_rel_gap"=>0.0,"mip_abs_gap"=>1e-9,
        "mip_feasibility_tolerance"=>1e-9,"primal_feasibility_tolerance"=>1e-9,
        "dual_feasibility_tolerance"=>1e-9,"random_seed"=>0))
    set_silent(model); set_time_limit_sec(model,60.0)
    DP=DecisionProgramming
    z=DP.DecisionVariables(model,diagram;names=false)
    variables=method==:DP ? DP.PathCompatibilityVariables(model,diagram,z;names=false) : DP.RJTVariables(model,diagram,z;names=false)
    @objective(model,Max,DP.expected_value(model,diagram,variables))
    build=(time_ns()-start)/1e9
    optimize!(model)
    # DP path expected_value includes translation; RJT local objective does not.
    shift=rewards_offset+(method==:DP ? diagram.translation : 0)
    mask=UInt64(0)
    for i in 1:ntests(x);value(z["T$i"].z[1])>0.5 && (mask |= UInt64(1) << (i-1));end
    ids=selected_tests(x,mask);rule=Dict{Tuple,Bool}()
    for reports in DecisionProgrammingAlgorithms.outcomes(size(x.reports,3),length(ids))
        history=ones(Int,ntests(x))
        for (k,i) in enumerate(ids);history[i]=reports[k]+1;end
        rule[reports]=value(z["D"].z[history...,1])>0.5
    end
    policy=OilPolicy(mask,rule)
    physical=upstream_costs ? OilInstance(x.prior,x.geology,x.reports,x.payoff,zeros(ntests(x))) : x
    policy_value=evaluate_policy(physical,policy)
    # Measure the actual Float32 path-utility perturbation, rather than relaxing
    # the common-input comparison tolerance to hide a different numeric model.
    rounding=zero(Exact)
    names=collect(keys(diagram.S))
    for portfolio in UInt64(0):full_mask(x),o in eachindex(x.prior),d in 1:2
        path=ones(Int16,length(names))
        path[findfirst(==("O"),names)]=o
        path[findfirst(==("D"),names)]=d
        for i in 1:ntests(x)
            path[findfirst(==("T$i"),names)]=portfolio & (UInt64(1) << (i-1))!=0 ? 1 : 2
        end
        s=Tuple(path)
        used=method==:DP ? Float64(diagram.U(s,diagram.translation)) :
            sum(Float64(Y(s[I])) for (I,Y) in zip(diagram.U.I_v,diagram.U.Y))
        intended=(d==1 ? x.payoff[o] : zero(Exact))-test_cost(physical,portfolio)
        rounding=max(rounding,abs(DecisionProgrammingAlgorithms.exact(used)-DecisionProgrammingAlgorithms.exact(shift)-intended))
    end
    (value=objective_value(model)-shift,shifted=objective_value(model),shift=shift,
        policy=policy,policy_value=policy_value,utility_rounding_bound=Float64(rounding),
        build_time=build,solve_time=solve_time(model),elapsed=(time_ns()-start)/1e9,
        variables=num_variables(model),constraints=num_constraints(model;count_variable_in_set_constraints=false),
        lower_bound=objective_value(model)-shift,upper_bound=objective_bound(model)-shift,
        status=termination_status(model))
end
end
