# Findings — Safety

The borrow, lifetime, and sanity analyses: what they judge, what they miss, and what they refuse
to judge at all. The borrow rules are the language and are always on; the analyses that prove a
runtime fault are tooling under `#[Swag.Sanity]`. The reference states the line
([013_004_borrowing.swg](../bin/reference/modules/language/src/013_004_borrowing.swg)).

Conventions, the identifier counter, and the rest of the backlog are in [README.md](README.md).
Entries are sorted by identifier, ascending; position carries no priority.

## Control-flow and lifetime analysis

### F-041 — A read reached only by a loop's back edge is missed

- Area: compiler
- Found while: making the borrow-invalidation check fire (a view read after the storage it views
  was moved), which is the first check to need "does a read come AFTER this call"
- Observation: `firstReadAfter` still decides by source offset. The half of this that produced
  false positives is fixed — an occurrence standing in a sibling arm of the change is now skipped,
  and a branch inside a loop is deliberately not treated as exclusive — but the opposite direction
  remains: a read written BEFORE the mutation in the text and executed after it on the next
  iteration is not seen at all. `mutationFollowedByLoopExit` only covers the reverse case, the
  find-then-remove-then-exit shape it exists to spare.
- Evidence: a loop body reading `view[0]` and then calling `buf.reserve(...)` compiles silently,
  while the same two statements swapped are rejected. The suite covers the branch half
  (`borrowInvExclusiveBranches`, `borrowInvExclusiveCases`, `borrowInvExclusiveBranchesInLoop` in
  `bin/unittests/sanity/borrow_invalidation.swg`); this shape has no test because it would not
  fail today.
- Next step: write the loop shape as a positive test and watch it stay silent, then decide where
  the fact belongs. Judging it in `firstReadAfter` means treating every occurrence inside the same
  enclosing loop as reachable from the mutation, whatever the offsets — cheap, and it needs the
  same enclosing-loop walk `positionsExcludeEachOther` already does. The risk is the view declared
  INSIDE the loop, which is rebound on every turn and must stay silent.

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
- Decided: the check is KEPT. It does not duplicate the language rule, it covers the rule's silence.
  The borrow rule is a proof obligation on syntax and per-function summaries, and it says nothing
  the moment provenance is opaque; `Check.StackEscape` asks a different question at a different
  level — whether the value actually in the return register is a stack address — and that residue is
  exactly what the rule declines to judge. Deleting a 41-line pass that can only fire where sema
  gave up would trade a real guarantee for a line count.
- Next step: give it the test its boundary needs. There is no sanitizer harness in `src/Unittest`
  today (`grep -rl Sanitizer src/Unittest` is empty), so this starts by building one: a
  `MicroPassContext` with a `callConvKind` and a `sanitizerFunction` whose return type is a pointer,
  a hand-built instruction sequence ending in `Ret` with the return register holding a stack
  address, and the assertion that `sanity_err_return_local_address` is reported. The fifteen
  `src/Unittest/Micro/Test.Micro.*.cpp` files are the model for building a micro function by hand;
  none of them constructs a `Sanitizer`, which is the piece to add.

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
- Next step: write the positive AND the "grow, then re-read the payload member" negative first — the
  latter is the ordinary body of `reserve`/`append` and is what makes this risky — then drop the
  condition on the receiver only when the negative stays silent. The open question is whether the
  caller's views must be considered at all: the callee cannot see them, so the judgement may belong
  entirely at the call site, where it already works.
- Related: [F-041](#f-041--a-view-is-judged-by-source-order-not-by-control-flow)

### F-089 — A borrow rule judged per body is silent inside a macro or an inline expansion

- Area: compiler
- Found while: making `@setcontext` of a frame-local context an error (the finding that was F-085)
- Observation: two checks now bail out when `SemaHelpers::effectiveInlinePayload` is set —
  `noteBorrowInvalidation` and `checkSetContext`. Both need to read the body AROUND the node they
  judge, and inside an expansion that body is the callee's while the analysis walks the caller's.
  Measured, not assumed: judging `Core.withAllocator` from the caller reported its correct `defer`
  restore at two of its five expansion sites and not at the other three, purely by how far the
  caller's tree had been built.
- Evidence: `bin/unittests/jit/compiler/push_allocator_local_interface.swg` is the reproduction —
  remove the `effectiveInlinePayload` guard in `checkSetContext` and two of its expansions report
  `sanity_err_context_escape` on a correct macro. A leaking macro is missed for the same reason.
- Next step: give the two checks the enclosing body of the node they judge instead of the current
  function's decl. The visit stack (`AstVisit::parentNodeRef`) has the real ancestors at judgement
  time; the question to settle first is which ancestor to stop at, because stopping at the file
  would let a correct restore in one function silence a fault in another.
