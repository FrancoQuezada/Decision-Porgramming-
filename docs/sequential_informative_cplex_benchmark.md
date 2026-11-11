# Sequential informative Oil Wildcatter campaign

This is a prepared, isolated campaign for 25 newly generated instances and 100
optimization runs. Preparation does not modify the earlier sequential or Phase-4
campaigns. The generator uses `generate_oil(M, seed; kind=:informative)` and accepts
an instance only when the exact rational comparison gives
`F(N) > F(empty)`. The manifest records every accepted seed, candidate index,
physical-instance hash, file hash and both exact values.

Choose a new directory below `experiments/results`:

```bash
CAMPAIGN=experiments/results/sequential_informative_2026_11
```

Generate and independently replay/validate the 25 instances without building an
optimization model:

```bash
julia --project=. scripts/sequential_informative_cplex/generate.jl "$CAMPAIGN"
julia --project=. scripts/sequential_informative_cplex/validate_instances.jl "$CAMPAIGN"
```

Prepare the immutable 100-job plan. This command does not launch workers:

```bash
python3 scripts/sequential_informative_cplex/benchmark.py prepare "$CAMPAIGN"
```

The following command is the explicit manual launch point:

```bash
python3 scripts/sequential_informative_cplex/benchmark.py run "$CAMPAIGN"
```

An interrupted campaign is resumed with the same plan and atomic results. Completed
jobs are skipped; add `--retry-failed` only when terminal failures should also be
retried:

```bash
python3 scripts/sequential_informative_cplex/benchmark.py resume "$CAMPAIGN"
python3 scripts/sequential_informative_cplex/benchmark.py status "$CAMPAIGN"
```

Generate reports strictly from saved records:

```bash
python3 scripts/sequential_informative_cplex/report.py "$CAMPAIGN"
```

The report directory contains `per_instance.csv`, `aggregated.csv`,
`comparison.md`, and `comparison.tex`. It includes observed and certified runtimes,
optimal/feasible counts, actual CPLEX model dimensions, and IR-B&B node, pruning,
evaluation, cache and bound-time statistics. Missing or unexecuted runs remain
explicitly marked; they are not imputed.

## Methods and resource scheduling

Every physical instance is reused by all four methods: dense Sequential RDP with
CPLEX-Default, Sequential RJT with CPLEX-Default, IR-B&B with the
`full_information` bound, and IR-B&B with the `legacy_nonsequential` bound. The
worker passes nonrestrictive `typemax(Int)` values to the pre-existing dimensional
guard arguments. It does not change the formulations, bounds, branching order or
policy evaluation.

Execution delegates to the existing Phase-4 Linux process scheduler. Each run has
an independent one-thread Julia process. Scheduling is dynamic, with at most four
workers globally and tier limits of 4/2/1 for M=1–3/M=4/M=5. Admission combines
per-method reservations, live process-tree RSS, 24 GiB global experimental RAM,
16 GiB per job and 3 GiB system headroom. The scheduler enforces a 3600-second
solve wall-clock watchdog, monitors descendants, terminates orphan processes,
saves attempt and terminal records atomically, and skips completed jobs on resume.
CPLEX jobs use the existing `experiments/phase4_extended/cplex.toml`
`CPLEX-Default` configuration with one optimizer thread.

Warm-up uses a separate one-test instance before the measured solve. Exact policy
validation and the independent sequential belief-state DP reference run after a
recoverable solve snapshot, following the existing sequential Phase-4 timing
convention.
