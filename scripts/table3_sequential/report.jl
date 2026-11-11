include("campaign.jl")

function report_campaign(campaign)
    config=verify_campaign(campaign)
    catalog=TOML.parsefile(joinpath(config["catalog"],"manifest.toml"))
    records=Dict{String,Any}[]
    probesdir=joinpath(campaign,"probes")
    probes=isdir(probesdir) ? sort(readdir(probesdir;join=true)) : String[]
    blocker=isempty(probes) ? "campaign not launched" :
        get(TOML.parsefile(last(probes)),"error","cohort not requested")
    for source in catalog["records"], method in METHODS
        job=joinpath(campaign,"jobs",source["id"]*"_"*method)
        file=completed_attempt(job)
        r=if file===nothing
            Dict{String,Any}("id"=>source["id"],"M"=>source["M"],"seed_id"=>source["seed_id"],
                "method"=>method,"solver"=>config["solver"],"status"=>"NOT_RUN",
                "instance_sha256"=>source["instance_sha256"],"feasible_found"=>false,
                "optimal_certified"=>false,"reason"=>blocker,"numerical_mode"=>config["numerical_mode"])
        else
            merge(validate_completed(file,config),Dict("record_file"=>relpath(file,campaign)))
        end
        push!(records,r)
    end
    dest=joinpath(campaign,"reports",Dates.format(now(UTC),"yyyymmddTHHMMSSsss")); mkpath(dest)
    write_records(joinpath(dest,"per_instance.csv"),records)
    aggregates=Dict{String,Any}[]
    for method in METHODS,m in 1:8
        group=[r for r in records if r["method"]==method && r["M"]==m]
        opt=[r for r in group if r["optimal_certified"]]
        row=Dict{String,Any}("method"=>method,"M"=>m,"solver"=>config["solver"],
            "planned"=>50,"attempted"=>count(r->r["status"]!="NOT_RUN",group),
            "optimal"=>length(opt),"feasible"=>count(r->r["feasible_found"],group),
            "native_optimal"=>count(r->get(r,"native_status","")=="OPTIMAL",group),
            "not_run"=>count(r->r["status"]=="NOT_RUN",group),
            "numerical_mode"=>config["numerical_mode"])
        for key in ("total_runtime","publication_scope_total","solver_time","preprocessing_time","build_time","solve_time")
            values=[r[key] for r in opt if haskey(r,key)]
            !isempty(values) && (row["avg_"*key]=sum(values)/length(values))
        end
        for key in ("variables","constraints")
            values=unique(r[key] for r in group if haskey(r,key))
            length(values)==1 && (row[key]=only(values))
        end
        if method=="rdp"
            size=rdp_size(m)
            row["expected_variables_formula"]=size.variables
            row["expected_constraints_formula"]=size.constraints
        end
        for status in ("OPTIMAL","TIME_LIMIT","MEMORY_LIMIT","OUT_OF_MEMORY","BUILD_FAILURE","OTHER_ERROR")
            row["status_"*status]=count(r->r["status"]==status,group)
        end
        row["time_limit_with_policy"]=count(r->r["status"]=="TIME_LIMIT" && r["feasible_found"],group)
        row["time_limit_without_policy"]=count(r->r["status"]=="TIME_LIMIT" && !r["feasible_found"],group)
        push!(aggregates,row)
    end
    write_records(joinpath(dest,"aggregated.csv"),aggregates)
    # Keep an explicit machine-readable join; never fill missing publication data.
    reference_rows=TOML.parsefile(joinpath(campaign,"published_reference.toml"))["rows"]
    # The immutable excerpt is also retained as its original CSV below. A TOML
    # mapping avoids treating model-dimension formulas as published observations.
    comparisons=Dict{String,Any}[]
    for r in aggregates
        r["method"] in ("rdp","rjt","dp_milp") || continue
        joined=copy(r)
        reference=only(a for a in reference_rows if a["method"]==r["method"] && a["M"]==r["M"])
        for (key,value) in reference
            startswith(key,"published_") && (joined[key]=value)
        end
        joined["reference_provenance"]="Supplementary_material_rev3.pdf, Table 3, page 3; visually checked"
        push!(comparisons,joined)
    end
    write_records(joinpath(dest,"reference_vs_reproduction.csv"),comparisons)
    roots=Dict{String,Any}[]; pairs=Dict{String,Any}[]
    for source in catalog["records"]
        group=[r for r in records if r["id"]==source["id"] && r["method"] in ("rdp","rjt","dp_milp")]
        available=[r for r in group if haskey(r,"root_lp_physical")]
        for r in group
            row=Dict{String,Any}("id"=>source["id"],"M"=>source["M"],"method"=>r["method"],
                "all_three_roots_available"=>length(available)==3,
                "RR_percent_status"=>"normalization unverified; not computed")
            for key in ("root_lp_physical","root_lp_shifted","root_lp_status","root_lp_kind")
                haskey(r,key) && (row[key]=r[key])
            end
            if haskey(r,"root_lp_physical")
                tightest=minimum(a["root_lp_physical"] for a in available)
                row["tightest_available_pure_LP_physical"]=tightest
                row["absolute_excess_vs_available_tightest"]=r["root_lp_physical"]-tightest
            end
            push!(roots,row)
        end
        a=only(r for r in group if r["method"]=="rdp")
        b=only(r for r in group if r["method"]=="rjt")
        row=Dict{String,Any}("id"=>source["id"],"M"=>source["M"],"seed_id"=>source["seed_id"],
            "rdp_status"=>a["status"],"rjt_status"=>b["status"],
            "both_usable_policies"=>a["feasible_found"] && b["feasible_found"])
        if row["both_usable_policies"]
            row["exact_policy_values_equal"]=a["policy_physical_exact"]==b["policy_physical_exact"]
            row["rdp_physical_value"]=a["policy_physical_objective"]
            row["rjt_physical_value"]=b["policy_physical_objective"]
        end
        push!(pairs,row)
    end
    write_records(joinpath(dest,"root_relaxations.csv"),roots)
    write_records(joinpath(dest,"rdp_rjt_pairs.csv"),pairs)
    cp(joinpath(campaign,"published_reference.csv"),joinpath(dest,"published_reference.csv"))
    # Publication data and measured data stay in separate columns/files.
    open(joinpath(dest,"reference_vs_reproduction.md"),"w") do io
        println(io,"# Supplementary Table 3 — partial reproduction status\n")
        println(io,"Solver: ",config["solver"],". Numerical mode: `",config["numerical_mode"],"`.\n")
        println(io,"Reference: Supplementary_material_rev3.pdf, Table 3, page 3. Reported values are immutable; rounded sizes and T/N/A remain literal.\n")
        println(io,"Means use only physically validated optimal runs. Native optimal counts are separately retained in CSV.\n")
        println(io,"| Method | M | Published total / solver | Measured total / solver | Published O/F | Validated O/F | Attempted / 50 | Published #c / #v | Measured #c / #v | Published / measured RR% |")
        println(io,"| --- | ---: | --- | --- | --- | --- | --- | --- | --- | --- |")
        for r in aggregates
            r["method"] in ("rdp","rjt","dp_milp") || continue
            p=only(a for a in reference_rows if a["method"]==r["method"] && a["M"]==r["M"])
            println(io,"| ",r["method"]," | ",r["M"]," | ",p["published_total_text"]," / ",p["published_solver_text"],
                " | ",get(r,"avg_total_runtime","—")," / ",get(r,"avg_solver_time","—")," | ",
                p["published_optimal"],"/",p["published_feasible"]," | ",r["optimal"],"/",r["feasible"]," | ",r["attempted"],"/50 | ",
                p["published_constraints_text"]," / ",p["published_variables_text"]," | ",get(r,"constraints","—")," / ",
                get(r,"variables","—")," | ",p["published_RR_text"]," / — |")
        end
        println(io,"\nNOT_RUN is not a timeout or failed solve. Blocking diagnostic: ",blocker,".\n")
        println(io,"Reference dimensions are preserved in published_reference.csv. Exact Table 3 equivalence is not claimed.")
    end
    open(joinpath(dest,"irbb_extension.md"),"w") do io
        println(io,"# IR-B&B extension (not an original Table 3 column)\n")
        println(io,"| Method | M | Attempted | Optimal / feasible | Mean total (optimal only) |")
        println(io,"| --- | ---: | ---: | --- | --- |")
        for r in aggregates
            startswith(r["method"],"irbb") || continue
            println(io,"| ",r["method"]," | ",r["M"]," | ",r["attempted"]," | ",r["optimal"]," / ",r["feasible"]," | ",get(r,"avg_total_runtime","—")," |")
        end
    end
    println("New report snapshot: ",dest)
    dest
end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==1 || error("report.jl CAMPAIGN")
    report_campaign(abspath(only(ARGS)))
end
