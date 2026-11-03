using DecisionProgrammingAlgorithms

variant = isempty(ARGS) ? :A : Symbol(ARGS[1])
variant in (:A, :B, :C, :D) || throw(ArgumentError("Choose A, B, C or D"))
diagram = maintenance_instance()
relaxation = InformationRelaxation(diagram, Dict(3 => [2]))
result = variant == :A ? solve_irbb(relaxation) :
    solve_reuse_irbb(relaxation; variant).result

println("variant: ", variant)
println("status: ", result.status)
println("objective (exact rational): ", result.value)
println("bounds: ", result.lower_bound, " .. ", result.upper_bound)
println("policy mappings: ", sort(collect(result.policy.actions); by=first))
