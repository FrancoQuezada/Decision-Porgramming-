# Source-derived Oil RDP adapters. External code is read at runtime, never edited.
using Base.Iterators: product
const PAPER_OIL_COMMIT="47d4a32716e9642fb1a04d67cce48204446d597b"
const PAPER_FUNCTIONS=Dict{Symbol,Function}()

paper_oil_path()=normpath(joinpath(@__DIR__,"..","..","external","Decision-Programming-new-formulation","oil","test_oil_DP.jl"))
function paper_oil_source()
    path=paper_oil_path();repo=dirname(dirname(path))
    readchomp(`git -C $repo rev-parse HEAD`)==PAPER_OIL_COMMIT || error("unexpected paper source commit")
    isempty(readchomp(`git -C $repo status --porcelain`)) || error("paper reference has local modifications")
    source=read(path,String)
    tree=Meta.parseall(source)
    definition=only(x for x in tree.args if x isa Expr && x.head==:function)
    source,definition
end

"""Keep singleton coordinates, rather than replacing them by dimension 1."""
paper_actual_indices(c)=CartesianIndices(Tuple(x isa Integer ? (x:x) : x for x in c))

function correct_paper_expression(e,counts;omit=nothing)
    e isa Expr || return e
    if e.head==:(=) && e.args[1]==:ST && omit!=:report_axis
        counts[:report_axis]+=1
        return :(ST=axes(T,4))
    elseif e.head==:(=) && e.args[1]==:PU && omit!=:coefficient_shape
        counts[:coefficient_shape]+=1
        # This is the original allocation with only its report dimensions fixed.
        return :(PU=zeros([2 for i in 1:No_tests]...,[length(ST) for i in 1:No_tests]...,2))
    elseif omit!=:drilling_axes && e.head==:(=) && e.args[1]==:c && e.args[2]==:( [Tuple(index)[1:end-1]...,[ST for i in 1:No_tests]...,Tuple(index)[end]] )
        counts[:drilling_axes]+=1
        return :(c=[[STI for i in 1:No_tests]...,Tuple(index)[1:end-1]...,Tuple(index)[end]])
    elseif omit!=:fixed_coordinates && e==:(CartesianIndices(Tuple(length.(c))))
        counts[:fixed_coordinates]+=1
        return :(paper_actual_indices(c))
    end
    Expr(e.head,(correct_paper_expression(x,counts;omit) for x in e.args)...)
end

function adapt_paper_solver(e)
    e isa Expr || return e
    if e.head==:(=) && e.args[1]==:optimizer
        return :(optimizer=runtime.optimizer)
    elseif e.head==:call && e.args[1]==:set_time_limit_sec
        return :(set_time_limit_sec($(e.args[2]),runtime.time_limit))
    elseif e.head==:call && e.args[1]==:optimize!
        return :(paper_optimize!(runtime,$(e.args[2])))
    elseif e.head==:return
        return :(return paper_extract(runtime,model2,y,z,z2,(dt2,dt1,dt8,dt5)))
    end
    Expr(e.head,(adapt_paper_solver(x) for x in e.args)...)
end

function strip_paper_plumbing(e)
    e isa LineNumberNode && return nothing
    e isa Expr || return e
    if e.head==:function
        signature=deepcopy(e.args[1]);signature.args[1]=:DP_model
        last(signature.args)==:runtime && pop!(signature.args)
        return Expr(:function,signature,strip_paper_plumbing(e.args[2]))
    elseif e.head==:(=) && e.args[1]==:optimizer
        return :(optimizer=SOLVER)
    elseif e.head==:call && e.args[1] in (:set_time_limit_sec,:optimize!,:paper_optimize!)
        return :SOLVER_CALL
    elseif e.head==:return
        return :RESULT_EXTRACTION
    end
    Expr(e.head,(strip_paper_plumbing(x) for x in e.args if !(x isa LineNumberNode))...)
end
function expression_fingerprint(e)
    bytes2hex(sha256(string(Base.remove_linenums!(deepcopy(e)))))
end

function derive_paper_model(version::Symbol)
    version in (:original,:corrected) || throw(ArgumentError("source version"))
    source,raw=paper_oil_source()
    raw=Base.remove_linenums!(deepcopy(raw))
    counts=Dict(k=>0 for k in (:report_axis,:coefficient_shape,:drilling_axes,:fixed_coordinates))
    math=version==:original ? deepcopy(raw) : correct_paper_expression(raw,counts)
    if version==:corrected
        counts[:report_axis]==counts[:coefficient_shape]==counts[:drilling_axes]==1 || error("source correction pattern changed: $counts")
        counts[:fixed_coordinates]==6 || error("source singleton-index patterns changed: $counts")
    end
    adapted=adapt_paper_solver(math)
    adapted.args[1].args[1]=Symbol("paper_oil_",version)
    push!(adapted.args[1].args,:runtime)
    @assert strip_paper_plumbing(math)==strip_paper_plumbing(adapted)
    (definition=adapted,raw_definition=raw,corrected_definition=math,counts=counts,
        source_sha256=bytes2hex(sha256(source)),
        mathematical_fingerprint=expression_fingerprint(strip_paper_plumbing(math)),
        source_mathematical_fingerprint=expression_fingerprint(strip_paper_plumbing(raw)))
end
function prepare_paper_models!()
    for version in (:original,:corrected)
        haskey(PAPER_FUNCTIONS,version) && continue
        derived=derive_paper_model(version)
        Core.eval(@__MODULE__,derived.definition)
        PAPER_FUNCTIONS[version]=getfield(@__MODULE__,Symbol("paper_oil_",version))
    end
    nothing
end

function paper_layout(x::OilInstance)
    m=ntests(x);ns=size(x.geology,2);nr=size(x.reports,3);no=length(x.prior)
    t=zeros(m,2,ns,nr+1);t[:,1,:,2:end]=Float64.(x.reports);t[:,2,:,1].=1
    v=zeros(2,m);v[1,:]=-Float64.(x.costs)
    u=zeros(no,2);u[:,1]=Float64.(x.payoff)
    shift=one(Exact)-min(zero(Exact),minimum(x.payoff))+sum(x.costs;init=zero(Exact))
    (O=Float64.(x.prior),S=Float64.(x.geology),T=t,V=v,U=u,scaler=Float64(shift))
end

function paper_model_size(x::OilInstance,version::Symbol)
    m=ntests(x);nr=version==:original ? size(x.geology,2) : size(x.reports,3)+1
    y=2*big(2*nr)^m;z=2*big(nr)^m+2*m
    # Original drilling groups repeat a report-sized block in the wrong axes.
    terms=version==:original ? 2*big(nr)^(2*m)+(m+1)*y : (m+2)*y
    (y=y,variables=y+z,estimated_matrix_terms=terms)
end

function paper_optimize!(runtime,model)
    remaining=max(0.001,runtime.time_limit-(time_ns()-runtime.start)/1e9-0.25)
    set_time_limit_sec(model,remaining)
    set_silent(model)
    optimize!(model)
end

function paper_onehot(values;tol=1e-6)
    all(v->isfinite(v) && abs(v-round(v))<=tol,values) || return 0
    active=findall(>(0.5),values)
    length(active)==1 ? only(active) : 0
end
function paper_policy(x,z,ztest)
    m=ntests(x);mask=UInt64(0);invalid_tests=0
    for i in 1:m
        a=paper_onehot([value(ztest[i,j]) for j in 1:2])
        invalid_tests+=a==0
        a==1 && (mask|=UInt64(1)<<(i-1))
    end
    invalid_chart=0
    for h in CartesianIndices(size(z)[1:m])
        paper_onehot([value(z[Tuple(h)...,a]) for a in 1:2])==0 && (invalid_chart+=1)
    end
    ids=selected_tests(x,mask);rule=Dict{Tuple,Bool}();missing_rows=0;invalid_rows=0
    for reports in outcomes(size(x.reports,3),length(ids))
        h=ones(Int,m)
        for (j,i) in enumerate(ids);h[i]=reports[j]+1;end
        if any(h[i]>size(z,i) for i in 1:m)
            missing_rows+=1;continue
        end
        a=paper_onehot([value(z[h...,j]) for j in 1:2])
        if a==0;invalid_rows+=1;continue;end
        rule[reports]=a==1
    end
    valid=invalid_tests==missing_rows==invalid_rows==0
    (policy=valid ? OilPolicy(mask,rule) : nothing,
        raw_invalid_test_rows=invalid_tests,raw_invalid_drilling_rows=invalid_chart,
        missing_reachable_rows=missing_rows,invalid_reachable_rows=invalid_rows)
end
paper_safe(f)=try f() catch; nothing end

function paper_extract(runtime,model,y,z,ztest,times)
    decode_start=time_ns();x=runtime.instance
    decoded=has_values(model) ? paper_policy(x,z,ztest) :
        (policy=nothing,raw_invalid_test_rows=nothing,raw_invalid_drilling_rows=nothing,
            missing_reachable_rows=nothing,invalid_reachable_rows=nothing)
    obj=has_values(model) ? objective_value(model)-runtime.input.scaler : nothing
    bound=paper_safe(()->objective_bound(model)-runtime.input.scaler)
    (nominal_value=obj,nominal_lower_bound=obj,nominal_upper_bound=bound,
        policy=decoded.policy,policy_diagnostics=decoded,
        status=termination_status(model),primal_status=primal_status(model),raw_status=raw_status(model),
        preprocessing_time=times[1],build_time=times[2],source_total_time=times[3],attach_time=times[4],
        solve_time=paper_safe(()->solve_time(model)),nodes=paper_safe(()->node_count(model)),
        variables=num_variables(model),constraints=num_constraints(model;count_variable_in_set_constraints=false),
        shift=runtime.input.scaler,policy_decoding_time=(time_ns()-decode_start)/1e9,
        solver=solver_name(model),solver_version=MOI.get(backend(model),MOI.SolverVersion()))
end

function solve_paper_rdp(x::OilInstance;version=:corrected,optimizer,
        time_limit=60.0,input=nothing)
    ntests(x)>0 || throw(ArgumentError("the paper adapter requires at least one test"))
    prepare_paper_models!()
    data=isnothing(input) ? paper_layout(x) : input
    if version==:original && size(data.T,4)<size(x.geology,2)
        throw(ArgumentError("original source indexes report states beyond the supplied axis"))
    end
    runtime=(optimizer=optimizer,instance=x,input=data,time_limit=Float64(time_limit),start=time_ns())
    Base.invokelatest(PAPER_FUNCTIONS[version],1:size(x.geology,2),1:length(x.prior),1:2,
        size(x.geology,2),ntests(x),data.scaler,data.O,data.S,data.T,data.V,data.U,runtime)
end
export derive_paper_model, prepare_paper_models!, paper_layout, paper_model_size, solve_paper_rdp
