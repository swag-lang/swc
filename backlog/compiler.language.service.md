# Compiler Language Service Backlog

This backlog owns compiler-backed editor services: analysis snapshots, diagnostics, semantic navigation and queries, symbol operations, and code actions. General compiler front-end invalidation and module-interface work remain in [compiler.core.md](compiler.core.md).

Entries stay in one flat list. Keep each outcome testable.

### compiler.language.service.001 — Language services still start a compiler for each edited snapshot

- Evidence: `vscode/src/server.js` keeps an LSP session with versioned open buffers, cancellation,
  shutdown, and module snapshots. `swc sema --editor-index` exports compiler-resolved symbols;
  `--editor-overlay` supplies unsaved buffers without replacing disk files. Each changed snapshot
  still starts a new compiler process and rebuilds its module's semantic state. A GUI analysis
  covered 279 files and 776,906 tokens in 8.3 seconds; scheduler phases attributed 5.8 seconds to
  semantic analysis, 60 ms to parsing, and 169 ms to module setup. Imported Core types were absent
  when the server omitted the standard generated-API root; supplying it resolved `Input.KeyModifiers`
  to `core.swg`.
- Next: host the analysis service in the compiler, retaining source and semantic state between
  edits. Prioritize semantic invalidation and reuse; a parse-only shortcut cannot preserve resolved
  types and references. Keep the existing LSP integration tests as the transport-independent
  contract.
- Done when: requests call retained compiler-library services, obsolete analyses can be
  cancelled inside that service, and unchanged files and interfaces reuse their compiler state.
- Related: compiler.core.001, compiler.core.002, compiler.language.service.002, compiler.language.service.006,
  compiler.language.service.003, compiler.language.service.004, compiler.language.service.005, compiler.language.service.007.

### compiler.language.service.002 — Diagnostics still wait for full-module reanalysis

- Evidence: the LSP server publishes one-line compiler diagnostics for open buffers, converts
  display columns to UTF-16, clears obsolete results, and rejects superseded snapshots. Analysis
  still runs per module; semantic features are cleared while that module has errors. Diagnostic
  notes and related locations are not represented as structured LSP diagnostic information.
- Next: export structured diagnostics from the compiler and retain usable semantic information
  through incomplete or erroneous source. Invalidate affected files through compiler.core.002.
- Done when: edits reanalyze affected files and their dependents, semantic queries continue on
  recoverable input, and identifiers, severity, primary and related locations survive conversion.
- Related: compiler.core.002, compiler.language.service.001.

### compiler.language.service.003 — Definition navigation needs dependency origins and generated-source mappings

- Evidence: the LSP server consumes resolved declaration locations from the compiler, including
  selected calls and symbols retained before folding. Source buffers keep their original paths.
  Imported definitions currently point to generated API files; generated source views without a
  physical mapping and ambiguous generic instances produce no location.
- Next: preserve canonical source origins through API publication, specialization, and generated
  source expansion, then extend the protocol tests to imports, aliases, members, and generics.
- Done when: navigation reaches original declarations across dependencies and expansions,
  covers resolved generic and alias uses, and never substitutes a plausible but unrelated location.
- Related: compiler.core.001, compiler.language.service.001, compiler.language.service.004.

### compiler.language.service.004 — Reference search stops at the analyzed module

- Evidence: LSP references compare resolved declaration identities within one compiler snapshot,
  distinguish declarations from uses, and exclude unrelated same-spelled symbols. Other modules
  are not searched, and unsaved dependency-module buffers are not part of a consumer's snapshot.
- Next: maintain a versioned workspace reference index over module identities and dependency
  interfaces, including invalidation when another module's public declarations change.
- Done when: references span open and on-disk workspace modules, retain semantic identity
  across imported APIs, and exclude stale entries after edits, file removal, and cancellation.
- Related: compiler.language.service.001, compiler.language.service.003, compiler.language.service.007.

### compiler.language.service.005 — Hover needs documentation, constant values, and expression types

- Evidence: hover shows the compiler's resolved type for named entities; inferred variable
  types also appear as inlay hints. Unknown and ambiguous locations return no answer. The
  snapshot does not yet carry public documentation, constant values, ownership, or attributes.
- Next: extend the semantic snapshot with declaration documentation and expression information,
  preserving Markdown escaping and original dependency source identity.
- Done when: hover covers inferred literals and expressions, generic parameters, aliases,
  selected overloads, imported documentation, and relevant ownership and attribute information.
- Related: compiler.language.service.001, compiler.language.service.006, compiler.language.service.003.

### compiler.language.service.008 — Offer semantic cleanup edits with explicit preservation checks

- Evidence: the bin/ cleanup changed 53 direct-return bodies, five declaration/with pairs and
  two relay locals. Candidate searches also found deliberate language-test syntax, owning locals
  and typed temporaries which cannot safely be removed by a textual rewrite. The formatter
  normalizes source shape; it cannot decide ownership, overload selection or evaluation effects.
  Existing LSP entries cover diagnostics, navigation, completion and rename, not these rewrites.
- Proposed contract: a compiler-backed suggestion produces a previewable, versioned source edit
  only after proving the specific transformation preserves meaning. Start with expression bodies,
  declaration-bound with and copyable relay returns. Preserve evaluation count/order, receiver
  binding, contextual type, selected overload, lexical scope and destruction timing.
  A single-use variable is a candidate, not proof of redundancy.
- Boundaries: distinguish semantics-preserving cleanup from a diagnostic explaining a costly copy
  and from a breaking language migration. Never turn a copy into a move, a required receiver into
  an optional call, or a named owner into a temporary borrow automatically. Preserve comments and
  do not rewrite intentional syntax fixtures as part of an unfiltered bulk operation.
- Next: implement a semantic rewrite query on an ordinary compiler snapshot with a dry-run diff.
  Prove positive and negative examples for each of the three initial transformations; expose the
  same edits as editor code actions once compiler.language.service.001 provides the session layer. Wider
  API-family renames use compiler.language.service.007 plus an explicit migration, not a cleanup heuristic.
- Done when: suggested edits apply only to the analyzed document version, are idempotent,
  compile with the same relevant contracts, and regression tests reject transformations that
  alter effects, ownership, overload resolution or scope. A CLI preview works independently of LSP.
- Related: compiler.language.service.001, compiler.language.service.002, compiler.language.service.007;
  language.design.024 in [language.design.md](language.design.md).

### compiler.language.service.006 — The editor has no semantic completion service


**Intent.** Provide completion candidates from the semantic snapshot at a source position, including local scope, members, visible imports, generic parameters, and applicable language constructs.

**Done when.**

- Completion operates on unsaved, syntactically incomplete buffers and honors shadowing and visibility.
- Items include stable kind, insertion text, signature/detail, and documentation fields where available.
- Results are deterministic and cancellable, and a stale request cannot populate a newer buffer.
- Protocol tests cover local, member, import, generic, incomplete-expression, and inaccessible-symbol cases.

**Related:** compiler.language.service.001, compiler.language.service.003, compiler.language.service.005.

### compiler.language.service.007 — The editor cannot rename a symbol semantically


**Intent.** Validate a requested identifier at a resolved declaration, reuse the semantic reference set, and produce a versioned workspace edit without changing unrelated text.

**Done when.**

- Prepare-rename rejects keywords, compiler-generated or immutable declarations, ambiguous positions, and names that would create a known collision.
- Rename covers declarations and references across open and on-disk workspace files while preserving comments and strings.
- Edits are sorted, non-overlapping, versioned where required, and rejected when snapshots become stale.
- Protocol tests cover shadowing, members, overloads, aliases, cross-module use, collision, and cancellation.

**Related:** compiler.language.service.001, compiler.language.service.004.
