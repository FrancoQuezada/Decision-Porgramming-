using DecisionProgrammingAlgorithms

tests = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 3
seed = length(ARGS) >= 2 ? parse(Int, ARGS[2]) : 26
instance = generate_oil(tests, seed)
result = solve_rdp(instance)

println("status: ", result.status)
println("unshifted objective: ", result.value)
println("recovered policy value (exact rational): ", result.policy_value)
