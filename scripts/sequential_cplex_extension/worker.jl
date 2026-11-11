# Extension worker: reuse the validated baseline record/validation path while
# replacing only the three former model-size guards for the explicitly selected
# M=4:8 jobs. Process memory and wall-clock limits remain parent-enforced.
include(joinpath(@__DIR__, "..", "sequential_cplex", "worker.jl"))

@eval SequentialCPLEXSupport begin
    function solve_method(method,x,seconds,config=SOLVER_CONFIG)
        m=ntests(x)
        rows=Int(sum(big(4)^i for i in 0:m-1))
        method=="irbb_fi" && return solve_sequential_probing(x;
            bound=:full_information,max_rows=rows)
        method=="irbb_legacy" && return solve_sequential_probing(x;
            bound=:legacy_nonsequential,max_rows=rows)
        factory,_=configured_optimizer(config,"CPLEX-Default",seconds)
        method=="rdp" && return solve_sequential_rdp(x;optimizer=factory,dense=true,
            time_limit=seconds,total_time_limit=seconds,
            max_segments=Int(2*big(size(x.reports,3)+1)^m*big(2)^m))
        method=="rjt" && return solve_sequential_rjt(x;optimizer=factory,
            time_limit=seconds,total_time_limit=seconds,max_tests=m,
            max_policy_rows=max(100_000,Int(big(size(x.reports,3)+1)^m)))
        error("unsupported sequential method: $method")
    end

    # Compile the method path without constructing a second high-dimensional
    # model before the measured solve. The actual model build remains measured.
    function warm_method(method,m,config=SOLVER_CONFIG)
        if startswith(method,"irbb")
            reports=reshape([1,0,0,1],1,2,2)
            witness=OilInstance([1//2,1//2],[1 0;0 1],reports,[-1,1],[1//10])
            solve_method(method,witness,30.,config)
        else
            cheap=OilInstance([1.],ones(1,1),ones(1,1,1),[1.],ones(1))
            solve_method(method,cheap,30.,config)
        end
    end
end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==1 || error("worker.jl ATTEMPT_DIRECTORY")
    worker(abspath(only(ARGS)))
end
