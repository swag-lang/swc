---
name: write-idiomatic-swag-code
description: Write, review, and modernize idiomatic Swag source in `.swg` and `.swgs` files. Use whenever adding or changing Swag implementations, APIs, tests, examples, scripts, or documentation code samples; apply current language features for value returns, ownership, cleanup, inference, interfaces, control flow, collections, and failure handling.
---

# Write Idiomatic Swag Code

Make every edited Swag fragment a concise, current example of the language. Fix an API that
forces awkward callers instead of standardizing the workaround in tests and examples.

Use every Swag programming task as a probe of the whole platform. When clean Swag code is blocked
or made needlessly awkward, investigate whether `bin/std`, the compiler, an optimization, or the
language design should change. Fix the underlying issue when it belongs in the current task;
otherwise capture the finding with evidence and a next step in the matching
[backlog/findings.*](../../../backlog/README.md) file, following `modify-swag-codebase`. Do not
silently teach a workaround as the idiom.

## Review Before Editing

1. Inspect nearby current code, the declaration being called, and representative consumers.
2. Search the repository for the preferred idiom and for every consumer of a changed API.
3. Distinguish deliberate compiler-test syntax from incidental support code. Preserve the exact
   construct when it is the behavior under test; modernize its surrounding harness.
4. Apply `modify-swag-codebase` for repository validation and `design-swag-bin-modules` plus
   `write-swag-public-api-docs` when a public declaration under `bin/` changes.

## Organize Source Files Around Types

A file is named for the type it introduces and holds that type with all of its `impl` blocks,
including `impl SomeInterface for Type`. Related enums and the small helper types a type owns —
its element type, its options, its result shape — belong in the same file.

- Never split one type's `impl` across files by aspect. A `foo.view.swg` / `foo.operations.swg`
  pair is the failure mode: it scatters one object's behavior over several files and none of the
  names says what the file contains. Merge them into the type's own file. Size is not a reason to
  split; the standard applications keep 800- to 900-line type files.
- Give a second type in the file its own file instead, unless the first type owns it.
- Extend a type from another file only when the extension belongs to a distinct feature that has
  its own file already — a command, an action, a platform backend. The `impl` then sits next to
  that feature, never in a file named after a layer.
- Group code with no type of its own — native bindings, constants, free helpers — by one coherent
  concern per file, and name the file for that concern.
- Remember that `private` is file-local. Moving a declaration away from its callers breaks the
  build unless it becomes `internal`, which is the default.
- A helper that operates on one type's data is a method of that type, in that type's file — never
  a `private func` in the consumer's file. A free `pointInPolygon(poly, pt)` beside its one caller
  is the failure mode: the next caller cannot find it and writes a second copy. Write
  `Polygon.contains(pt)` in `polygon.swg` instead, and give it the doc comment public API
  requires. Before writing any geometric, textual, or numeric helper, check whether the type
  already offers it or should.

## Name Source Files Consistently

- Name `.swg` and `.swgs` files entirely in lowercase. Do not mirror type casing in filenames.
- Concatenate the words of one symbol or indivisible concept, as in `filebrowserctrl.swg` and
  `gridlayoutctrl.swg`.
- Use dots to separate the named parts of a coherent file family, such as `gif.palette.swg`,
  `app.operations.swg`, and `image.filter.grayscale.test.swg`. Platform, test, initialization,
  backend, role, and feature parts all use the same notation; `.test`, `.init`, and `.win32` are
  common parts, not the only valid ones. Follow the surrounding family when it is more specific.

## Lay Out Statements Without a Column Budget

The canonical Swag style has no maximum line width: `column-limit` is 0. `swc format` normalizes
the shape and indentation of the breaks you write, but it never adds a break to fit a width, and it
can never remove one you added. Every line break inside a statement is permanent and is your
decision, so a wrap made to satisfy an imagined column budget stays in the file forever.

- Write one statement on one line. Do not split a call, a declaration, or an expression because
  the line looks long; long lines are normal here, and the standard library and applications
  routinely reach 180 to 220 columns.
- Break a statement only when the break carries structure, one item per line:
  - an argument that is a multi-row data table,
  - a chain of `and` / `or` conditions,
  - a chain of composed bit flags or packed byte reads.
- Never split a conditional expression around its `?` or `:`. Put it on one line, or give the
  condition a name.
- When a statement is genuinely too dense to read on one line, extract a named local for the part
  that carries meaning. A name beats a continuation line.

```swag
// A boolean chain earns its breaks, and the name makes the assertion readable.
let scanned = entries.count == 24 and
              containsEntry(entries.toSlice(), "item-0.bin") and
              containsEntry(entries.toSlice(), "item-23.bin")
try verify(scanned, "directory scans must return every created file")
```

Never hand-align a continuation line, a declaration column, or a trailing comment. Run
`swc format` and let it place them; manual padding is what drifts when a neighbouring line
changes. Follow `modify-swag-codebase` for the formatting and validation workflow.

## Return Values Directly

- Return the operation's primary result. Do not make a caller declare an uninitialized value and
  pass its address merely so a `create`, `load`, `parse`, `build`, or query function can fill it.
- Construct non-trivial returned values in `retval` storage. Use `var result: retval` or
  `with var result: retval` when fields are filled incrementally, so ownership and return-slot
  construction stay explicit.
- Return a tuple or a named result struct for several cohesive results. Keep output parameters
  only for genuine in-place mutation, caller-provided reusable storage, or a low-level/native ABI.
- A successful `create` or `load` must return a valid value. Report recoverable failure with
  `fail`; do not combine a plausible sentinel with hidden partial mutation.

```swag
func createWindow(options: WindowOptions)->Window fail
{
    var result: retval
    // Initialize result in place.
    return result
}
```

## Let Types and Interfaces Compose

- Rely on contextual implicit conversion to an implemented interface. Give a binding its intended
  interface type when inference would otherwise retain the concrete pointer:

```swag
let renderer: IRenderer = &cpu
```

- Do not write `cast(IRenderer)`, or another interface cast, when assignment, argument, or return
  context already names that interface.
- Pass the address of the concrete instance when the interface must borrow that instance. A
  contextual conversion replaces the interface cast, not the required `&`. Keep an explicit
  interface cast for the rarer value-to-interface construction when no borrowed pointer is the
  intended representation.
- Use `@mkinterface` only for genuinely reflective construction, such as a generic interface value
  with no concrete receiver. When an instance exists, prefer a typed interface binding.
- Omit redundant explicit types and conversions when the compiler preserves the intended type.
  Keep casts that document or enforce narrowing, signedness, representation, pointer nullability,
  native ABI boundaries, or bit reinterpretation.
- Prefer enum shorthand such as `.Linear`, inferred aggregate literals, and inferred local types
  when their context is unambiguous.

## Make Ownership Scope-Bound

- Give owning value types an idempotent `close`/`reset` operation when early release is useful and
  an `opDrop` that safely releases remaining ownership. Mark exclusive owners `#[Swag.NoCopy]`.
- Immediately place `defer` after a successful manual acquisition when the resource cannot own its
  cleanup. Order acquisitions so deferred releases naturally run in reverse dependency order.
- Use `defer` for cleanup, state restoration, and failure-safe unwinding. Keep an explicit `end`
  when it is semantic finalization whose result must be inspected before leaving the scope.
- Never retain a borrow beyond its owner. Prefer non-null pointers (`*T`) for borrowed values,
  nullable pointers (`#null *T`) only for real absence, and slices instead of pointer/count pairs
  outside native code.

### Choose `defer` by what the cleanup is for

`defer` is for the cleanup a reader should stop thinking about. Apply it in one direction only:

- Release, restore, and unwind with `defer`, on the line after the acquisition succeeds. Never
  repeat the same release on each exit path, and never park it at the bottom of the function.
- Roll a multi-step mutation back with a single `defer` guarded by a success flag set last. One
  guarded block per operation; do not scatter partial rollbacks through the body.
- Call the operation directly when its result is part of the logic — a commit whose failure must
  propagate, a close whose error the caller reports. `defer` swallows that.

## Borrow Through Pointers

`*T` is the only borrowed indirection: it is non-null, member access and method calls read
through it directly, and only a whole-value write needs `dref`.

- Iterate elements as pointers. Over struct elements, `for v in items` binds `const *T` — never
  a copy — and `for &v in items` binds `*T`. Access members and call methods through the binding
  directly; write a scalar element with `dref v = value`.
- Pass structs by value. The ABI hands the callee a const address, so a by-value struct
  parameter costs no copy. Take `*T` only when the callee mutates the caller's value, and write
  the whole pointee with `dref`.
- `me` is a non-null pointer to the receiver. Pass `me` itself where a `*T` is expected; `&me`
  is the address of the receiver slot, never the object.
- Index places directly: `items[i].field = x` and `&items[i]` route through the container's
  `opIndexPtr`. Reach for `frontPtr`/`backPtr`/`peekPtr` when a borrowed element must outlive
  the expression, and the value forms (`front`, `back`, `peek`) otherwise.

## Use `with` for Construction, Not for Shorthand

`with` earns its braces when it turns a declaration and its configuration into one unit. Anywhere
else it costs a reader more than it saves.

- Open a `with` when populating one value is the block's whole purpose: a value introduced in the
  header (`with let x = ...`, `with var x: T`, `with owner.field = ...`), or an output parameter
  the function exists to fill. Use it from three consecutive member statements upward; below that,
  plain assignments read better than braces.
- Do not open a `with` on a receiver that merely appears often, and do not wrap a block that mixes
  configuration with unrelated logic. A `with` that contains control flow over other values has
  stopped being a construction block.
- Never open a `with` inside a method whose body also uses `.` for `me`. Both spell a member
  access the same way, and `with` outranks `me`, so the reader has no way to tell them apart.

```swag
with let rail = Wnd.create'Wnd(view, {0, 0, 4})
{
    .dockStyle       = .Left
    .backgroundStyle = .Window
    .style.addStyleSheetColors("wnd_Bk $hilight")
}
```

## Group Statements and Comment the Reasons

The formatter fixes structural blank lines; it cannot see meaning. Both are the author's job.

- Separate the phases of a function body with one blank line — validate, acquire, transform,
  publish. Keep the lines of one phase together, and never blank-separate a run of assignments
  that describe a single value.
- Do not open or close a block with a blank line, and never use two blank lines to group.
- Comment why, not what. `// Increments the counter` above `count += 1` is noise; the invariant
  that makes the increment safe is not.
- Every public declaration, every non-obvious constant, and every rollback, retry, ordering
  constraint, or security property deserves a sentence. State the constraint, not the mechanism.
- Put a short comment above a phase when its purpose is not evident from the code it contains.

## Use Direct Control and Data Flow

- Prefer early exits over nested success paths.
- Use `orelse`, the postfix `!`, optional chaining, and `with` when they express absence or
  structured initialization more directly than temporary variables and repeated checks.
- Use range, value, index, and filtered iteration instead of manual counters when iteration itself
  is the intent.
- Make switches exhaustive. Do not append an unreachable dummy return solely to satisfy an old
  control-flow pattern when the current compiler proves all cases.
- Use expression-bodied functions for one direct expression, but keep blocks when validation,
  ownership, or failure behavior deserves to remain visible.

## Keep APIs Hard to Misuse

- Prefer values, slices, and single-value pointers (`*T`) at the product layer; isolate raw
  handles and block-pointer (`[*] T`) shapes in native bindings.
- Accept slices for contiguous data and options structs for related optional policy.
- Keep ownership, nullability, units, failure, and invalidation visible in the type and name.
- Review the whole operation family before renaming or reshaping one member, then migrate every
  source consumer, test, example, guide, and code sample in the same change.

## Treat Tests and Examples as Language Showcases

- Exercise the preferred public path. Do not expose an internal/native workaround when a product
  API can express the workflow.
- Factor lifecycle-heavy setup into a small helper when that makes the tested behavior dominant,
  but keep test-specific expectations visible.
- Follow successful fixture setup immediately with its cleanup `defer`; do not leave teardown at
  the bottom of a test where an assertion or early return can bypass it.
- Use `expect` for failures that make a test invalid and `try` in examples that propagate failure.
- Prefix `expect` or `catch` with `discard` when a non-`void` result is intentionally ignored;
  failure handling does not make an unused return value implicit.
- `expect` needs a valid fallback value and therefore cannot directly materialize a non-null
  pointer. A test-only adapter may return the same successful pointer as nullable; consume it as
  `expect adapter()!` — a `!` after an error-management keyword asserts its result. Keep the
  adapter value-returning rather than hiding the rule behind an output parameter.
- Remove redundant setup, casts, temporaries, comments, and wrappers. Keep boundary cases and
  intent-bearing names even when fewer lines are possible.
- Do not modernize an error fixture or compiler feature test away from the construct it exists to
  compile, reject, or execute.

## Finish the Pass

1. Search again for the obsolete spelling or pattern across the entire repository.
2. Compile early after representative migrations; do not assume a conversion or lifetime rule.
3. Run the narrowest relevant tests for each family, then the combined validation required by the
   repository skills.
4. Capture newly proven idioms or pitfalls in this skill. Keep rules concise and backed by code
   that the current compiler accepts.
