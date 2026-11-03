# Phase 3: exact structured relaxation

Design and implementation contract, 2026-10-31. The existing enumerative
relaxation and Oil algorithms remain independent references.

## Supported decomposition

Use the existing causal order 1,...,n. Assign each utility factor to its largest
variable index; constant factors belong to stage 0. Before variable k define
the physical separator S_k as the earlier variables occurring in a chance
factor at a stage >= k or a utility factor closing at a stage >= k. All arrays
and calculations use the existing exact rational input model.

Define F_k as the earlier variables in an **original** information set of a
decision at a stage >= k. This is conservative: it accounts for every possible
partial-policy fixing, including currently unfixed and unreachable rows.

The sufficient support condition is, for each decision d,

```
S_d union F_d ⊆ I_relaxed(d).
```

It permits forgetting irrelevant past variables and actions. It rejects hidden
states needed by future kernels/utilities and unobserved dependencies of future
fixings. It is not a necessary characterization of solvable influence diagrams,
and not a general limited-memory solver. Unsupported models use the unchanged
enumerator or raise an explicit unsupported-model exception. No extra
information is silently added to make an elimination order work.

## Recurrence

For a full prefix h before k, H_k(h,P) is future expected utility, with utilities
closing before k excluded and original fixings P respected in every relaxed
extension. Let u_k be the sum of utilities closing at k. Then

```
H_{n+1} = 0
H_k(h,P) = sum_a p_k(a|h_parents) [u_k(h,a)+H_{k+1}(h,a,P)]  (chance)
H_k(h,P) = max_{a in A_k(h,P)} [u_k(h,a)+H_{k+1}(h,a,P)]    (decision).
```

A_k is the full action set unless P fixes the original history obtained by
projecting h; in that case it is the singleton fixed action. This enforces all
lifted copies without materializing an enlarged fixing table. Chance kernels,
including decision-dependent ones, are unchanged. The root adds stage-0 utility.
Zero-probability branches contribute zero and need not be optimized.

Actual recurrence calls enforce past fixed actions before extending a prefix.
Suffix messages describe the remaining causal continuation, not the probability
or feasibility of an already specified prefix under every global partial policy.
Thus a retained message at a now-unreachable prefix is harmless: it is used only
if the causal recursion reaches that prefix again, after enforcing current past
fixings. This is also why past policy fixings can drop out of a suffix key.

## Correctness argument

Induct backward. All future physical factors depend on a prefix only through
S_k. The remaining action restrictions depend only on original fixing rows
compatible with the prefix, projected onto their unassigned information variables.
Thus H_k depends only on the separator assignment and those residual restrictions.

At a decision, the support condition makes both the separator and every past
component used to select a residual restriction observable. Its maximizing action
therefore depends only on its permitted relaxed information. Prefixes that are
observationally indistinguishable have the same optimization problem and the
same deterministic tie-breaking action. Continuation choices also agree at
merged future information histories by the same induction. The local optima
can consequently be assembled into one admissible relaxed policy, rather than
incompatible independently optimized histories. Expectation uses the original
causal kernels; the recurrence attains exactly the enumerative relaxed optimum.

Combining this equality with the previously proved original-policy embedding
gives a certified partial-policy upper bound. This is policy optimization,
not merely fixed-policy inference. The order of sum and max follows the support
test; failing that test does not authorize an interchange.

The initial implementation enumerates conditional state/action branches, not
complete policies. With memoization, each distinct separator/restriction context
is solved once while retained. Complexity can still be exponential in separator
width, remaining restriction patterns, and rational numerator/denominator size.

The implementation is a chronological, additive-utility Bellman recursion.
Variant B leaves that recursion uncached; C tabulates equivalent continuation
values within and across queries. It does not implement a general sum/max
variable-elimination optimizer, a minimum-SIS algorithm, or junction-tree inference.
Individual original policy rows are materialized for branching and dependency
tracking; avoiding complete-policy enumeration does not remove that possible
exponential source of input size.

## Validation plan

First compare the structured uncached recurrence to the existing enumerator at
all 27 maintenance partial policies and all partial policies of a small
three-decision chain. Next validate equivalent-context reuse, including negative
tests for changed relevant fixings, physical kernels and information. Only then
add dependency-directed updates. Larger instances use sampled partial policies
and exact original-policy enumeration where feasible; exhaustive and sampled
coverage are reported separately.
