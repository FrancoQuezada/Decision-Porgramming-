# Sequential Oil Wildcatter baseline

This specialization changes only the Oil testing information sets:
`I(T_i)={R_1,...,R_(i-1)}`, `I(D)={R_1,...,R_M}`. It uses the same `OilInstance`,
generator, exact TOML snapshots, nonnegative costs and causal probabilities as
ex-ante Oil. Skipping produces N/A (`0`); commissioning produces a real report
`1:R`, independent of other potential reports conditional on latent geology S.
Tests are passive and do not change O, S or later report kernels. No-drill
utility is zero; the objective is additive expected utility without extra policy
constraints. This is an Oil-specific baseline, not a general influence-diagram
algorithm or a claim of novelty or computational superiority.

## Interfaces and policies

```julia
using DecisionProgrammingAlgorithms
x = generate_oil(2, 26; states=2)
physical_reference = solve_sequential_dp(x)
fi = solve_sequential_probing(x; bound=:full_information)
legacy = solve_sequential_probing(x; bound=:legacy_nonsequential)
rdp = solve_sequential_rdp(x)           # availability-reduced (8a)-(8f)
dense = solve_sequential_rdp(x; dense=true)
rjt = solve_sequential_rjt(x)
ex_ante_rjt = solve_rjt(x)
@assert fi.value == legacy.value == physical_reference.value
@assert evaluate_policy(x, rdp.policy) == physical_reference.value
```

`SequentialOilPolicy.testing` maps `(i,h)` to a Bool (false=skip, true=test).
`h` has length `i-1` and contains all previous reports, including zeros.
`drill` maps complete report histories to Bool. `PartialSequentialOilPolicy`
contains only fixed testing rows; action inputs must be 0/1. Every completed
policy defines all testing and drilling rows, including off-policy histories.
`sequential_policy_rows` orders by stage, then Julia's Cartesian product order
(the first report coordinate varies fastest). A stage has `(R+1)^(i-1)` rows.

`complete_sequential_testing` respects every fixing and skips in all unfixed
rows. `optimize_sequential_drilling` propagates likelihoods over S, using
`beta(s)=sum_o p(o)p(s|o)` and `alpha(s)=sum_o p(o)p(s|o)u(o)`. At a tested
history with likelihood L(s), it charges `c_i sum_s beta(s)L(s)`. At a terminal
history it adds `max(0,sum_s alpha(s)L(s))`. This optimizes drilling exactly
and returns the explicit policy. Separate `evaluate_policy(x,policy)` traverses
the original causal process for each O,S, using the recovered actions directly;
it uses neither alpha nor the optimal-drilling formula.

## Direct branch-and-bound

A node fixes a subset of testing mappings. At every visited node the algorithm:

1. Completes unfixed rows with skip and optimizes final drilling exactly.
2. Updates the feasible incumbent if this candidate improves it.
3. Computes the selected optimistic bound using the existing `OilEvaluator`.
4. Prunes when `UB <= incumbent`, with `Rational{BigInt}` arithmetic.
5. Otherwise branches on the first unfixed testing row, visiting skip before
   test by depth-first search. A fully fixed leaf is evaluated and closed even
   when its bound is loose.

Drilling decisions are never branched on. After exhausting the stack,
`SearchResult` reports `:optimal_exact`, equal final bounds and zero tolerance.
The finite tree has `K=sum_i (R+1)^(i-1)` binary rows and at most `2^(K+1)-1`
visited nodes. The default guard is 24 testing rows; this is a safety ceiling,
not a practical scaling claim. Positive costs can make the FI bound loose at
every node, causing complete enumeration of testing mappings.

## Upper bounds and preserved feasible policies

Write `F(T)=operating_value(e,mask(T))`: optimal drilling value from the reports
of T without any testing costs. The two supported options are

```
UB_FI(P)     = F(N)
UB_legacy(P) = F(N \ B_global(P)) - sum_{i in A_global(P)} c_i.
```

`A_global` contains i only if **every** possible history row for i is explicitly
fixed to test. `B_global` similarly requires all rows fixed to skip. Conditional
fixings, missing rows and unreachable rows are not silently interpreted as
global decisions. All histories are counted, including zero-probability ones.

For validity, introduce potential reports Y_i with the unchanged joint law
`p(o)p(s|o) product_i p_i(y_i|s, test)`. This coupling is valid specifically
because tests are passive and conditionally independent given S. For any
original policy compatible with P, a decision maker observing all Y_i for
`i in N\B_global` can simulate that policy chronologically: present N/A for
skipped tests, reveal Y_i only when its original action tests, preserve each
fixed action, and apply its original drilling rule to the simulated history.
The induced probabilities and operating reward are identical. The added
reports can be ignored, so this operating reward is at most `F(N\B_global)`.
Every globally required test is paid on every realization. Dropping all other
nonnegative costs proves the legacy bound. The same embedding with all N and
all costs dropped proves FI. Monotonicity of F and nonnegative costs also give
`optimum(P) <= UB_legacy(P) <= UB_FI(P)`.

Neither bound needs to be exact at a complete policy leaf. The optimal ex-ante
**net** value is a lower bound on the sequential optimum (constant testing
policies are feasible sequential policies), and is not used as an upper bound.
These proofs would need revision for active tests, dependent report mechanisms
beyond the specified latent model, negative costs or coupled drilling actions.

## Independent exact reference

The optional reachability, cost-aware and combined ablations, including their
validity proofs and diagnostic limitations, are documented in
[`sequential_irbb_variants.md`](sequential_irbb_variants.md). The default
`variant=:baseline` retains the direct search described above.

`solve_sequential_dp(x,p)` performs backward recursion on an unnormalized joint
belief b(o,s). For history h at stage i, skip leads to `(h,0)` with unchanged b;
test has value `-c_i sum(b) + sum_r V(i+1,(h,r),b .* p_i(r|s))`.
The recursion maximizes over allowed testing actions (a singleton at a fixed
row). At the terminal stage it uses `max(0,sum_{o,s} b(o,s)u(o))`. It never
divides by observation probability, so zero-probability histories are defined.
Recovered policies retain all partial fixings, including off-policy fixings.
This separate exact reference is used only for validation and experiments;
the B&B implementation never calls it.

## RDP and RJT

Sequential RDP independently implements Terho et al. (2026), (6), (8a)-(8f).
Binary `ztest` rows depend on the previous report prefix; `zdrill` depends on
the entire report history. Continuous y variables satisfy aggregated testing
and drilling compatibility and a capacity of one per report history. Safe
Gamma values count matching segments; no new bound strengthening is added.
Every coefficient sums over O,S with the original report kernels and **net**
utility. The positive translation is the existing convention
`shift=1-min(0,min(payoff))+sum(costs)`. Every translated path utility is at
least one. For a fixed policy, exactly one action segment can survive at a
report history; every positive-probability compatible segment activates.
Their causal probability mass is one even with adaptive testing. Subtracting
the shift once therefore recovers the unshifted physical objective.

Default RDP removes only action/report availability inconsistencies. A report
history then uniquely determines the testing actions on that segment, including
the costs paid. It retains the full policy rows, without reachability reduction.
`dense=true` keeps all action/report combinations including zero coefficients.
For `H=(R+1)^M` and `K=sum_i (R+1)^(i-1)`, dense sequential counts are
`2*(2*(R+1))^M + 2H + 2K` variables and `4H+3K` constraints, excluding bounds.
Reduced counts are `4H+2K` variables and the same number of constraints. With
three real report states, the observed dense dimensions are:

| M | Nonseq variables / constraints | Seq variables / constraints |
| --- | --- | --- |
| 1 | 26 / 19 | 26 / 19 |
| 2 | 164 / 70 | 170 / 79 |
| 3 | 1158 / 265 | 1194 / 319 |

The non-sequential independent/source-derived RDP implementations are retained.
`oil_diagram` is the shared constructor extracted from the existing
`OriginalSources.package_diagram`; sequential mode changes only information
parents. RJT uses the installed DecisionProgramming.jl `InfluenceDiagram`,
`DecisionVariables`, `RJTVariables` and `expected_value`, with its original
junction-tree construction and constraints. The package stores utilities in
Float32. The new RJT solver corrects the resulting local expected-utility
coefficients to the Float64 image of the same OilInstance after calling
`expected_value`; it never edits the package or its external checkout. RJT's
local objective needs no utility translation. The original audit pipeline
still uses its original Float32 behavior and explicit rounding diagnostic.

All MILP testing and drilling rows are decoded from z, checked for one-hot
integrality, and physically reevaluated in exact rational arithmetic. A solver
optimality status remains a numerical certificate. Equality to the independent
exact reference is separately tested, not inferred from that status.

## Sources and audit

The supplied Salo et al. (2022) PDF, Sections 3.1-3.5, and supplied
[Terho et al. v2](https://arxiv.org/abs/2601.08460v2), (6), (8a)-(8f), Section 4.3,
were inspected. A DP path remains a state assignment. The main 2026 PDF refers
to sequential testing in its supplement; a separate supplementary PDF was not
available locally. The requested information structure and dense counts were
checked against the specified newer upstream implementation and the model
dimension formulas, rather than claiming to have read an unavailable supplement.
The official arXiv v2 source archive was also inspected; it contains the main
article TeX, bibliography and archive metadata, without a separate supplement.

The original source pin `47d4a32716e9642fb1a04d67cce48204446d597b` is unchanged.
`external.lock.toml` adds a **separate** checkout of
[revision c8af1af](https://github.com/toubinaattori/Decision-Programming-new-formulation/tree/c8af1afc111f7f2c7ec81105225fa3854d5edf9a).
The four `Final codes/oil_{new,new_seq,rjt,rjt_seq}.jl` scripts were inspected.
The newer sequential script has the requested adaptive information sets and
preserves singleton coordinates correctly. Its newer non-sequential RDP still
constructs testing groups with `CartesianIndices(Tuple(length.(c)))`, which
loses fixed integer action coordinates; this was not copied into the new model.
The newer generators draw from a single seeded stream and diagonal-favoring
weights, unlike the repeated-Xoshiro pattern of the older audited source.
They also translate test utilities by `50*M` per test and no-drill utility by
100. Those objective offsets are not used as physical utility in this project.

`scripts/audit_sequential_sources.jl` checks clean pinned references, prints
the four file hashes, extracts only the two RDP function definitions and adapts
solver plumbing to HiGHS. It never runs top-level generators or campaigns and
never modifies upstream code. See the validation report for observed comparisons.

## Validation and small experiments

```bash
julia --project=. -e 'using Pkg; Pkg.test(allow_reresolve=false)'
julia --project=. scripts/audit_sequential_sources.jl
julia --project=. scripts/benchmark_sequential_oil.jl
```

The benchmark freezes/reloads identical exact snapshots for all eight methods,
with M=1,2,3, seeds 7,26 and two real report states. Binary-report M=3 has 13
testing rows; three-report M=3 would have 21 and potentially millions of B&B
nodes. Three-report dense MILP dimensions and objective agreement are checked
separately. No large campaign is launched by the benchmark.

One warm-up per method is saved separately. Each measured total includes
preprocessing, model construction, optimization, policy recovery and the exact
evaluation performed inside the method. MILP preparation and optimize! wall
time are separate fields; the 60-second limit applies only to optimize!.
An additional independent post-run physical validation is outside the measured
total. Environment, source/Manifest hashes, input hashes, policies and result
records are saved under a fresh ignored run directory. One repetition is
descriptive evidence, without a speedup or scaling claim.

For sequential B&B, `SearchStats.evaluations` counts feasible complete testing
policies; `evaluation_time` includes completion and exact drilling optimization.
`bound_time` includes global classification/cache lookup/oracle work;
`bound_policy_evaluations` counts `OilEvaluator` cache misses and `cache_hits`
counts its hits. There is one bound request per visited B&B node. No new policy
cache is introduced. Complete leaves with loose UB are closed, but are not
counted as bound-pruned. The original ex-ante stats retain their original
portfolio-oracle meaning. DP visited histories are reported separately from
B&B nodes. Missing/inapplicable benchmark fields remain blank.

Only the requested baseline is implemented: no expected-cost bounds,
history-specific information relaxations, strong branching, policy compression,
unreachable-row elimination, cross-node policy caching, incremental updates or
generic-DP extensions. Policies and search trees grow rapidly. HiGHS is the
default; callers may supply another JuMP optimizer, including optional CPLEX.
