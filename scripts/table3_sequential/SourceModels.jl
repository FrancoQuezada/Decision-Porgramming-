# This file is included inside Table3Common. Mathematical AST remains unchanged.
const SOURCE_RDP_FUNCTION=Ref{Any}(nothing)
function source_solver_adapter(e)
    e isa Expr || return e
    if e.head==:(=) && e.args[1]==:optimizer
        return :(optimizer=runtime.optimizer)
    elseif e.head==:call && e.args[1]==:set_time_limit_sec
        return :(set_time_limit_sec($(e.args[2]),runtime.budget))
    elseif e.head==:call && e.args[1]==:optimize!
        return nothing # the experimental worker performs optimization separately
    elseif e.head==:return
        return :(return (model=model2,z=z,ztest=z2,preprocessing_time=dt2,
            build_time=dt1,source_construction_scope=dt8))
    end
    Expr(e.head,(source_solver_adapter(a) for a in e.args)...)
end

function source_rdp_model(x,optimizer,budget)
    Table3SourceGenerator.verify_source()
    if SOURCE_RDP_FUNCTION[]===nothing
        file=joinpath(Table3SourceGenerator.SOURCE,"oil_new_seq_Gurobi.jl")
        tree=Meta.parseall(read(file,String))
        f=only(e for e in tree.args if e isa Expr && e.head==:function)
        adapted=source_solver_adapter(deepcopy(f))
        adapted.args[1].args[1]=:_table3_source_rdp
        push!(adapted.args[1].args,:runtime)
        Core.eval(@__MODULE__,adapted)
        SOURCE_RDP_FUNCTION[]=getfield(@__MODULE__,:_table3_source_rdp)
    end
    d=paper_layout(x); offset=100+50*ntests(x)^2
    runtime=(optimizer=optimizer,budget=budget)
    b=Base.invokelatest(SOURCE_RDP_FUNCTION[],1:3,1:3,1:2,3,ntests(x),
        d.O,d.S,d.T,d.V,d.U .+ offset,runtime)
    merge(b,(shift=Float64(offset),))
end
