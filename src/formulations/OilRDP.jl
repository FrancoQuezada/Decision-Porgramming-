"""HiGHS reference for (8a)-(8f), expected utility only.

Structural zeros are removed: each report tuple (including N/A=0) uniquely
determines the ex-ante test portfolio. Coefficients still sum over all O,S.
"""
function solve_rdp(x::OilInstance; optimizer=HiGHS.Optimizer, time_limit=60.0,
        max_segments=200_000, silent=true)
    m=ntests(x); nr=size(x.reports,3)
    2*big(nr+1)^m <= max_segments || throw(ArgumentError("RDP segment size guard"))
    start=time_ns()
    reports=collect(Iterators.product(ntuple(_ -> 0:nr,m)...))[:]
    n=length(reports)
    shift=one(Exact)-min(zero(Exact),minimum(x.payoff))+sum(x.costs; init=zero(Exact))
    coeff=zeros(n,2)
    masks=zeros(UInt64,n)
    prepstart=time_ns()
    for (k,r) in enumerate(reports)
        mask=UInt64(0)
        for i in 1:m; r[i]>0 && (mask |= UInt64(1) << (i-1)); end
        masks[k]=mask
        for d in 1:2
            eu=zero(Exact)
            for o in eachindex(x.prior), s in axes(x.geology,2)
                p=x.prior[o]*x.geology[o,s]
                for i in 1:m; r[i]>0 && (p *= x.reports[i,s,r[i]]); end
                u=(d==2 ? x.payoff[o] : zero(Exact))-test_cost(x,mask)+shift
                eu += p*u
            end
            coeff[k,d]=Float64(eu)
        end
    end
    preprocessing=(time_ns()-prepstart)/1e9
    buildstart=time_ns()
    model=Model(optimizer)
    silent && set_silent(model)
    set_time_limit_sec(model,time_limit)
    if optimizer === HiGHS.Optimizer
        set_optimizer_attribute(model,"threads",1)
        set_optimizer_attribute(model,"mip_rel_gap",0.0)
        set_optimizer_attribute(model,"mip_abs_gap",1e-9)
        set_optimizer_attribute(model,"mip_feasibility_tolerance",1e-9)
        set_optimizer_attribute(model,"random_seed",0)
    end
    @variable(model,0 <= y[1:n,1:2] <= 1)
    @variable(model,ztest[1:m,1:2],Bin) # 1=skip; 2=run
    @variable(model,zdrill[1:n,1:2],Bin) # 1=no drill; 2=drill
    @constraint(model,[i in 1:m],sum(ztest[i,a] for a in 1:2)==1)
    @constraint(model,[k in 1:n],sum(zdrill[k,d] for d in 1:2)==1)
    @constraint(model,[k in 1:n,d in 1:2],y[k,d] <= zdrill[k,d])
    for i in 1:m, a in 1:2
        ks=[k for k in 1:n if (reports[k][i]>0)==(a==2)]
        # At most one drilling action per report tuple can be active (8d).
        @constraint(model,sum(y[k,d] for k in ks,d in 1:2) <= length(ks)*ztest[i,a])
    end
    @constraint(model,[k in 1:n],sum(y[k,d] for d in 1:2)<=1)
    @objective(model,Max,sum(coeff[k,d]*y[k,d] for k in 1:n,d in 1:2))
    buildtime=(time_ns()-buildstart)/1e9
    solvestart=time_ns(); optimize!(model); optimization=(time_ns()-solvestart)/1e9
    status=termination_status(model)
    has_values(model) || error("RDP has no feasible solution: $status")
    mask=UInt64(0)
    for i in 1:m; value(ztest[i,2])>0.5 && (mask |= UInt64(1) << (i-1)); end
    ids=selected_tests(x,mask); rule=Dict{Tuple,Bool}()
    for k in 1:n
        if masks[k]==mask
            rule[Tuple(reports[k][i] for i in ids)]=value(zdrill[k,2])>0.5
        end
    end
    policy=OilPolicy(mask,rule)
    obj=objective_value(model)-Float64(shift)
    ub=objective_bound(model)-Float64(shift)
    physical=evaluate_policy(x,policy)
    (value=obj, policy=policy, policy_value=physical, lower_bound=Float64(physical),
        upper_bound=ub, status=status, shift=Float64(shift), elapsed=(time_ns()-start)/1e9,
        preprocessing_time=preprocessing, build_time=buildtime, solve_time=optimization,
        solver_time=solve_time(model), variables=num_variables(model),
        constraints=num_constraints(model; count_variable_in_set_constraints=false),
        policy_variables=2*m+2*n, observable_segments=2*n,
        coefficient_joint_terms=2*n*length(x.prior)*size(x.geology,2),
        solver=solver_name(model), solver_version=MOI.get(backend(model),MOI.SolverVersion()))
end
export solve_rdp
