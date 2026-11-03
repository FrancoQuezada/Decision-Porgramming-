# Context equivalence and safe reuse

Before stage k, filter original fixed rows `(d,h_d,a)` to d>=k and to histories
matching all already assigned information variables. Remove those assigned
components from the retained history. Sort the resulting `(d,h_future,a)` tuples.
Call this residual signature R_k(P,h). Decision identity and k determine which
variables the future tuple indexes, including their original ordering.

The planned immutable key is

```
(exact original model, relaxed information, k, h[S_k], R_k(P,h)).
```

The model identity contains node types/names/cardinalities, ordered chance
parents, every exact kernel entry, original information, every utility scope and
entry, and the unconstrained expected-utility model convention. Relaxed
information is separate. Cache ownership uses private model snapshots. Different
instances or relaxations cannot accidentally share entries. A precomputed hash
can accelerate lookup but is never an equality certificate: full immutable
content equality must still be checked.

Equal keys imply equal remaining chance factors, closing utilities, action
domains and fixing restrictions under every common suffix assignment. Backward
induction on the structured recurrence gives equal values and equal smallest
maximizing actions. This justifies dropping earlier fixings, fixings inconsistent
with the prefix, and past state values absent from the physical separator **only
when** the residual signature and support condition above are retained.

For example, after D1=2, a new fixing of D2(D1=1) does not change a continuation.
After D1=1 it does change the key, even if the numerical optimum happens to tie.
Decision-dependent probability parents remain in S_k until their last future
use. No information-history coupling is discarded on an unsupported diagram.

Additional policy constraints and risk criteria are not represented in this
release and are outside the key theorem. Supporting them would require new
dependencies and model identity fields, not ignoring their effects.
