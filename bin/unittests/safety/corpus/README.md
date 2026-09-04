# CWE Safety Corpus

What the language does with each classic memory-safety fault, written down as compilable
programs rather than as prose.

One file per CWE, each with two halves:

- **Faults** — the program is wrong. Where Swag rejects it, the line carries a
  `swc-expected-error` marker naming the exact diagnostic, and the suite fails if that
  diagnostic stops being raised.
- **Sound** — the program is right and must compile in silence. This half is the one that
  measures false positives, and it is the half that decides whether a new rule is shippable:
  a rule that rejects correct code is worse than the fault it catches.

## Reading a case

Every case names ONE layer. A case aimed at a static proof turns the runtime guard off, so
the guard cannot answer for it; a case aimed at a guard launders its operands through
`Corpus.opaque*`, so constant folding cannot. Without that discipline the corpus cannot say
which half of the system did the work.

A runtime guard is reached through `#run`: the panic then arrives as a compile-time
diagnostic the marker can match, instead of ending the run.

## Gaps

A case Swag does not catch, and should, stays in the file. It is commented out, tagged
`GAP <backlog id>`, and says what was expected. Commenting is not cosmetic: several of these
really do corrupt memory, and one of them takes the compiler's own heap with it.

```
grep -rn "GAP " bin/unittests/safety/corpus
```

is the current scorecard. A gap disappears by being uncommented, not by being deleted. Two
other markers exist and are deliberately not gaps: `NO GAP` records that the class has no Swag
form at all, and `BY DESIGN` records a documented miss with a stated reason.

Two cases are blocked by compiler defects rather than by a safety hole, and say so:
compiler.core.028 (release-only inlining loses null narrowing) and compiler.core.029 (a
release-only compiler assertion). The `#[Swag.NoInline]` attributes in this folder are their
workarounds and come out when those entries close.

A few gaps are left **live** instead, when the fault is a wrong value rather than a memory
fault — a leak, a forged enum value, a switch that silently falls through. Those pin today's
behavior with an assertion, so the change shows up as a test failure when the rule lands.

## Where each class stands

| CWE | Class | Swag |
| --- | --- | --- |
| 457 | Uninitialized variable | **Designed out** — no escape hatch exists |
| 170, 134 | Null termination, format string | **Designed out** — counted strings, typed formatting |
| 476 | Null dereference | **Designed out** — non-null by default, proof at every use site |
| 562 | Return of stack address | **Proven**, always on, no annotation |
| 825 | Expired pointer (container realloc, iterator invalidation) | **Proven**, always on, no annotation |
| 590 | Free of non-heap memory | **Proven** |
| 758 | Falling off the end of a function | **Proven** |
| 252, 391 | Unchecked error | **Proven** — a fallible call needs a visible handler |
| 665 | Improper initialization | **Proven** (definite assignment) + guarded (`late`) |
| 121, 125, 129, 193, 787 | Out-of-bounds on a sized value | Proven when constant, **guarded** otherwise |
| 190, 191, 197, 195 | Overflow, truncation, sign conversion | Proven when constant, **guarded** otherwise; never undefined |
| 843 | Type confusion, dynamic half (`any`) | **Guarded** |
| 672 | Use after move | Proven, plus runtime poison for what it misses |
| 415, 416 | Double free, use after free | **Partial** — see the gaps in those files |
| 843 | Type confusion, static half (pointer cast, union) | **Not judged** — compiler.safety.006 |
| 122, 124, 787, 806, 823 | Faults through `[*] T` and the raw intrinsics | **Not judged** — compiler.safety.006 |
| 704 | Integer to enum | **Not judged** — compiler.safety.010 |
| 478 | Non-exhaustive switch | **Not judged** — language.design.001 |
| 401 | Memory leak | **Not modelled at all** — compiler.safety.017 |
| 674 | Stack exhaustion | Guard pages probed; no diagnostic — compiler.safety.012 |

## Scope

Concurrency is deliberately absent. Swag's concurrency model is undecided
(language.design.005), so a data-race corpus would measure a design that does not exist yet.

## Provenance

The taxonomy is the one the established analyzer benchmarks use — NIST's Juliet suite
(64 099 cases over 118 CWEs), the Toyota ITC benchmark (half the cases defect-free, which is
where the fault/sound split comes from), SV-COMP's `valid-deref` / `valid-free` /
`valid-memtrack` memory-safety properties, and CASTLE. None of them tests a *language*: they
test analyzers on C. What is borrowed here is the class list and the two-halves structure,
not the corpus.
