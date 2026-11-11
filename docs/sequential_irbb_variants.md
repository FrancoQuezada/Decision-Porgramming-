# Sequential Oil IR-B&B variants

These variants remain specific to passive Sequential Oil Wildcatter. They are
not a general exact algorithm for arbitrary Decision Programming influence
diagrams and do not establish novelty or computational superiority.

## Interface and ablation contract

```julia
solve_sequential_probing(x;
    variant=:baseline,                 # :baseline, :reachability, :cost_aware, :combined
    bound=:legacy_nonsequential,       # or :full_information
    max_rows=100_000,
    time_limit=Inf,
    progress_every=0)
```

The variants are deliberately factorial only in reachability, cost bounds and
new caches:

| Variant | Reachability | Cost-aware bound | New caches |
|---|---:|---:|---:|
| `baseline` | no | no | no |
| `reachability` | yes | no | no |
| `cost_aware` | no | yes | no |
| `combined` | yes | yes | yes |

All variants retain the first-unfixed-row order, skip-first DFS, exact rational
comparisons and the selected FI or Legacy primary bound. The baseline still
completes every unfixed row with skip, evaluates a feasible policy at every
node and permits loose complete-leaf bounds. Its changes are instrumentation
and an optional cooperative time limit only; defaults reproduce the previous
search.

## Reachability reduction

Let `H_1(P)={()}`. For each potentially reachable history `h in H_i(P)`:

- append `(h,0)` when row `(i,h)` is fixed to skip or remains unfixed;
- append `(h,r)`, `r=1,...,R`, when the row is fixed to test or remains unfixed.

The corresponding `(i,h)` are the potentially reachable rows. This definition
uses only the causal N/A/report support implied by actions; it deliberately
does not remove numerically zero-probability reports.

**Validity.** A row outside this inductive set cannot occur under any completion
of `P`, because its first inconsistent coordinate would require N/A after test
or a real report after skip. Its action therefore changes neither trajectory
probabilities, testing costs nor drilling decisions. Removing all such fixings
defines a canonical representative. Conversely, any canonical policy can be
extended by assigning skip to omitted rows, producing a complete original
policy with identical physical trajectories and value. Thus canonical classes
are in value-preserving correspondence with physical policies and maximizing
over them preserves the original optimum.

Complete canonical policies are evaluated explicitly. The algorithm never
uses a loose upper bound to declare such a policy complete.

## Cost-aware upper bound

For a partial policy `P`, define `C_min(P)` as the minimum expected testing cost
over its original feasible completions. With unnormalized latent likelihood
`l(s)` and marginal `beta(s)=sum_o p(o)p(s|o)`, the exact backward recursion is

```text
C(i,h,l) = min over allowed a at (i,h) of
  skip: C(i+1,(h,0),l)
  test: c_i sum_s beta(s)l(s)
        + sum_r C(i+1,(h,r), l(s)p_i(r|s)).
```

A fixed row has a singleton allowed action; an unfixed row has both. This
recursion uses only the observed history, so it does not relax the testing
information structure. It follows by backward induction that it equals the
minimum expected cost of a compatible original policy, including conditional
fixed decisions.

Let `F(N)` be the optimal operating value when all potential reports are
available for free. For every completion `pi` of `P`, passive signals and the
unchanged causal kernels permit embedding `pi` in the all-report information
relaxation, so its operating reward is at most `F(N)`. Its expected testing cost
is at least `C_min(P)`. Therefore

```text
V(pi) <= F(N) - C_min(P) = UB_cost(P).
```

The implemented bound is

```text
min(UB_primary(P), UB_cost(P)),
```

where `UB_primary` is the unchanged FI or Legacy bound. The minimum of valid
upper bounds remains valid. The proof uses nonnegative additive costs, passive
tests, unchanged chance kernels and ignorable extra reports; it must not be
reused for active tests or coupled policy constraints without a new proof.

### Root certificate

Any nontrivial sequential policy has a first commissioned test on an all-N/A
prefix. That test is performed with probability one, so its cost is at least
`min_i c_i`. Hence every nontrivial policy satisfies

```text
V(pi) <= F(N) - min_i c_i.
```

The all-skip policy has value `F(empty)`. When
`F(N)-min_i c_i <= F(empty)`, the all-skip policy is exactly optimal. This is
the implemented one-node root certificate. It is stronger than treating only
globally required/forbidden tests and is valid for conditional policies.

## Combined caches

Caches are local to one solve and therefore one physical instance and bound.

- A physical-policy key records testing actions only on histories reached by
  that complete testing policy. The exact forward evaluator never consults an
  omitted action, so equal keys imply equal induced probabilities, costs and
  optimized drilling values.
- A partial-policy key records every fixed action on a potentially reachable
  row after canonicalization. With the instance and bound fixed by the solve,
  this retains every input used by the primary and cost-aware bounds.
- The global row vector is constructed once in `combined`; exact operating
  values retain the pre-existing `OilEvaluator` mask cache.

The implementation records actual policy-evaluation and bound cache hits and
misses separately. A zero hit count is valid evidence that a cache did not help
a particular tree.

## Validation evidence

`test/sequential_irbb_variants.jl` checks:

- 1,215 cost-bound inequalities against exhaustive compatible completions;
- four variants, both primary bounds and five small/degenerate instances
  against the independent exact sequential DP;
- exact physical reevaluation of every recovered policy;
- canonical equivalence of policies differing only at unreachable rows;
- preservation of the optimum after grouping all small complete policies by
  physical key;
- the one-node root certificate.

No floating-point pruning tolerance is introduced. An optional cooperative
time limit returns `:time_limit`, the best physical policy found and the
unchanged valid root upper bound; it never returns an optimal status.

## Short targeted diagnostics

The following are two-second diagnostic runs, not benchmark timings. They
include JIT/order effects and exist only to identify the bottleneck. Raw exact
records are in
`experiments/results/sequential_irbb_diagnostics/20261111_short/`.

| Instance | Variant | FI status/nodes | Legacy status/nodes |
|---|---|---:|---:|
| `j03_m4` | Baseline | time limit / 9,739 | time limit / 12,163 |
| `j03_m4` | Reachability | time limit / 2,019 | optimal / 2,021 |
| `j03_m4` | CostAware | optimal / 1 | optimal / 1 |
| `j03_m4` | Combined | optimal / 1 | optimal / 1 |
| `j01_m5` | Baseline | time limit / 4,032 | time limit / 3,927 |
| `j01_m5` | Reachability | time limit / 2,319 | time limit / 3,143 |
| `j01_m5` | CostAware | time limit / 2,848 | time limit / 4,029 |
| `j01_m5` | Combined | optimal / 23 | optimal / 23 |

For `j03_m4`, `F(empty)=114.3430464203`, `F(N)=114.5135872745` and
`min(c)=25`; the nontrivial-policy upper bound is `89.5135872745`, below
`F(empty)`, so the cost certificate proves optimality immediately. For
`j01_m5`, the root certificate does not apply. Reachability or the cost bound
alone does not close the short run. Combined closes both bounds in 23 nodes,
with 12 physical-policy evaluation cache hits. This isolates the observed
benefit to the interaction of canonical reachability, stronger bounds and
evaluation reuse; the full prepared ablation is required before generalizing.

## Prepared parallel ablation

The campaign reuses the 25 immutable informative instances and schedules
`25 x 4 x 2 = 200` independent jobs through the existing Phase-4 process,
memory-admission, monitoring, watchdog, atomic-save and resume infrastructure.
Preparation does not launch a worker:

```bash
OUTPUT=experiments/results/sequential_irbb_ablation/20261111_v1
python3 scripts/sequential_irbb_ablation/benchmark.py prepare "$OUTPUT"
```

Manual launch, resume, status and reporting:

```bash
python3 scripts/sequential_irbb_ablation/benchmark.py run "$OUTPUT"
python3 scripts/sequential_irbb_ablation/benchmark.py resume "$OUTPUT"
python3 scripts/sequential_irbb_ablation/benchmark.py status "$OUTPUT"
python3 scripts/sequential_irbb_ablation/report.py "$OUTPUT"
```

The scheduler retains 3600 seconds per job, 24 GiB global memory, live process
admission, at most eight one-thread workers and resumable terminal records.
The 200-job campaign is prepared at
`experiments/results/sequential_irbb_ablation/20261111_v1/` with all jobs
pending. No campaign worker has been launched.
