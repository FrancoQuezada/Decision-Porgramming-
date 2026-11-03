# Agent instructions: DecisionProgrammingAlgorithms

Read `RESEARCH_BACKGROUND.md` completely before editing code. Treat it as research context and implementation boundaries, **not** as a replacement for the original papers.

## Scientific safeguards

- Maintain the distinction between a **probing-specific IR-B&B** (mathematically specified and preliminarily piloted in Python for ex-ante Oil Wildcatter) and a **general exact algorithm for Decision Programming** (research hypothesis, not yet validated).
- A DP "path" is an assignment of states, not automatically a shortest directed graph path.
- Never claim that revealing information provides a valid bound without explicitly preserving the original feasible policy set, fixed policy actions and causal probability kernels.
- Never claim computational superiority or scientific novelty without reproducible tests and literature comparison.
- Confirm actual code and formulas from the 2022/2026 papers and official Julia repositories; document discrepancies.

## Engineering safeguards

- Write new optimization code in Julia using reproducible packages; default to free/open solver support where feasible.
- Clone original repositories as pinned, read-only references; avoid modifying their code or pushing externally.
- Audit the suspected repeated-seed generator issue in the original Oil Wildcatter Julia scripts before relying on their instances.
- Create an independently generated informative test set and exhaustive small-instance validation.
- Keep objective-value shifts and experimental timing conventions consistent across IR-B&B, RDP, and enumeration.
- Implement the first Oil Wildcatter specialization completely before claiming broader algorithmic generality.
- Maintain automated exactness / bound-validity tests and a running `docs/STATUS.md` of evidence and unresolved issues.

## Deliverable priority

1. Reproducible baseline, source audit and environment.
2. Correct and tested Julia IR-B&B for ex-ante Oil Wildcatter.
3. Consistent independent RDP vs IR-B&B tests on exactly identical informative instances.
4. Small non-probing influence diagram / partial-policy bound proof-of-concept.
5. Extended research algorithms **only after** mathematical validation.

Do not create a remote repository or push changes without explicit authorization.
