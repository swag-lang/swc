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
- Related: [F-041](#f-041--a-read-reached-only-by-a-loops-back-edge-is-missed)

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

## Views the escape rule does not recognize

### F-105 — A local stored into a global `any` escapes with no diagnostic

- Area: compiler
- Found while: auditing the language reference for `backlog/findings.language.md`, checking whether
  `any` behaves like a view of an existing value or like a box
- Observation: the borrow rule names `any` as a view — "a pointer, a slice, a `string`,
  an `any`, an interface, a closure capturing by address"
  ([013_004_borrowing.swg:5-8](../bin/reference/modules/language/src/013_004_borrowing.swg#L5-L8)) —
  and the escape half of that rule does not apply it. Assigning a function-local to a global `any`
  compiles silently and leaves the global addressing a dead frame. The identical escape written with
  a pointer is rejected, so it is not the *rule* that is missing, only its reach through the `any`
  conversion: the storage the conversion takes the address of never becomes a borrow source.
- Evidence: an isolated probe, `swc test -d <dir>` on one standalone file, `fast-debug`:

  ```swag
  var g_stash: #null any

  func stashLocal()
  {
      var local = 42
      g_stash = local          // accepted
  }

  #test { stashLocal(); @print(cast(s32) g_stash!, "\n") }
  ```

  It prints `-2143397400` under the JIT and `2092228504` from the forged binary — a stack read, and
  a different one each way, which is what makes it worth stopping on rather than a stable wrong
  answer. `return local` from a function returning `any` is accepted the same way.

  The control is the same local behind a pointer, which the rule catches exactly as documented:

  ```swag
  var g_ptr: #null *s32
  func stashLocalPointer() { var local = 42; g_ptr = &local }
  ```

  > error: borrowed data from local variable 'local' may escape through an assignment

- Next step: find where the value-to-`any` conversion is lowered (`Cast::castToAny`, and the codegen
  that fills the `any` data pointer) and check what it takes the address of — a local's storage, or
  a materialized temporary. The borrow source has to be attributed at that point, because after the
  conversion the assignment only sees an `any`. Do the temporary case at the same time: a literal
  stored into a global `any` (`g_stash = 7`) also compiles, and whatever storage the compiler
  invents for the `7` cannot outlive the statement either. Then write both as positives in
  `bin/unittests/sanity`, next to the pointer cases that already pass.
- Related: the reference now states on both the `any` page and the intrinsics page that an `any` is
  a non-owning view, so what is missing here is the rule that enforces it.

### F-179 — Null narrowing does not survive a receiver the caller wrote as an index

- Area: safety
- Found while: publishing the inline bodies a generated module API used to drop, so a consumer can
  expand them instead of calling across the module boundary.
- Observation: `if .buffer do .buffer[0] = 0` narrows inside the method that declares it, and stops
  narrowing once that body is expanded at a call site whose receiver is an array element. `me`
  becomes `lines[lip]`, both occurrences of `.buffer` become `lines[lip].buffer`, and the guard no
  longer covers the access: an indexed base is not a path narrowing follows. The same source is
  accepted or rejected depending on how the caller spelled the receiver, and the caller has no way
  to see why.
- Evidence: with `Core.String.clear` publishing its body,
  `swc tools/examples.swgs dm build -m aoc2020` reports "indexing into '#null [*] u8' dereferences a
  value that can still be null" inside the generated `core.swg`, from the three `lines[lip].clear()`
  call sites in `8A.swg` and `8B.swg`. Calling `s.clear()` on a plain local compiles. `String.clear`
  now binds the pointer to a local before the guard, which narrows whatever the receiver is.
- Next step: decide whether narrowing should accept an indexed base when no assignment to the index
  or the container separates the guard from the use, or whether the rule should stay path-based and
  the diagnostic should say that the receiver is what stops it. The second is cheap and removes the
  mystery; the first removes the workaround. Either way a `bin/unittests/sanity` case belongs here:
  the same guarded access reached through a local, a field, and an array element.

### F-181 — Null narrowing through a conditional expression depends on the build configuration

- Area: compiler
- Found while: writing a native optimizer test whose select arm dereferences a guarded pointer
- Observation: `func guarded(p: #null *s32) -> s32 => p != null ? p[] : -1` compiles and runs
  under `fast-debug`, and is rejected under `release` with "cannot dereference '#null *s32',
  which can still be null". The narrowing the true arm of a conditional expression receives from
  its condition is therefore not a pure function of the source: the same file is accepted by one
  configuration and refused by the next, which a test suite run in one configuration cannot see.
- Evidence: one-file probe (`swc test --artifact-kind executable -d <dir> --build-cfg fast-debug`
  passes, `--build-cfg release` stops at the diagnostic), swc 0.0.177, 2026-08-22. The `if`
  statement form narrows in both configurations; only the `cond ? a : b` form differs.
- Next step: find what the conditional's narrowing reads that changes with the configuration —
  the safety mask, an inlining decision, or the sanitizer's pass over the condition — and make the
  acceptance configuration-independent, then keep the probe as a sema suite test that runs in
  both configurations.
