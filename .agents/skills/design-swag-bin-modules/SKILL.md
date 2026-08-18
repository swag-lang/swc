---
name: design-swag-bin-modules
description: Design, review, normalize, and complete public Swag module APIs under bin/. Use whenever adding or changing public declarations, reviewing API consistency or completeness, renaming exported symbols, changing ownership or failure contracts, reorganizing standard or runtime modules, or performing a module-wide API quality pass in bin/runtime, bin/std, bin/native, or bin/examples.
---

# Design Swag Bin Modules

Treat every exported declaration as a durable product contract. Optimize the whole
module for predictability, composability, safety, and discoverability instead of
improving one symbol in isolation.

## Establish the review boundary

1. Read `../modify-swag-codebase/SKILL.md` before changing repository files.
2. Read `../write-swag-public-api-docs/SKILL.md` before changing a public
   declaration or its documentation.
3. Inspect `module.swg`, imports, platform-specific files, tests, examples, and
   direct consumers before designing the change.
4. Generate the module's API documentation when `BuildCfg.genDoc.kind` is `.Api`.
   Use that output, not `public` tokens alone, as the authoritative surface.
5. Partition a broad review into coherent families and keep an explicit checklist.
   Mark a family complete only after reviewing its declarations, behavior, tests,
   examples, documentation, and consumers.

Exclude tests, examples, raw native bindings, and implementation details from the
public-product review unless the request explicitly includes them. Still update
their call sites when a public API changes.

## Keep module boundaries intentional

- Export only behavior that a caller needs. Prefer private or `internal` state to
  public representation, and use `#[Swag.Opaque]` when a public type has a useful
  contract but no useful public fields.
- Keep lower-level modules independent of higher-level ones. Do not introduce a
  dependency cycle to share a minor helper.
- Put one coherent concept in each source file. Use suffixes such as `.win32.swg`
  for platform implementations and keep the platform-independent contract in the
  unsuffixed file.
- Reuse Core value types and vocabulary when they express the contract. Do not
  create module-local substitutes with nearly identical meaning.
- Keep native handle types and upstream-shaped declarations at the binding layer.
  Wrap them with Swag ownership, errors, and value types at the product layer.

For upstream bindings, fidelity is the API rule: preserve canonical symbol names,
integer widths and signedness, pointer depth, pointee constness, nullability, and
calling convention. File every declaration under the upstream feature that
introduces it, one source file per core version and one per extension vendor, so
a reader can tell from the file name which version or extension a symbol needs.
Bindings are checked in as ordinary hand-maintained sources; do not leave a
generator in the tree to reproduce them. Keep ergonomic Swag naming and ownership
policy in a separate product wrapper; never hand-normalize the raw binding until
it no longer matches upstream.

## Name the surface predictably

- Use `UpperCamelCase` for namespaces, types, interfaces, aliases, attributes,
  enum types, and enum cases. Use `lowerCamelCase` for functions, methods,
  parameters, local values, and fields.
- Let a namespace carry context shared by a coherent type family instead of repeating the same
  prefix on every symbol: prefer `Markdown.View`, `Markdown.Style`, and `Markdown.Block` to
  `MarkdownView`, `MarkdownStyle`, and `MarkdownBlock`. Do not introduce a namespace merely to
  shorten a lone type or a coincidental lexical prefix; migrate the whole family and its consumers
  when the namespace represents a real subsystem vocabulary.
- Give types noun names and operations verb names. Use singular type and enum
  names; use plural names for collections and sequences.
- Prefix Boolean queries with `is`, `has`, `can`, `should`, or another unambiguous
  predicate. Keep Boolean fields affirmative so `!value` has one clear meaning.
- Treat initialisms as words in ordinary identifiers (`Utf8`, `Argb`, `Msdf`,
  `getUrl`). Preserve canonical all-capital spelling only in format or protocol
  labels where the spelling is itself meaningful (`RGBA8`, for example). Avoid
  new abbreviations that save only a few letters.
- Reserve `create` for constructing a valid value or owned resource, `load` for
  acquiring or decoding external input, `save` for external persistence, `parse`
  for syntax conversion, and `tryX` for a normal miss reported without `fail`.
- Use `get` only when retrieving a value through a meaningful lookup or external
  boundary. Prefer a noun or predicate for an inexpensive property-like query.
- Use the same root word, parameter order, units, defaults, and failure model for
  related operations. Preserve familiar pairs: `add`/`remove`, `attach`/`detach`,
  `push`/`pop`, `begin`/`end`, `encode`/`decode`, `load`/`save`, and `toX`/`fromX`.
- Name units when ambiguity is realistic, either in the type or identifier. Never
  make callers guess between bytes and elements, radians and degrees, or design
  units and pixels.

Do not rename a symbol in isolation. Search sibling APIs first, choose the family
vocabulary once, then migrate declarations, all consumers, tests, examples,
documentation, serialization names, and string-based lookup sites together.

## Design complete operation families

For each public type or subsystem, write down the meaningful operation matrix.
Review both axes before adding individual conveniences:

- construction, validation, copying, moving, resetting, and destruction;
- mutable and read-only access, including pointer-returning place counterparts when a
  container exposes element storage (`opIndexPtr` beside `opIndex`, in const and mutable
  forms; `frontPtr`/`backPtr`/`peekPtr` beside `front`/`back`/`peek`);
- single-item and bulk operations;
- owned and borrowed inputs or results;
- synchronous variants and callbacks only where both are genuinely useful;
- file, memory, and stream entry points when the implementation already supports
  those sources without duplicating policy;
- horizontal and vertical, scalar and vector, or encode and decode counterparts;
- success, empty input, boundary values, malformed input, and backend failure.

Add a missing counterpart when users would otherwise reimplement it incorrectly
or break an invariant. Do not manufacture symmetry that has no real use case.
Prefer an options struct or enum over a growing sequence of Boolean parameters.

## Make contracts hard to misuse

- Establish validity in constructors and mutators. Do not expose partially
  initialized states unless the type explicitly models a builder or decoder.
- When resetting an entire value, call `@drop(me, 1)` first if it can own
  resources, then call `@init(me, 1)` to restore its declared defaults. Follow
  initialization only with assignments required by non-zero invariants or
  freshly sampled external state; do not use `Memory.clear` for whole values or
  maintain a hand-written field-by-field clear. Reserve `Memory.clear` for raw
  buffers and explicitly selected byte ranges.
- Use `fail` for recoverable environmental, input, allocation, decoding, and
  backend failures. Use assertions for programmer-only invariants. Do not encode
  failure through a plausible value unless absence is the documented result.
- Keep failure atomic when practical: validate first and do not leave an object
  half-mutated. State any unavoidable partial progress explicitly.
- Define behavior for empty inputs, zero sizes, negative coordinates, overflow,
  aliasing, overlap, invalid enum values, repeated cleanup, and null pointers as
  applicable. Test the supported boundary and reject the unsupported one.
- Prefer value semantics and automatic cleanup. When explicit destruction is
  required, pair acquisition and release clearly, make ownership transfer
  visible, and document exactly which views or pointers are invalidated.
- Return borrowed slices, strings, and pointers only when their lifetime has an
  obvious owner. Do not retain a caller-provided borrow beyond the call unless
  the API says so and the type system enforces or exposes that relationship.
- Keep defaults deterministic and inexpensive. Avoid hidden I/O, global-state
  mutation, backend selection, or allocation in property-like queries.
- Make platform behavior agree at the public boundary. Translate native errors
  and conventions instead of leaking platform-specific surprises.

## Evolve APIs deliberately

- Treat removing, renaming, retyping, reordering, changing a default, adding
  `fail`, or changing ownership as a breaking change.
- Preserve compatibility unless the user explicitly authorizes a breaking pass.
  A request for global API normalization is authorization only for the modules
  named in that request.
- When compatibility is required, keep a thin forwarding form only if the
  language and project have a clear deprecation path. Do not leave two permanent
  competing vocabularies.
- Separate mechanical migration from semantic changes when that makes review and
  regression diagnosis clearer, but finish the entire family in the same task.

## Prove the result

For every reviewed family:

1. Search for equivalent or conflicting APIs inside the module and its imports.
2. Inspect every declaration and overload for naming, parameter order, defaults,
   units, nullability, ownership, failure, mutation, and visibility.
3. Add or update tests at the public behavioral boundary, including failure and
   lifecycle cases. Prefer table-driven coverage for operation matrices. They go
   in `<module>/src/tests`, laid out as *Lay Out A Module's Tests The Same Way
   Every Time* in [modify-swag-codebase](../modify-swag-codebase/SKILL.md)
   describes. Test support the module *publishes* — a `Testing` namespace a
   consumer imports — is public API: it lives in `<module>/src/testing`, and it
   is reviewed and documented as a family like any other.
4. Update examples to use the preferred path and remove obsolete workarounds.
5. Document the exact contract according to `write-swag-public-api-docs`.
6. Search the entire repository for old spellings and implicit consumers.
7. Build and run the narrowest relevant validation, then complete the validation
   required by `modify-swag-codebase` for the final combined change.

A module-wide review is complete only when every public family has a recorded
decision, generated documentation passes its audit, all consumers use the chosen
surface, relevant tests pass, and no placeholder, accidental export, unexplained
asymmetry, or unresolved naming variant remains.
