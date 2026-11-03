# Source-derived Oil RDP: auditable changes

Reference: `external/Decision-Programming-new-formulation/oil/test_oil_DP.jl`,
commit `47d4a32716e9642fb1a04d67cce48204446d597b`.
The external tree remains clean. Its executable function is parsed at runtime;
the top-level experimental loop is never executed. The source transformation is
`src/formulations/PaperOilRDP.jl`, not the independent structural-zero RDP.

## Separate layers

1. **Solver/extraction layer:** replace only the optimizer factory, configure the
   common budget, wrap `optimize!` and extract solver diagnostics and policy
   variables safely even without an incumbent. An AST comparison removes these
   explicitly identified plumbing expressions and asserts exact equality of all
   remaining expressions before/after this layer. Original index sets, variables,
   coefficients, objective, constraints, utility shift and probability calculations
   survive unchanged. Original has zero mathematical correction counts.
2. **Mathematical layer:** exactly four verified corrections below. This runs
   before the same solver layer. Pattern counts assert one occurrence of each
   tensor/order correction and six uses of the fixed-coordinate constructor.
   Unexpected upstream code fails closed.

## Verified corrections

| Issue | Original behavior | Minimal correction |
|---|---|---|
| Report axis | `ST = 1:No_states` excludes the last report: the supplied `T` contains N/A plus all geological report states | `ST = axes(T,4)` |
| Coefficient tensor | `PU` allocates only `No_states` positions per report axis | Allocate `length(ST)` per report axis |
| Fixed coordinates | `CartesianIndices(Tuple(length.(c)))` replaces integer coordinates by dimension 1; Julia `length(3)==1` | Replace all six occurrences with a helper constructing singleton `j:j` ranges for integers and preserving existing ranges |
| Drilling compatibility axis order | The drilling group places fixed report coordinates in the test-action axes and free report axes afterward | Use free test-action ranges first, fixed report coordinates next, fixed drilling action last |

The last issue is independently confirmed: after fixing singleton coordinates,
report positions 3/4 otherwise index a test-action axis of size 2, causing a
`BoundsError`. It is distinct from loss of integer coordinate values.

**Retained:** dense continuous `y`, binary `z,z2`, structural-zero columns,
all compatibility inequalities, the original `(1+No_states)` multiplier,
probability/utility coefficient sum, objective and positive utility translation.
No structural-zero elimination, stronger inequalities or preprocessing from the
independent RDP is imported. `No_states` still denotes geological states; the
number of reports is taken from the actual probability kernel.

## Why the repaired model represents the physical problem

For each complete report history, the corrected chart constraint selects one
binary drilling action. Each test also has one globally fixed ex-ante action.
Compatibility forces every `y` entry inconsistent with these actions to zero.
The per-report capacity limits the sum of remaining entries to one. For a fixed
portfolio/history exactly one test-action tuple and the chosen drilling action
can remain. The original big-M multiplier is still at least the number of
summands, so it does not exclude a compatible policy.

The unchanged shift is `1 - min(0,min(payoff)) + sum(costs)`. Every translated
path utility is at least one. Thus every positive-probability compatible history
saturates its capacity at an optimum. Summing the unchanged causal probability
kernels over every actual report gives total probability one for the fixed
portfolio. Subtracting the shift once recovers the physical expected utility.
Zero-probability histories may have arbitrary drilling actions and do not change
this argument. The two test-action kernels remain selected-report versus N/A;
no information is revealed or probability kernel changed by this repair.

This reasoning concerns ex-ante Oil Wildcatter with nonnegative additive costs
and expected utility. It is not a proof of a general DP algorithm.

## Independent checks and limitations

Automated tests compare repaired objectives and exact independent policy sums
with portfolio enumeration, including non-square state/report dimensions,
structural zeros, expensive tests and negative drilling utilities. Ablations
omit each correction: the tensor/order omissions fail construction; the other
two lose the physical optimum on an informative witness. The existing root
suite uses HiGHS for portability; the separate primary campaign uses CPLEX.

Policies are decoded from the actual `z,z2` values. Missing or non-one-hot
reachable rows are reported as invalid, never repaired from the objective or
from `y`. Original-source objective/bounds describe the defective source model;
they are not physical optimality certificates, even when their nominal value
happens to agree with enumeration.

The upstream Float64 inputs and canonical normalized rational inputs are both
archived. All primary comparisons reload the same canonical snapshot; MILP
coefficients use its Float64 image. The original Float64 seed mapping and any
normalization perturbation are recorded. Equality tests use absolute tolerance
1e-7 plus relative tolerance 1e-9. Exact IR-B&B pruning uses no CPLEX bound.

## Check against the actual paper

The supplied arXiv:2601.08460v2 PDF (22 October 2026), Section 3.1,
equations (6) and (8a)–(8f), was checked directly, along with Section 4.3,
Figure 2 and Table 5. The latter gives four report states (including N/A) and
three geological states. The pinned generator also differs from the paper's
state-dependent, diagonal-favoring probability description: it resets the same
RNG stream for every row. We reproduce that source behavior in Campaign A;
Campaign B is independently generated, not a reproduction of the paper's
claimed diagonal-sharpness distribution.

The corrected dense model's counts match Table 6's RDP counts exactly:

| M | Corrected variables | Corrected constraints (excluding variable bounds) | Table 6 variables / constraints |
|---|---:|---:|---:|
| 1 | 26 | 19 | 26 / 19 |
| 2 | 164 | 70 | 164 / 70 |
| 3 | 1,158 | 265 | 1,158 / 265 |
| 4 | 8,712 | 1,036 | 8,712 / 1,036 |

In general, with `R = report_states + 1`, the retained dense model has
`2*(2R)^M + 2*R^M + 2M` variables and `4*R^M + 3M` constraints.
The pinned uncorrected function uses `R = geological_states`, so its counts
already disagree with those published RDP counts. This discrepancy does not
establish which historical code revision generated the published tables.
The original script's local `No=3` loop limit also differs from the paper's
M=1..8 range, although supplied seed files cover all eight sizes.

Primary sources: [Terho et al. v2](https://arxiv.org/abs/2601.08460v2),
[Salo et al.](https://doi.org/10.1016/j.ejor.2021.12.013), and the
[pinned experimental repository](https://github.com/toubinaattori/Decision-Programming-new-formulation/tree/47d4a32716e9642fb1a04d67cce48204446d597b).
