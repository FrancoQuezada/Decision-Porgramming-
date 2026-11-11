# Code organization

The public tree contains the Julia implementation and its supporting material.
Local research campaigns keep their existing paths but are outside the
publication allowlist in `.gitignore`.

`src/DecisionProgrammingAlgorithms.jl` loads all package components. The physical
models and policy classes are shared by independent evaluators, formulations and
search implementations; experimental runners are not imported by the package.

| Directory | Responsibility |
| --- | --- |
| `src/core` | Search interfaces, finite influence diagrams, policies and partial policy mappings |
| `src/instances` | Oil model representation, sequential testing policies and in-memory Oil/maintenance constructors |
| `src/evaluation` | Exact rational Oil oracles, fixed-policy inference and supported structured optimization |
| `src/relaxations` | Information enlargement that preserves physical kernels and lifted policy fixings |
| `src/algorithms` | Ex-ante/sequential Oil probing IR-B&B, enumerative partial-policy IR-B&B and structured variants |
| `src/caching` | Exact model/context identity, bounded dictionary storage and dependency-directed snapshots |
| `src/formulations` | Ex-ante/sequential Oil RDP, shared package RJT and runtime adapters to pinned original/corrected source |
| `src/utilities` | Optional serialization and environment-record helpers |

`examples` contains small explicit entry points without campaign loops or saved
datasets. `test` contains the existing mathematical and implementation checks.
They are not benchmarks. External-source and local-snapshot checks are optional
when their separately obtained inputs are absent.

`scripts/setup_external.jl` retrieves the pinned upstream repositories into the
ignored `external` directory. `scripts/OriginalSources.jl` accesses upstream
generator/model definitions and the DecisionProgramming.jl DP/RJT models.
`scripts/setup_cplex.jl` prepares the optional locked CPLEX environment. These
are setup/model-access tools, not experiment launchers.

The Oil-specific extension is documented in [sequential_oil.md](sequential_oil.md).
`scripts/audit_sequential_sources.jl` checks the separate newer source pin and
small parsed source functions; `scripts/benchmark_sequential_oil.jl` is an
explicit, fixed M=1,2,3 comparison runner. It saves a new ignored run directory
and does not touch the older local campaigns. Neither script is loaded when
importing the package.

Local-only material includes `experiments`, campaign scripts, scheduler tests,
performance reports, result figures, prototypes, downloaded papers and the
detailed `docs/STATUS.md` research log. Keeping those files locally does not add
them to future commits. New top-level publication content must be explicitly
enabled in `.gitignore`; ordinary changes under `src` remain trackable.

The GitHub history is based on its existing manuscript branch. The previous
local research history is preserved in a `local/research-before-github-*` branch
and is not an ancestor of the published code commit. Only `main` is configured
for pushing to `origin`; do not use `git push --all` or `--mirror` to publish
local research branches.
