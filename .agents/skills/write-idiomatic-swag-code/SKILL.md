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
otherwise capture the finding with evidence and a next step in the root
[TODO.md](../../../TODO.md), following `modify-swag-codebase`. Do not silently teach a workaround
as the idiom.

## Review Before Editing

1. Inspect nearby current code, the declaration being called, and representative consumers.
2. Search the repository for the preferred idiom and for every consumer of a changed API.
3. Distinguish deliberate compiler-test syntax from incidental support code. Preserve the exact
   construct when it is the behavior under test; modernize its surrounding harness.
4. Apply `modify-swag-codebase` for repository validation and `design-swag-bin-modules` plus
   `write-swag-public-api-docs` when a public declaration under `bin/` changes.

## Name Source Files Consistently

- Name `.swg` and `.swgs` files entirely in lowercase. Do not mirror type casing in filenames.
- Concatenate the words of one symbol or indivisible concept, as in `filebrowserctrl.swg` and
  `gridlayoutctrl.swg`.
- Use dots to separate the named parts of a coherent file family, such as `gif.palette.swg`,
  `app.operations.swg`, and `image.filter.grayscale.test.swg`. Platform, test, initialization,
  backend, role, and feature parts all use the same notation; `.test`, `.init`, and `.win32` are
  common parts, not the only valid ones. Follow the surrounding family when it is more specific.

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
- Never retain a borrow beyond its owner. Prefer references for non-null borrowed values, nullable
  pointers only for real absence, and slices instead of pointer/count pairs outside native code.

## Use Direct Control and Data Flow

- Prefer early exits over nested success paths.
- Use `orelse`, `notnull`, optional chaining, and `with` when they express absence or structured
  initialization more directly than temporary variables and repeated checks.
- Use range, value, index, and filtered iteration instead of manual counters when iteration itself
  is the intent.
- Make switches exhaustive. Do not append an unreachable dummy return solely to satisfy an old
  control-flow pattern when the current compiler proves all cases.
- Use expression-bodied functions for one direct expression, but keep blocks when validation,
  ownership, or failure behavior deserves to remain visible.

## Keep APIs Hard to Misuse

- Prefer values and references at the product layer; isolate raw handles and pointer-heavy shapes
  in native bindings.
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
  `notnull expect adapter()`. Keep the adapter value-returning rather than hiding the rule behind
  an output parameter.
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
