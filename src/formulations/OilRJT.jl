"""Shared package diagram for both information structures.

Moved from scripts/OriginalSources.jl; the audit-only utility options remain
available there. sequential changes information arcs only, never kernels/costs.
"""
function oil_diagram(x::OilInstance; sequential=false, upstream_costs=false, rewards_offset=0)
    DP=DecisionProgramming
    diagram=DP.InfluenceDiagram()
    no,ns=size(x.geology); nr=size(x.reports,3); m=ntests(x)
    DP.add_node!(diagram,DP.ChanceNode("O",[],string.(1:no)))
    DP.add_node!(diagram,DP.ChanceNode("S",["O"],string.(1:ns)))
    for i in 1:m
        info=sequential ? ["Tr$j" for j in 1:i-1] : String[]
        DP.add_node!(diagram,DP.DecisionNode("T$i",info,["yes","no"]))
        DP.add_node!(diagram,DP.ValueNode("C$i",["T$i"]))
        DP.add_node!(diagram,DP.ChanceNode("Tr$i",["S","T$i"],["N/A";string.(1:nr)]))
    end
    DP.add_node!(diagram,DP.DecisionNode("D",["Tr$i" for i in 1:m],["yes","no"]))
    DP.add_node!(diagram,DP.ValueNode("P",["O","D"]))
    DP.generate_arcs!(diagram)
    p=DP.ProbabilityMatrix(diagram,"O"); p[:]=Float64.(x.prior); DP.add_probabilities!(diagram,"O",p)
    p=DP.ProbabilityMatrix(diagram,"S"); p[:,:]=Float64.(x.geology); DP.add_probabilities!(diagram,"S",p)
    for i in 1:m
        p=DP.ProbabilityMatrix(diagram,"Tr$i")
        for s in 1:ns
            p[string(s),"yes",:]=vcat(0.,Float64.(x.reports[i,s,:]))
            p[string(s),"no",:]=vcat(1.,zeros(nr))
        end
        DP.add_probabilities!(diagram,"Tr$i",p)
        u=DP.UtilityMatrix(diagram,"C$i")
        u[:]=upstream_costs ? [0.,0.] : [-Float64(x.costs[i]),0.]
        DP.add_utilities!(diagram,"C$i",u)
    end
    u=DP.UtilityMatrix(diagram,"P")
    u[:,"yes"]=Float64.(x.payoff).+rewards_offset
    u[:,"no"]=fill(Float64(rewards_offset),no)
    DP.add_utilities!(diagram,"P",u)
    DP.generate_diagram!(diagram;positive_path_utility=true)
    diagram
end

"""Restore original Float64 local utilities in the package RJT expectation.

DecisionProgramming 2.0.1 stores UtilityMatrix in Float32. Correct only the
objective coefficients; use its junction tree, moments and constraints intact.
No positive-utility translation is included in the RJT local expectation.
"""
function physical_rjt_expectation(model,diagram,mu,x)
    DP=DecisionProgramming
    ev=DP.expected_value(model,diagram,mu)
    correction=0.
    for name in keys(diagram.V)
        parent=diagram.RJT.arcs[findfirst(a -> a[2]==name,diagram.RJT.arcs)][1]
        positions=[findfirst(==(node),diagram.RJT.clusters[parent]) for node in diagram.I_j[name]]
        for index in CartesianIndices(mu.data[parent].statevars)
            h=Tuple(index)[positions]
            intended=if name=="P"
                h[2]==1 ? Float64(x.payoff[h[1]]) : 0.
            else
                i=parse(Int,name[2:end])
                h[1]==1 ? -Float64(x.costs[i]) : 0.
            end
            delta=intended-Float64(diagram.Y[name][h...])
            correction=max(correction,abs(delta))
            add_to_expression!(ev,delta,mu.data[parent].statevars[index])
        end
    end
    ev,correction
end

function solve_rjt(x::OilInstance; sequential=false, optimizer=HiGHS.Optimizer,
        time_limit=60., total_time_limit=nothing, max_tests=5, max_policy_rows=100_000, silent=true)
    ntests(x)<=max_tests || throw(ArgumentError("RJT size guard"))
    # Guard terminal policy size before the package constructs its junction tree.
    big(size(x.reports,3)+1)^ntests(x)<=max_policy_rows || throw(ArgumentError("RJT policy size guard"))
    start=time_ns(); DP=DecisionProgramming
    diagram=oil_diagram(x;sequential)
    model=Model(optimizer); configure_oil_optimizer!(model,optimizer,time_limit,silent)
    z=DP.DecisionVariables(model,diagram;names=false)
    mu=DP.RJTVariables(model,diagram,z;names=false)
    ev,correction=physical_rjt_expectation(model,diagram,mu,x)
    @objective(model,Max,ev)
    build=(time_ns()-start)/1e9
    oil_remaining_time_limit!(model,total_time_limit,start)
    optstart=time_ns(); optimize!(model); optimization=(time_ns()-optstart)/1e9
    diagnostics=oil_mip_diagnostics(model,0.)
    result=merge(diagnostics,(policy=nothing,policy_value=nothing,lower_bound=nothing,
        shift=0.,elapsed=(time_ns()-start)/1e9,preprocessing_time=0.,build_time=build,
        solve_time=optimization,solver_time=solve_time(model),variables=num_variables(model),
        constraints=num_constraints(model;count_variable_in_set_constraints=false),
        utility_coefficient_correction=correction))
    diagnostics.has_solution || return result
    nr=size(x.reports,3); m=ntests(x)
    policy=if sequential
        testing=Dict{SequentialOilKey,Bool}()
        for (i,h) in sequential_policy_rows(x;max_rows=max_policy_rows)
            testing[(i,h)]=oil_binary_action(z["T$i"].z[(h .+ 1)...,:])==1
        end
        drill=Dict{Tuple,Bool}(h=>oil_binary_action(z["D"].z[(h .+ 1)...,:])==1
            for h in Iterators.product(ntuple(_ -> 0:nr,m)...))
        SequentialOilPolicy(testing,drill)
    else
        mask=UInt64(0)
        for i in 1:m
            oil_binary_action(z["T$i"].z[:])==1 && (mask |= UInt64(1)<<(i-1))
        end
        ids=selected_tests(x,mask); rule=Dict{Tuple,Bool}()
        for r in outcomes(nr,length(ids))
            h=ones(Int,m)
            for (k,i) in enumerate(ids); h[i]=r[k]+1; end
            rule[r]=oil_binary_action(z["D"].z[h...,:])==1
        end
        OilPolicy(mask,rule)
    end
    physical=evaluate_policy(x,policy)
    merge(result,(policy=policy,policy_value=physical,lower_bound=Float64(physical),
        elapsed=(time_ns()-start)/1e9))
end

solve_sequential_rjt(x::OilInstance;kwargs...)=solve_rjt(x;sequential=true,kwargs...)
export oil_diagram, solve_rjt, solve_sequential_rjt
