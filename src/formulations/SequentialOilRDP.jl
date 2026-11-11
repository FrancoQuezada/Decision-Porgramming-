"""Configure the free solver consistently; custom optimizer factories stay configurable."""
function configure_oil_optimizer!(model,optimizer,time_limit,silent)
    silent && set_silent(model)
    set_time_limit_sec(model,time_limit)
    if optimizer === HiGHS.Optimizer
        for (name,v) in (("threads",1),("mip_rel_gap",0.),("mip_abs_gap",1e-9),
                ("mip_feasibility_tolerance",1e-9),("random_seed",0))
            set_optimizer_attribute(model,name,v)
        end
    end
end

"""Build (8a)-(8f) with adaptive testing rows and the original causal kernels.

Default: availability-inconsistent segments are removed, as in solve_rdp.
dense=true retains all test-action/report combinations, including structural
zeros, for direct checks of the published dense model dimensions.
"""
function build_sequential_rdp(x::OilInstance; dense=false, optimizer=HiGHS.Optimizer,
        time_limit=60., max_segments=200_000, silent=true)
    start=time_ns(); m=ntests(x); nr=size(x.reports,3)
    2*big(nr+1)^m*(dense ? big(2)^m : 1)<=max_segments ||
        throw(ArgumentError("sequential RDP segment size guard"))
    histories=collect(Iterators.product(ntuple(_ -> 0:nr,m)...))[:]
    rows=sequential_policy_rows(x;max_rows=max_segments)
    segments=Tuple{Int,UInt64}[] # (full history index, test portfolio on that segment)
    for (k,h) in enumerate(histories)
        available=UInt64(0)
        for i in 1:m; h[i]>0 && (available |= UInt64(1)<<(i-1)); end
        for mask in (dense ? (UInt64(0):full_mask(x)) : (available,))
            push!(segments,(k,mask))
        end
    end
    shift=one(Exact)-min(zero(Exact),minimum(x.payoff))+sum(x.costs;init=zero(Exact))
    coeff=zeros(length(segments),2)
    for (j,(k,mask)) in enumerate(segments), d in 1:2
        h=histories[k]; eu=zero(Exact)
        for o in eachindex(x.prior), s in axes(x.geology,2)
            prob=x.prior[o]*x.geology[o,s]
            for i in 1:m
                run=mask & (UInt64(1)<<(i-1))!=0
                prob*=run ? (h[i]>0 ? x.reports[i,s,h[i]] : zero(Exact)) :
                    (h[i]==0 ? one(Exact) : zero(Exact))
            end
            eu+=prob*((d==2 ? x.payoff[o] : zero(Exact))-test_cost(x,mask)+shift)
        end
        coeff[j,d]=Float64(eu)
    end
    prep=(time_ns()-start)/1e9; buildstart=time_ns()
    model=Model(optimizer); configure_oil_optimizer!(model,optimizer,time_limit,silent)
    n=length(histories); l=length(segments)
    @variable(model,0<=y[1:l,1:2]<=1)
    @variable(model,ztest[1:length(rows),1:2],Bin) # skip, run
    @variable(model,zdrill[1:n,1:2],Bin) # no drill, drill
    @constraint(model,[j in eachindex(rows)],sum(ztest[j,a] for a in 1:2)==1)
    @constraint(model,[k in 1:n],sum(zdrill[k,d] for d in 1:2)==1)
    byhistory=[[j for j in 1:l if segments[j][1]==k] for k in 1:n]
    for k in 1:n, d in 1:2
        js=byhistory[k]
        @constraint(model,sum(y[j,d] for j in js)<=length(js)*zdrill[k,d])
    end
    for (q,(i,h)) in enumerate(rows), a in 1:2
        js=[j for (j,(k,mask)) in enumerate(segments)
            if histories[k][1:i-1]==h && (mask & (UInt64(1)<<(i-1))!=0)==(a==2)]
        @constraint(model,sum(y[j,d] for j in js,d in 1:2)<=length(js)*ztest[q,a])
    end
    for k in 1:n
        @constraint(model,sum(y[j,d] for j in byhistory[k],d in 1:2)<=1)
    end
    @objective(model,Max,sum(coeff[j,d]*y[j,d] for j in 1:l,d in 1:2))
    (model=model,ztest=ztest,zdrill=zdrill,rows=rows,histories=histories,
        shift=shift,preprocessing_time=prep,build_time=(time_ns()-buildstart)/1e9,
        observable_segments=2*l,policy_variables=2*length(rows)+2*n,
        coefficient_joint_terms=2*l*length(x.prior)*size(x.geology,2),dense=dense)
end

function oil_binary_action(row)
    v=value.(row)
    all(isfinite,v) && abs(sum(v)-1)<=1e-6 &&
        all(t -> min(abs(t),abs(t-1))<=1e-6,v) || error("invalid binary policy row")
    argmax(v)
end

function solve_sequential_rdp(x::OilInstance; total_time_limit=nothing, kwargs...)
    start=time_ns(); b=build_sequential_rdp(x;kwargs...); model=b.model
    oil_remaining_time_limit!(model,total_time_limit,start)
    optstart=time_ns(); optimize!(model); optimization=(time_ns()-optstart)/1e9
    diagnostics=oil_mip_diagnostics(model,b.shift)
    result=merge(diagnostics,(policy=nothing,policy_value=nothing,lower_bound=nothing,
        shift=Float64(b.shift),elapsed=(time_ns()-start)/1e9,
        preprocessing_time=b.preprocessing_time,build_time=b.build_time,solve_time=optimization,
        solver_time=solve_time(model),variables=num_variables(model),
        constraints=num_constraints(model;count_variable_in_set_constraints=false),
        policy_variables=b.policy_variables,observable_segments=b.observable_segments,
        coefficient_joint_terms=b.coefficient_joint_terms,dense=b.dense))
    diagnostics.has_solution || return result
    testing=Dict{SequentialOilKey,Bool}(key=>oil_binary_action(b.ztest[j,:])==2
        for (j,key) in enumerate(b.rows))
    drill=Dict{Tuple,Bool}(h=>oil_binary_action(b.zdrill[k,:])==2
        for (k,h) in enumerate(b.histories))
    policy=SequentialOilPolicy(testing,drill); physical=evaluate_policy(x,policy)
    merge(result,(policy=policy,policy_value=physical,lower_bound=Float64(physical),
        elapsed=(time_ns()-start)/1e9))
end

export build_sequential_rdp, solve_sequential_rdp
