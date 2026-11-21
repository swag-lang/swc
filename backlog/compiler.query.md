# Compiler Query Backlog

This file owns semantic queries, analyzed-snapshot comparison, and verified source edits built on compiler analysis.

### compiler.query.001 — The compiler answers no semantic question from the command line

- Evidence: the compiler has no editor service and no retained analysis process: an autonomous
  caller compiles with one-shot commands. What a text search cannot answer still has no command:
  the type of an expression, the overload a call selected, the exact signature of an imported
  symbol, the callers of a function. Semantic analysis resolves each of them
  (`NodePayload::resolveSymbols`); nothing prints them. A definition reached through an import
  resolves to the generated API file, and a generated source view has no physical mapping.
- Next: add a one-shot `swc query` beside `swc sema` that analyzes a module and answers one
  question about a source position or a symbol. Start with the type and definition, then
  add refined types, the selected signature, implicit conversions and defaults, applicable
  methods and UFCS functions, and references keyed by symbol identity.
- Done when: one command each returns the resolved type, the selected
  overload, the declaration at its original source location across modules and expansions, and
  the references inside a workspace. Report unresolved and ambiguous positions explicitly. Reuse
  the module and prelude caches for cold latency.
- Related: compiler.build.120, compiler.build.119, compiler.build.121, compiler.query.003,
  compiler.command.doc.011, compiler.command.002.

### compiler.query.002 — Report semantic changes at untouched call sites

- Evidence: a new import, overload or changed default can change the meaning of source
  that still compiles. Text diffs and exit status cannot identify those callers.
- Next: compare two snapshots through the query engine. Start with selected callees,
  implicit conversion categories and applied defaults at unchanged call-site expressions.
  Map sites and symbols to stable source identities so a location shift does not look
  like a binding change.
- Done when: fixtures for adding a competing import, changing a parameter type and
  changing a default expose exactly the affected calls. Pure formatting produces no
  semantic changes.
- Related: language.design.050, language.design.051, compiler.query.001, compiler.query.004.

### compiler.query.003 — Offer semantic cleanup edits with explicit preservation checks

- Evidence: candidate cleanups (direct-return bodies, declaration-bound `with`, relay locals)
  also match deliberate language-test syntax, owning locals and typed temporaries, which a
  textual rewrite cannot safely remove. The formatter normalizes source shape but cannot
  decide ownership, overload selection or evaluation effects.
- Proposed contract: a compiler-backed suggestion produces a previewable, versioned source edit
  only after checking the relevant semantic contract. Preserve evaluation count and order,
  receiver binding, contextual type, selected overload, lexical scope and destruction timing.
  A single-use variable is a candidate, not proof of redundancy.
- Boundaries: distinguish semantics-preserving cleanup from a diagnostic explaining a costly copy
  and from a breaking language migration. Never turn a copy into a move, a required receiver into
  an optional call, or a named owner into a temporary borrow automatically. Preserve comments and
  do not rewrite intentional syntax fixtures as part of an unfiltered bulk operation.
- Next: implement a semantic rewrite query on an ordinary compiler snapshot with a dry-run diff.
  Start with a unique verified import, explicit qualification of an existing target, and explicit
  argument names that preserve evaluation order. Check positive and negative cases on the resulting
  snapshot. Then extend it to expression bodies, declaration-bound `with` and relay returns.
  Route API-family renames through explicit semantic migration.
- Done when: suggested edits apply only to the analyzed document version, are idempotent,
  compile with the same relevant contracts, and regression tests reject transformations that
  alter effects, ownership, overload resolution or scope. A CLI preview shows each edit before it applies.
- Related: compiler.query.001, language.design.058, compiler.query.004.

### compiler.query.004 — Check a proposed edit over the real workspace in memory

- Evidence: [in-memory semantic analysis](../src/Unittest/Compiler/Test.Compiler.InMemorySource.cpp#L1107)
  exists internally. The CLI takes files and directories, or a workspace and module,
  so checking a prospective edit currently requires writing the source first.
- Next: accept a versioned overlay of additions, substitutions and deletions keyed by
  workspace paths. Feed it to ordinary module analysis and the semantic query command,
  retaining source locations and the actual import graph. Report a blocked query when
  reaching a phase that needs compile-time execution under a read-only request.
- Done when: a proposed edit can be checked against the real module and its dependencies
  without changing the checkout. Overlay and on-disk checks agree for the same inputs,
  and incomplete or stale overlays produce explicit results.
- Related: compiler.query.001, compiler.query.002, compiler.build.119, compiler.command.001.
