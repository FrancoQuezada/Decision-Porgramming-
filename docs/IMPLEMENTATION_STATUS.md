# Implementation scope

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

Experimental inputs, outputs and performance evidence are not part of this
publication. The complete local research log remains in `docs/STATUS.md` outside
the publication allowlist, alongside the preserved local campaigns.
