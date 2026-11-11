# Supplementary Table 3: source replay and reproduction status

Date: 2026-11-10. Work is local, uncommitted, on top of `88d2dc8`. The preceding
sequential baseline and all earlier campaigns/results are preserved. No IR-B&B
bound, branch rule, cache, policy evaluator or production formulation was edited.

**The Gurobi timing reproduction is blocked by the missing license.** The local
Gurobi.jl installation reports runtime 12.0.3 and error 10009, “No Gurobi license
found”. The publication used Gurobi 11.0.2. The requested 50-instance RDP/RJT
M=1,2,3 cohorts have therefore not run. HiGHS checks below are mathematical
sanity checks, not substitutes for the publication's Gurobi results.

## Sources and immutable reference

The user located the supplement at `Docs/Supplementary_material_rev3.pdf`.
Its nine-page document was inspected, including Section 2.1, Figure 1, Table 2
and a rendered view of Table 3 on page 3. SHA-256:
`c1e5139e6f4bb87c0a8d538b167c2da6b99a34a37cdd19c1e4445b569578b6fc`.
The supplied main paper in `Docs/` matches the already inspected `papers/` copy
bit for bit. The earlier baseline report's supplement-availability statement
describes that earlier search; this task now uses the located supplement.

`scripts/table3_sequential/PublishedTable3.csv` transcribes all 24 method/size
rows, preserving printed times, O/F, RR%, rounded dimensions and T/N/A. Each
campaign copies the reference into separate CSV/TOML files and locks both hashes.
The reporting code never substitutes those numbers for measured results.
In particular, Table 3 reports DP M=5 times 400.5/371.8 with O/F=0/0. This
apparent inconsistency with the optimal-only averaging convention is retained,
not corrected or interpreted as evidence of a completed optimal solve.

The experimental reference remains a clean detached checkout at
`c8af1afc111f7f2c7ec81105225fa3854d5edf9a`. The older source/package pins and
both existing Julia environment locks remain unchanged. No external code or
third-party PDF is redistributed by the new publication allowlist.

## Archived seeds and source arrays

All 50 distinct `Final codes/Data/oil_seed_gurobi_1.csv` through
`oil_seed_gurobi_50.csv` were recovered and checksummed. Files without the
`_gurobi_` component are not used. The generator ASTs extracted from
`oil_new_seq_Gurobi.jl`, `oil_rjt_seq_Gurobi.jl` and `oil_dp_seq_Gurobi.jl` are
identical after removing line numbers. Extraction stops before any model,
solver, output-writing or time-dependent seeding operation. It retains the
original probability weights, noise, normalization, integer cost/reward draws,
and their exact execution order.

For each archived seed a single default-RNG stream is seeded once and consumed
by `[1,1,2,...,8]`. The first M=1 is preserved as a discarded warm-up; the
second M=1 is the retained instance, matching the source's filename overwrite.
Sizes are not independently reseeded. A fresh Task isolates each seed's stream;
its initial seed is explicitly reset. No optimization intervenes in replay.

Julia 1.10.3 was installed as an additional juliaup channel without changing
the default Julia. Both 1.10.3 and 1.11.7 independently replayed all 450 array
sets (400 retained instances plus 50 warm-ups). **All 450 sets agree bit for
bit in O, S, T, V and U**, including integer draws. The raw comparison hashes
write Float64 bit patterns with dimensions, independently of TOML formatting.

Important historical limit: all three pinned scripts literally set `No=7`.
Their retained M=1,...,7 are source-faithful replays. M=8 is an explicitly
labeled continuation of the same RNG stream, requested for the Table 3 design;
the pinned loop does not itself execute M=8. No original historical array
archive was supplied, so cross-version replay equivalence is not a claim of
bytewise comparison against the authors' actual historical outputs.

Saved local material:

- `experiments/table3_sequential/source_replay_julia1103/`: 450 original array
  sets, archived seed/file hashes, generator implementation/expression hashes.
- `experiments/table3_sequential/source_replay_julia111/`: independent current
  runtime replay of the same 450 draws.
- `experiments/table3_sequential/frozen_julia1103/`: **400 frozen exact
  OilInstance snapshots**, copies of the original Float64 arrays, manifest,
  instance/file/array hashes, audit and CSV catalog.

The physical payoff is `U[:,yes]-100`; test costs are `V[no,:]-V[yes,:]`.
The original utility is the physical utility plus the constant
`100+50*M^2`. This removes the original additive offsets without changing any
feasible policy or its relative expected utility. Original arrays remain saved.
OilInstance's established exact row-normalization semantics are retained; each
snapshot records its maximum Float64 normalization difference from the raw
arrays. Canonical normalized rationals and raw source Float64 arrays are not
silently equated. Every optimization method reloads the same frozen snapshot.

## Model sizes and numerical modes

Observed construction counts below exclude variable-domain constraints:

| M | Published RDP #c / #v | Observed dense RDP | Published RJT #c / #v | Observed package RJT |
| --- | --- | --- | --- | --- |
| 1 | 19 / 26 | 19 / 26 | 196 / 144 | 221 / 179 |
| 2 | 79 / 170 | 79 / 170 | 795 / 610 | 959 / 787 |
| 3 | 319 / 1194 | 319 / 1194 | 3170 / 2468 | 3905 / 3219 |
| 4 | 1279 / 8874 | 1279 / 8874 | 1e4 / 9894 (rounded #c) | 15683 / 12947 |

RDP uses `H=4^M`, `K=(4^M-1)/3`, variables `2*8^M+2H+2K` and constraints
`4H+3K`. These formulas are checked through M=8, where #v=33,729,194 and
#c=327,679. Such dimensions do not imply that those larger models were built.

The package reports version 2.0.1 at the existing locked commit. Its RJT
construction differs in size from the supplied reference. The package source
was compared with its v2.0.1 tag; no decomposition implementation was replaced
to force a matching count. This unresolved implementation/count discrepancy is
not a physical-objective correctness claim. The same physical models and
recovered policies are checked independently.

There are two explicit experimental numerical modes:

- `corrected_same_input`: calls the existing `solve_sequential_rdp(dense=true)`
  and `solve_sequential_rjt` without changing their code. The existing RDP uses
  its positive-utility shift and safe compatibility multipliers. RJT retains its
  documented correction of the package's Float32 utility coefficients.
- `publication_offsets`: an experimental adapter reads the original dense RDP
  function's mathematical AST unchanged, replaces only solver/extraction
  plumbing, and supplies the original constant utility offset. RJT uses the
  same package and the original local utility offsets/Float32 behavior.
  Original costs and payoffs are integer-valued on these source instances, so
  Float32 represents these local utilities exactly. Physical evaluation still
  uses the same canonical snapshot and subtracts the recorded offset.

The two RDP integer policy problems agree, but their **LP relaxations differ**:
the existing model's test compatibility multiplier is smaller than the source's
and its utility translation is different. A positive constant shift is harmless
on complete feasible policies; it need not be harmless on fractional RDP y
solutions with relaxed activation mass. Therefore equal policy optima and
matching dense dimensions do not establish identical root relaxations or timing.
The source adapter is separate and does not edit the validated formulation.

The prepared original DP baseline is `dp_milp`, using DecisionProgramming.jl's
`PathCompatibilityVariables(...; probability_cut=false)` and `expected_value`.
It is distinct from the exact belief-state dynamic programming validator.
The package removes zero-probability paths: at M=1 it builds 15 constraints /
82 variables versus the table's 15 / 154. The published 154 count corresponds
to retaining the full path space. This difference is reported, not silently
repaired by modifying package or influence-diagram algorithms.

## Small mathematical checks actually executed

The final successful sanity run is stored under
`experiments/results/table3_sequential_sanity/20261110_v3/`.
It compares the existing dense RDP and corrected RJT on seed IDs 1,2 and
M=1,2,3, plus the publication-offset RDP/RJT and original DP MILP at M=1.
That is **18 small HiGHS MILP solves**, each with policy recovery, saved-policy
reload, exact physical evaluation and independent belief-state DP comparison.
RDP and RJT agree exactly in recovered physical value:

| M | Seed ID | RDP / RJT / exact DP physical optimum |
| --- | --- | ---: |
| 1 | 1 | 231.469019488330 |
| 1 | 2 | 548.827556147857 |
| 2 | 1 | 440.660798582087 |
| 2 | 2 | 108.193700691112 |
| 3 | 1 | 293.272051970358 |
| 3 | 2 | 205.620792796211 |

Exact rational values, nominal/physical/shifted values, model counts and pure-LP
roots are retained individually in CSV. Earlier development attempts remain at
`20261110_initial` and `20261110_v2`; they are not merged into the final cohort.
No 50-instance timing cohort, large-M solve or IR-B&B extension was executed.

## Root relaxations and RR%

The main manuscript, Section 4.1, says that root-node LP relaxations are compared
with the tightest relaxation, assigned RR%=0. Neither that passage nor the
supplement specifies the percentage denominator or enough procedural detail
to distinguish a plain LP from a root-node bound after Gurobi cuts. The pinned
scripts also do not record or calculate RR%. The normalization remains
**unverified**, despite having the full published table. Reproduced RR% cells
therefore remain blank.

The pipeline separately copies each unpresolved input MILP, relaxes binary /
integer domains, preserves binary bounds and solves a pure LP with its own
60-second auxiliary budget. It never substitutes the final MIP bound for a
missing root value. Per-instance shifted/physical root values, statuses and
available-method comparisons are saved so normalization can later be revisited.
Root-after-cuts values remain explicitly unavailable. The full three-method
comparison is marked incomplete when one of the three roots is missing.

Example, archived seed ID 1 at M=1: exact physical optimum is 231.46901948833;
existing dense RDP pure LP is 548.93803897666, source/offset RDP pure LP is
593.93803897666, RJT pure LP is 258.25824474613 and original DP MILP pure LP
is 717.78024947609. These are **HiGHS pure-LP diagnostics**, not reconstructed
published RR% or default-Gurobi post-cut root results.

## Execution, resource limits and results

`campaign.jl` prepares all five method plans for M=1,...,8, freezes source/input
and publication-reference hashes, and defaults to a single worker process.
The Gurobi factory sets no Presolve, Heuristics, Cuts, MIPFocus, NodeMethod or
Threads overrides. Only time limits and logging controls are applied. Julia
thread count and the separate single-thread HiGHS sanity setting are recorded;
they do not imply `Gurobi Threads=1`.

Each process warms the selected method once at the same seed ID's retained
M=1 snapshot, then starts its measured model/solve phase. This compiler warm-up
is distinct from the source RNG's discarded first M=1. Process startup/warm-up
have a separate 120-second watchdog. A parent wall-clock watchdog covers model
construction and optimization with a **3600-second total budget** in the
Gurobi protocol, and polls RSS at 0.1-second intervals against a 14-GiB cap.
The RSS guard is sampled, not an OS-enforced instantaneous allocation limit.
Root-LP work has a separate budget and never replaces main MIP results.

Successful records include native/primal status, bounds, gap, model/solver
times, physical and shifted objectives, explicit policy, exact reference checks
for M<=3, solver/environment details and RSS diagnostics. If the existing solver
entry point throws without returning phase timings, those timings stay missing.
A watchdog-killed process may have an unexported native incumbent; the record
states that native feasibility is unknown rather than inferring a usable policy
from solver logs. A validated post-solve checkpoint is preserved if an auxiliary
root-LP task fails.

Results use atomic TOML checkpoints and one immutable attempt directory per
job. Resume verifies protocol, input and saved-policy hashes and physically
reevaluates a completed saved policy before skipping it. It does not rerun
validated completed jobs. Interrupted attempt directories remain preserved.
Reports are regenerated into new timestamped snapshots; prior reports are kept.

`experiments/results/table3_sequential_gurobi/20261110_baseline_v2/` holds the
3600-second primary campaign and the failed license preflight. **Zero Gurobi
cohort jobs were launched.** Every absent observation is NOT_RUN, not a timeout
or a synthetic failed/optimal solve. The separate HiGHS driver smoke campaign
tests actual isolated-worker execution and resume on one M=1 archived instance.

`report.jl` produces per-instance/aggregate CSVs, immutable reference copies,
reference-versus-reproduction CSV/Markdown, paired RDP/RJT checks, root values
and a separate IR-B&B extension table. Average times use only physically
validated optimal runs. Native optimal counts are also retained. IR-B&B is
gated on completed RDP/RJT baselines and is not an original Table 3 column.

## Commands

Rebuild the frozen data into **new** directories (existing data are never
overwritten):

```bash
julia +1.10.3 --startup-file=no --project=@stdlib scripts/table3_sequential/SourceGenerator.jl NEW_RAW_1103
julia --project=. scripts/table3_sequential/SourceGenerator.jl NEW_RAW_111
julia --project=. scripts/table3_sequential/campaign.jl freeze NEW_RAW_1103 NEW_RAW_111 NEW_FROZEN_CATALOG
```

After a valid Gurobi installation/license is available, resume staged execution:

```bash
julia --project=. scripts/table3_sequential/campaign.jl run experiments/results/table3_sequential_gurobi/20261110_baseline_v2 --methods=rdp --sizes=1,2,3
julia --project=. scripts/table3_sequential/campaign.jl run experiments/results/table3_sequential_gurobi/20261110_baseline_v2 --methods=rjt --sizes=1,2,3
julia --project=. scripts/table3_sequential/report.jl experiments/results/table3_sequential_gurobi/20261110_baseline_v2
```

For the source numerical mode, prepare a separate new campaign:

```bash
julia --project=. scripts/table3_sequential/campaign.jl prepare experiments/table3_sequential/frozen_julia1103 NEW_SOURCE_MODE_CAMPAIGN --solver=gurobi --numerical-mode=publication_offsets --budget=3600 --memory-gib=14
```

Larger-M and original DP jobs require explicit invocation. For example,
`run CAMPAIGN --methods=rdp,rjt --sizes=4 --allow-large` and
`run CAMPAIGN --methods=dp_milp --sizes=1,2,3`. The IR-B&B extension starts with
`run CAMPAIGN --methods=irbb_fi,irbb_legacy --sizes=1,2`; the code enforces
completed baseline prerequisites. No such larger or IR-B&B campaign is launched
automatically. Protocol/source changes require a new campaign, preserving the old.

Tests: `julia --project=. -e 'using Pkg; Pkg.test(allow_reresolve=false)'`.
`Dates` was declared as a test-only stdlib extra so the pipeline tests run in
Pkg's isolated test environment. No runtime solver dependency or Manifest was
changed. The initial full test invocation exposed that missing declaration;
the final full suite was rerun after fixing it. The sanity run's source hashes
retain the pre-declaration Project.toml; mathematical implementation files and
runtime package versions are unchanged by that test metadata addition.
The added source-dependent pipeline checks are optional when its separately
downloaded pinned source is absent; frozen-archive checks are optional without
local data. Here both are present. They verify stream/warm-up semantics,
reference transcription, independent pure LP versus MIP bounds, watchdog
budgets, atomic writes, preservation on resume and optimal-only aggregation.

Final test result: **13,016 passed**, including all 12,968 preceding checks
and 48 new pipeline checks. The actual isolated-worker smoke run at
`experiments/results/table3_sequential_driver_smoke/20261110_v3/` completed
two M=1 jobs (RDP and RJT, seed ID 1). Resume preserved both result files byte
for byte and launched no replacement worker. This adds two driver checks to
the separate 18-solve mathematical cohort; it is not a 50-instance campaign.
All 400 frozen inputs and hashes were reloaded and checked. The maximum
Float64 normalization change from the archived arrays is
`1.1102230246251565e-16`. No instance was replaced after freezing.

## Files changed for this follow-up

New files are `scripts/table3_sequential/SourceGenerator.jl`, `Common.jl`,
`SourceModels.jl`, `worker.jl`, `campaign.jl`, `report.jl`, `validate.jl`,
`PublishedTable3.csv`, `test/table3_pipeline.jl` and this document.
Modified files are `.gitignore` (allow these sources), `Project.toml`
(test-only Dates declaration), `test/runtests.jl` (optional include), README,
`docs/IMPLEMENTATION_STATUS.md` and the ignored local `docs/STATUS.md`.
The preceding sequential implementation and earlier changes remain untouched.
