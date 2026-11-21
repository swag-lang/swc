# Doc Command Backlog

This backlog covers `swc doc`, measured against rustdoc and docs.rs, godoc and
pkg.go.dev, Doxygen, Sphinx, DocFX, and Zig's autodoc. The compiler that hosts it is
[compiler.build.md](compiler.build.md).

Evidence, investigations, and intended outcomes for the command stay together here.
[README.md](README.md) has the whole layout.


## Entries

The `doc` command: what a documentation run collects, what it renders, and what it costs.

What belongs here is what the documentation pipeline itself does — collection, rendering, and the
price of a run. A frontend or semantic-analysis defect that a documentation run merely exposed belongs in
[compiler.frontend.md](compiler.frontend.md); code emission belongs in [compiler.codegen.md](compiler.codegen.md),
and workspace scheduling or reuse belongs in [compiler.build.md](compiler.build.md): the file follows the fix,
not the discovery.

### compiler.command.doc.002 — Search stops at the page it is printed in

- Evidence: each page prints its own index and inline search script (`DocSearch`), so a page
  stays a single file that reaches nothing. From `std.core.html`, no query reaches
  `Gui.Wnd`. A shared index loaded by every page is the second file that the identity
  rule refuses ([design-swag-identity](../.agents/skills/design-swag-identity/SKILL.md)).
- Next: choose between two options and implement it:
  - a `search.html` that carries the whole workspace index with the same script and is
    linked from the header
  - a per-page no-hit fallback that offers the workspace's module pages as places to
    continue
- Done when: a query typed on any page can lead to a symbol declared in another module of the
  workspace, while every other page stays one self-contained file.

### compiler.command.doc.004 — No public-API diff consumes the documentation model

- Evidence: no tool compares two public surfaces without scraping HTML.
- Next: once compiler.command.doc.010 publishes stable item identities and signatures,
  compare two serialized models and report additions, removals and signature changes.
- Done when: a command reports source-compatible additions, removals and changes between two
  serialized models, with a test for each kind.
- Related: compiler.command.doc.010

### compiler.command.doc.005 — No documentation-coverage report

- Evidence: nothing reports undocumented public symbols.
- Next: report undocumented public symbols from the compiler.command.doc.010 model, with a
  warning contract that can be enforced independently of API diffing.
- Done when: `swc doc` lists or warns on every undocumented public symbol of a module, and a
  test covers a documented and an undocumented declaration.
- Related: compiler.command.doc.010, compiler.command.doc.004

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
  remaining cost is left to compiler.build.119 and compiler.build.003.
- Related: compiler.build.119, compiler.build.003

### compiler.command.doc.009 — Filtering to a child reference page asserts while building the table of contents

- Evidence: `swc.dm doc --workspace bin/reference --workspace-module language --file-filter
  008_005_memory_and_atomic_intrinsics --num-cores 6` asserts `hasOpenItem` in
  `DocGenerator.cpp:229`. `generateExamples` opens a nested list for the first selected
  level-two file before any parent item exists. Generating the full language page succeeds.
- Next: define table-of-contents handling for a filtered child without its chapter source and
  cover the focused `doc` command at the command boundary.
- Done when: an isolated child source generates valid HTML without an assertion or malformed
  list nesting, and the complete reference keeps its chapter hierarchy.

### compiler.command.doc.010 — There is no serializable documentation model

- Evidence: the pipeline collects `DocItem`/`DocOverload` ([DocTypes.h](../src/Doc/DocTypes.h))
  and renders straight to HTML, so nothing else can consume it. `--export-api-dir` publishes
  the public surface as Swag source, but not the items with their documentation and links.
- Next: publish the collected model with stable item identity, kind, signature, documentation,
  source location, imports, target restrictions and available ownership summaries. Emit
  it from `swc doc` beside the HTML.
- Done when: a documentation run can write the serialized model, its item identities stay
  stable across runs on unchanged sources, and a test reads it back.
- Related: compiler.command.doc.004, compiler.command.doc.005

### compiler.command.doc.011 — Documentation is not available as version-matched local data

- Evidence: the language reference and standard-library documentation are maintained in the
  repository and the website is generated from them, but the command help points at remote pages.
  The `doc` pipeline has no serializable documentation model yet (compiler.command.doc.010), so an
  agent or offline command cannot ask a stable local semantic question without scraping HTML.
- Intent: publish documentation as local, version-matched data, with both
  concise terminal rendering and structured retrieval. It includes the language tour, command-line
  reference, runtime and standard-module APIs, ownership/lifetime rules, platform limits, and the
  source-backed examples needed by first use. A release may also offer browser-opening HTML, but no
  task may require a browser or Internet connection.
- Next: make compiler.command.doc.010's documentation serialization the source of the local index;
  define `swc docs show <topic>`, `swc docs search <terms>`, and API/module lookup around that
  index. Every returned item carries a release version, stable identifier, local source/topic
  reference, signatures, imports, platform requirements, and a minimal compilable example where
  one exists. Index by operation and input/output type as well as by symbol, and expose
  the owner and invalidation rules of borrowed results.
- Done when: the compiler can answer an offline query for a language feature, a standard symbol,
  an import, a lifetime contract, and a command option from data built by the same release. A query
  cannot accidentally combine documentation, runtime, or standard-library data from different
  compiler builds.
- Related: compiler.command.doc.012, compiler.command.doc.002, compiler.command.doc.010,
  compiler.command.help.001, compiler.query.001.

### compiler.command.doc.012 — Code examples in documentation are rendered, never compiled

- Evidence: every ```` ```swag ```` fence goes through `DocMarkdown::renderCodeBlock`, which
  only syntax-colors it. Nothing compiles it, so examples such as the worked example in the
  `truetype` module header ([module.swg](../bin/std/modules/truetype/module.swg)) are
  unchecked.
- Next: synthesize one `#test` per documentation example and compile and run it with the
  module's tests. Mark intentionally incomplete or illustrative snippets explicitly. Give
  diagnostic examples expected failures and executable examples behavioral checks.
- Done when: every unmarked ```` ```swag ```` example in `bin/` compiles, behavioral examples
  run, and a broken example reports its location inside the documentation comment.
- Elsewhere: rustdoc compiles and runs every example; Go compiles `Example` functions and
  checks their output.
