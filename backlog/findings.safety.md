# Findings — Safety

The borrow, lifetime, and sanity analyses: what they judge, what they miss, and what they refuse
to judge at all. The borrow rules are the language and are always on; the analyses that prove a
runtime fault are tooling under `#[Swag.Sanity]`. The reference states the line
([013_004_borrowing.swg](../bin/reference/modules/language/src/013_004_borrowing.swg)).

Conventions, the identifier counter, and the rest of the backlog are in [README.md](README.md).
Entries are sorted by identifier, ascending; position carries no priority.

### F-041 — A view is judged by source order, not by control flow

- Area: compiler
- Found while: making the borrow-invalidation check fire (a view read after the storage it views
  was moved), which is the first check to need "does a read come AFTER this call"
- Observation: `firstReadAfter` picks the first occurrence of the view whose source offset is at or
  past the end of the mutating call, and takes it as a read on a path that follows the mutation.
  Source order is not execution order in two directions. A read placed after the mutation in the
  text but in a mutually exclusive branch (`if c do container.add(x) else do use(view)`) would be
  reported although it never runs after the change; a read placed before the mutation in the text
  but executed after it on the next iteration of a loop is missed. Only the loop case has a
  mitigation today (`mutationFollowedByLoopExit`, for the find-then-remove-then-exit shape).
- Evidence: the one false positive this produced in the tree was the argument case —
  `values.add(values.toSlice())` in `array.test.swg`, where the view is named inside the mutating
  call and therefore read before it runs — and that is fixed: the search now starts past the whole
  call expression rather than past its name. The branch case has no instance in `std`, `examples`,
  `apps`, `reference` or the workspace suite, so it remains a latent precision limit rather than an
  observed defect.
- Next step: build the sibling-branch shape as a negative test first and confirm it fires; then
  decide between a cheap structural filter (walk to the nearest common ancestor of the mutation and
  the read, and skip when it is an `if`/`switch` with the two in different arms) and threading the
  real flow state, which the check does not have at judgement time because it runs after the body
  is resolved.

### F-042 — Views into a global owner's payload are never judged

- Area: compiler
- Found while: the same work
- Observation: `noteBorrowInvalidation` requires the mutated receiver to root at
  `isLocalVariableStorage`, so a view into what a GLOBAL owner holds is not a candidate. The
  reasoning that excluded globals is about *escape* — a global outlives every frame, so a view of
  it can never dangle by outliving its owner — but invalidation is a different fault: growing a
  global container moves its payload exactly like a local one, and a view taken before the growth
  is stale afterwards.
- Evidence: `var g: String` at file scope, `let v = g.toString()`, `g.append("x")`, then reading
  `v` compiles silently, while the identical body with a local `g` is rejected.
- Next step: drop the `isLocalVariableStorage` condition on the RECEIVER for the invalidation check
  only (the escape checks still need it), keep it on the view, and sweep. The risk is the shape
  where a global container is mutated by one function and viewed by another, which the per-body
  analysis cannot see and must keep ignoring.

### F-043 — The backend stack-escape check is now unreachable from source

- Area: compiler
- Found while: making the borrow rules always on
- Observation: `Check.StackEscape` proves that a returned pointer addresses the current frame. Every
  shape that reaches it from source is now rejected earlier, in sema, by the borrow rule: the
  function never reaches codegen, so the check cannot fire. `bin/unittests/sanity/return_local.swg`
  used to hold `#[Swag.Sanity(.Lifecycle, false)]` precisely to let those functions through, and
  that opt-out no longer exists.
- Evidence: the two positives in that file now report `sanity_err_borrow_escape` from sema instead
  of `sanity_err_return_local_address` from the sanitizer, and no source-level test of the backend
  check remains.
- Next step: decide whether the check still earns its place. If it does, it needs a test at its real
  boundary — a C++ test in `src/Unittest` that hands the sanitizer a micro-IR sequence sema cannot
  produce — rather than a `.swg` fixture that no longer compiles. If it does not, deleting it
  removes a check whose only remaining role is to duplicate a language rule.
