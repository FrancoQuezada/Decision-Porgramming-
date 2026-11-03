using DecisionProgrammingAlgorithms

tests = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 4
seed = length(ARGS) >= 2 ? parse(Int, ARGS[2]) : 26
instance = generate_oil(tests, seed)
result = solve_probing(instance)

println("status: ", result.status)
println("objective (exact rational): ", result.value)
println("selected tests: ", selected_tests(instance, result.policy.tests))
println("bounds: ", result.lower_bound, " .. ", result.upper_bound)
