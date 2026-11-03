# Algorithms and interfaces

Phase 3 adds `StructuredOracle`, `cached_oracle`, `incremental_oracle` and
`solve_reuse_irbb`; the reference algorithms described below are unchanged.
The checked recurrence is specified in `structured_relaxation.md`, exact keys
in `context_equivalence.md`, counters/storage in `hash_based_reuse.md`, and
snapshot updates in `incremental_bounds.md`. Some information structures,
including supported instances that forget irrelevant past information, satisfy
the support criterion. Others retain the original enumerative fallback.

`src/core/Interfaces.jl` defines evaluator/bound types, search statistics and
results. `SearchResult` retains exact rational objective and bounds. Normal B&B
termination returns `:optimal_exact` with equal lower/upper bounds. Size guards
raise an exception; they do not return an optimality certificate. There is no
time-limited B&B mode in v0.1.

## Specialized search

`OilInstance` represents only the ex-ante passive-test model. `OilEvaluator`
stores hidden-state coefficients and a per-solve portfolio cache. `OilPolicy`
stores a UInt64 portfolio and a drilling action for every tuple of selected
reports. The omitted-report histories are unavailable under that portfolio.

Instances and their arrays remain unchanged during a solve or while an evaluator
cache is reused; generators and solvers do not mutate physical inputs.

The depth-first stack branches on an undecided test maximizing the operating
value lost when removing that test from the allowed set. Ties are deterministic.
At each node, evaluate feasible A, update the incumbent, calculate
`F(N\B)-cost(A)`, and prune iff this exact rational bound is no larger than the
incumbent. Inclusion is explored before exclusion. Every uncached oracle computes
its entire drilling rule; no RDP variables are constructed by this oracle.

`validate_probing_bounds` checks all `3^M` required/forbidden/free nodes against
subtree maxima from the independent enumerator. `enumerate_oil` has a separate
joint-state summation implementation, and small tests additionally enumerate all
drilling rules. These checks include root/leaf equality, redundant signals,
uninformative signals, deterministic/zero probabilities and different costs.

The mask API supports up to 60 tests. The default solver size guard is 16 tests;
this is a guard against accidental enumeration, not a practical scaling claim.
Runtime is exponential in selected report count, with rational numerator and
denominator growth adding arithmetic cost. The RDP guard limits observable
segments to 200,000 by default. Bound audits default to at most 8 tests.

## General interfaces and small prototype

`InfluenceDiagramInstance` separates chance kernels, decision information, and
utility factors. `Policy` and `PartialPolicy` map `(decision, information tuple)`
to an action. A causal order is explicit; every chance parent and information
variable precedes its node. Risk measures and arbitrary policy constraints have
no representation in this release.

`EnumerationEvaluator` recursively visits chance assignments and substitutes
policy actions. `VariableEliminationEvaluator(order)` constructs chance factors
and deterministic policy-indicator factors, then sums products of factors for
each additive utility. Both use exact rational arithmetic. No maximization is
introduced during evaluation. Optimizing policies is handled separately; moving
max through a sum without respecting information would generally solve a
different problem.

`InformationRelaxation` validates the unchanged physical model and enlarged
information. `lift_fixings` projects every augmented context to its original
context. `solve_irbb` branches on the first unfixed original policy mapping,
uses action-1 completions as feasible candidates, and exhaustively optimizes the
relaxed policy set for bounds. This is an intentionally simple reference oracle.
It can be **more expensive than original enumeration**, since observation
enlargement increases the number of policy rows. No SIS construction, join-tree
reuse, dominance, Benders, pricing, or stochastic bounds are implemented.

General bound validation enumerates every combination of fixed/free policy rows
and compares to the true constrained original optimum. Complete policies must
embed with exactly equal value. Tests compare both evaluation methods in forward
and reverse elimination orders. In general, elimination factor size depends on
induced width; no polynomial-time guarantee is implied.

The non-probing experiment compares the original information oracle (an exact
node-value enumeration) with the oracle revealing X. The former is a zero-slack
reference bound; the latter is a genuine information relaxation. With these
enumerative oracles, adding information increases policy count and weakens the
bound, and offers no inference simplification. Root bound time, total bound time,
slack, search/pruned nodes and relaxed policy evaluations are recorded separately.

`SearchStats.evaluations` counts portfolio or incumbent-policy evaluations as
appropriate. `bound_policy_evaluations` counts the relaxed full policies examined
by the general bound oracle separately. Cache hits refer to actual lookups.
The probing bound timer includes any cache misses in its operating-value call;
evaluation and bound timers overlap and must not be summed as disjoint phases.
