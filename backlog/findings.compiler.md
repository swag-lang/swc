# Findings — Compiler

Frontend, semantic analysis, and code generation defects: something observed in `swc` itself, with
a reproduction and a next investigation step. Optimization passes and generated-code performance
are [findings.optimization.md](findings.optimization.md); the borrow, lifetime and sanity analyses
are [findings.safety.md](findings.safety.md).

Conventions, the identifier counter, and the rest of the backlog are in [README.md](README.md).
Entries are sorted by identifier, ascending; position carries no priority.

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

### F-090 — `mtd const` on an enum cannot be called and cannot pass `me` on

- Area: compiler
- Found while: giving `Gui.AnimationEasing` an `evaluate` method so a curve preview can plot the
  exact function the animation scheduler applies.
- Observation: a `const` method declared in an `impl` block over an *enum* is rejected at both ends.
  Passing `me` to a by-value parameter of the enum type fails with `argument 1 for call to 'takeEnum'
  has type 'const Color', but parameter 'value' needs 'Color'`, and calling the method on an ordinary
  enum value fails the other way with `argument 1 for call to 'viaConstMethod' has type 'Color', but
  parameter 'c' needs 'const Color'`. The same `mtd const` over a struct compiles and runs, and a
  non-const `mtd` over the enum compiles and runs even on a `let` binding or an enum literal. So the
  const receiver, not the enum `impl`, is what breaks: a `const T` receiver of a value type neither
  decays to `T` for a by-value argument nor accepts a `T` at the call site.
- Evidence: standalone, no imports beyond `Swag`:

  ```swag
  enum Color { Red, Green }
  func takeEnum(value: Color)->s32 => value == Color.Red ? 1 : 2
  impl Color { mtd const viaConstMethod()->s32 => takeEnum(me) }
  #test { let c = Color.Red; @assert(c.viaConstMethod() == 1) }
  ```

  Replacing `mtd const` with `mtd` compiles and passes; replacing `enum Color` with a struct and
  keeping `mtd const` compiles and passes.
- Next step: find where a method receiver is typed and where an argument is matched for a value
  parameter, and check what makes the struct path accept `const T` -> `T` while the enum path does
  not. The suspicion is that the enum receiver is typed as `const` *value* rather than as a const
  reference to a value, so the usual const-to-value copy never applies. Decide from that whether the
  fix is at the receiver typing or in the by-value argument match, and add the case to the `sema`
  suite either way.
- Workaround in the tree: [curve.swg](../bin/std/modules/core/src/math/curve.swg) declares
  `Math.CurvePreset.evaluate` as a plain `mtd`, which reads as mutable and is not. `Gui.AnimationEasing`
  is now an alias of that enum, so the workaround travels with it.

### F-091 — A method declared over an enum is published with its body, not as an import

- Area: compiler
- Found while: adding `Gui.AnimationEasing.evaluate`, whose first implementation delegated to a
  private helper of the same file.
- Observation: the generated public interface of a shared-library module turns each method into a
  `#[Swag.Foreign(...)]` declaration with no body — `AnimationHandle.isValid` is emitted as
  `#[Swag.Foreign(module: "gui", function: "animation_handle__is_valid", ...)] mtd const isValid()->bool`.
  A method declared in an `impl` block over an *enum* is not: its source body is copied into the
  interface verbatim. A consumer then compiles that body itself, so every symbol it names has to be
  public too, and anything private to the defining file breaks the consumer rather than the module.
- Evidence: `impl AnimationEasing { mtd evaluate(progress: f32)->f32 => Animator.easingFactor(me, progress) }`
  builds `gui.dll` cleanly and then fails in `gui11` with `unknown symbol 'easingFactor'`, pointed at
  `bin/examples/.dep/gui/shared-library/fast-debug/x86_64/gui.swg`, where the `=>` body is reproduced
  as written. Rewriting the same method with a block body changes nothing: the body is still copied,
  so the trigger is the enum `impl`, not the body form.
- Next step: find where the interface writer decides between emitting a foreign import and emitting
  a definition, and check what it keys that decision on — most likely a lookup that only recognizes
  a struct owner, leaving an enum-owned method on the "inline it" path. Confirm against a second
  enum method with a distinct signature before changing anything, since copying is the correct
  answer for a genuinely constant-evaluable declaration and the fix must not remove that case.
- Workaround in the tree: [curve.swg](../bin/std/modules/core/src/math/curve.swg) writes the body of
  `Math.CurvePreset.evaluate` with every symbol fully qualified, because that body is what the
  consumer compiles.
- Related: [F-090](#f-090--mtd-const-on-an-enum-cannot-be-called-and-cannot-pass-me-on), the other
  half of incomplete `impl`-over-enum support.

### F-092 — A `const` cannot be the bound of a `for ... in a..b` range

- Area: compiler
- Found while: plotting an easing curve in `gui11`, sampling it with `for i in 1..CurveSamples`.
- Observation: naming a `const` as either bound of a range in a `for` header fails with
  `unknown symbol`, pointed at the constant. The same constant resolves everywhere else in the same
  function — as an initializer, inside arithmetic, and as the count of a counted `for` — and a `let`
  binding holding its value is accepted as a range bound. So the constant is visible; only the range
  bound refuses to look it up. It holds for a module-level `const` and for a `const` declared in the
  function itself, at file scope and inside a method.
- Evidence: standalone, no imports beyond `Swag`:

  ```swag
  const Samples = 8

  func broken()->s32
  {
      var total = Samples          // fine
      for i in 1..Samples do       // error: unknown symbol 'Samples'
          total += i
      return total
  }

  func works()->s32
  {
      let bound = Samples          // same value, now a binding
      var total = 0's32
      for i in 1..bound do         // accepted
          total += i
      return total
  }
  ```

- Next step: find where the `for` header parses its range and how it resolves each bound, and check
  whether the bound is looked up in a restricted scope or resolved in a pass that runs before
  constants are published. Compare with the counted form `for [i] in Samples`, which resolves the
  same symbol correctly from the same header — the difference between those two paths is where the
  answer is. Add the case to the `parser` or `sema` suite depending on which side it lands on.
