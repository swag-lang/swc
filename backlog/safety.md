# Safety Backlog

The borrow, lifetime, and sanity analyses: what they judge, what they miss, and what they refuse
to judge at all. The borrow rules are the language and are always on; the analyses that prove a
runtime fault are tooling under `#[Swag.Sanity]`. The reference states the line
([013_004_borrowing.swg](../bin/reference/modules/language/src/013_004_borrowing.swg)).

[README.md](README.md) defines the shared backlog conventions.

## Control-flow and lifetime analysis

### F-088 — A view into what a PARAMETER owns is never judged for invalidation

- Area: compiler
- Found while: widening the invalidation check to global owners (the finding that was F-042)
- Observation: `noteBorrowInvalidation` now accepts a local or a global as the mutated owner, and
  deliberately still refuses a parameter. Inside a method, `me` is a parameter, so the body of every
  collection method is unjudged: take a view of what `me` owns, call something that reallocates it,
  read the view again, and nothing is reported — which is the same fault the check rejects one call
  level higher.
- Evidence: `isInvalidationJudgeableOwner` in
  [SemaEscape.cpp](../src/Compiler/Sema/Helpers/SemaEscape.cpp) tests `isLocalVariableStorage` or
  `GlobalStorage`. The equivalent local body is rejected by
  `bin/unittests/sanity/borrow_invalidation.swg:borrowInvDirectMember`.
- Experiment: allowing every parameter owner and treating its pointee type as the lifecycle owner
  catches the direct stale view, but makes `core` uncompilable. It reports valid old-buffer copies in
  `Array.opPostCopy` and `String`, and treats changes to sibling fields in `HashSet`, `TextReader`,
  `TagBinReader`, and `Regexp` as changes to the viewed payload. The receiver-level reallocation bit
  is therefore not precise enough for this judgement.
- Next step: extend reallocation summaries with the receiver field projection they can invalidate
  and preserve conditional old-buffer routes. Re-enable parameter owners only after the direct
  positive, old-buffer copy, and sibling-field cases all give the intended verdict.
