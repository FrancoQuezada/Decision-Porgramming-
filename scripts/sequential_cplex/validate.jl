using Test
include("Support.jl")
using .SequentialCPLEXSupport
using DecisionProgrammingAlgorithms, JuMP, TOML, SHA
import MathOptInterface as MOI

function validate(dest)
    ispath(dest) && error("validation output already exists")
    mkpath(dest); rows=Dict{String,Any}[]
    @testset "CPLEX-Default initializes and preserves the established controls" begin
        factory,parameters=configured_optimizer(SOLVER_CONFIG,"CPLEX-Default",60.)
        model=Model(factory)
        @variable(model,v[1:1100],Bin); @constraint(model,sum(v)<=550)
        @objective(model,Max,sum(v)); optimize!(model)
        @test termination_status(model)==MOI.OPTIMAL
        @test objective_value(model)==550
        @test MOI.get(backend(model),MOI.SolverVersion())=="22.1.1"
        for (name,value) in parameters
            @test get_optimizer_attribute(model,name)==value
        end
        atomic_toml(joinpath(dest,"cplex_environment.toml"),Dict("julia"=>string(VERSION),
            "cplex_native"=>MOI.get(backend(model),MOI.SolverVersion()),
            "cplex_jl"=>string(pkgversion(SequentialCPLEXSupport.CPLEX)),
            "parameters"=>parameters,"environment"=>environment_record()))
    end
    @testset "RDP dense/reduced and RJT physical policies under CPLEX" begin
        for m in 1:2, id in 1:2
            x,item=frozen_input("j$(lpad(id,2,'0'))_m$m")
            reference=solve_sequential_dp(x)
            factory,_=configured_optimizer(SOLVER_CONFIG,"CPLEX-Default",60.)
            for method in ("dense","reduced","rjt")
                r=method=="rjt" ? solve_sequential_rjt(x;optimizer=factory,time_limit=60.,total_time_limit=60.) :
                    solve_sequential_rdp(x;optimizer=factory,dense=method=="dense",time_limit=60.,total_time_limit=60.)
                @test r.status==MOI.OPTIMAL
                @test r.primal_status==MOI.FEASIBLE_POINT && r.has_solution
                @test r.policy_value==reference.value==evaluate_policy(x,r.policy)
                @test isapprox(r.value,Float64(reference.value);atol=1e-7,rtol=1e-9)
                @test r.upper_bound>=r.lower_bound-1e-7
                @test r.mip_gap!==nothing && r.mip_gap<=1e-4
                push!(rows,Dict("M"=>m,"id"=>id,"method"=>method,"status"=>string(r.status),
                    "value"=>r.value,"physical_exact"=>string(r.policy_value),"bound"=>r.upper_bound,
                    "native_gap"=>r.mip_gap,"variables"=>r.variables,"constraints"=>r.constraints,
                    "instance_hash"=>instance_hash(x),"solver_version"=>r.solver_version))
            end
        end
    end
    @testset "No-incumbent CPLEX limits return diagnostics and no invented policy" begin
        x,_=frozen_input("j01_m3")
        factory,_=configured_optimizer(SOLVER_CONFIG,"CPLEX-Default",60.)
        for method in (solve_sequential_rdp,solve_sequential_rjt)
            r=method(x;optimizer=factory,time_limit=60.,total_time_limit=1e-9)
            @test r.status in (MOI.TIME_LIMIT,MOI.OPTIMAL)
            @test r.elapsed<10.
            if !r.has_solution
                @test r.policy===nothing && r.policy_value===nothing
                @test r.value===nothing && r.lower_bound===nothing
            else
                @test isapprox(r.value,Float64(evaluate_policy(x,r.policy));atol=1e-7,rtol=1e-9)
            end
        end
    end
    write_records(joinpath(dest,"validation.csv"),rows)
    println("CPLEX sequential model validation complete: ",length(rows)," physical comparisons.")
end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==1 || error("validate.jl NEW_OUTPUT_DIRECTORY")
    validate(abspath(only(ARGS)))
end
