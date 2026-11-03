# Decision Programming Algorithms: Research Background and Implementation Contract

**Status:** research handoff, 2026-10-30.  
**Intended reader:** Codex working in a local Julia repository.  
**Main language:** Julia (JuMP / MathOptInterface); English identifiers and documentation.  
**Purpose:** establish the scientific and mathematical context, current validation status, scope, sources of truth, and testable requirements. This is not a claim of algorithmic novelty or computational superiority.

> **Critical distinction:** A probing-specific Information Relaxation Branch-and-Bound (IR-B&B) is mathematically specified and has been piloted on small synthetic Oil Wildcatter instances in Python. A **general IR-B&B for arbitrary Decision Programming (DP) influence diagrams is NOT implemented or validated**. Do not treat these as the same deliverable.

## 1. Research objectives and scientific boundaries

### Track A: General exact algorithms for Decision Programming

The overarching research goal is to solve a broad variety of influence diagrams under expected utility, including problems **without** test-selection, inspection, monitoring, or other probing decisions.

Candidate approaches:

- Information-relaxation Branch-and-Bound over **partial decision policies** (the main research direction currently under consideration).
- Logic-based Benders with exact policy-evaluation and valid policy-family upper-bound oracles.
- Branch-and-Price / branch-cut-and-price using implicit generation of observable path segments.

These are hypotheses and algorithm-design opportunities, **not three already developed algorithms**. B&B with information-relaxation bounds for influence diagrams has prior art; novelty must be established relative to the relevant literature.

### Track B: Multistage probing-enhanced stochastic programming

A distinct scientific project could extend probing to sequential/adaptive decisions, with DP as a modeling alternative to scenario-based multistage stochastic programming. In this track, probing **is** fundamental. Do not confuse Track B with the general-purpose algorithmic contribution of Track A.

**Immediate engineering scope:** reproduce the 2026 Julia baselines; audit their instances; implement and rigorously validate a probing-specialized IR-B&B on extended Oil Wildcatter; design clean abstractions for partial policies and general information relaxations; then make a small, independently validated non-probing demonstrator. Do not announce that the general algorithm is solved until it works on non-probing examples with certified bounds.

## 2. Priority references and repositories

### Primary papers (provide PDF files locally)

1. Salo, A., Andelmin, J., and Oliveira, F. (2022). **Decision programming for mixed-integer multi-stage optimization under uncertainty.** *European Journal of Operational Research* 299(2), 550-565. DOI: 10.1016/j.ejor.2021.12.013. Read Section 3.1-3.5, especially the precise definition of paths and policy compatibility.
2. Terho, T., Oliveira, F., Salo, A., and Munari, P. (2026). **An efficient mixed-integer linear programming formulation for solving influence diagrams.** arXiv:2601.08460 (check latest supplied version). Read Section 2; equations (3a)-(3e) for DP, (8a)-(8f) for RDP, Sections 3.2-3.3 for risk / size; Section 4.3 and Figure 2 / Table 5 for Oil Wildcatter; Sections 4.2 and 4.4 for additional benchmarks.
3. Ma, Z., Kim, Y., Linderoth, J., Luedtke, J. R., and Matthews, L. R. (2024). **Probing-Enhanced Stochastic Programming.** arXiv:2407.10669. Read its information-relaxation B&B definitions, lemmas, exact-oracle assumptions, and distinction between exact and statistical bounds. This is the probing IR-B&B methodological reference, **not** an already established generic DP solver.

### Essential prior art for general DP B&B

4. Yuan, C., Wu, X., and Hansen, E. (2010). **Solving Multistage Influence Diagrams using Branch-and-Bound Search.** UAI 2010, 690-699. Read their upper-bound influence diagrams, Sufficient Information Sets (SIS), and incremental inference.
5. Khaled, A., Yuan, C., and Hansen, E. (2013). **Solving Limited-Memory Influence Diagrams Using Branch-and-Bound Search.** UAI 2013, 471-480. Read the exact AND/OR decision-graph search, context sharing, and information-related bounds. Beware differing bibliographic author ordering across repositories; check the paper directly.

### User's prior research (provide if available)

- Manuscript and code of the user's probing-enhanced lot-sizing / Information Relaxation B&B project, including any AIR-B&B improvements (dominance, stability, hierarchical bounds, reuse). **These files are not included in the two DP PDFs currently available.** Do not assert, reproduce, or extend an AIR-B&B theorem without first reading the actual manuscript and relevant implementation.

### Public code to clone and preserve unmodified

- 2026 experimental scripts: `https://github.com/toubinaattori/Decision-Programming-new-formulation.git` (default branch `main`, as checked 2026-10-30).
- General Julia package: `https://github.com/gamma-opt/DecisionProgramming.jl.git` (default branch `master`, as checked 2026-10-30).

The 2026 scripts contain `oil/`, `turbine/`, `water_cvar/`, `Results/`, and `Printing/` folders. Several scripts rely on working-directory-relative paths and Gurobi; the README specifies `julia --threads=2` for the original scripts. Identify exact commits and requirements at setup time. Prefer a read-only external snapshot or pinned git submodules, subject to license review. **Do not silently change paper scripts.**

**Source-of-truth priority:** original paper mathematical definitions > inspected corresponding reference implementation for implementation details > this handoff (research plan) > earlier conversational or prototype claims. Document any inconsistency instead of silently reconciling it.

## 3. Decision Programming: formal objects and paths

A finite influence diagram is a directed acyclic graph `G=(N,A)` with chance nodes `C`, decision nodes `D`, and value nodes `V`. For node `n`, its information/parent set is `I(n)` and its finite state set is `S_n`.

**Path terminology is crucial:** a DP *full path* is a **complete assignment of states**, `s=(s_n)_{n in C union D}`. It is not a directed source-to-sink graph walk and not, in general, a shortest path in the Dijkstra sense. A *path segment* is a partial assignment to some nodes. The number of full paths can be exponential:

`|S| = product_{n in C union D} |S_n|`.

Chance-node factors and additive utility are

```text
p(s) = product_{c in C} P(s_c | s_{I(c)})
U(s) = sum_{v in V} U_v(s_{I(v)})
```

For a deterministic policy `Z=(Z_d)_{d in D}`,

```text
Z_d : S_{I(d)} -> S_d
z_d(a | h) in {0,1},  sum_{a in S_d} z_d(a | h) = 1.
```

The policy-dependent probability of a joint assignment is

```text
P_Z(s) = p(s) * product_{d in D} 1{Z_d(s_{I(d)}) = s_d}.
```

The expected utility is

```text
Q(Z) = sum_{s in S} P_Z(s) U(s).
```

For finite, causally ordered chance kernels and valid policies, the induced `P_Z` is a probability distribution. The product `p(s)` alone should NOT be treated as a probability distribution normalized over all unrestricted assignments of decision states.

**Computational opportunity:** For a fixed policy, inference can sometimes evaluate `Q(Z)` by eliminating variables / calculating local marginals without explicitly constructing all full paths. Runtime is governed in part by factor sizes and induced graph width, which may itself be exponential. Neither shortest-path methods nor generic efficient inference is guaranteed for arbitrary diagrams.

## 4. 2026 Reformulated Decision Programming (RDP)

Let `C_I` denote chance nodes that appear in at least one decision's information set, and let `O_obs = D union C_I` (avoid confusing this notation with the Oil Wildcatter chance node named `O`). A full assignment to `O_obs` is an *observable segment* `s_{O_obs}`.

RDP aggregates unobserved chance nodes into objective coefficients:

```text
EU(s_{O_obs}) = sum_{s extending s_{O_obs}} p(s) U(s).
```

Variables:

- `z_d(a | h)`: binary policy variables.
- `y(s_{O_obs}) in [0,1]`: path/observable-segment compatibility variables.

The paper's expected-utility formulation (equations 8a-8f) can be summarized as

```text
maximize   sum_{s_{O_obs}} EU(s_{O_obs}) y(s_{O_obs})
subject to sum_a z_d(a|h) = 1                       for all d,h
           sum_{s_{O_obs} extending (d,a,h)} y(s_{O_obs}) <= Gamma(d,a,h) z_d(a|h)
           sum_{s_{O_obs} extending s_{C_I}} y(s_{O_obs}) <= 1 for all s_{C_I}
           z binary;  0 <= y <= 1.
```

The paper uses positive utility transformations for the expected-utility model: objective maximization then activates compatible continuous `y` variables. **For independently written formulations, utility shifting, normalization, probability mass, and risk/distribution constraints must be handled exactly.** Do not apply positive-utility arguments blindly to arbitrary negative utilities or CVaR. The paper treats risk objectives separately; those extensions are NOT in the initial algorithm's validation scope.

The `z` variables, `y` variables, constraints, and especially the preprocessing for `EU(s_{O_obs})` can each be large. Retain three different metrics: number of policy decisions, number of observable segments, and amount of probabilistic coefficient preprocessing. An RDP benchmark should report total model preparation time, not just solver time.

**Implementation detail to verify:** some 2026 repository scripts have names such as `test_oil_DP.jl` even when the implemented mathematical formulation uses observable variables and resembles RDP. Classify the implementation by equations and variable sets, not filenames alone.

## 5. Extended Oil Wildcatter: the first controlled benchmark

The Figure 2 / Table 5 structure from the 2026 paper is:

- Chance node `O`: oil-well state (dry/medium/wet).
- Chance node `S`: latent geological conditions, conditional on `O`.
- Initial binary decision nodes `T_i`: whether to commission each of `M` tests.
- Chance nodes `R_i`: test reports, conditional on `S` and `T_i`; if a test is not commissioned, `R_i=N/A` with probability one.
- Value nodes `C_i`: test costs.
- Terminal decision node `D`: drill or not, informed by test reports `R_1,...,R_M`.
- Value node `U`: drilling reward minus drilling costs, conditional on `O,D`.

**Important:** the *main* Oil Wildcatter variant in Section 4.3 chooses the test portfolio **ex ante**. The paper also mentions a **sequential-testing** variation in supplemental material; do not conflate the two. The specialized IR-B&B below solves the main ex-ante variant only.

For selected tests `T` and a vector of outcomes `r_T`, define the unnormalized expected drilling gain:

```text
g_T(r_T) = sum_{o,s} P(O=o) P(S=s|O=o)
           * product_{i in T} P(R_i=r_i | S=s,T_i=yes)
           * u_drill(o).
```

Assume `u_no_drill(o)=0` for this specialization (otherwise include the two action values explicitly). Conditional independence of reports given the latent geology and chosen tests must be checked in the instance specification.

The optimal *operating* value before paying for tests is

```text
F(T) = sum_{r_T} max(0, g_T(r_T)).
```

For additive nonnegative test costs `c_i`, the net portfolio value is

```text
V(T) = F(T) - sum_{i in T} c_i.
```

The formula implicitly optimizes the drilling rule for each observed report combination. If there are extra downstream constraints or cross-history couplings, this separable max may be invalid and must be replaced by an exact downstream optimization oracle.

## 6. Probing-specific IR-B&B: exact initial formulation

The B&B node `P=(A,B)` consists of disjoint sets of tests:

- `A`: tests required to be selected.
- `B`: tests forbidden.
- `N \ (A union B)`: still undecided tests.

Every descendant chooses `T` with `A subseteq T subseteq N\B`.

A valid node upper bound for maximization is

```text
UB(P) = F(N\B) - sum_{i in A} c_i.
```

**Why valid:** observing more (cost-free) signals cannot reduce optimal expected operating value when signals can be ignored, physical chance mechanisms do not change, and the original policy set remains feasible; `sum_{i in A} c_i` is a lower bound on costs of any completion when costs are nonnegative and additive.

A feasible lower-bound candidate is to commission only `A` and solve its optimal drilling rule:

```text
LB_candidate(P) = V(A).
```

Use valid branch-and-bound conventions: incumbent from feasible candidate, prune only when certified `UB <= incumbent` (with a documented tolerance), branch on an undecided `T_i`, and terminate only when bounds certify global optimality. Cache evaluations `F(T)` by subset representation. Validate `UB(P)` against exact subtree maxima for **every** partial assignment on small `M` (there are `3^M` possible required/forbidden/unfixed combinations).

**Exactness conditions:** test selection does not alter the underlying geology or other physical transitions (except report availability), reports can be ignored, and test costs meet the stated conditions. If tests affect the physical state, or costs are general nonmonotone set functions, do not reuse this bound without a new proof.

**This is not a generic DP algorithm.** It branches on test portfolios and uses a particular downstream one-decision rule. It is essentially a specialized use of the Ma et al. information-relaxation idea.

## 7. Preliminary Python prototype: status and use

Existing local files from preliminary research, **if transferred to Codex**:

- `oil_wildcatter_irbb_rdp_validated.py`: synthetic Oil Wildcatter generator and three solvers: exhaustive portfolios, probing IR-B&B, and structurally specialized RDP MILP via SciPy/HiGHS.
- `README_oil_wildcatter_irbb_rdp.md`: method, assumptions, initial results, limitations.
- `oil_wildcatter_results_m4_seed26.json` and `oil_wildcatter_results_m5_seed25.json`: example outputs.
- `oil_2026_generator_check.py`: exploratory generator check.

Previously reported Python synthetic cases:

| Tests M | Synthetic seed | Reported optimum | Reported selected tests | Partial nodes checked |
|---:|---:|---:|---|---:|
| 4 | 26 | 57.61204043 | test 4 | 81 |
| 5 | 25 | 39.17992612 | test 2 | 243 |

These are **small synthetic validation cases** with a deliberately informative generator, not published-instance reproductions, not an established scaling result, and not evidence that the generic algorithm already exists. Re-run them independently and compare within numerical tolerance before reusing any numerical claim. The Python special-purpose RDP may prune structurally impossible report combinations; its model dimensions need not match the unpruned Julia RDP from the paper. Python is a validation artifact only; develop the production code in Julia.

## 8. Audit the original Julia instance generator before experiments

In the published `oil/` code, the instance generator appears to recreate an RNG with the **same seed** inside loops. Example pattern:

```julia
for i in 1:No_states
    x_S = rand(Xoshiro(seed+1), No_states)
    S[i, :] = x_S ./ sum(x_S)
end
```

Related code also uses `Xoshiro(seed+2)` inside test-result loops. If those calls reset to identical RNG states, the generated conditional probability rows may become identical and tests may be statistically uninformative. This would make the specialized information-relaxation bound trivially tight for some published instances and distort the methodological comparison.

**Required action:** verify the exact Julia behavior empirically, characterize implications for `P(S|O)`, `P(R_i|S,T_i)`, and the value of information, and check consistency against the published descriptions. Write a standalone audit report with a repeatable Julia test. Treat suspected issues as hypotheses until checked; do not alter the preserved original script to obtain more favorable results.

Keep separate datasets:

1. `original`: exact paper repository generator and supplied original seeds, untouched and clearly identified.
2. `informative`: new generator with genuine dependence between geology and reports, varied informativeness and costs.
3. `control`: uninformative/redundant signal constructions to test bounds and degeneracy.

Use distinct labels and record seeds, generator version, parameter settings, and checksums. **Do not call corrected synthetic instances 'paper instances'.**

## 9. General DP information-relaxation B&B: a research design, NOT a finished method

A complete policy is `Z=(Z_d)`; a B&B node fixes only a subset of mappings `Z_d(h)=a`. Let `Z(P)` be the policies compatible with those assignments.

The true node value is

```text
V(P) = max_{Z in Z(P)} Q(Z).
```

A *candidate* information-relaxation bound is obtained by enlarging selected information sets `I(d)` to `I_tilde(d)` while retaining all original physical chance kernels and required action choices:

```text
Z(P) subseteq Z_tilde(P)
UB(P) = max_{Z in Z_tilde(P)} Q(Z).
```

The inclusion implies `V(P) <= UB(P)` and gives validity **if** the enlarged policy class is well-defined. In particular:

- If `Z_d(h)=a` is fixed, it must remain fixed for **every augmented history** extending `h`.
- Preserve conditional probabilities and the causal order; do not casually reveal future decision-dependent outcomes before the decisions that determine them.
- Providing more information may loosen the objective bound while sometimes simplifying inference; neither stronger bounds nor lower computational cost are guaranteed.
- A bound-oracle can itself be computationally hard. Merely writing `UB(P)=MEU(relaxed diagram)` does **not** define a competitive implementation.
- For memory-limited diagrams (LIMIDs), information patterns, decision ordering, and shared contexts require particular care.
- If physical distributions are decision-dependent, ensure the augmented diagram defines a valid causal policy distribution. Exogenous primitive uncertainties may help in special models but are not assumed available generically.
- Check risk objectives (CVaR, chance constraints) separately; do not copy expected-utility formulas without proof.

This is an algorithmic **research hypothesis** to be benchmarked against exact inference, RDP, RJT, Yuan/Wu/Hansen (2010), and Khaled/Yuan/Hansen (2013). Information-relaxation B&B and SIS-based bounds are established ideas; claim novelty only for demonstrably new bounds, proofs, representations, or computational advantages.

**Suggested first non-probing validation:** a tiny maintenance influence diagram with a first action changing failure probabilities and a later action that does not observe the failure. Add a relaxed observation for the later action, rigorously preserve fixings, enumerate all feasible original policies and relaxed policies, and verify upper-bound inequalities at every partial assignment. This is a proof-of-concept, **not** a competitive general solver.

## 10. Graph algorithms and future work

- **Fixed-policy evaluation:** use factors over conditional distributions and local utilities. Compare explicit full-state enumeration to variable elimination / junction-tree inference. For additive utility, compute relevant marginals instead of full joint path tables where feasible.
- **Partial-policy bounds:** attempt exact or certified information-relaxed maximization on suitably structured influence diagrams; investigate admissible bounds and caching among related partial policies.
- **Logic-based Benders (future):** an exact policy evaluator alone is insufficient for useful global convergence; cuts must be valid for other policies, e.g., via certified bounds on compatible policy families. Trivial no-good-style optimality cuts may be very weak.
- **Branch-and-Price (future):** pricing over observable segments must optimize *expected coefficients minus dual terms*; in general this is not a Dijkstra shortest-path problem. Sum-over-hidden-state followed by max-over-observable-state can be hard. Do not call generic pricing tractable without a structural reduction and proof.

Do not develop all algorithm families in the first implementation pass; prioritize independently verified, testable modules.

## 11. Implementation architecture and experimental protocol

Create a stand-alone Julia project with reproducible `Project.toml` / `Manifest.toml`, tests, scripts, and local documentation. Use modular abstractions such as:

```text
InfluenceDiagramInstance (or equivalent backed by DecisionProgramming.jl)
Policy / PartialPolicy
PolicyEvaluator
InformationRelaxationBound
BranchAndBoundState
InstanceGenerator
BenchmarkRunner
```

Keep *problem-specific* Oil Wildcatter optimization separate from generic policy/evaluator interfaces. If a clean generic abstraction is premature, document it and isolate specialized code instead of pretending it is general.

Recommended work phases:

1. **Environment and baseline:** clone/pin both repositories, inspect license and dependencies, reproduce small paper instances; understand whether each script is DP, RDP, or RJT.
2. **Generator audit:** run Julia checks for probability dependence; preserve original data; add an informative independent generator.
3. **Exact Oil oracle and IR-B&B:** implement the formulas from Sections 5-6; cache subproblem values; recover optimal testing and drilling policies.
4. **Independent checks:** brute-force small portfolios, validate every node bound, compare RDP and IR-B&B on exactly the same input and objective, verify root and leaf bounds.
5. **Broader experiments:** vary number of tests, probabilities and costs; measure total time, solver time, oracle time, nodes, cache hits, peak memory, and optimality certificate; never infer speedups from one instance.
6. **General DP research prototype:** explicitly represent partial policy fixings, relaxed information, generic evaluation interface, and a small **non-probing** example. Document unresolved general-case efficiency and exactness questions.

Use HiGHS as a free MILP baseline where supported and Gurobi when installed and licensed. Do not change the mathematical formulation to obtain compatibility without documenting the change. Beware of utility shifts in RDP: report **unshifted physical expected utility** for comparing approaches.

Version all seeds, algorithm parameters, Julia / solver versions, package hashes, CPU / memory and time-limit conventions. Separate preprocessing + model construction from optimizer solve time, and report end-to-end time as the primary metric. Record complete final `LB`, `UB`, absolute and relative gaps with well-defined conventions. Do not invent runs, metrics, or claims.

## 12. Acceptance criteria for the first research implementation

The initial implementation is acceptable **only if**:

- Original experimental repository and DecisionProgramming.jl are locally present and pinned, with license/dependency notes.
- At least one small published Julia formulation can run or a concrete reproducible blocker is documented.
- Original Oil generator audited in Julia with explicit evidence; separate informative generator implemented and validated.
- New Julia IR-B&B solves the main ex-ante extended Oil Wildcatter problem and recovers a drilling policy.
- A mathematically independent exhaustive enumerator agrees with IR-B&B on small informative instances.
- A specialized RDP reference solved on the **same instances** yields the same unshifted objective to stated tolerance.
- All `3^M` partial test-selection nodes are checked for bound validity for multiple small `M`.
- Unit tests cover no-test, all-test, uninformative tests, redundant tests, zero/near-zero probability branches, negative operating utilities, and differing test costs.
- There is a concrete, small **non-probing** demonstration of policy fixing and a valid information relaxation, or an explicitly documented blocker; a general DP solver must NOT be claimed on that basis alone.
- README and reports distinguish implemented, verified, unverified, proposed, and blocked features.

**Success is correctness and reproducibility, not a pre-decided conclusion that IR-B&B is faster or scientifically novel.**

## 13. Instructions for Codex's reporting

At the end of each phase, report:

- Exact files created or changed and local commit identifiers.
- Commands executed, Julia and solver versions, test results.
- Mathematical assumptions actually implemented and tested.
- Any discrepancy between paper, original code, and new generated data.
- Which claims can now be independently reproduced, and which remain open.

Do not push a new public/private repository or modify upstream sources without explicit user authorization. Preserve the distinction between the **general-DP algorithm research goal** and the **probing-specific first validated implementation**.
