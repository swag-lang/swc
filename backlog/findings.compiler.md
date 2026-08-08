# Findings — Compiler

Frontend, semantic analysis, and code generation defects: something observed in `swc` itself, with
a reproduction and a next investigation step. Optimization passes and generated-code performance
are [findings.optimization.md](findings.optimization.md); the borrow, lifetime and sanity analyses
are [findings.safety.md](findings.safety.md).

Conventions, the identifier counter, and the rest of the backlog are in [README.md](README.md).
Entries are sorted by identifier, ascending; position carries no priority.

### F-004 — Droppable call-result temporaries are never dropped

- Area: compiler
- Found while: fixing the `String`-rvalue `+=` heap corruption (root cause was the return
  path: `return local` bit-copied and still dropped the local — a use-after-free/double-free
  for any `opDrop`-without-`opPostCopy` struct, and for every inlined `String` return; both
  now move out, see `CodeGenMoveElision::canMoveOutAtReturn`)
- Observation: a call result with a `Drop` lifecycle that lands in a compiler temporary is
  never dropped. `discard makeThing()`, `takeView(makeThing())` through an implicit `opCast`,
  and `acc += Format.toString(...)` all leak the temporary's buffer on every execution;
  `Format.toString` itself leaks its inner `ConcatBuffer.toString` temporary per call.
- Evidence: micro dump of `g_Str += Format.toString(...)` shows no drop call anywhere after
  `String.opAssign`; a Tracer struct counting drops confirms zero drops for the `discard` and
  argument-cast shapes while `var x = makeThing()` drops exactly once. An implementation of the
  statement-end flush below was written, measured, and reverted: it took the `core` suite from
  green to 36 crashing tests, then to 5 failing ones once the ownership transfers were found, and
  the last 5 are the design question, not a defect in the mechanism.
- Next step: settle the lifetime question FIRST, because the mechanism is straightforward and the
  rule is not. Dropping at the end of the consuming statement is what a temporary means everywhere
  else, but `bin/std` currently keeps views into temporaries alive past that point:
  `splitArgumentsEx` stores `Latin1.trim(split[0])` — a `string` into the buffer of an `Array`
  temporary — into the array it returns
  ([commandline.swg:93-100](../bin/std/modules/core/src/system/commandline.swg#L93-L100)), and
  `textreader`/`reflection`/`log` do the same shape. Either those sites are wrong and get fixed, or
  a temporary lives to the end of its block, which needs its slot zeroed on entry so a path that
  never produced a value still drops nothing.
- Next step (mechanism, once the rule is settled): register `{flushRootRef, storageSym}` when a
  call's result lands in a compiler temporary and flush in the generic `CodeGen::postNode`. Four
  things the reverted attempt had to get right, each of which cost a debugging session:
  (1) read the storage with `CodeGen::runtimeStorageSymbol`, the way the sret argument reads it —
  the node payload's `runtimeStorageSym` is overwritten by a surrounding cast, so it names the
  cast's slot and the drop lands on the wrong stack offset; (2) resolve the address UNCACHED
  (`resolveLocalStackPayload(sym, false)`), since the call can sit in another block; (3) clear the
  pending list per function in `CodeGen::start`, or an unflushed entry drops a slot belonging to
  the next function's frame; (4) cancel the pending drop wherever a consumer takes over the bits
  instead of copying them — a plain `=` store with no `opPostCopy` and no source reset
  (`emitAssignLifecycle`), and a return that moves out (`returnSourceIsOwnedTemporary`, whose
  comment already states that nothing drops the abandoned temporary). Registration must also stand
  down inside a lazily-evaluated region (ternary, `and`/`or`, `orelse`, `?.`, `try`/`catch`), where
  a skipped path leaves the slot unwritten.
- Next step (flush root): the nearest ancestor that is a block child, EXCEPT that a statement
  keeping the value it evaluates — a `for` range, a `switch` value, a `with` subject — must flush
  after the whole statement, while a loop condition flushes per evaluation. `for` needs more than
  that: it lowers through the `opVisit` macro, so the range expression is emitted inside an
  expansion and the ancestor walk lands inside the macro body, dropping the container before the
  first iteration (`for one in probeList()` then counts 0 elements). A flush point taken from the
  visit stack cannot see through an expansion; the root has to come from the pre-expansion AST.

### F-015 — Calling through a reference to a function pointer never reaches a backend

- Area: compiler
- Found while: closing the use-site nullability hole on a call through a reference (`&#null
  func()->T` now needs a proof like every other nullable value)
- Observation: a call whose callee is a reference to a function value compiles, and then no backend
  can emit the function that contains it. The JIT dies on a hardware exception and the native
  backend refuses the relocation, both while emitting the CALLER of that function, which reads like
  a linker problem rather than a lowering gap. Sema is happy; only codegen is not.
- Evidence: a struct holding `fn: func()->s32` with `mtd const atFn()->const &(func()->s32)`, then
  `let fn = h.atFn(); return fn()`. JIT: `native backend cannot resolve a local function relocation
  for 'probeCallPlain'` / `local target function has no prepared JIT address`; native
  (`--no-test-jit`): the same message with an empty name. The nullable spelling of the same shape is
  now rejected in sema, so only the plain one reaches codegen
  ([sema_err_nullable_use_site.swg](../bin/unittests/errors/sema/sema_err_nullable_use_site.swg) pins
  the rejection). Reproduced identically on the pre-change compiler, so it predates that work.
- Next step: find what the callee payload holds for a reference-typed call target.
  `materializeCallTargetReg` receives the payload of the callee expression; for a reference it is
  the address of the slot holding the code pointer, which needs one load before the call, and the
  emitted relocation suggests it is instead treated as a direct local target. Compare against
  `normalizeIndexReferenceOperand`/`CodeGenReferenceHelpers::unwrapAliasRefPayload`, which is how
  the index and `dref` paths resolve the same reference layer.

### F-019 — A thread-local global cannot hold a droppable type

- Area: compiler
- Found while: implementing `#[Swag.Tls]`, which until then was parsed and then ignored
- Observation: a thread-local global now has one copy per thread, created from the declared value on
  first access and released when the thread ends. What is released is the storage, not the value:
  nothing calls `opDrop` on it. Shutdown cannot stand in for that either, because it runs on one
  thread and dropping only that thread's copy would pick an arbitrary one, so thread-local globals
  are excluded from the shutdown drop list on purpose. A `#[Swag.Tls] var s: String` therefore leaks
  every thread's buffer, silently.
- Evidence: `collectGvtdEntriesRec` skips `symVar->isThreadLocal()`
  ([CodeGen.Function.cpp](../src/Compiler/CodeGen/Ast/CodeGen.Function.cpp)), and the fiber-local
  destructor `__releaseTlsVar` ([os_windows.swg](../bin/runtime/os_windows.swg)) frees the block
  without knowing its type. The three users in `bin/` — `Random.shared()`, and the generator behind
  `Guid64`/`Guid128` — are plain value types, so nothing leaks today.
- Next step: decide whether to reject the combination or support it. Rejecting is one diagnostic on
  a global that carries `Swag.Tls` and a type with a lifecycle, and it is honest. Supporting it
  means the per-thread block has to carry a drop hook the destructor can call, which is the same
  type-erased drop the `@gvtd` table already builds — reuse that shape rather than inventing a
  second one.

### F-021 — A `#run` block cannot initialize a zero-segment global

- Area: compiler
- Found while: the language reference's `Swag.Late` page, whose `#run` set a global and whose
  `@isset` then failed in the native build only. The page now sets the global from a setup
  function, which is what the attribute is for.
- Observation: a global written by a `#run` block keeps its value into the emitted binary only
  when the global was declared with an initializer. Without one it lives in the zero segment,
  which the native backend emits as `.bss`, so every compile-time write is dropped. The JIT run of
  the same `#test` sees the values, so the two halves of the language disagree about what `#run`
  can establish.
- Evidence: a module with `var zero: s32` and `var init: s32 = 1`, both assigned in one `#run`,
  prints `zero 7 / init 9` under the JIT and `zero 0 / init 9` from the produced executable. Same
  split for a struct global and for a `#[Swag.Late]` pointer. `dataSectionName` maps
  `DataSegmentKind::GlobalZero` to `.bss`
  ([DebugRecordCollector.cpp:50](../src/Backend/Debug/DebugRecordCollector.cpp#L50)).
- Next step: decide the rule before touching the backend, because the scalar half is the easy
  half. Promoting a written zero-segment global to initialized data is mechanical; a *pointer*
  written at `#run` time holds a compiler host address, and emitting those bytes verbatim would
  ship a wild pointer — worse than the current zero. Persisting them needs the store to record a
  `DataSegmentRelocation` at the written offset, which nothing does today because the write comes
  from JIT-executed code rather than from a sema-built initializer. Either instrument those stores
  or reject a `#run` write to a global that no initializer placed in the initialized segment.

### F-025 — An ambiguous `.member` still reads "not published yet" as "not there"

- Area: compiler
- Found while: fixing the same race for the unambiguous case, which was making `sCapture` fail to
  compile with 18 to 26 errors per attempt, a different set every run
- Observation: `probeAutoMemberCandidates` looks every candidate up with `noWaitOnEmpty`, because
  with several candidates it must step over the ones that legitimately lack the name. An empty
  result therefore means both "this scope has no such member" and "this scope has not published it
  yet", and the two are indistinguishable. With exactly one candidate the lookup now waits, like
  the qualified spelling of the same access; with more than one it still decides immediately and
  reports `sema_err_cannot_compute_auto_scope`.
- Evidence: a member minted by a `#[Swag.Mixin]` inside one `impl` block of a type arrives when
  that block's body runs, and a struct is marked sema-completed once its `impl` blocks are
  *registered* — `decPendingImplRegistrations` fires before the body
  ([Sema.Impl.cpp:157-166](../src/Compiler/Sema/Ast/Sema.Impl.cpp#L157-L166)) — so a lookup on a
  "complete" type can still miss members. Every sCapture failure was that shape:
  `struct 'ActionQuickStyle' has no field 'Reset'` for a `Reset` that `newCmdId("Reset")` mints in
  a neighbouring `impl` block. The single-candidate half is fixed; a `with` block or a method
  carrying binding vars puts more than one candidate in scope and reopens it.
- Next step: reproduce it deliberately before changing anything — a type whose id is minted by a
  mixin, used as `.Id` inside a `with` block over an unrelated value, in a module big enough to
  spread the jobs. Then decide whether the multi-candidate path can park too: waiting on each
  candidate in turn is wrong (one of them is expected to lack the name), so the wait has to be
  "no candidate can still grow", which needs a scope-settled predicate the compiler does not have.
  A cheaper answer may be to park only while at least one candidate type has an `impl` block whose
  body has not run.

### F-072 — A generic type publishes neither its fields nor its methods

- Area: compiler
- Found while: indexing the API pages for the `doc` search box, which mirrors what the page renders.
- Observation: on an `.Api` page a generic type documents its declaration and nothing else. `Core.Array`
  and `Core.HashTable` render their comment and their signature, with no `Fields` table, no `Methods`
  table, and no standalone entry for any method. A non-generic type beside them is complete:
  `Core.String` renders both tables, `Core.Log` renders its methods.
- Evidence: in `web/std.core.html`, `id="Core_Array"` is followed directly by the next symbol, while
  `id="Core_String"` carries `<h3>Fields</h3>` and `id="Core_String_methods"`. No `id="Core_Array_add"`
  exists anywhere on the page, although `Array.add` is public and documented. Fields are collected by
  `renderMemberTable` and methods by the owner buckets, both keyed on the symbol reached through
  `DocApi::collectDocItems` ([DocApi.Collect.cpp:568-604](../src/Doc/DocApi.Collect.cpp#L568-L604)).
- Next step: dump the symbols `collectSymbolTree` returns for `Core.Array` and check where they are
  dropped — whether `documentationOwner` resolves the generic root, whether `canDocumentMember` rejects
  a member whose owner is a generic struct, or whether the members hang off an instantiated clone that
  `isCurrentModuleSourceFile` then rejects. The answer decides whether the fix belongs in collection or
  in the owner mapping.
- Related: [T-014](todo.doc.md#t-014--search-stops-at-the-page-it-is-printed-in), whose search index is missing the same symbols.

### F-076 — A struct reaching a variadic parameter through a reference formats as `?`

- Area: compiler
- Found while: building the child environment block of `Env.startProcess`, which formats the name
  and the value of every variable a `HashTable` visit hands over.
- Observation: passing a `const &String` to a variadic `any` parameter loses the value. The same
  `String` passed by value formats correctly, so the reference is what the boxing mishandles. It
  is silent: nothing fails, and the output is one `?` per argument, which reads like a formatting
  option rather than a lost value.
- Evidence: with `let direct = String.from("hello")`, `Format.toString("%", direct)` answers
  `hello`, while a `func f(value: const &String) => Format.toString("%", value)` answers `?`.
  Identical under the JIT and from the forged executable. This is how every `for key, [value] in
  table` reaches its bindings — `opVisit` casts them to `const &K` and `const &V` — so
  `Format.toString("%=%", key, value)` over a `HashTable'(String, String)` answers `?=?`.
- Next step: inspect what the variadic boxing records for a reference argument. The `?` is what a
  formatter prints for a type it cannot convert, so the question is whether the `any` carries the
  `typeinfo` of the reference rather than of the pointee, or the address of the reference slot
  rather than of the value. Decide then whether the fix is to strip the reference where the
  argument is boxed, or to have the conversion follow it.

### F-079 — A native callee reached through a plain `func` pointer may mutate a large by-value aggregate the Swag caller did not copy

- Area: compiler
- Found while: fixing F-078, which aligned the Swag convention's small-aggregate argument passing
  with the native rule.
- Observation: for aggregates larger than eight bytes both conventions pass a pointer, but they
  disagree on who owns the pointee. The native contract makes the caller pass a copy the callee may
  scribble on; the Swag convention borrows the caller's storage (`passByReferenceNeedsCopy` is
  false in `CallConv::setup()`). A `func` type carries no convention, so a call through a
  function-pointer value always lowers with the Swag one — and when the real target is native, the
  callee receives the caller's own aggregate. A native callee that mutates its by-value parameter,
  which its ABI permits, then corrupts the caller's variable. The inbound direction is safe: a
  native caller passes a copy and the Swag callee only reads it.
- Evidence: no shipped binding hits it — the COM interfaces under `bin/std/modules/win32` pass
  every structure larger than a register through an explicit pointer — so this is a latent
  contract gap, not a reproduced fault. The direct-call direction is already correct: a call that
  names a `#[Swag.Foreign]` symbol uses that symbol's convention and copies.
- Next step: decide whether a `func` type should carry a calling convention (which would also let
  a callback declare itself native), or whether the Swag convention should adopt the caller-copy
  rule for large aggregates; measure the second option's cost on `gui`/`pixel` call sites before
  choosing.
### F-080 — A conditional expression yielding an owning value copies it without its post-copy

- Area: compiler
- Found while: porting `tools/*.bat` to Swag, where a tool picked its command as
  `options.command.isEmpty() ? String.from("build") : options.command`.
- Observation: a conditional expression whose branches produce a struct that owns memory hands
  the result over without running `opPostCopy`, so the result aliases the buffer of the branch it
  took. Dropping it frees memory the original still points at. Nothing reports anything at the
  point of the mistake: the program keeps running and dies later, in an unrelated teardown.
- Evidence, reduced to one `#test`: `var source = String.from("value")`, then in an inner scope
  `let picked = source.isEmpty() ? String.from("other") : source` followed by
  `@assert(picked == "value")`. The assertion passes; leaving the inner scope frees the buffer,
  and the next use of `source` crashes with `EXCEPTION_ACCESS_VIOLATION`. The unreduced case cost
  a whole `apps test sCapture` run to surface: every test passed, and the process died in the
  tool's `#main` epilogue afterwards.
- Next step: compare what code generation emits for the two arms of a conditional against what a
  plain assignment from the same expression emits, in `CodeGen.Conditional.cpp`. A plain
  `let picked = source` runs the post-copy, so the question is whether the conditional path skips
  the lifecycle call, or whether it materializes into a slot the caller then treats as already
  constructed. Decide at the same time what a conditional mixing a temporary and a borrowed value
  should mean: forcing a copy on both arms is the simple answer, moving the temporary and copying
  the other is the fast one.
- Related: [[reference_conditional_int_to_float_miscompile]] touched the same generator for a
  different reason, so the two may share a root.

---

### F-081 — An all-literal array passed as a slice of a converting struct type never reaches code generation

- Found while: replacing 107 `arguments.add(String.from("..."))` calls in `tools/src` with slice
  literals, which is what the same tool would be in Python.
- Observation: `["a", "b"]` passed where `const [..] String` is expected is accepted by the type
  checker and then fails in three different ways depending on the shape of the call. Every element
  is a `string` literal, so the aggregate is marked constant; every element also needs `opAffect`
  to become a `String`, so it is not one. Nothing reconciles those two facts. One non-constant
  element in the same literal makes all of it work, which is why nobody has hit this.
- Evidence, three reductions, all against a `String` slice:
  - `var a: Array'String` then `a.add(["--publish"])` — code generation reports `internal compiler
    error while lowering: cannot materialize an aggregate constant payload`.
  - `func take(v: const [..] String)` then `take(["a", "b"])` — assertion, `ConstantLower.cpp:774`,
    `SWC_UNREACHABLE` in `lowerConstantToBytes`: the destination is a struct and the constant is a
    string, which that function has no case for.
  - The same call inside `@print(...)` — `SemaJIT::tryRunConstCall` decides the call is constant,
    and `buildConstCallArguments` asserts at `ConstantLower.cpp:439` lowering the argument.
  - `a.add(["build", "--workspace", ws])` with `ws` a `String` variable compiles and runs.
- Cause, as far as it was traced: `Cast::castToSlice` (`Cast.Runtime.cpp`, the `isAggregateArray`
  branch) validates every element with `castAllowed` and then materializes a constant slice,
  assuming each element cast folded. For a `String` element the cast is legal only through the set
  operator that `Cast::castToStruct` resolves with `resolveStructSetCastCandidate`, and that
  function returns `Result::Continue` without recording the chosen operator anywhere, so the slice
  path cannot see that a call is involved and reuses the source `string` constant.
- Next step: `Cast.Array.cpp::checkElemCast` already solves this for the array destination — it
  asks `resolveStructSetCastCandidate` per element and, when an operator answers, rewrites the
  element *node* through `castIfNeeded` so the value is built at run time. The slice branch of
  `castToSlice` has no equivalent and never touches the element nodes. Give it the same treatment,
  and clear the aggregate node's constant when it does, otherwise code generation still tries to
  materialize the payload — suppressing the fold inside the cast alone was tried and only moves
  the failure to the third form above. Suite: `bin/unittests/jit`, one case per reduction.

---

### F-082 — A script that imports `core` without `using Core` cannot compile the imported API

- Found while: probing nested `#load`, where a reduced script happened to leave `using Core` out.
- Observation: the generated dependency API of `core` fails to compile in the importing script,
  reporting `unknown symbol 'Reflection'` inside `core.swg` itself. Whether a module's *own*
  generated source resolves its *own* namespaces must not depend on what the importer wrote.
- Evidence, the whole reproduction, and it is the smallest script that imports anything:

  ```swag
  #import("core", location: "swag@std")

  #main
  {
      @print("hello\n")
  }
  ```

  `error: unknown symbol 'Reflection'` at `<temp>/swag/scripts/<hash>/.dep/core/.../core.swg`,
  first at line 4227 (`Reflection.attribute`) and again at 601 (`Reflection.isString`, while
  checking `HashTable`). Adding `using Core` to the script makes all of it compile. Deterministic:
  identical with `--num-cores 1`, and identical on an untouched master `swc.exe`, so it predates
  the current branch and is not a race.
- Consequence: the first thing anyone writes after `swc new script` is an import, and the failure
  names a file the author never wrote and cannot fix. It also makes every documented script
  example load-bearing on a `using` line that reads as a convenience.
- Next step: the imported-API files are collected as `FileFlagsE::ImportedApi` and their top-level
  symbols are created under the shared import-root namespace rather than the module namespace
  (`topLevelCreationSymMap` in `Sema.Block.cpp`). Look at what scope an `ImportedApi` file
  *resolves* from: it very likely resolves through the importing module's namespace, so a sibling
  namespace of its own module is only reachable when the importer happens to have pulled it in.
  An imported API should resolve against its own module root first.

### F-084 — Runtime `Swag.*` types have no cross-module identity: `==`, `case`, and `is` silently miss

- Area: compiler
- Found while: adding `Core.Errors.message`, which walks a caught error's typeinfo down to
  `Swag.BaseError`; the comparison held inside core's own tests and failed the moment the error
  crossed the core.dll boundary into a script.
- Observation: runtime types are compiled into every module under that module's root namespace,
  so their descriptor fullname is `Scratchpad.Swag.BaseError` in a script and `Core.Swag.BaseError`
  inside core.dll. The typeinfo `crc` hashes that module-prefixed scoped name
  (`canonicalScopedNameHash` in `src/Compiler/Sema/Type/TypeRuntimeHash.cpp`), so two modules never
  agree on the identity of the same runtime type. Imported API symbols were canonicalized by the
  cross-DLL interface fix; runtime files were not, because they are local sources in every module.
- Evidence: a script that catches `Errors.SyntaxError` from core and walks
  `fields[0].pointedType` reads fullname `Scratchpad.Swag.BaseError`, and `ft == Swag.BaseError`
  is true script-side but false inside core.dll. Latent in the tree: `guardianErrorText` in
  `bin/apps/modules/sCrypt/src/winfsp/guardian.win32.swg` does `case Swag.SystemError:` on errors
  raised by core.dll, which can only fall through to its generic fallback text. `Core.String`
  compares fine, which is what hides the gap: only `Swag.*` types are affected.
- Next step: in `canonicalScopedNameHash` and in the descriptor fullname emission
  (`TypeGen.Payload.cpp`), strip the owning module's namespace when the defining source file is
  `isRuntime()`, so every module emits `Swag.BaseError` with one crc. Then simplify
  `Core.Errors.message` to compare `type == Swag.BaseError` instead of matching the base shape
  structurally, and add a cross-DLL `case Swag.SystemError` check to the workspace suite.
- Related: the fixed cross-DLL interface identity work (canonical runtimeHash), which covered
  imported API symbols only.
