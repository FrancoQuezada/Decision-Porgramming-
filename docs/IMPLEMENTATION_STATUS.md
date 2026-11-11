# Implementation scope

2026-11-11: added modular reachability, cost-aware and combined ablations for
the probing-specific Sequential Oil IR-B&B while retaining the baseline and
both original bounds. Exact small-instance validation and short archived-case
diagnostics are documented in
[`sequential_irbb_variants.md`](sequential_irbb_variants.md). This remains an
Oil specialization, not a validated general Decision Programming algorithm.

2026-11-10, sequential CPLEX baseline: CPLEX 22.1.1 solved dense RDP on all
25 selected M=1--5 inputs and RJT on 24/25 under the strict objective-policy
certificate. The remaining RJT policy is independently exact-optimal but its
native tolerance-level objective differs from the physical value by 2.02e-5,
so it remains a recorded validation error. Both IR-B&B bounds solved all five
inputs at M=1--3; larger cases and RDP/RJT M=6--8 are recorded under the existing
size guards. All 25 usable RDP/RJT physical policy pairs agree exactly. See
[the CPLEX protocol, results and limitations](sequential_cplex_benchmark.md).

2026-11-10, Table 3 follow-up: all 50 archived default-Gurobi seeds were replayed
with the pinned source operations. All 450 raw sets (including discarded warm-ups)
match bit for bit between Julia 1.10.3 and 1.11.7; 400 exact snapshots are frozen.
M=8 explicitly extends the pinned scripts' literal M<=7 loop. The default-Gurobi
timing cohorts are blocked by the missing license. RJT counts differ from the
located supplement and RDP numerical modes have distinct LP relaxations;
neither discrepancy is hidden by matching physical optima. See
[the reproduction record and resume commands](table3_sequential_reproduction.md).

2026-11-10: sequential Oil baseline added alongside the ex-ante specialization:
adaptive testing policies, exact policy evaluation, independent belief-state DP,
direct DFS IR-B&B with full-information/legacy bounds, sequential RDP (reduced
and dense), and reusable ex-ante/sequential package RJT. The existing ex-ante
algorithms and generic/structured algorithms are retained. See
[the mathematical contract](sequential_oil.md) and
[the validation record](sequential_oil_validation.md) for executed checks,
common-input comparisons and limitations. The sections below retain the earlier
publication-preparation context, not the current validation status.

Source publication prepared on 2026-11-03. This organization change does not
alter optimization formulas, branching, chance kernels, policy fixings,
arithmetic conventions or solver parameters. No tests, model runs, experimental
campaigns or benchmarks were executed as part of the publication preparation.

The code contains an exact probing-specific IR-B&B for ex-ante Oil Wildcatter,
independent portfolio enumeration, recovered drilling policies and an independent
JuMP RDP specialization. Its information bound assumes passive ignorable
signals, an unchanged latent probability model and nonnegative additive costs.

The non-probing implementation branches on partial policy mappings and uses
exact policy evaluation and information-relaxed upper bounds. The reference
bound oracle enumerates relaxed policies; its exponential cost is explicit.
Structured variants B/C/D implement uncached, cached and incremental bounds
only when their separator/fixing support criterion holds, with enumeration or
an exception for unsupported structures. This is a research prototype, not an
established competitive general-purpose exact DP solver.

The existing correctness suite is retained. Source-dependent checks are optional
without the separately obtained pinned upstream checkout; historical pilot
snapshot checks are optional without local experiment files. The suite was not
run for this repository organization change, and no new validation claim follows
from publishing the source.

IR-B&B equality certificates concern the explicit rational input model. MILP
bounds and recovered-policy agreement depend on their recorded numerical
settings. Risk objectives, additional policy constraints and scientific claims
of generality, novelty or computational superiority require separate evidence.

Experimental inputs, raw outputs and campaign datasets remain outside this
publication; the sequential validation document summarizes its small local checks.
The complete local research log remains in `docs/STATUS.md` outside
the publication allowlist, alongside the preserved local campaigns.
