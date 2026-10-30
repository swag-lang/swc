# Doc Command Backlog

This backlog covers `swc doc`, measured against rustdoc and docs.rs, godoc and
pkg.go.dev, Doxygen, Sphinx, DocFX, and Zig's autodoc. The compiler that hosts it is
[compiler.core.md](compiler.core.md).

Evidence, investigations, and intended outcomes for the command stay together here.
[README.md](README.md) has the whole layout.


## Entries

The `doc` command: what a documentation run collects, what it renders, and what it costs.

What belongs here is what the documentation pipeline itself does — collection, rendering, and the
price of a run. A frontend, semantic-analysis, or code-generation defect that a documentation run
merely exposed belongs in [compiler.core.md](compiler.core.md): the file follows the fix,
not the discovery.

### compiler.command.doc.002 — Search stops at the page it is printed in

- Evidence: each page prints its own index and inline search script (`DocSearch`), so a page
  stays a single file that reaches nothing. From `std.core.html`, no query reaches
  `Gui.Widget`. A shared index loaded by every page is the second file that the identity
  rule refuses ([design-swag-identity](../.agents/skills/design-swag-identity/SKILL.md)).
- Next: choose between two options and implement it:
  - a `search.html` that carries the whole workspace index with the same script and is
    linked from the header
  - a per-page no-hit fallback that offers the workspace's module pages as places to
    continue
- Done when: a query typed on any page can lead to a symbol declared in another module of the
  workspace, while every other page stays one self-contained file.

### compiler.command.doc.001 — Code examples in documentation are rendered, never compiled

- Evidence: every ```` ```swag ```` fence goes through `DocMarkdown::renderCodeBlock`, which
  only syntax-colors it. Nothing compiles it, so examples such as the worked example in the
  `truetype` module header ([module.swg](../bin/std/modules/truetype/module.swg)) are
  unchecked.
- Next: synthesize one `#test` per documentation example and compile and run it with the
  module's tests, with an explicit marker for a fence that must not be compiled.
- Done when: every unmarked ```` ```swag ```` example in `bin/` is compiled and run by the test
  suite, and a broken example fails with a location inside its documentation comment.
- Elsewhere: rustdoc compiles and runs every example; Go compiles `Example` functions and
  checks their output.

### compiler.command.doc.003 — There is no serializable documentation model

- Evidence: the pipeline collects `DocItem`/`DocOverload` ([DocTypes.h](../src/Doc/DocTypes.h))
  and renders straight to HTML, so nothing else can consume it. `--export-api-dir` publishes
  the public surface as Swag source, but not the items with their documentation and links.
- Next: define a versioned serialization of the collected model, with stable item identity,
  kind, signature, documentation, links and source location, and emit it from `swc doc`
  beside the HTML.
- Done when: a documentation run can write the serialized model, its item identities stay
  stable across runs on unchanged sources, and a test reads it back.
- Related: compiler.command.doc.004, compiler.command.doc.005

### compiler.command.doc.004 — No public-API diff consumes the documentation model

- Evidence: no tool compares two public surfaces without scraping HTML.
- Next: once compiler.command.doc.003 publishes stable item identities and signatures,
  compare two serialized models and report additions, removals and signature changes.
- Done when: a command reports source-compatible additions, removals and changes between two
  serialized models, with a test for each kind.
- Related: compiler.command.doc.003

### compiler.command.doc.005 — No documentation-coverage report

- Evidence: nothing reports undocumented public symbols.
- Next: report undocumented public symbols from the compiler.command.doc.003 model, with a
  warning contract that can be enforced independently of API diffing.
- Done when: `swc doc` lists or warns on every undocumented public symbol of a module, and a
  test covers a documented and an undocumented declaration.
- Related: compiler.command.doc.003, compiler.command.doc.004

### compiler.command.doc.006 — Attribute the remaining semantic and JIT cost of documentation

- Evidence: `swc doc` runs full workspace sema on every invocation, with or without
  `--rebuild`, and persists no sema artifact. A profile before automatic machine-code reuse
  put page generation below 1 s of a roughly 8 s `std` run, with compile-time execution
  JIT-emitting about 7,800 functions. Its hottest preparation roots were `isStruct`,
  `__message_0`, `isEnum`, `fromArgb` and `fourCc`. Those are historical leads: eligible
  runtime and imported-API JIT bodies can now reuse machine code unless `--rebuild` is used.
  Imported API parsing and semantic analysis remain fresh.
- Next: rebaseline cold, warm and `--rebuild` documentation runs on the same `std` inputs.
  Attribute each remaining newly emitted function and its lowering CPU to the first JIT root
  and dependency closure that demanded it, excluding reused bodies and already-ready
  preparations. Follow the historical roots only where the new profile confirms their cost,
  then decide whether a doc-mode fast path exists.
- Done when: `swc doc --workspace bin/std` no longer pays for JIT emission or lowering its
  pages do not need, or the attribution shows that no doc-mode fast path exists and the
  remaining cost is left to compiler.core.002 and compiler.core.003.
- Related: compiler.core.002, compiler.core.003

### compiler.command.doc.009 — Filtering to a child reference page asserts while building the table of contents

- Evidence: `swc.dm doc --workspace bin/reference --workspace-module language --file-filter
  008_005_memory_and_atomic_intrinsics --num-cores 6` asserts `hasOpenItem` in
  `DocGenerator.cpp:229`. `generateExamples` opens a nested list for the first selected
  level-two file before any parent item exists. Generating the full language page succeeds.
- Next: define table-of-contents handling for a filtered child without its chapter source and
  cover the focused `doc` command at the command boundary.
- Done when: an isolated child source generates valid HTML without an assertion or malformed
  list nesting, and the complete reference keeps its chapter hierarchy.

### compiler.command.doc.010 — Resolve signature links by symbol identity

- Evidence: GUI method signatures link `Image`, including the qualified `Pixel.Image` in
  `Application.setAppIcon`, to `Gui.Pdf.ItemKind.Image` instead of `Pixel.Image`. The newly
  generated `IconAtlas.setRaster` signature inherits the same error, while explicit prose
  links and semantic field tables resolve the type correctly. The GUI page audit also finds
  a broken cross-page `std.pixel.html#Property_name` link.
- Next: preserve semantic symbol identity when coloring declaration signatures; do not let
  a same-spelled enum value win over the resolved parameter type. Reduce the broken property
  link separately and add generated-page assertions for both targets.
- Done when: imported types and same-spelled members link to their canonical declarations in
  signatures, and the GUI page has no broken cross-page property anchor.
