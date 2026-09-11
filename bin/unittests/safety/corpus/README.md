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
rg -n "GAP " bin/unittests/safety/corpus
```

is the current scorecard. Closing a gap adds an expected-diagnostic regression; it never deletes
the reproducer. A live probe marked `GAP` still describes a missing guarantee. Two
other markers exist and are deliberately not gaps: `NO GAP` records that the class has no Swag
form at all, and `BY DESIGN` records a documented miss with a stated reason.

Some gaps are **live probes**: a forged enum value, a switch that falls through, or an
explicit pointer reinterpretation whose address is compared without dereferencing it. Those
pin today's behavior with an assertion, so a new diagnostic makes the case fail and asks for
promotion to an expected-error test.

`Corpus.RetainedHeap` also lets known allocation-lifetime misses execute. It wraps the current
allocator, records logical releases, and keeps each physical block until the probe leaves its
scope. CWE-401 checks the exact live-block count on every leak path; CWE-415 counts the second
release of a copied handle; CWE-416 exercises both conditional-release paths and nested fields. Sound counterparts
must leave no logical leaks or duplicate releases. Restore the context allocator with `defer`
before the retaining heap drops. A passing probe records an analysis limitation: it does not
claim that the real allocator detects the fault, or that reading freed memory is safe.

## Running the corpus

```text
bin/swc.dm.exe --num-cores 6 tools/unittests.swgs dm safety -bc devmode --file-filter corpus --num-cores 6
```

The corpus shares `helpers.swg`, so a filename-only filter would discard required declarations.
The `corpus` filter keeps those helpers and excludes the other safety fixtures. No compiler
rebuild or broader consumer campaign is needed for a corpus-only change.

## Where each class stands

| CWE | Class | Swag |
| --- | --- | --- |
| 457 | Uninitialized variable | **Designed out** — no escape hatch exists |
| 170, 134 | Null termination, format string | **Designed out** — counted strings, typed formatting |
| 476 | Null dereference | **Designed out** — non-null by default, proof at every use site |
| 562 | Return of stack address | **Proven**, always on, no annotation |
| 825 | Expired pointer (container realloc, iterator invalidation) | **Proven**, always on, no annotation |
| 590 | Free of non-heap memory | **Proven** — frame storage by the borrow route, a global by its provenance |
| 758 | Falling off the end of a function | **Proven** |
| 252, 391 | Unchecked error | **Proven** — a fallible call needs a visible handler |
| 665 | Improper initialization | **Proven** (definite assignment) + guarded (`late`) |
| 121, 125, 129, 193, 787 | Out-of-bounds on a sized value | Proven when constant, **guarded** otherwise |
| 190, 191, 197, 195 | Overflow, truncation, sign conversion | Proven when constant, **guarded** otherwise; never undefined |
| 369 | Integer divide by zero | Proven when constant, **guarded** otherwise |
| 843 | Type confusion, dynamic half (`any`) | **Guarded** |
| 672 | Use after move | Proven, plus runtime poison for what it misses |
| 415, 416 | Double free, use after free | **Proven** through the storage a program actually keeps a pointer in — a parameter, an element of a local table, a field of a local, a field of an OBJECT, a copy into another local — across casts, wrappers and an ordinary call, at the return that would hand a released pointer to the caller, and through ownership: a type declaring `opDrop` states no copy. A release on one path only, and storage a callee could re-establish, are must-analysis misses by design |
| 843 | Direct cast between unrelated structs | **Rejected** at the cast; related pointers remain accepted |
| 843 | Reinterpretation through `*void`, inactive union member | **Not judged** — compiler.safety.006 |
| 122, 124, 787, 806, 823 | Faults through `[*] T` and the raw intrinsics | **Not judged** — compiler.safety.006 |
| 704 | Integer to enum | **Not judged** — compiler.safety.010 |
| 478 | Non-exhaustive switch | **Not judged** — language.design.001 |
| 401 | Memory leak | No static proof; runtime allocator leak report available — compiler.safety.017 |
| 674 | Stack exhaustion | Fatal host-stack fault; Windows compiler execution reports it, native reporting follows its host |

## Scope

Concurrency is deliberately absent from this corpus. The runtime already ships tasks, groups,
synchronization, and `parallel for`, but does not prove race freedom.
[language.parallelism.005](../../../../backlog/language.parallelism.md) owns checked captures and
cross-task access; a data-race corpus must distinguish those future proofs from the behavior of
the synchronization primitives that exist today.

## Provenance

The taxonomy is the one the established analyzer benchmarks use — NIST's Juliet suite
(64 099 cases over 118 CWEs), the Toyota ITC benchmark (half the cases defect-free, which is
where the fault/sound split comes from), SV-COMP's `valid-deref` / `valid-free` /
`valid-memtrack` memory-safety properties, and CASTLE. None of them tests a *language*: they
test analyzers on C. What is borrowed here is the class list and the two-halves structure,
not the corpus.
