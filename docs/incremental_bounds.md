# Dependency-directed updates and inherited bounds

Implement incremental updates only after the cached oracle has passed its
independent equality and negative-reuse tests (milestone C: 581 checks).

## Snapshot semantics

A message position is `(k, full prefix)`. This is deliberately more conservative
than the ordinary cache key. A bound snapshot stores message values at positions,
the full partial policy for that query, and a reverse dependency map. A position
depends on **every possible original policy row** at a decision d>=k whose
already assigned information agrees with the prefix. These dependencies include
unfixed rows and unreachable contexts; they are independent of the current
optimizer's selected actions and positive-probability search paths.

For changed original rows Delta, invalidate the union of their recorded position
sets. Remove invalid entries from the new snapshot and remove their reverse-map
references. Retain unchanged entries, then run the same recurrence at the root.
An unchanged position returns its exact value before building a hash key. An
affected/new position uses the ordinary exact cache and computes its recurrence
only if that cache also misses. Newly computed or cached positions receive their
full conservative dependencies. Parent snapshots are not mutated.

Pseudocode:

```
Delta = changed_rows(parent.policy, child.policy)
affected = union(parent.dependents[row] for row in Delta)
child.messages = parent.messages without affected
evaluate root:
    if position retained: exact incremental reuse
    else if context key in shared cache: exact hash reuse
    else: evaluate recurrence and store exact message
```

## Justification

If none of a position's dependencies changes, the residual fixing signature is
identical: all excluded original rows are either in the past or inconsistent
with that prefix. Physical separator assignments, model and information remain
identical. Context equivalence proves the retained value remains exact. If a
dependency changes, invalidation is conservative: even a numerically unchanged
value must be recovered by an exact key or recomputed. This supports adding,
removing and changing fixings, and thus sibling/backtracking queries as well as
parent-to-child updates. Invalid entries are removed even when currently
unreachable, preventing later retractions from reviving stale values.

An incremental structured update rejects snapshots from another model or
information relaxation before reuse. Enumerative fallback does not read snapshots.
No heuristic
dominance or unproved stability test is used. Omitting fixed rows merely because
their current optimal branch was not visited would not be a safe dependency rule.

## Separate mechanisms and accounting

An ordinary cache hit checks full key equality. An incremental reuse checks an
unchanged position using the dependency theorem and avoids that key construction
and dictionary lookup. `reused_messages` counts only the latter. Invalidated
positions, actual affected-position recomputations and total recurrence solves
are separate counters. Snapshot copying and invalidation have measured overhead;
fewer hash accesses do not imply a runtime improvement.

Optional inherited pruning uses the parent's valid upper bound after another
feasible policy improves the incumbent. It is recorded as `:inherited`, never
as an exact relaxed node value or cache hit. It is off for the B/C/D comparison
so all variants use the same bound, branching and incumbent rules.
