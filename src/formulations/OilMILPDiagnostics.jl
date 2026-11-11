"""Portable solver diagnostics, also when a time limit produces no incumbent.

Optional optimizer attributes can be unavailable before/after an interrupted
solve. Such values stay missing; they are never replaced with a primal value.
No solver package or solver-specific settings are introduced in this module.
"""
function oil_mip_metric(query)
    try
        v=query()
        v isa AbstractFloat && !isfinite(v) && return nothing
        v
    catch
        nothing
    end
end

"""Optionally include model preparation in the native solver's remaining budget.
The parent process must still guard construction, which cannot be interrupted
by a solver TimeLimit. Existing optimizer-only time_limit behavior is retained
unless total_time_limit is explicitly supplied.
"""
function oil_remaining_time_limit!(model,total_time_limit,start)
    total_time_limit===nothing && return
    isfinite(total_time_limit) && total_time_limit>0 || throw(ArgumentError("positive finite total_time_limit required"))
    remaining=max(0.,Float64(total_time_limit)-(time_ns()-start)/1e9)
    current=time_limit_sec(model)
    set_time_limit_sec(model,current===nothing ? remaining : min(current,remaining))
end

function oil_mip_diagnostics(model,shift)
    available=has_values(model)
    primal=available ? oil_mip_metric(() -> objective_value(model)) : nothing
    bound=oil_mip_metric(() -> objective_bound(model))
    (status=termination_status(model),primal_status=primal_status(model),
        raw_status=raw_status(model),has_solution=available,
        shifted_value=primal,shifted_upper_bound=bound,
        value=primal===nothing ? nothing : primal-Float64(shift),
        upper_bound=bound===nothing ? nothing : bound-Float64(shift),
        mip_gap=oil_mip_metric(() -> MOI.get(backend(model),MOI.RelativeGap())),
        nodes=oil_mip_metric(() -> MOI.get(backend(model),MOI.NodeCount())),
        solver=solver_name(model),solver_version=oil_mip_metric(() -> MOI.get(backend(model),MOI.SolverVersion())))
end
