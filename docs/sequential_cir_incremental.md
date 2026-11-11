# CIR-I for passive Sequential Oil Wildcatter

Implemented 2026-11-11. This is an exact rational relaxation specialized to the
existing passive sequential testing model. It is not a general influence-diagram
solver or a claim of novelty. The original sequential DP remains independent.
RDP, RJT, FI, Legacy and the four original IR-B&B implementations are unchanged.

## Interface and independent reference

```julia
using DecisionProgrammingAlgorithms
r = solve_sequential_probing(x; variant=:combined_cir,
    bound=:full_information, max_rows=100_000, time_limit=5)
# bound=:legacy_nonsequential is also supported, with its existing definition.
ref = sequential_cir_reference(x, PartialSequentialOilPolicy())
s = SequentialCIRState(x; mode=:cached)
checkpoint = cir_checkpoint(s)
cir_update!(s, Dict((1, ()) => true))
cir_rollback!(s, checkpoint)
```

`sequential_cir_reference` propagates full unnormalized joint (O,S) matrices
recursively and returns every U/L/C message. It neither reads the incremental
arrays nor the cache. `SequentialCIRState` uses independently precomputed latent
likelihood sufficient statistics. `mode=:incremental` disables dictionary reuse;
`:cached` enables it. `:reference` additionally overwrites all messages with the
independent recurrence after each update; it is a validation mode, and its timing
includes incremental bookkeeping as well as full reference recomputation.
The search entry point `solve_sequential_cir(x; mode=...)` supports all three.
These internal modes do not create a campaign.

## Model and recurrences

The required assumptions are passive tests, unchanged geological/report kernels,
reports conditionally independent given S, full recall of the observed report
history, nonnegative additive testing costs, zero no-drill utility and one
unconstrained terminal drilling decision. There are no cross-history feasibility
constraints. At history h before test i define

```
q_h(o,s) = p(o) p(s|o) product_{j:h_j != 0} p_j(h_j|s),
mu(h) = sum_{o,s} q_h(o,s).
```

N/A (0) does not change the likelihood. Terminal messages are

```
U[M+1,h] = L[M+1,h] = max(0, sum_{o,s} q_h(o,s) payoff(o)),
C[M+1,h] = 0.
```

Write `S_V=V[i+1,(h,0)]`, `T_V=sum_r V[i+1,(h,r)]`, and
`f=c_i mu(h)`. For each testing row:

| Status | U | L | C |
|---|---|---|---|
| FIXED_SKIP | S_U | S_L | S_C |
| FIXED_TEST | T_U - f | T_L - f | T_C + f |
| FREE | max(S_U,T_U) | S_L | min(S_C,T_C+f) |

FREE maximizes both alternatives: a free current test can activate costly
mandatory downstream tests. Selecting TEST automatically is invalid. An explicit
two-stage regression tests this situation. All objectives, probabilities, costs
and messages use `Rational{BigInt}`; floating-point values occur only in timings.

## Upper-bound proof and monotonicity

Fix a partial policy P. Consider the same causal policy optimization problem,
with the same information, physical kernels and fixed actions, charging zero
for testing at a FREE row and the original cost at a FIXED_TEST row. Every
original completion is feasible in this problem, with its operating reward
unchanged and its expected cost no larger. Its relaxed value therefore bounds
its physical value from above. Backward induction, using full observed history,
gives exactly the U recurrence: terminal drilling optimizes the two original
actions, fixed rows have one allowed action, and free rows have the two allowed
actions with zero current cost. Thus U(root) >= OPT(P).

Equivalently, induct on the original completion's value: at a FREE TEST row its
physical continuation subtracts `f>=0`, whereas U uses T_U; all other transitions
preserve the same chance factors. This explicitly accounts for expected costs
and conditional prohibitions, without revealing or changing any physical state.

Fixing a FREE row to SKIP replaces `max(S_U,T_U)` by `S_U`; fixing it to TEST
replaces it by `T_U-f`. Neither increases U. All ancestor operators (identity,
sum, subtraction of a fixed constant and max) are coordinatewise monotone.
Therefore U(child) <= U(parent). Multiple added fixings follow by composition.
Removing an unreachable restriction leaves the root unchanged and so preserves
this conclusion for canonical parent-child policies.

At a complete canonical policy every structurally reachable row is fixed; its
recurrence pays exactly every physical cost and maximizes only terminal drilling.
Backward induction gives U(root) equal to the independent physical policy value.
Unfixed off-trajectory rows have no coefficient in the root recurrence. These
claims include histories of probability zero: all descendant joint masses and
payoffs then vanish exactly.

## Feasibility, minimum cost and combination

L fixes every FREE row to SKIP and otherwise respects P. Its root is the value
of a feasible complete testing policy with optimized terminal drilling. When L
improves the incumbent, the implementation materializes that policy and checks
both the drilling optimizer and the independent O,S physical evaluator for exact
equality with L. Other nodes use L without materializing a full policy.

C is the backward minimum over the original allowed testing actions, retaining
all conditional mandatory/prohibited rows. Induction gives exactly
`minimum_sequential_testing_cost(x,P)`. No per-node call to that full DP occurs
in `combined_cir`. The new bound is

```
min(UB_primary(P), F(N)-C(root), U(root)).
```

The existing cost-bound proof applies unchanged. The minimum of these valid
bounds is valid and never greater than the previous Combined bound on the same
P. FI and Legacy remain selectable primary bounds. Pruning compares exact
rationals. The first-test root certificate is tested before message construction
and is preserved. A cooperative time limit returns the incumbent and a valid
root UB with `:time_limit`, never a false optimality certificate.

## Dependency theorem and reversible updates

Precomputation constructs all histories, their unique parent, skip/report
children, mass-weighted cost and optimal terminal gain. It marginalizes the
joint distribution to `beta(s)=sum_o p(o)p(s|o)` and
`alpha(s)=sum_o p(o)p(s|o)payoff(o)`, multiplying report likelihoods once per edge.
No part of this plan depends on P.

Each message depends only on its own row's status and its child messages.
Changing row (i,h) can consequently affect only that position and its unique
ancestor path, by induction toward the root. Batched changes invalidate the
union of these paths. Unchanged positions retain their exact stored values
before any dictionary lookup. Each affected position is recorded on an undo
stack with its previous triple and signature; status changes are also recorded.
Rollback restores those entries in reverse order without copying arrays.

Search uses the existing structural reachability/canonicalization rules and
the original skip-first, first-unfixed-row order. Off-trajectory restrictions
may remain stored internally; fixed action operators do not consult their
incompatible child. Their messages are still updated when their dependencies
change, allowing later unfixing or sibling exploration safely. Canonicalization
removals through `cir_update!` are tested as batched changes.

## Exact continuation equivalence and caches

The generic structured cache's separator objects implement a different
recurrence and are not reused as interchangeable Oil messages. CIR follows its
existing equality and dependency contract with a specialized history-tree key.
Each state owns a deep copy of the model and a private cache; caches cannot be
injected/shared between states through the public constructor. Model probabilities,
costs and payoffs are therefore fixed for that entire namespace. Only the
explicitly supported `:cir_v1` semantics is accepted.

For each position j, intern the immutable expression `(j,status,child_signatures)`
by full Julia dictionary equality. A fixed SKIP includes only its skip child;
a fixed TEST includes all real-report children; FREE includes both. The chosen
maximizing action never removes a FREE continuation from the signature. Leaf
signatures are zero; the parent's identity fixes which terminal it references.
Interned integer identities are solve-local exact names, not hashes. A message
key contains semantics, position (hence stage/history and its exact precomputed
likelihood), interned signature and U/L/C type. It omits only past restrictions
and structurally incompatible descendants. Induction on this expression proves
equal keys describe equal continuation problems and equal exact messages.

Dictionary hashes accelerate lookup only. `CIRMessageKey.isequal` compares full
content; deliberate identical hashes with distinct contents are tested.
Changed relevant rows get different signatures even when values happen to tie.
Changed model parameters create private namespaces. Unsupported semantics fail
explicitly. The dictionary defaults to 100,000 message entries and clears at
capacity; eviction never changes validity. Interned signatures remain retained
for the solve, so the entry cap is not a total memory budget.

## Work, instrumentation and limitations

With `H=sum_{i=0}^M (R+1)^i`, storage is O(H) messages and sufficient statistics
plus dictionaries and active undo records. Precomputation is O(H |S|), in addition
to computing alpha/beta. A single-row update recomputes at most M triples, each
with O(R) rational arithmetic and O(R) signature work. The current implementation
sorts affected positions, adding O(M log M) integer bookkeeping for a single
path; batch size uses the union of dependencies. Undo is O(number of changed
positions). No child aggregate optimization is claimed. Rational bit complexity,
dictionary collision behavior, canonical row traversal, primary Legacy scans
and incumbent policy materialization add costs beyond this arithmetic count.
Signatures include position/history; merging distinct sufficient beliefs is
deliberately not attempted.

`SearchStats.cir` records evaluations, recomputed messages, preserved messages,
cache hits/misses, arithmetic work, retained cache bytes (including signature
interning), peak message entries, update/lookup/key/rollback time, physical
evaluations avoided and CIR-attributed prunes. Recomputed counts include initial
bottom-up construction. Preserved counts are the three messages at each position
outside an update's dependency union, including terminals; these are stored
positions retained, not dictionary accesses or an estimate of time saved. Cache
hits count only affected-position retrievals, including retrievals across changes
and sibling exploration, never reads of unchanged arrays. Root LB/UB, primary/cost
pruning and incumbent counters remain in SearchStats. Timing counters overlap:
update time includes key/lookup time; total bound time includes initialization
and updates. Allocated bytes from `@timed` are not peak RSS.

The exact unconstrained sequential DP already directly solves this model. CIR-I
is reusable relaxation machinery for possible future extensions, with no claim
of better complexity or speed than that DP. Active tests, risk measures, limited
memory and coupled policy constraints would require new recurrences and proofs.

## Reproduction and evidence

```bash
julia --project=. --startup-file=no test/sequential_cir.jl
julia --project=. --startup-file=no -e 'using Pkg; Pkg.test(allow_reresolve=false)'
julia --project=. --startup-file=no scripts/sequential_cir/diagnose.jl \
  experiments/results/sequential_cir_diagnostics/manual_new_run 5
```

The diagnostics refuse to overwrite results and accept at most 30 seconds per
solve. They compare both variants and primary bounds with exact independent DP
and physical reevaluation. No campaign scheduler is involved.

The CIR-specific suite passes 4,727 checks: exhaustive completions and all partial
policies on four two-stage rational examples, validity of all three combined
bounds, monotonicity of every free-row child, complete-policy exactness, C equality,
L feasibility, arbitrary updates/removals/canonicalization/rollback, zero-probability
histories, deliberate hash collisions, private model namespaces and independent
DP agreement in all three internal modes. Three-stage random update/rollback,
bounded/disabled cache and interrupted-search certificates are also tested.
The full package suite passed 18,933 checks before these final 376 additional
targeted checks; the final CIR-specific suite was then rerun successfully.
Existing tests are retained.

Eight short diagnostics with Julia 1.11.7 are saved under
`experiments/results/sequential_cir_diagnostics/20261111_v1/`.
All eight return `:optimal_exact` and the exact DP objective.

| Instance | Primary | Combined nodes / seconds / allocated bytes | CIR-I nodes / seconds / allocated bytes |
|---|---|---:|---:|
| j03_m4 | FI | 1 / 0.405593 / 22,299,272 | 1 / 0.372269 / 15,326,984 |
| j03_m4 | Legacy | 1 / 0.002212 / 855,208 | 1 / 0.002191 / 851,112 |
| j01_m5 | FI | 23 / 2.628120 / 221,855,464 | 15 / 1.281514 / 75,950,544 |
| j01_m5 | Legacy | 23 / 0.028640 / 21,301,552 | 15 / 0.051051 / 16,371,696 |

The exact optima are `8239284820012191748//72057594037927937` (j03_m4,
seed 63913306555501) and `14118123396604240038//72057594037927933` (j01_m5,
seed 63913306435426). The M4 root certificate avoids CIR construction entirely.
For M5, both primary modes perform 1,161 message recomputations (1,092 initial,
69 subsequent), retain 57,192 unchanged message positions over updates, perform
4,644 counted arithmetic operations, and retain 1,161 cache entries / 426,424
bytes including interned signatures. There are **zero cross-node cache hits**
in these diagnostic searches: their work saving comes from incremental arrays
and stronger pruning, not observed dictionary reuse. Separate regression tests
exercise genuine dictionary reuse after repeated or equivalent contexts.
Two nodes are pruned specifically by CIR; only one physical incumbent evaluation
is needed versus twelve in Combined. Raw TOMLs include all timing components,
bound time and allocations. The Legacy example has higher elapsed time with
CIR-I despite fewer nodes. These single runs retain compilation/order effects
and are correctness/performance diagnostics, not evidence of general speedup.
