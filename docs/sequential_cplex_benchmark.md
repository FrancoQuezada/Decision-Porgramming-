# Sequential Oil baseline with CPLEX 22.1.1

On 2026-11-10 the dense sequential RDP and the existing
DecisionProgramming.jl RJT formulation were executed with CPLEX 22.1.1 on the
first five archived source-replay instances for every supported problem size.
The exact sequential IR-B&B baseline was run under the same Phase-4 process,
timing and resource protocol. This is a local computational baseline; it is not
a reproduction of the publication's Gurobi timings.

## Protocol

- Inputs are the frozen Julia 1.10.3 source replay snapshots with archived
  indices 1--5. Every method verifies the stored instance and file hashes.
- RDP uses the existing dense formulation. RJT uses the existing package
  junction tree and restored Float64 physical utility coefficients. Neither
  mathematical formulation was changed for the benchmark.
- RDP and RJT use the locked `environments/cplex` project and the established
  Phase-4 `CPLEX-Default` settings: one thread, wall clock, deterministic
  parallel mode, random seed 0, 512 MiB work memory and 8192 MiB tree memory.
- Each execution has a 3600-second total procedure budget plus parent-process
  construction, initialization and validation guards. The scheduler admits at
  most 4/2/1 small/medium/large workers.
- Existing guards are retained: at most 200,000 dense RDP segments, five RJT
  tests and 24 IR-B&B policy rows. They admit RDP/RJT through M=5 and IR-B&B
  through M=3. All larger planned rows are recorded as size-guard exclusions.
- Reported means use only certified optimal executions. Policy extraction is
  checked by exact rational physical evaluation, serialization/reload and an
  independent exact belief-state DP for every executed M<=5 case.

## Results

The final campaign contains 160 planned method-instance jobs: 79 certified
optima, one retained validation error and 80 static size-guard exclusions. The
following totals are means in seconds over certified optima. `O/F` is the
number of certified optima and usable exact physical policies out of five.

| M | RDP total / solver / O/F | RJT total / solver / O/F | IR-B&B FI total / O/F | IR-B&B legacy total / O/F |
| --- | --- | --- | --- | --- |
| 1 | 0.009740 / 0.001409 / 5/5 | 0.018342 / 0.004233 / 5/5 | 0.000383 / 5/5 | 0.000171 / 5/5 |
| 2 | 0.034568 / 0.011687 / 5/5 | 0.051481 / 0.015367 / 5/5 | 0.010689 / 5/5 | 0.010719 / 5/5 |
| 3 | 0.227228 / 0.128805 / 5/5 | 0.268651 / 0.057879 / 5/5 | 0.024582 / 5/5 | 0.024596 / 5/5 |
| 4 | 1.338908 / 0.890518 / 5/5 | 2.261665 / 0.230089 / 5/5 | guard | guard |
| 5 | 238.077334 / 233.522814 / 5/5 | 26.967425 / 2.197540 / 4/5 | guard | guard |
| 6--8 | guard | guard | guard | guard |

Actual model dimensions are retained rather than adjusted to match the
published table. At M=5, dense RDP has 68,266 variables and 5,119 constraints;
RJT has 51,859 variables and 62,789 constraints. The complete CSV, Markdown and
LaTeX reports are in
`experiments/results/sequential_cplex/20261110_baseline/reports/20261110T220807752304Z/`.
The published Gurobi Table 3 is copied separately in that directory and is not
combined with these observations. RR% remains deferred.

RDP and RJT produced usable exact policies on all 25 commonly executed physical
instances, and all 25 policy values agree exactly. Both methods satisfy the
stricter full certificate on 24 pairs. In RJT M=5 index 2, CPLEX returned
`integer optimal, tolerance` with a relative MIP gap of 7.99e-6. Its recovered
policy equals the independent exact DP optimum, but the native model objective
exceeds the exact physical value by about 2.02e-5. The campaign therefore keeps
the row as `ERROR: OBJECTIVE_POLICY_MISMATCH`, excludes it from the timing mean,
and retains the raw bound, gap, policy and exact validation evidence.

Both IR-B&B variants visit one node on every selected M=1--3 input. These
archived inputs have no gain from observing every report for free at M=3, so
the result is a degeneracy of this five-instance subset and provides no evidence
of general computational superiority.

## Validation and reproduction

Direct CPLEX validation passed 91 checks, including dense/reduced RDP and RJT
agreement with the exact reference on archived M=1--2 inputs, native parameter
readback and no-incumbent time-limit handling. The scheduler/reporting tests
pass four independent test groups. The root package test suite passes 13,028
checks. A resume dry run preserved the hashes of all 160 terminal records.

The campaign is resumable and does not regenerate inputs:

```bash
python3 scripts/sequential_cplex/benchmark.py status \
  experiments/results/sequential_cplex/20261110_baseline
python3 scripts/sequential_cplex/report.py \
  experiments/results/sequential_cplex/20261110_baseline
```

No Gurobi package was used or installed for this baseline. No algorithmic
improvement, remote push or commit was made.
