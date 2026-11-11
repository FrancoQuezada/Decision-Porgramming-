# Mathematical contract

## Sources and domains

The supplied Terho et al. PDF is arXiv:2601.08460v2, 22 October 2026;
its SHA-256 is identical to the current arXiv v2 download. The 2022 source
is Salo, Andelmin and Oliveira, EJOR 299, 550–565,
DOI [10.1016/j.ejor.2021.12.013](https://doi.org/10.1016/j.ejor.2021.12.013).
The implementation uses finite state spaces, deterministic policies and additive
expected utility. It does not implement risk objectives or extra policy constraints.

A DP path is a full state assignment, not a directed graph walk. For a policy Z,

```
P_Z(s) = ∏_{c∈C} p_c(s_c | s_parents(c)) ∏_{d∈D} 1{Z_d(s_I(d))=s_d}
Q(Z)   = ∑_s P_Z(s) ∑_v U_v(s_scope(v)).
```

These are the policy compatibility and probability semantics in Salo et al.,
Sections 3.1–3.5, especially equations (2)–(4), (16)–(22). The 2026 DP model
uses compatibility variables and aggregated big-M constraints (including changes
from intervening work); it should not be described as the identical 2022 MILP.
The chance-factor product alone does not normalize over unrestricted decision
assignments. The implemented chronological policy substitution does normalize.

## Finite-input arithmetic

`Exact = Rational{BigInt}`. Each supplied finite real input is converted to its
exact rational value. A probability row must be nonnegative and sum to one within
`1e-12` in the input check, then is divided by its exact rational row sum.
This defines an exactly normalized nearby rational model for generated Float64
probabilities. Serialized TOML instances store those rational numerators and
denominators. Certificates refer to this explicitly represented model, rather
than an ideal distribution before rounding. Utilities and costs are converted
without renormalization. The generic diagram constructor requires exactly
normalized kernels and rejects malformed causal orders.

No tolerances, rounded bounds or statistical estimates are used for B&B pruning.
RDP converts the same serialized rational model to Float64 solver coefficients;
the recovered policy is reevaluated exactly on the rational instance. Agreement
is checked with absolute tolerance `1e-7` and relative tolerance `1e-9`.

## Oil Wildcatter

Physical factorization is `p(O)p(S|O)∏_i p(R_i|S,T_i)`. Ex-ante tests have no
observations. Selected tests report states `1:R`; skipped tests report N/A (`0`)
with probability one. Downstream drilling observes all reports. Selected reports
are conditionally independent given S; correlated marginal reports are possible
through S. The latent physical distribution is identical for every portfolio.
No-drill utility is zero. There are no cross-history drilling constraints.

```
g_T(r) = ∑_{o,s} p(o)p(s|o)u_drill(o) ∏_{i∈T} p_i(r_i|s)
F(T)   = ∑_{r_T} max(0,g_T(r_T))
V(T)   = F(T) - ∑_{i∈T} c_i,     c_i ≥ 0.
```

The optimized oracle eliminates O into `alpha(s)`. The independent enumerator
recomputes O,S joint contributions directly. Tests also enumerate *all drilling
rules* for very small binary-report cases; portfolio enumeration alone would not
be independent evidence of the pointwise-max argument.

For disjoint required A and forbidden B, every completion satisfies
`A ⊆ T ⊆ N\B`, and

```
UB(A,B) = F(N\B) - cost(A).
```

Proof: any original drilling rule for T embeds in the larger observation space
by ignoring added reports. The common latent model gives identical expected
utility to the embedded rule; summing extra report outcomes marginalizes to one.
Thus `F(T) ≤ F(N\B)`. Nonnegative additive costs give `cost(A) ≤ cost(T)`.
Subtracting proves the bound. `V(A)` is a feasible incumbent candidate. At a leaf
`A=N\B`, the bound equals `V(A)` exactly. This is a specialization of Ma et al.
(2024), Lemmas 1–2; it is not a new generic-DP theorem. Ma's stated feasible
lower bound selects all allowed tests; selecting A is another feasible completion.

## Independent RDP specialization

Terho et al., equations (6), (8a)–(8f): observable nodes are all decisions and all
chance nodes appearing in some decision's information. Hidden O,S are summed
into expected utility coefficients. In Oil, a report tuple r (including N/A)
determines its portfolio T(r). Remove only segments violating availability.
Let `k` index these tuples and `d∈{no,drill}`. The variables are `y[k,d]∈[0,1]`,
binary `z_test[i,a]`, binary `z_drill[k,d]`.

```
∑_a z_test[i,a] = 1;             ∑_d z_drill[k,d] = 1
y[k,d] ≤ z_drill[k,d]
∑_{k: availability(k,i)=a,d} y[k,d] ≤ |K(i,a)| z_test[i,a]
∑_d y[k,d] ≤ 1.
```

These are (8b)–(8f) after structural-zero elimination. Gamma for drilling is 1;
Gamma for a test action is the number of matching report tuples: (8c) bounds
their total activation by that number. These need not be the strongest Gamma.
The coefficient includes the **net** utility plus a constant
`shift = 1 - min(0,min_o u_drill(o)) + sum_i c_i`, so every possible full-path
utility is at least one. Nonnegative coefficients activate all compatible
positive-probability tuples. Their physical probability mass is one; subtracting
the shift recovers the unshifted objective. Structural-zero histories can have
zero coefficients and arbitrary policy actions without changing physical value.
No CVaR or general signed-coefficient shortcut is asserted.

The sequential Oil specialization preserves these physical kernels and utility
conventions while making testing rows depend on prior reports. Its policy
representation, exact reference, two conservative bounds and their preserved
policy embeddings are specified in [sequential_oil.md](sequential_oil.md).

## Partial policies and causal relaxation

A partial policy fixes mappings `Z_d(h)=a`. The original feasible family consists
of all deterministic policies respecting these mappings. The v0.1 constructor
permits adding only *earlier chance nodes* to a decision's information. It checks
unchanged nodes, chance kernels, utility factors, and inclusion of the original
information. It does not move a future outcome before its causal decision.

For every fixed original mapping, `lift_fixings` fixes a at **every augmented
history projecting to h**, including histories of zero probability. Embed any
original policy by ignoring new information. Embedded actions coincide on every
full assignment, hence all chance-kernel factors and induced probabilities
coincide. The embedding respects the lifted fixings. Therefore

```
Z(P) ⊆ Z_tilde(P),    max_{Z∈Z(P)} Q(Z) ≤ max_{Z∈Z_tilde(P)} Q(Z).
```

Enumerating relaxed policies computes the right side exactly. This proof needs
no perfect-recall assumption, but assumes the explicit finite causal ordering,
unconstrained deterministic policy family and unchanged expected-utility model.
Additional policy constraints would need a separate preserved embedding and are
not silently relaxed by this API.

The non-probing example is ordered `D1, X, D2`. The kernel `p(X|D1)` depends on
maintenance; `I(D1)=∅`, `I(D2)={D1}`. X is not observed originally. The relaxation
adds X only to D2, after X has realized. Fixing `D2(D1=a)` constrains both X
extensions. This is a functional example, not validation of a competitive solver
for arbitrary influence diagrams.
