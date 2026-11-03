# Exact reuse through native Julia dictionaries

Variant B evaluates the structured recurrence without memoization. Variant C
uses `SubproblemCache`, a native `Dict{ContextKey,MessageSolution}` shared across
all bound queries in a solve. Values and smallest maximizing actions are exact.
The terminal zero is not cached, so hits cannot merely reflect sharing a trivial
terminal constant. Chance and decision recurrence solves are counted separately.

Key equality follows `context_equivalence.md`. Model identity stores full exact
content as well as a precomputed hash; `isequal` compares content, never only its
hash. Tests force collisions and require distinct entries. Different physical
models and relaxed information patterns have separate namespaces, even when
some numerical values coincide. Compiled plans own private copies of model arrays.

Counters distinguish oracle calls, complete-policy evaluations in fallback,
structured recurrence solves, dictionary hits/misses, unique keys seen, retained
entries, peak retained entries, evictions, key construction time and exclusive
recurrence arithmetic time. `compute_time` excludes child-call durations; key
construction is outside that arithmetic timer. Total bound wall time includes
all overhead and is the primary measure of oracle cost.

An optional nonnegative `max_entries` uses FIFO eviction. Capacity zero disables
storage without changing the recurrence. `clear_cache!` empties data and resets
the cache's counters; an oracle's lifetime counters are separate. Unique-key
tracking is optional: when enabled its `Set` is not capacity limited. The entry
limit is not a total-memory budget. Reported cache memory includes bookkeeping
and unique-key tracking, with entry memory separately available. Julia allocation
counts and dictionary object sizes are not peak resident memory.

Equal values alone do not authorize reuse. A relevant action fixing changes the
key even if its optimum happens to equal the old result. Irrelevant past fixings
or incompatible future histories disappear only according to the proven residual
restriction construction. No statistical, dominance or approximate cache rule
is used for pruning.

`run_phase3_reuse_audit.jl` separates within-query sharing from cross-B&B-node
sharing by replaying identical bound queries with a cache cleared per query and
a cache retained across queries. Its recurrence-count differences measure real
cross-node work savings; total dictionary hits alone would not establish this.

Inherited ancestor bounds are a different mechanism: restricting policies cannot
increase the relaxed optimum. A parent upper bound can therefore certify a
descendant prune, but it is not an exact descendant value or dictionary hit.
Incremental reuse is separately documented in `incremental_bounds.md`.
