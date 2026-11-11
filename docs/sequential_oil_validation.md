# Sequential Oil validation record

Date: 2026-11-10. Local implementation based on Git HEAD `88d2dc8`, with the
new source files and modifications listed below. No commit or push was made for
this task. No manuscript, generic algorithm, structured bound or incremental
cache implementation was changed. Both existing Julia environments are retained.

## Executed correctness checks

```
julia --project=. -e 'using Pkg; Pkg.test(allow_reresolve=false)'
```

Result: **12,968 passing checks**, no failures or errors. This includes all
6,315 previous checks and 6,653 new sequential checks. The existing local
upstream source checks and historical pilot-snapshot checks ran (they were not
skipped on this workspace). No Python process or runtime dependency is needed
by the implementation or its tests.

| New test group | Passing checks |
| --- | ---: |
| Policy representation, conditional fixings, physical evaluation and exhaustive drilling rules | 54 |
| All small partial policies, compatible optima and both exact bounds | 5,556 |
| Dense/reduced RDP dimensions, objectives and shared RJT physical kernels | 39 |
| Identical-instance ex-ante/sequential methods, degeneracies and policy recovery | 1,004 |

The partial-policy group covers **1,389 distinct nodes** across informative
M=1,2 instances (two seeds and two/three real report states), an adaptive
witness, redundant/uninformative controls, deterministic/zero-probability
reports, zero costs and prohibitively expensive tests. At every node, all
complete testing policies are filtered by its fixings, their optimum is
compared with the independent joint-belief DP, recovered/default completions
are checked against every fixing, and
`UB_FI >= UB_legacy >= compatible optimum` is checked with exact rationals.

Other checks cover M=0, M=1 equivalence, sequential value at least ex-ante
value, both B&B bounds, original physical evaluation of recovered MILP
policies, non-square state/report spaces, heterogeneous costs and negative
drilling utilities. On the rational two-test witness, ex-ante value is **17**
and sequential value is **903/50 = 18.06**. Test 1 costs 1 and has accuracy
4/5; test 2 costs 8 and has accuracy 19/20; the prior wet probability is 3/10
and payoffs are -100/100. The sequential policy commissions test 2 only after
the positive first report, avoiding its cost after a negative report.

The observed dense variable/constraint counts match 26/19, 170/79, 1194/319
for sequential M=1,2,3, and 26/19, 164/70, 1158/265 for the existing corrected
non-sequential source-derived RDP. Dense and reduced sequential objectives
agree with exact DP. All MILP comparisons use absolute tolerance 1e-7 plus
relative tolerance 1e-9; recovered rational policy values agree exactly.

## Executed upstream audit

```
julia --project=. scripts/audit_sequential_sources.jl
```

The three references were checked at their locked detached commits and had
clean working trees. Existing pin `47d4a32716e9642fb1a04d67cce48204446d597b`
was preserved. The separate new checkout is pinned at
`c8af1afc111f7f2c7ec81105225fa3854d5edf9a`. No upstream file was modified.

| New reference file | SHA-256 |
| --- | --- |
| `oil_new_seq.jl` | `10fcb8a89b84a65bd3fff847c320db75346b76dbe5f4fdcca879409053584b13` |
| `oil_rjt_seq.jl` | `eb4fb0ad516b179ba00aff6f37a765ce8ec4861cc9890299506801b761d2fc8b` |
| `oil_new.jl` | `7a7e857122291d1f88f2897ada3b8c8002ac5d022e96895ebce932c0ace12e94` |
| `oil_rjt.jl` | `38ba78ca7da4c8e9482ba62c350265bfb2eae5451a6eb5b328eb6f9a44f9f106` |

Only parsed RDP function definitions were executed with solver plumbing adapted
to HiGHS and the same canonical instances; the reference campaigns and random
generators were not launched. A single positive constant is supplied through
drilling utility and subtracted after solution. No mathematical expression in
either reference function is repaired in this audit.

| Reference | M | Nominal physical objective | Independent exact objective (decimal) | Agreement |
| --- | ---: | ---: | ---: | --- |
| Newer nonseq RDP | 1 | 0 | 9.95347068325642 | No: fixed-action index defect |
| Newer sequential RDP | 1 | 9.953470683256427 | 9.95347068325642 | Yes |
| Newer sequential RDP | 2 | 11.452660584788504 | 11.452660584788491 | Yes |
| Newer sequential RDP | 3 | 16.79064536752155 | 16.79064536752155 | Yes |

These source-audit instances use three real report states, seed 26. They are
separate from the binary-report benchmark below. The newer sequential RJT
information arcs and physical kernels were inspected; the implementation
reuses the installed pinned package decomposition. RJT objective coefficients
are restored from Float32 storage to the original instance's Float64 image;
the previous source-audit behavior remains available separately.

## Files and mathematical decisions

New implementation files:

- `src/instances/SequentialOilPolicies.jl`: explicit total/partial testing maps.
- `src/evaluation/SequentialOilEvaluation.jl`: optimized-drilling evaluator,
  independent physical evaluator and independent backward DP.
- `src/algorithms/SequentialProbingIRBB.jl`: direct DFS, first unfixed row,
  skip-first children, FI/legacy bounds and exact termination certificate.
- `src/formulations/SequentialOilRDP.jl`: reduced/dense (8a)-(8f), policy
  extraction and common free-solver configuration for the new formulations.
- `src/formulations/OilRJT.jl`: shared physical diagram and reusable package RJT.
- `test/sequential_oil.jl`: focused mathematical and integration checks.
- `scripts/audit_sequential_sources.jl`, `scripts/benchmark_sequential_oil.jl`:
  pinned-source audit and fixed small common-input experiment.
- `docs/sequential_oil.md`, `docs/sequential_oil_validation.md`: contract/evidence.

Modified files: `src/DecisionProgrammingAlgorithms.jl` (includes/import),
`scripts/OriginalSources.jl` (delegate the existing diagram constructor),
`test/runtests.jl` (include), `external.lock.toml` (separate reference pin),
`.gitignore` (allow new source/test/documentation scripts), `README.md`,
`docs/IMPLEMENTATION_STATUS.md`, `docs/architecture.md`,
`docs/mathematical_formulation.md` (correct the compatibility constraint's
equation label and link the specialization), and local ignored `docs/STATUS.md`.

The unchanged causal probability model, all fixed actions (including
unreachable rows) and every original feasible compatible policy are preserved
in both bound proofs. Globally required/forbidden sets require **all** explicit
rows. No expected-cost bound, history-specific relaxation, advanced branching,
reachability elimination, new search cache, incremental update or generic-DP
extension was introduced. Bound slack at complete leaves is handled explicitly.

The separate supplement PDF was unavailable; the supplied main papers, requested
information structure, model-count formulas and specified new code revision
were checked. This limitation is explicit in the mathematical contract.
The official arXiv v2 source archive was checked as well: it contains
`main_arxiv.tex`, `bibliography.bib` and `00README.json`, without a supplement.

## Small common-input comparison

Executed **after** the complete correctness suite passed:

```
julia --project=. scripts/benchmark_sequential_oil.jl
```

Saved run: `experiments/results/sequential_baseline/20261110T105615030/`.
The directory contains six exact instance snapshots, eight separate warm-ups,
48 comparison records and 48 explicit saved policies. Every policy was reloaded
from TOML and reevaluated independently. All runs have an optimal status and
match their respective exact physical reference. Raw test/audit logs are in
the run's `verification/` directory. Inputs/results remain ignored by Git;
rerunning the command creates another directory without overwriting this one.

Environment: Julia 1.11.7, JuMP 1.32.1, DecisionProgramming 2.0.1 at its existing
locked source revision, HiGHS.jl 1.26.1 / solver 1.15.1, Linux x86_64,
Intel Core i7-1260P, 16 logical CPUs, one Julia thread and one solver thread.
No CPLEX execution was needed. Root Manifest SHA-256:
`c8399e6694ea6189e78f9d827b4584595c2e0fe777184bdfe8f68041c095f134`.
Source/input/policy hashes and the complete environment are saved with the run.

The physical generator is the existing independent-v1, with two oil/geology
states and two real reports plus N/A, seeds 7 and 26. These are informative
synthetic instances, not paper-instance reproductions. Three ex-ante methods
(RDP, RJT, existing IR-B&B) agree exactly in recovered physical value; all five
sequential methods (RDP, RJT, FI B&B, legacy B&B, independent DP) agree likewise:

| M | Seed | Ex-ante physical optimum | Sequential physical optimum |
| --- | --- | ---: | ---: |
| 1 | 7 | 60.77192492510117 | 60.77192492510117 |
| 1 | 26 | 55.6172545116125 | 55.6172545116125 |
| 2 | 7 | 57.793409311751816 | 58.827296452346715 |
| 2 | 26 | 53.21702516973003 | 53.21702516973003 |
| 3 | 7 | 58.068283781932266 | 60.06485360101831 |
| 3 | 26 | 55.46854531806365 | 56.222303218458315 |

The saved CSV also contains full exact rational objectives. The following times
are **sums over six measured runs**, in seconds, not averages or paired speedups.
Total time includes each method's internal recovery/physical evaluation.
RJT diagram/decomposition work is included in build time. RDP probabilistic
coefficients are included in preprocessing time. A single warm-up at M=1 does
not remove every later dimension-specific compilation; notably the first M=2
RJT build and FI policy evaluation include residual compilation. These results
are baseline observations, not scientific timing or superiority conclusions.

| Method | Total | Preprocessing | Build | Optimization |
| --- | ---: | ---: | ---: | ---: |
| Nonseq RDP | 0.515944 | 0.030348 | 0.082982 | 0.242106 |
| Nonseq RJT | 5.822498 | included in build | 5.386754 | 0.388372 |
| Nonseq IR-B&B | 0.001077 | — | — | — |
| Sequential RDP | 0.585621 | 0.011567 | 0.261884 | 0.170360 |
| Sequential RJT | 1.387633 | included in build | 0.070468 | 1.176560 |
| Sequential FI B&B | 2.006823 | — | — | — |
| Sequential legacy B&B | 1.698824 | — | — | — |
| Independent sequential DP | 0.001171 | — | — | — |

Sequential search counters and bound-evaluation times (seconds):

| M | Seed | Bound | Visited / candidate evaluations | Expanded | Bound-pruned | Bound time | Cache hits / misses |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| 1 | 7 | FI | 3 | 1 | 0 | 0.000032039 | 2 / 1 |
| 1 | 7 | Legacy | 3 | 1 | 2 | 0.000039881 | 1 / 2 |
| 1 | 26 | FI | 3 | 1 | 0 | 0.000028832 | 2 / 1 |
| 1 | 26 | Legacy | 3 | 1 | 2 | 0.000037899 | 1 / 2 |
| 2 | 7 | FI | 31 | 15 | 0 | 0.000112906 | 30 / 1 |
| 2 | 7 | Legacy | 31 | 15 | 4 | 0.000238619 | 27 / 4 |
| 2 | 26 | FI | 31 | 15 | 0 | 0.000079735 | 30 / 1 |
| 2 | 26 | Legacy | 31 | 15 | 4 | 0.000136892 | 27 / 4 |
| 3 | 7 | FI | 16383 | 8191 | 0 | 0.044553103 | 16382 / 1 |
| 3 | 7 | Legacy | 15361 | 7680 | 13 | 0.096222986 | 15353 / 8 |
| 3 | 26 | FI | 16383 | 8191 | 0 | 0.044534351 | 16382 / 1 |
| 3 | 26 | Legacy | 14339 | 7169 | 12 | 0.128919600 | 14331 / 8 |

Across all six instances, FI visits/evaluates 32,834 nodes, expands 16,414 and
bound-prunes zero; bound time is 0.089341 s and candidate-evaluation time is
1.849890 s. Its portfolio oracle has six misses and 32,828 hits. Legacy
visits/evaluates 29,768 nodes, expands 14,881 and bound-prunes 37; bound time
is 0.225596 s and candidate-evaluation time is 1.408997 s, with 28 misses and
29,740 hits. Closed complete leaves with loose UB are not counted as pruned.
The original ex-ante IR-B&B visits 48 nodes, expands 21 and prunes 27; these
are portfolio-search nodes rather than partial sequential-policy nodes.

The baseline's weakness is visible: positive-cost FI B&B exhausts the full
testing-policy tree in every measured case. Legacy pruning is conservative
and its global-set scans cost more bound time. No stronger oracle, minimum
expected testing cost, policy compression, reachability reduction, stronger
branching or new cache was added to improve these observations. Only small
finite instances and a single timing repetition were run. The reference DP is
kept separate and is not substituted into the B&B bound oracle.
