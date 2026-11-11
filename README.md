# Decision Programming — IR-B&B

Julia implementations of Information Relaxation Branch-and-Bound for finite
influence diagrams, with exact specializations for ex-ante and sequential
Extended Oil Wildcatter and a research prototype over partial decision policies.
Models use deterministic policies, causal chance kernels and additive expected
utility. The repository makes no claim of novelty or computational superiority.

The published repository contains model and algorithm code, correctness tests,
small usage examples, locked environments and method documentation. Experimental
campaigns, generated instances, numerical result files, logs, plots, Python
pilots and third-party PDFs remain local and are excluded from Git publication.
The existing [research manuscript](paper/main.tex) is retained.

## Implemented algorithms and models

| Component | Entry point | Scope |
| --- | --- | --- |
| Probing IR-B&B | `solve_probing` | Exact rational portfolio search for ex-ante Oil Wildcatter, with recovered drilling policies |
| Partial-policy IR-B&B | `solve_irbb` | Finite influence-diagram research prototype with an exhaustive relaxed-policy oracle |
| Structured IR-B&B | `solve_reuse_irbb` | Variants B/C/D: uncached, cached and incremental exact bounds on supported information structures |
| Independent Oil RDP | `solve_rdp` | JuMP formulation with HiGHS by default, consistent utility shifts and physical policy evaluation |
| Source-derived Oil RDP | `solve_paper_rdp` | Original/corrected adapters using locally checked-out, pinned upstream source; configurable JuMP optimizer |
| Sequential Oil IR-B&B | `solve_sequential_probing` | Exact baseline over adaptive testing-policy rows, with full-information or conservative legacy bounds |
| Sequential Oil RDP | `solve_sequential_rdp` | Adaptive testing policies; availability-reduced or dense (8a)-(8f) formulation |
| Oil RJT | `solve_rjt`, `solve_sequential_rjt` | Shared physical diagram and DecisionProgramming.jl junction-tree formulation for both information structures |
| Sequential exact reference | `solve_sequential_dp` | Independent backward DP on joint Oil/geology beliefs, for small-instance validation |

The probing bound requires passive signals that can be ignored, an unchanged
latent physical model, and nonnegative additive test costs. The partial-policy
prototype preserves every fixed action in all augmented histories and leaves
causal probability kernels unchanged. Its exhaustive bound oracle can be more
expensive than original policy enumeration. Structured bounds require the
documented separator and fixing-dependency support condition; other models use
enumerative fallback or an explicit exception. These implementations do not
establish a competitive general-purpose exact DP algorithm.

## Layout

```text
src/
  core/          Influence diagrams, policies and common interfaces
  instances/     In-memory Oil/maintenance models and sequential Oil policies
  evaluation/    Exact policy evaluation and structured bound oracles
  relaxations/   Causal information relaxation and lifted policy fixings
  algorithms/    Ex-ante/sequential probing, partial-policy and structured IR-B&B
  caching/       Exact context keys, memoization and incremental updates
  formulations/  Ex-ante/sequential Oil RDP and RJT models
  utilities/     Record and environment helpers
examples/        Small standalone usage examples
test/            Algorithm, bound-validity and model correctness tests
scripts/         Setup, source access/audit and small sequential Oil comparison
environments/    Optional locked CPLEX environment
docs/            Mathematical scope and implementation notes
paper/           Existing LaTeX manuscript
```

## Setup and use

Julia 1.11 is required; the locked environment was prepared with Julia 1.11.7.
The root environment uses the free HiGHS solver.

```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. examples/probing.jl 4 26
julia --project=. examples/rdp.jl 3 26
julia --project=. examples/nonprobing.jl A
julia --project=. examples/nonprobing.jl C
```

Examples run only when explicitly invoked and print their output without saving
an experimental dataset. The non-probing example accepts `A`, `B`, `C` or `D`.
To use the package directly:

```julia
using DecisionProgrammingAlgorithms

x = generate_oil(4, 26)
probing = solve_probing(x)

diagram = maintenance_instance()
relaxation = InformationRelaxation(diagram, Dict(3 => [2]))
reference = solve_irbb(relaxation)
cached = solve_reuse_irbb(relaxation; variant=:C).result
```

For adaptive Oil testing, use the same physical instance:

```julia
x = generate_oil(2, 26; states=2)
sequential = solve_sequential_probing(x; bound=:legacy_nonsequential)
reference = solve_sequential_dp(x)
rdp = solve_sequential_rdp(x)
rjt = solve_sequential_rjt(x)
@assert sequential.value == reference.value == rdp.policy_value == rjt.policy_value
```

This baseline defines every testing-history row and branches on the first
unfixed row. Its two optimistic bounds can remain loose at complete policies;
the search can enumerate the full policy tree. See the
[sequential mathematical contract and limits](docs/sequential_oil.md) and
[validation evidence](docs/sequential_oil_validation.md). After correctness tests
pass, run `julia --project=. scripts/benchmark_sequential_oil.jl` for the fixed
M=1,2,3 comparison; exact inputs, policies and results are saved to a fresh local
directory excluded from Git publication.

The [Supplementary Table 3 reproduction pipeline](docs/table3_sequential_reproduction.md)
replays the 50 archived Gurobi seeds with the original shared RNG stream and
freezes identical source-derived inputs for all methods. Its default-Gurobi
timing campaign is prepared but currently blocked by the missing local license;
separate HiGHS mathematical checks are labeled accordingly.

The [sequential CPLEX baseline](docs/sequential_cplex_benchmark.md) runs the
dense RDP, package RJT and both exact IR-B&B bounds on five frozen archived
instances per supported size. CPLEX 22.1.1 results are reported separately from
the published Gurobi table, with exact recovered-policy checks and explicit
size-guard exclusions.

The [new informative sequential campaign](docs/sequential_informative_cplex_benchmark.md)
prepares 25 reproducible `generate_oil` instances and a resumable 100-run
RDP/RJT/IR-B&B plan without launching the experiment during setup.

The [Sequential IR-B&B ablation](docs/sequential_irbb_variants.md) adds exact
reachability, cost-aware and combined variants, their validity proofs, targeted
diagnostics and a prepared resumable comparison campaign.

The existing tests can be invoked separately with:

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

Tests construct their small inputs in memory or temporary directories. Tests
requiring the original experimental repository run only when its local checkout
is present; optional Python-pilot snapshot checks run only when those local
snapshots exist. No experimental inputs or outputs are bundled here.

For source-derived adapters and upstream audits, obtain the pinned read-only
references explicitly:

```bash
julia --project=. scripts/setup_external.jl
```

External checkouts are ignored by Git. For an existing licensed CPLEX
installation, set `CPLEX_STUDIO_BINARIES` to its library directory and run
`julia --project=. scripts/setup_cplex.jl`; use
`--project=environments/cplex` for CPLEX applications. CPLEX is optional and
does not change the root environment.

## Documentation and scientific boundaries

See [implementation status](docs/IMPLEMENTATION_STATUS.md),
[architecture](docs/architecture.md),
[mathematical contract](docs/mathematical_formulation.md),
[algorithm interfaces](docs/algorithms.md),
[structured relaxation](docs/structured_relaxation.md),
[exact context equivalence](docs/context_equivalence.md),
[cache reuse](docs/hash_based_reuse.md),
[incremental updates](docs/incremental_bounds.md), and
[source-derived RDP corrections](docs/phase4_source_corrections.md).

IR-B&B certificates use exact rational arithmetic for the explicitly represented
input model. MILP certificates use numerical solver tolerances. Arbitrary policy
constraints, risk objectives, and unrestricted efficient influence-diagram
optimization remain outside the implemented scope.

## Sources and licensing

`external.lock.toml` records upstream URLs and exact commits. External sources
are not bundled. The pinned experimental repository has no license file;
redistribution permission is not assumed. DecisionProgramming.jl is MIT-licensed;
its original notices apply. No new license is assigned on behalf of the research
authors, and supplied third-party manuscripts are not redistributed.

The working-draft manuscript is in [`paper/main.tex`](paper/main.tex); compile
it from `paper/` with `latexmk -pdf main.tex` when the LaTeX packages are available.
