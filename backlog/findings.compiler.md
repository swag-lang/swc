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

### F-078 — A Swag function used as a foreign callback faults on an eight-byte aggregate parameter

- Area: compiler
- Found while: implementing `IDropTarget` in `std/gui`, whose `DragEnter`, `DragOver` and `Drop`
  all take a `POINTL` by value.
- Observation: when a *native* caller invokes a Swag `func` through a function pointer and one
  parameter is an eight-byte aggregate passed by value, the call faults on entry — before the
  first statement of the callee runs. `ABITypeNormalize.cpp:82-95` classifies a struct of size 1,
  2, 4 or 8 as `ByValue` and normalizes it to an integer of that width, which is the MS x64 rule
  and is what makes the *outbound* direction correct. Something on the inbound side does not agree,
  and the prologue reads the register as though it addressed the aggregate.
- Evidence: with `DragEnter` declared as `func(*IDropTarget, #null *IDataObject, DWORD, POINTL, *DWORD)`,
  dragging any file from Explorer over an `sCrypt` window produces, in the Windows application log:
  `APPCRASH sCrypt.exe / gui.dll / c0000005 / offset 0x2218e`. A diagnostic written as the first
  statement of the callback never reaches the file, so the fault precedes the body. Respelling the
  same parameter as `u64` — the register image the ABI mandates for that aggregate — and unpacking
  it by hand makes the whole path work: enter, hover and drop all arrive with correct coordinates.
  That workaround is what `Win32.PACKEDPOINTL` and `Win32.pointFromPacked` are, and the comment on
  `IDropTargetVtbl` points here.
- Why the suites missed it: every case in `src/Unittest/ABI/Test.ABI.FFI.cpp` runs Swag → native,
  including `ffiNativeStructPair32Sum`, which passes an eight-byte aggregate by value and is
  correct. Nothing exercises native → Swag. The `gui` unit tests do drive the drop-target vtable,
  but both sides of that call are Swag, so they agree in the error and pass.
- Next step: add the inbound direction to `Test.ABI.FFI.cpp` — JIT a Swag callee whose signature is
  `(u64, <8-byte struct>, u64) -> u64`, take its native address, and call it from C++ through a
  matching function pointer. That reproduces it in seconds and is where the fix has to be proven.
  Then compare the emitted prologue for a by-value aggregate parameter against the one emitted for
  the integer of the same width: they should be identical, and the crash says they are not.
- Related: [[reference_abi_prologue_framepointer]] territory — the fault is in the callee prologue,
  not at the call site.
