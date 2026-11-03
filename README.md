# Decision Programming — IR-B&B

Julia implementations of Information Relaxation Branch-and-Bound for finite
influence diagrams, with an exact specialization for ex-ante Extended Oil
Wildcatter and a research prototype that branches on partial decision policies.
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
  instances/     In-memory Oil and maintenance model constructors
  evaluation/    Exact policy evaluation and structured bound oracles
  relaxations/   Causal information relaxation and lifted policy fixings
  algorithms/    Probing, partial-policy and structured IR-B&B
  caching/       Exact context keys, memoization and incremental updates
  formulations/  Independent and source-derived Oil RDP models
  utilities/     Record and environment helpers
examples/        Small standalone usage examples
test/            Algorithm, bound-validity and model correctness tests
scripts/         Dependency setup and upstream model access
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
