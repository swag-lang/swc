---
name: write-idiomatic-swag-code
description: Write, review, and modernize readable, idiomatic Swag source in `.swg` and `.swgs` files. Use whenever adding or changing Swag implementations, APIs, tests, examples, scripts, or documentation code samples, including visual layout and cognitive readability reviews.
---

# Write Idiomatic Swag Code

Make every edited Swag fragment a concise, current example of the language. Fix an API that
forces awkward callers instead of standardizing the workaround in tests and examples.

Prefer the expression that takes the least effort to understand, not the fewest lines. A local, a block, or a helper earns its
place by naming meaning, preserving an evaluation or lifetime boundary, or grouping a coherent
action. Do not add one merely to give the next statement something to refer to. Concision is
about removing ceremony, not hiding ownership, failure, or effects. Judge the formatted function
and its neighbours together: horizontal density, vertical sprawl, and jumps to helpers all cost
attention. When those goals conflict, preserve the visible reasoning and the operation's contract.

Use every Swag programming task as a probe of the whole platform. When clean Swag code is blocked
or made needlessly awkward, investigate whether `bin/std`, the compiler, an optimization, or the
language design should change. Fix the underlying issue when it belongs in the current task;
otherwise capture the lead with evidence and a next step in the matching
[backlog domain](../../../backlog/README.md), following `modify-swag-codebase`. Do not
silently teach a workaround as the idiom.

## Review Before Editing

1. Inspect nearby current code, the declaration being called, and representative consumers.
2. Search the repository for the preferred idiom and for every consumer of a changed API.
3. Distinguish deliberate compiler-test syntax from incidental support code. Preserve the exact
   construct when it is the behavior under test; modernize its surrounding harness.
4. Apply [validate-swag-changes](../validate-swag-changes/SKILL.md) for repository validation and `design-swag-bin-modules` plus
   `write-swag-public-api-docs` when a public declaration under `bin/` changes.

## Review Diagnostics Before Repairing Rejected Code

Whenever Swag code you write triggers a legitimate compiler error, use the rejected code to
review that diagnostic before fixing the source. Follow
[write-swag-compiler-messages](../write-swag-compiler-messages/SKILL.md): check that the wording
is accurate, clear, complete, and well written, and inspect the actual presentation, including
source spans, notes, help, ordering, and wrapping. A correct rejection alone is not enough.

If any part falls short, improve the compiler diagnostic and verify it on the same rejected
code before correcting the Swag code. Keep a regression fixture when the diagnostic contract or
source presentation changes. Apply this review to incidental programming mistakes as well as
deliberately invalid test cases.

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

### Keep constructors as composition outlines

A constructor for a window, service, or other aggregate should reveal the object it creates before
it explains every part. Initialize the root contract, invoke construction methods in dependency or
visual order, connect cross-part behavior, establish derived state, and return.

- Extract a receiver method when one coherent part's construction, configuration, and callbacks
  obscure that outline. Name the method after the part it produces, and keep the method beside the
  receiver rather than creating an aspect file for it.
- Create a separate type and file when the part owns state or behavior independently. Moving a
  block only to shorten a function is not a component boundary; distinct ownership, lifecycle,
  invariants, or reuse is.
- Keep heterogeneous parts explicit. Data-driven construction earns its indirection when every
  row has the same typed lifecycle and the data captures the complete variation. If callers still
  need per-item fields, casts, callback switches, or exceptional setup, the table hid code instead
  of removing ceremony.
- Judge existing examples by these rules before copying them. Repetition elsewhere can identify a
  reusable contract, but it can also expose the same missing boundary.

## Name Source Files Consistently

- Name `.swg` and `.swgs` files entirely in lowercase. Do not mirror type casing in filenames.
- Concatenate the words of one symbol or indivisible concept, as in `filebrowserctrl.swg` and
  `gridlayoutctrl.swg`.
- Use dots to separate the named parts of a coherent file family, such as `gif.palette.swg`,
  `app.operations.swg`, and `image.filter.grayscale.test.swg`. Platform, test, initialization,
  backend, role, and feature parts all use the same notation; `.test`, `.init`, and `.win32` are
  common parts, not the only valid ones. Follow the surrounding family when it is more specific.
- Let the immediate directory carry its own context. Do not repeat its name as the prefix of a
  file that already has a meaningful local name: write `markdown/syntax.swg` and
  `markdown/inlineview.swg`, not `markdown/markdown.syntax.swg` or
  `markdown/markdowninlineview.swg`. An exact eponymous file may remain when it is the primary
  type or concern and removing the directory name would leave no useful filename.

## Use Namespaces to Carry Shared Context

When several related symbols repeat the same domain prefix, prefer a dedicated namespace that
states the context once. Inside a `Markdown` family, use `Markdown.View`, `Markdown.Style`, and
`Markdown.Block`, not `MarkdownView`, `MarkdownStyle`, and `MarkdownBlock`.

- Introduce a namespace for a coherent subsystem whose symbols are normally discovered and used
  together. Do not create one merely to shorten a lone type or a coincidental lexical prefix.
- Remove the absorbed prefix from every symbol in that family, including private helpers; do not
  leave two competing naming schemes inside the namespace.
- Keep the namespace, source directory, and file vocabulary aligned. A `Markdown.View` belongs in
  `markdown/view.swg`, while a `Markdown.InlineView` belongs in `markdown/inlineview.swg`.
- Treat moving a public symbol into a namespace as an API rename: migrate declarations,
  consumers, tests, examples, documentation, and string-based references together.

## State Access Once at the Widest Exact Scope

`internal` is the language default for both top-level declarations and aggregate members. Put an
access modifier on the widest scope whose declarations all share it, and never repeat the level
inside that scope.

- Start a uniformly public, private, or internal file with the matching `#global` directive. Use
  `#global export` for a documented module API file. Do not repeat that level on its top-level
  functions, types, or `impl` blocks.
- An access modifier governs the whole declaration it prefixes. A modifier on an `impl` governs
  every method in that `impl`; a modifier on a namespace or `{ ... }` block governs every
  declaration in that body. Do not repeat the same level inside that governed body: write
  `private impl Cache { mtd reset() {} }`, never
  `private impl Cache { private mtd reset() {} }`. The compiler rejects the repeated level.
- A different nested level is a deliberate override in a top-level declaration block, namespace,
  or `impl`. Put the common level on that scope, then qualify isolated exceptions there; for example,
  `private impl Cache { mtd reset() {}; public mtd open() {} }`. Split substantial method families
  into sibling `impl` blocks by visibility when that grouping reads more clearly. An unqualified
  `impl` inherits the file level.
- A named aggregate starts its members at `internal` regardless of the file, the aggregate's own
  visibility, or an enclosing top-level access block. Omit `internal` at that member root. Use one
  access block for adjacent fields that share another level, and a modifier on the declaration for
  an isolated exception.
- Member access blocks do not nest visibility levels. Close the current block before starting a
  `public`, `internal`, or `private` group, and preserve declaration order across the sibling groups.
  Unlike an `impl`, an aggregate has no local visibility override inside an access block.
- `readonly` is a write restriction layered on the current member level, not a fourth visibility.
  Write `readonly` inside a `public` block, `public readonly` outside one, or a corresponding block
  for several fields. Never write `internal readonly` at the member root: bare `readonly` already
  means that. `private readonly` is invalid because `private` already restricts writes to the type.
  Bare `readonly` is the only modifier that can be nested in a member access block: it adds the write
  restriction without restating visibility. `public readonly` inside a `public` block is rejected.
- When an entire access block contains only a `readonly` block, combine their headers:
  `public readonly { ... }`. Put any group comment above it. Keep a nested `readonly` group only
  when the surrounding access block also contains writable members; never change field order or
  effective access just to flatten the source.

```swag
#global public

struct Result
{
    public
    {
        value: s32
        readonly checksum: u32
    }

    scratch: u64
}

impl Result
{
    mtd valueOrZero()->s32 => .value
}

private impl Result
{
    mtd resetScratch() { .scratch = 0 }
}
```

## Optimize For Reading, Function By Function

Read [references/readability.md](references/readability.md) for a visual/cognitive quality pass,
or when choosing between a dense expression, a named step, a helper, and a multiline layout.
It supplies concrete examples and a review rubric; its score is a heuristic, not a measurement
of a reader's brain. Apply these rules to all edited Swag code:

- Aim for ordinary code around 100 columns including indentation. Review lines beyond 120:
  simplify, name a meaningful intermediate value, or break at a syntactic boundary. These are
  authoring guides, not hard limits. Keep an indivisible literal, a useful data row, or an imposed
  signature intact when splitting it would make understanding worse. Existing long lines are
  candidates to improve, not the style to imitate.
- Write one operation per statement. Break a long call or declaration between arguments or
  parameters, a boolean chain between conditions, and a packed expression between components.
  Keep one meaningful item per continuation line; avoid staircases of deeply nested calls.
  Apply this to long `#inject` calls too: expose value bindings and `break`/`continue` targets on
  separate lines, preserving their scopes, types, order, and control targets exactly.
- Prefer a named local when its name explains a unit, bound, decision, or transformation. Wrap
  when the expression already reads naturally and only needs space. Do not manufacture relay
  locals, abbreviate useful names, or add a helper merely to meet a column target.
  In storage code, make units visible: `storageBytes` can name a repeated byte-size calculation,
  while `capacity` remains an element count. Reuse that local only while its inputs stay unchanged;
  allocation, initialization, copying, and release must keep their original order and sizes.
  For repeated accesses within a block, naming its base addresses once can reveal the relative
  offsets, as in an unrolled SIMD comparison. Preserve load order and the guard establishing the
  block's bounds; do not hoist the addresses or loads outside their valid scope.
  A callback or effectful call is also a boundary: do not reuse an earlier read across it unless
  the contract guarantees that the value remains unchanged. Wrapping the repeated expression
  can be safer and clearer than factoring away the read.
- Name values by the representation actually being processed. A convolution radius is not its
  kernel width; a row stride is measured in bytes. In code shared by RGB and BGR storage, use
  `channel0`, `channel1`, and `channel2` for physical slots instead of implying a fixed color order.
  Reserve `red`, `green`, and `blue` names for logical colors or a path whose format guarantees them.
- Use a conditional expression only when the condition and both values read at a glance.
  Expand nested choices or branches with substantial work into control flow. Preserve lazy
  evaluation: do not hoist a guarded access, fallible call, or side effect out of its branch.
  When several nested choices map to a small set of named states, use explicit branches or a
  helper that names the decision. Keep short-circuit guards inside that helper when moving them
  out would eagerly evaluate work that the original expression skipped.
- Keep `=>` and single-line bodies for short, obvious accessors, predicates, and delegations.
  A single statement is not necessarily simple: a long signature plus a long expression, nested
  calls, or mixed operators merits a block. Never compress a function solely to match a neighbour.
  When expanding an inferred expression body, spell its existing return type in the signature
  and preserve the expression's evaluation and return behavior.
- Reduce visible repetition with direct returns, declaration-bound `with`, and helpers that name
  coherent operations. Extract a phase when its detail hides the caller's story, even if used
  once. Keep the helper with its owner and count the extra navigation it introduces. Do not
  replace clear local steps with chains of tiny wrappers, switches on modes, or boolean controls.
  Before extracting a helper from a hot loop or per-item decode path, inspect its call frequency
  and enclosing loops. Mark a small helper `#[Swag.Inline]` when that analysis puts it on a hot
  path. Do not benchmark a readability-only change; make the performance decision by inspection.
- Remove repeated namespace prefixes when an appropriate `using` keeps resolution unambiguous.
  For example, `using Math` lets vector-heavy code use `Simd.load` instead of `Math.Simd.load`.
  Retain a useful domain label such as `Simd`; do not invent cryptic aliases or hide which API
  owns an operation. Check existing unqualified calls when extending the visible namespaces.

The default formatter keeps `column-limit = 0`: general wrapping remains an author decision.
Its narrow `bitwise-chain-column-limit = 100` rule splits an unbroken chain of at least three
`&`, `|`, or `^` operands when the chain plus line indentation exceeds that width. The analogous
`logical-chain-column-limit = 100` rule splits chains of at least three conditions joined by the same `and` or `or`. Mixed operators
at the same parenthesis depth remain an author decision. Call prefixes and trailing comments do
not make a compact chain expand. Both rules preserve authored multiline chains and do not simplify
logic. The formatter normalizes authored break placement (for example, bringing a call's first argument back beside its opening parenthesis), and preserves
the choice of a block or one-line named function. Run `swc format` instead of padding
continuations, declaration columns, or trailing comments by hand, then read its output again.
For a vertical argument or parameter list, place the second item on its own line: the default
source-selected layout can join later breaks when the first two items share a source line.

For byte assembly and extraction, prefer `Math.make16`, `Math.make32`, `Math.make64`, and
`Math.byteAt` when they express the operation directly. Assembly arguments run from most to
least significant; byte index zero is least significant. These are numeric operations, not
native-memory-order conversions. Use the existing byte stream/source and endian conversion
APIs when those contracts match the task. Keep explicit shifts for actual bit fields, SIMD
lanes, or transforms whose meaning would be hidden by a byte helper.

Branches and adjacent closures still have group layout rules: an `if` / `elif` / `else` chain
uses `do` or braces consistently, and sibling closures can compact or expand together. Judge
their whole group after formatting. Do not insert dummy comments or statements to defeat a pass;
if it destroys a useful reading boundary, investigate the formatter.

### Make Small Tables Out Of Real Siblings

- Keep adjacent short declarations of one role together: accessors, constants, aliases, enum
  values, or fields. Remove blank lines that scatter that one pattern; keep one blank line when
  the purpose changes. Use a short group comment when the role is otherwise hard to see.
- Let the formatter align the group. A long declaration may deliberately remain unaligned;
  never shorten a meaningful name or reorder dependent declarations to force a rectangular table.
- In a table of typed fields, give a field with a default its type too (`wrapping: bool = true`,
  `hovered: u32 = Swag.U32.Max`), so the column stays one table. An inferred `name = value` row
  among `name: type` rows lines up with neither column. A group made only of inferred fields can
  stay inferred.
- Keep trailing comments near the code they explain. The formatter's `align-outlier-gap` also
  excludes unusually long rows from comment alignment, so one literal cannot push every
  neighbouring comment off the screen. A long explanation usually belongs above its subject;
  preserve documentation ownership and comment directives when moving it.
- Compare related operations in the same order and shape when their contracts match. Keep a
  complex sibling expanded and make exceptions visible instead of hiding them for symmetry.
- In component-wise calculations, use one component per line when each component has its own
  arithmetic or call arguments. Keep short coordinate tuples compact. A long Boolean comparison
  reads similarly: one component check per line, preserving short-circuit order.
- When many branches compare the same stable value with literal keys, use a `switch` to make
  the mapping visible once. Group aliases on one case and separate meaningful families with
  short comments. Preserve every key, result, default, and case-sensitive distinction. Do not
  replace repeated effectful evaluations with one evaluation, or allocate a lookup container
  solely to make the source resemble a table. Place a family comment on its own line aligned
  with the following `case`; the formatter keeps these headers outside the preceding arm when
  deciding whether a uniform switch can stay compact. The multiline case-spacing policy retains
  the paragraph gap before these headers. Comments inside an arm remain attached.

## Return Values Directly

- Return the operation's primary result. Do not make a caller declare an uninitialized value and
  pass its address merely so a `create`, `load`, `parse`, `build`, or query function can fill it.
- Construct non-trivial returned values in `retval` storage. Use `var result: retval` or
  `with var result: retval` when fields are filled incrementally, so ownership and return-slot
  construction stay explicit.
- For a plain value such as a vector of scalars, return an aggregate literal when it shows the
  complete result directly. Remove a temporary plus repetitive field writes only when defaults,
  ownership, evaluation order, and side effects remain unchanged. Keep effectful per-component
  updates explicit, as in `smoothDamp` with its mutable velocity argument.
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
- Use `Swag.makeInterface` only for genuinely reflective construction, such as a generic interface value
  with no concrete receiver. When an instance exists, prefer a typed interface binding.
- Omit redundant explicit types and conversions when the compiler preserves the intended type.
  Keep casts that document or enforce narrowing, signedness, representation, pointer nullability,
  native ABI boundaries, or bit reinterpretation.
- Prefer enum shorthand such as `.Linear`, inferred aggregate literals, and inferred local types
  when their context is unambiguous.
- Let `String` and `string` convert where the context names the target. Pass a `String` to a
  `string` parameter without `.toString()`. Pass, assign, `add`, `insertAt`, return, or place a
  string value in a `String` parameter, element, or field without `String.from`, nested aggregate
  literals included. Keep the explicit form where nothing names the target: an inferred `let`, a
  conditional whose branches have no target type (`cond ? text : "--"` is rejected), or a call
  chained on the result. `String.toLower(Path.extension(name))` already accepts a nullable
  `string`, so no `orelse ""` or `String.from` is needed. Compare with the `String` on the left
  (`string == String` is rejected), and dereference a loop binding (`path[]`), which is a pointer
  to the `String`.
- A `string` converts to `const [..] u8` wherever the target names that type: a parameter
  (`File.writeAllBytes(path, text)`, `Utf8.startsWith(argument, prefix)`), a return value, or a
  typed declaration. Do not write `cast(const [..] u8, text)` there. A `String` gives its bytes
  through `.toSlice()`.

## Make Ownership Scope-Bound

- Give owning value types an idempotent `close`/`reset` operation when early release is useful and
  an `opDrop` that safely releases remaining ownership. A type with `opDrop` is non-copyable
  unless it supplies `opPostCopy`; use `#[Swag.NoCopy]` for an additional copy restriction.
- Immediately place `defer` after a successful manual acquisition when the resource cannot own its
  cleanup. Order acquisitions so deferred releases naturally run in reverse dependency order.
- Use `defer` for cleanup, state restoration, and failure-safe unwinding. Keep an explicit `end`
  when it is semantic finalization whose result must be inspected before leaving the scope.
- Never retain a borrow beyond its owner. Prefer non-null pointers (`*T`) for borrowed values,
  nullable pointers (`*T?`) only for real absence, and slices instead of pointer/count pairs
  outside native code.
- Factor repeated alias checks into a named predicate, but keep the owning copy and its lifetime
  visible beside the mutation it protects. For example, `let copy = String.from(value)` owns
  bytes while an inferred `let copy = value` can only borrow them. Preserve the checked range,
  guard order, and copying before growth or overlapping writes; test inline and allocated storage.

### Choose `defer` by what the cleanup is for

`defer` is for the cleanup a reader should stop thinking about. Apply it in one direction only:

- Release, restore, and unwind with `defer`, on the line after the acquisition succeeds. Never
  repeat the same release on each exit path, and never park it at the bottom of the function.
- Roll a multi-step mutation back with a single `defer` guarded by a success flag set last. One
  guarded block per operation; do not scatter partial rollbacks through the body.
- In a `fail` function, put what only a failure must undo in `defer #fail`, right after the
  change it undoes: a window hidden for a screen grab is shown again, a half-written file is
  removed. It replaces the success flag when the success path needs no rollback at all.
- The command that starts a user action reports its failure (`catch ... as err`, then a message
  naming what failed). A bare `catch action()` makes a failed save, load, or capture look like
  nothing happened.
- Call the operation directly when its result is part of the logic — a commit whose failure must
  propagate, a close whose error the caller reports. `defer` swallows that.

## Borrow Through Pointers

`*T` is the only borrowed indirection: it is non-null, member access and method calls read
through it directly, and only a whole-value read or write opens the place with the postfix `[]`.

- Iterate elements as pointers. Over struct elements, `for v in items` binds `const *T` — never
  a copy — and `for &v in items` binds `*T`. Access members and call methods through the binding
  directly; write a scalar element with `v[] = value`.
- Pass structs by value. The ABI hands the callee a const address, so a by-value struct
  parameter costs no copy. Take `*T` only when the callee mutates the caller's value, and write
  the whole pointee with `[]`.
- `me` is a non-null pointer to the receiver. Pass `me` itself where a `*T` is expected; `&me`
  is the address of the receiver slot, never the object.
- Index places directly: `items[i].field = x` and `&items[i]` route through the container's
  `opIndexPtr`. Reach for `frontPtr`/`backPtr`/`peekPtr` when a borrowed element must outlive
  the expression, and the value forms (`front`, `back`, `peek`) otherwise.

## Remove Relay Locals

- Call through a short receiver directly: `.parent!.invalidate()`, not
  `let parent = .parent!` followed by `parent.invalidate()`. Likewise, return a direct result
  instead of declaring `let result = operation()` only to return it on the next line.
- A single use is a review cue, not proof that a local is redundant. Keep names that explain a
  unit, condition, or algorithmic step; keep owners, snapshots, addresses, and intentional copies.
  Preserve `retval`, contextual types, overload selection, evaluation order, and drop timing.
- For one optional call, use `.surface?.invalidateRect(.paintExtent(.surfaceRect()))` instead of
  copying `.surface` to a local and guarding the call with `if`. The receiver is evaluated once;
  arguments and the rest of the chain run only when it is present. Keep `!` for a required value:
  replacing an asserted receiver with `?.` would silently change the contract.
- Keep a guard and a named binding when several operations share the non-null value or absence
  needs its own behavior. Use the flow-refined value after the guard; do not add a redundant `!`
  when the compiler already knows it is non-null, and do not copy it into a second name
  (`let validNode = node`, `let it = item`) to use it after its guard. Narrowing follows a `do
  return` guard, a `where` filter, and an `if not x { x = ... }` that fills the value. Name the
  parameter or the loop binding for what it holds instead (`applyFilter(id: WndId?)`). End such a
  guard with the `fail` statement itself, not with `try` on a helper that always fails: give the
  helper the error to build (`fail volumeError("...", .NotFound)`), so both the reader and the
  narrowing see that the branch leaves, and no `!` or `unreachable` is needed after it. Remove an unreachable `orelse` fallback after
  that guard too: it suggests a default policy that the path cannot actually take. Keep required
  side effects outside assertions, even if inlining an action into the assertion would remove a
  temporary.

## Bind Construction and Configuration with `with`

`with` earns its braces when it turns a declaration and its configuration into one unit. Anywhere
else, judge whether naming the receiver once makes the operation easier to follow.

- Prefer `with let x = ...`, `with var x: T`, `with var result: retval`, or
  `with owner.field = ...` when the next statements configure that value. Fold a declaration
  immediately followed by `with x` into the header. End the block when configuration ends.
- Preserve construction when introducing `with`. For a type with required fields, bind a complete
  initializer such as `with var info = StartInfo{fileName: fileName, arguments: arguments}`,
  then configure optional fields. Replacing an aggregate literal with `var x: T` and a few
  assignments can leave the whole value uninitialized; `with` does not supply missing defaults.
- Choose by coherence and repetition, not a fixed statement count. Two meaningful settings can
  belong together; one ordinary assignment usually reads better without a block. Prefer a small
  aggregate literal when it states the complete value more clearly than incremental setup.
- Keep a small aggregate literal passed as an argument on one line when it reads easily. When its fields need lines of
  their own — a callback table, a closure with a block body — build the value in
  `with var x: T` with one `.field = value` per line, then pass `x`. A literal spread across a
  call's parentheses buries the call and every closure body in it.
- Move owning fields directly in that literal: `Block{kind, #move text}` or
  `{header, #move previews}`. A conditional can mix a newly constructed value, a copyable
  lvalue, and an explicit transfer: `flag ? String.from("rule") : #move block.text`.
  Only the selected branch transfers; an unmarked lvalue still copies and must be copyable.
  Do not introduce a temporary or a sequence of field assignments just to place `#move`.
- Inside the block, `.` names its subject. A method can use `with` safely: spell accesses to the
  enclosing receiver as `me.field` or `me.method()` inside it. Audit every existing leading dot
  when introducing a block, including arguments, address expressions, and nested callbacks.
  Do not change an outer receiver into the subject accidentally; enum shorthand remains contextual.
- Keep the subject's name when passing the whole value or capturing it. Do not nest `with`
  blocks or pull unrelated control flow inside merely to save repeated prefixes. Preserve the
  lifetime of owning locals and the order of fallible or effectful configuration calls.
- Keep conditional configuration in that same block when it still builds the subject, such as
  attaching a new window only when `parent` exists. A branch is not by itself a reason to split
  construction. Remove duplicate field writes only after checking intervening calls and reads.
- Order a widget's configuration as one table: plain property writes first (`.dockStyle`,
  `.margin`, `.toolTip`), so the formatter aligns them, then the configuring calls, then the
  signal subscriptions. A write that a later call would overwrite, or that reads a value a call
  produces, keeps its place. Merge two calls that add flags to the same set into one.

```swag
with let rail = Wnd.create'Wnd(view, {0, 0, 4})
{
    .dockStyle       = .Left
    .backgroundStyle = .Window
    .style.addStyleSheetColors("wnd_Bk $hilight")
}

with var search: Viewer.SearchApi
{
    .revealMatch = func|view|(match, text)->bool => view.revealOffset(match.offset, text)
    .clear       = func|view|() { Viewer.clearRichEditMatch(view.editor) }
}

host.setSearch(search)
```

## Group Statements and Comment the Reasons

Use blank lines as paragraph boundaries. The formatter fixes structural spacing; only the
author can group by meaning. Reduce both walls of code and unrelated fragments spread far apart.

- Separate the phases of a function body with one blank line — validate, acquire, transform,
  publish. Keep the lines of one phase together. Keep a resource acquisition with its `defer`,
  a calculation with its immediate use, a guard with the operation it protects, and assignments
  describing one value together. Separate a guard group from the main operation when that makes
  the transition clearer; do not add a blank line after every declaration or early exit.
- Do not open or close a block with a blank line, and never use two blank lines to group.
- Group constants by meaning before aligning them: ordinary vectors and numeric limits are
  separate families. A blank line lets each family keep nearby comments; do not split coherent
  data merely because several rows are longer. See the [review guide](references/readability.md).
- Use short comments as reading landmarks for substantial phases, even when no subtle trick is
  involved: `// Resolve names before publishing the entries.` gives the next paragraph a purpose.
  Put one blank line before the comment and keep it attached to its code. Avoid banners, numbered
  narration, and repetitive labels such as `// Loop` or `// Set values`.
- Explain reasons and invariants where needed. `// Increments the counter` above `count += 1`
  is noise; the invariant that makes the increment safe is not. Try clearer names or structure
  before adding a comment that translates an opaque expression into English.
- Every public declaration, every non-obvious constant, and every rollback, retry, ordering
  constraint, or security property deserves a sentence. State the constraint, not the mechanism.
- Do not add comments or blank lines to meet a quota. Remove stale comments and comments that
  repeat a newly extracted helper's name. A small obvious function usually needs neither.

## Use Direct Control and Data Flow

- Mark every fallible call explicitly with `try`, `catch`, `expect`, or `assume`, including calls inside
  a fallible function or an error-handling block. A function's `fail` declaration does not make
  propagation implicit. Choose the keyword for the intended failure path.
- A `catch` expression supplies an implicit default on failure. Use
  `let value = catch operation() as error` only when the result type has that default, and guard
  the error before consuming the result. For a non-nullable `string` or pointer, keep an explicitly
  initialized local and assign it inside `catch { value = try operation() }`. That initializer
  represents a required state, not disposable boilerplate. Preserve translated errors and lifetimes.
- Use `assume operation()` only when the caller guarantees success. `.Assume` safety checks
  that invariant; disabling it removes the caller's error check. Use `expect` when failure
  must terminate in every configuration. Neither form constructs a default result.
- Preserve expression grouping when inserting `try`: after a cast or another operator, use
  parentheses such as `cast(u16, (try readByte())) << 8` so the conversion still precedes the shift.
- Prefer early exits over nested success paths.
- Use `orelse`, the postfix `!`, optional chaining, and `with` when they express absence or
  structured initialization more directly than temporary variables and repeated checks.
- Use range, value, index, and filtered iteration instead of manual counters when iteration itself
  is the intent.
- Filter a loop with `where` instead of opening its body with `if ... do continue` when the
  condition reads naturally as a property of the visited element. Merge consecutive guards that
  skip the same element into one condition, and hoist values that do not depend on the element
  above the loop.
- When the arms of an event handler's `switch evt.kind` grow past a few lines, keep the handler as
  a one-line-per-kind dispatch and give each phase its own method (`press`, `release`, `drag`),
  each returning whether it handled the event. A table indexed by the same handle replaces a
  `switch` that maps handle numbers to cursors or edges.
- Write a key-shortcut handler as `switch evt.key` with `where` guards on the modifier state, one
  statement per arm, so the formatter lays the shortcuts out as a table. Name the modifier
  combinations once as locals (`control`, `controlShift`) before the switch.
- Name the states a worker publishes through an atomic (`LoadRunning`, `LoadSucceeded`,
  `LoadFailed`) instead of comparing it with bare integers.
- Replace a cascade of nested conditionals that maps two small indices to a value with a constant
  table indexed by them, when the table shows the whole mapping at once.
- Count a condition with `if condition do total += 1` instead of casting its boolean result to an
  integer; the conditional states the counting rule directly.
- Use `startsWith` to test a literal prefix instead of indexing and comparing each prefix character.
- When a long sum aggregates peer counters, diagnostics, or geometry terms, put each term on its
  own line and keep the source order; do not bury the categories in one arithmetic expression.
- In a circular scan, name a derived partner index when wrapping arithmetic obscures the relation
  being compared. Keep the offset visible as well when it defines the algorithm (for example, the
  next item versus the item halfway around); do not inline modulo arithmetic into the comparison.
- Write a text template (a style sheet, generated source, a theme sheet) as one `"""` constant laid
  out as it reads, not as a sequence of calls appending one line each. Continuation lines strip
  their indentation up to the column that follows the opening delimiter, so align them under the
  first character of text; deeper indentation is kept.
- Make switches exhaustive. Do not append an unreachable dummy return solely to satisfy an old
  control-flow pattern when the current compiler proves all cases.
- Use expression-bodied functions when the whole declaration reads easily, not merely when it
  contains one expression. Keep blocks when reasoning, ownership, or failure deserves more space.
- Every local, parameter, and capture is used, or the compiler rejects it. A parameter the body
  ignores is spelled `_` (`func(_, index)`, `mtd impl onPaint(_: *PaintEvent) {}`); a loop that
  does not read its index has no name (`for 3`, `parallel for |c| 8`), and an unread position is
  `_` (`for _, v in`, `#code(_, b)`, `let {_, b} =`). `_` is not a name: it can repeat in one
  declaration and cannot be read. `?` only ever marks a nullable type. Remove an unused local;
  keep a needed initializer as `discard init`. There is no `_name` convention: `_x` is an
  ordinary name that must be used.
- Keep a name with `discard name` only when the name itself must stay: a public parameter the
  documentation cites or callers pass by name, a parameter reflection or a generator reads, or a
  value used only in a `#static if` branch. One `discard a, b` lists them all; a list holds
  variable names only, and any other expression keeps its own `discard`.

## Use Dynamic Type Patterns

- Use `value is T` when only compatibility matters, and `if value is T as name`
  when the branch needs the borrowed result. Add `where` to filter the non-null binding.
- Use `switch value` with `case T` or `case T as name`, optionally guarded by `where`,
  for dynamic dispatch over `any`, interfaces, or pointers to dynamic structs. Concrete
  bindings are pointers; interface bindings are views. Both preserve source constness.
- Use `try cast(T, value)` to propagate a conversion error, or `expect cast(T, value)`
  to panic on failure in every build configuration. Keep statically resolved conversions
  as `cast(T, value)`; a contextual conversion is `cast(value)`.
- Use `catch cast(*T?, value)` when the nullable conversion result is itself needed.
  Prefer type patterns when the purpose is testing compatibility or selecting a branch.
- Use `assume cast(T, boxed)` or `assume cast(*T, value)` only when the concrete type
  is an established invariant. `.Assume` safety checks that assertion; disabling it
  does not make a wrong assumption valid.
- Write `where T is IFoo` for a generic compatibility constraint and `T == U` for exact
  type equality. Expression `as`, `Swag.typeAs`, and `Swag.typeIs` remain retired;
  `as` binds a successful type pattern or a caught error.

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
- Keep required side effects outside `Swag.assert`: ordinary release builds and explicit safety
  overrides can omit the entire assertion, including its condition. The `test` command enables
  assertions by default even in release. Execute actions, allocations, mutations, and asynchronous flushes
  first, then assert their saved results (for example, `files.test.swg` in Swag Capture).
- Prefix `expect` or `catch` with `discard` when a non-`void` result is intentionally ignored;
  failure handling does not make an unused return value implicit.
- `expect` returns the successful value or panics in every configuration. Use it directly for
  non-null results; do not introduce nullable adapters or add `!` for failure handling.
  A successful nullable result remains nullable and still needs its own presence check.
- Remove redundant setup, casts, temporaries, comments, and wrappers. Keep boundary cases and
  intent-bearing names even when fewer lines are possible.
- Do not modernize an error fixture or compiler feature test away from the construct it exists to
  compile, reject, or execute.

## Finish the Pass

1. Search again for the obsolete spelling or pattern across the entire repository.
   For a broad cleanup, review relay locals, guarded one-call receivers, separate declaration /
   `with` pairs, repeated configuration prefixes, dense one-liners, long expressions, redundant
   modifier nesting, and scattered sibling declarations throughout the selected modules. Search
   identifies candidates; it does not authorize a blind rewrite or a repository-wide rewrite
   beyond the requested scope.
2. Compile early after representative migrations; do not assume a conversion or lifetime rule.
3. Run the smallest sufficient validation selected by
   [validate-swag-changes](../validate-swag-changes/SKILL.md) for the final
   combined behavior.
4. Read each changed function after formatting, then the file and its related module entry points.
   Can a reader see the purpose, phases, decisions, effects, and result without mentally expanding
   expressions or chasing trivial helpers? Check the weakest function, not just average line length.
   Preserve evaluation order, short-circuiting, borrowing, ownership, cleanup, and test intent.
5. Capture newly proven idioms or pitfalls in this skill. Keep rules concise and backed by code
   that the current compiler accepts.
