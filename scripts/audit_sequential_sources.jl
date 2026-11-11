"""Inspect pinned references without executing their top-level campaigns.
Run: julia --project=. scripts/audit_sequential_sources.jl
"""
module SequentialSourceAudit
using DecisionProgrammingAlgorithms, JuMP, HiGHS, SHA, TOML
using Base.Iterators: product
const CAPTURED=Ref{Model}()

function capture!(model)
    CAPTURED[]=model
    set_silent(model); optimize!(model)
end

function solver_adapter(e)
    e isa Expr || return e
    if e.head==:(=) && e.args[1]==:optimizer
        return :(optimizer=optimizer_with_attributes(HiGHS.Optimizer,"threads"=>1,
            "mip_rel_gap"=>0.,"mip_abs_gap"=>1e-9,"mip_feasibility_tolerance"=>1e-9))
    elseif e.head==:call && e.args[1]==:set_time_limit_sec
        return :(set_time_limit_sec($(e.args[2]),60.))
    elseif e.head==:call && e.args[1]==:optimize!
        return :(capture!($(e.args[2])))
    end
    Expr(e.head,(solver_adapter(a) for a in e.args)...)
end

function audit()
    root=dirname(@__DIR__); lock=TOML.parsefile(joinpath(root,"external.lock.toml"))
    for key in ("paper_code","paper_sequential_code","decision_programming")
        ref=lock[key]; path=joinpath(root,ref["path"])
        readchomp(`git -C $path rev-parse HEAD`)==ref["commit"] || error("wrong reference pin")
        isempty(readchomp(`git -C $path status --porcelain`)) || error("modified reference")
        println(key,": ",ref["commit"]," (clean)")
    end
    ref=joinpath(root,lock["paper_sequential_code"]["path"],"Final codes")
    for name in ("oil_new_seq.jl","oil_rjt_seq.jl","oil_new.jl","oil_rjt.jl")
        println(name," sha256=",bytes2hex(sha256(read(joinpath(ref,name)))))
    end
    # Execute only parsed mathematical RDP functions, with solver plumbing adapted.
    # Physical inputs are our identical canonical OilInstance, not a new source generator.
    for sequential in (false,true)
        file=joinpath(ref,sequential ? "oil_new_seq.jl" : "oil_new.jl")
        tree=Meta.parseall(read(file,String))
        f=only(e for e in tree.args if e isa Expr && e.head==:function)
        Core.eval(@__MODULE__,solver_adapter(f))
        for m in 1:(sequential ? 3 : 1)
            x=generate_oil(m,26)
            d=paper_layout(x)
            # Add a constant once through the drilling utility to make every path positive.
            # No constraint/coefficient expression of the upstream function is repaired.
            Base.invokelatest(DP_model,1:3,1:3,1:2,3,m,d.O,d.S,d.T,d.V,d.U .+ d.scaler)
            model=CAPTURED[]
            target=sequential ? solve_sequential_dp(x).value : solve_probing(x).value
            nominal=objective_value(model)-d.scaler
            agreement=isapprox(nominal,Float64(target);atol=1e-7,rtol=1e-9)
            println((sequential=sequential,M=m,nominal=nominal,physical_reference=Float64(target),
                agreement=agreement,variables=num_variables(model),
                constraints=num_constraints(model;count_variable_in_set_constraints=false)))
            sequential && !agreement && error("sequential source mismatch")
            !sequential && agreement && error("expected non-sequential source-defect witness disappeared")
        end
    end
end
end

if abspath(PROGRAM_FILE)==@__FILE__
    SequentialSourceAudit.audit()
end
