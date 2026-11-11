# Small HiGHS mathematical audit. Never a Gurobi timing reproduction.
include("worker.jl")
using Dates

function validate_table3(catalog,dest)
    ispath(dest) && error("validation output already exists")
    mkpath(dest); records=Dict{String,Any}[]; sizes=Dict{String,Any}[]
    base=optimizer_with_attributes(Table3Common.HiGHS.Optimizer,"threads"=>1,
        "mip_rel_gap"=>0.,"mip_abs_gap"=>1e-9)
    for m in 1:4
        x,_=frozen_record(catalog,"j01_m$m")
        expected=rdp_size(m)
        for (name,b) in (("rdp_existing",DecisionProgrammingAlgorithms.build_sequential_rdp(x;dense=true,optimizer=base)),
                ("rdp_source",source_rdp_model(x,base,60.)),("rjt_package",package_model(x,"rjt",base)))
            observed=(constraints=num_constraints(b.model;count_variable_in_set_constraints=false),variables=num_variables(b.model))
            startswith(name,"rdp") &&
                (observed.variables!=expected.variables || observed.constraints!=expected.constraints) && error("RDP dimension mismatch")
            push!(sizes,Dict("method"=>name,"M"=>m,"constraints"=>observed.constraints,"variables"=>observed.variables))
        end
    end
    write_records(joinpath(dest,"model_sizes.csv"),sizes)
    for m in 1:3, seed_id in (1,2)
        id="j$(lpad(seed_id,2,'0'))_m$m"; x,source=frozen_record(catalog,id)
        ref=solve_sequential_dp(x)
        # The two primary validated entry points are used without mathematical edits.
        variants=[("rdp","corrected_same_input"),("rjt","corrected_same_input")]
        m==1 && append!(variants,[("rdp","publication_offsets"),("rjt","publication_offsets"),("dp_milp","publication_offsets")])
        for (method,mode) in variants
            captured=Ref{Any}(nothing)
            factory=() -> begin
                optimizer=MOI.instantiate(base); captured[]=optimizer; optimizer
            end
            r=run_method(x,method,factory,60.,mode)
            physical=evaluate_policy(x,r.policy)
            physical==ref.value || error("physical policy disagrees with exact DP: $id/$method/$mode")
            isapprox(r.value,Float64(physical);atol=1e-7,rtol=1e-9) || error("MILP nominal mismatch")
            r.status==MOI.OPTIMAL || error("small validation not optimal")
            policyfile=id*"_"*method*"_"*mode*".toml"; save_policy(joinpath(dest,policyfile),r.policy)
            evaluate_policy(x,load_policy(joinpath(dest,policyfile)))==physical || error("policy serialization mismatch")
            row=Dict{String,Any}("id"=>id,"M"=>m,"seed_id"=>seed_id,"method"=>method,
                "numerical_mode"=>mode,"solver"=>"HiGHS","label"=>"MATHEMATICAL SANITY CHECK, not Gurobi reproduction",
                "instance_sha256"=>instance_hash(x),"physical_objective"=>Float64(physical),
                "physical_exact"=>string(physical),"publication_utility"=>Float64(physical)+source["original_utility_offset"],
                "nominal_physical"=>r.value,"status"=>string(r.status),"exact_reference_agreement"=>true,
                "elapsed"=>r.elapsed,"preprocessing_time"=>r.preprocessing_time,"build_time"=>r.build_time,
                "solve_time"=>r.solve_time,"solver_time"=>r.solver_time,"variables"=>r.variables,
                "constraints"=>r.constraints,"objective_translation"=>r.shift,"policy_file"=>policyfile)
            merge!(row,root_lp(captured[],base,r.shift;budget=60.))
            push!(records,row)
            write_records(joinpath(dest,"sanity_comparisons.csv"),records)
            println((id=id,method=method,mode=mode,objective=Float64(physical),root=row["root_lp_physical"]))
        end
    end
    atomic_toml(joinpath(dest,"provenance.toml"),Dict("created_utc"=>string(now(UTC)),
        "catalog_manifest_sha256"=>sha(joinpath(catalog,"manifest.toml")),"source_hashes"=>source_hashes(),
        "environment"=>DecisionProgrammingAlgorithms.environment_record(),"julia"=>string(VERSION),
        "JuMP"=>string(pkgversion(JuMP)),"DecisionProgramming"=>string(pkgversion(Table3Common.DP)),
        "label"=>"Separate HiGHS mathematical validation, not Table 3 Gurobi timing reproduction",
        "solves"=>length(records)))
    println("Validated ",length(records)," small MILPs and recovered policies.")
end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==2 || error("validate.jl FROZEN_CATALOG NEW_OUTPUT_DIRECTORY")
    validate_table3(abspath(ARGS[1]),abspath(ARGS[2]))
end
