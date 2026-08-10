# Compiler Roadmap

This roadmap covers the compiler front end, back end, workspace build engine, and editor-facing compiler services. Documentation, formatting, and language-design work have their own roadmap files. Only unfinished intent belongs here; completed investigations and implementations remain discoverable through Git history and the related findings files.

Items are ordered by decreasing expected value inside each tier. Every completion condition is intended to be testable. Measurements below are a dated baseline, not permanent product claims.

As of 2026-08-09, excluding the vendored `src/Support/Memory/mimalloc` tree, `src/` contains 240,616 physical lines in 652 `.cpp` and `.h` files. `src/Compiler/Sema` accounts for 81,570 lines in 150 files. The compiler diagnostic catalog contains 539 `SWC_DIAG_DEF` entries, and the formatter configuration schema exposes 123 options. Recompute these figures when using them to prioritize work.

## Tier A — Persisted compiler state

### T-001 — Dependencies cross the module boundary as regenerated source

**Intent.** Replace generated dependency API source with a versioned binary module interface. The interface must preserve exported symbols, types, constants, attributes, ABI information, and any bodies or metadata required by downstream optimization, while allowing lazy lookup by symbol.

**Complete when.**

- Workspace imports no longer add generated API `.swg` files to the lexer and parser.
- `--export-api-dir` still emits a human-readable `.swg` representation for inspection and tooling.
- Cache invalidation covers compiler version, build configuration, public declarations, exported constants, ABI-relevant attributes, and serialized inlinable bodies.
- Workspace tests prove that fresh and reused interfaces produce identical diagnostics and artifacts.

**Related:** T-002, T-006, T-008, T-338.

### T-002 — Front-end invalidation is module-wide

**Intent.** Persist lexical, parsed, and semantic state per source file. Cache keys must include the source content, relevant build configuration, and fingerprints of imported public symbols actually observed by the file.

**Complete when.**

- Editing a private body reanalyzes only the changed file and its semantic dependents.
- Changing a public signature invalidates every consumer that observed it.
- Adding, removing, or renaming a file, changing relevant configuration, and changing compiler versions invalidate the correct state.
- Statistics from T-004 report reused and rebuilt files, tokens, and semantic work.
- Clean and incremental workspace builds are covered by equivalent-result tests.

**Related:** T-001, T-004, T-122, T-125.

### T-122 — Code-generation invalidation is module-wide

**Intent.** Cache code generation at function granularity. A reusable artifact must be keyed by the function's semantic fingerprint plus the reachable ABI and inlinable-body dependencies that can affect its generated code.

**Complete when.**

- A body-only edit regenerates the changed function and any function whose generated code depends on it, while unrelated functions are reused.
- Reuse works for JIT and native builds, including debug and unwind metadata.
- A deterministic test compares clean and warm native images, manifests, and observable behavior.
- Cache entries reject compiler, target, configuration, ABI, and relevant optimization changes.

**Related:** T-001, T-002, T-004.

## Tier B — Measurement and budgets

### T-004 — The benchmark campaign measures only hello world

**Evidence.** `bench/history.json` currently uses protocol 2 and contains three records, all dated 2026-08-07. They cover only `hello_build_ms` (99.5432–112.6252 ms) and `hello_build_peak_mb` (105.28125–107.4375 MiB). They do not establish full-core, warm no-op, or touched-file baselines.

**Intent.** Extend the reproducible benchmark campaign with a full core rebuild, a warm no-op rebuild, and a single-file incremental edit. Measure Release and the supported fast-debug configuration where their behavior differs.

**Complete when.**

- Each history record contains wall time, peak memory, processed and reused files, and processed and reused tokens for every workload.
- Results include a normalized control, clean-worktree provenance, compiler revision, host description, and configuration.
- At least five clean baseline campaigns establish stable thresholds before regressions are enforced.
- The campaign and CI report threshold violations without silently rewriting the baseline.

**Related:** T-002, T-005, T-007, T-123.

### T-123 — Detailed compiler profiling is compiled out of shipped builds

**Evidence.** `src/Main/Stats.h` is enabled through `SWC_HAS_STATS`, while `src/pch.h` defines that capability only under `SWC_FORCE_STATS`. Release builds therefore cannot expose the detailed phase and allocation data needed to explain regressions.

**Intent.** Make detailed counters and timings available in the shipped compiler through `--stats` and `--stats-mem`, with negligible cost when disabled.

**Complete when.**

- A Release compiler can report lexer, parser, semantic, code-generation, and Micro phase timings plus material AST, type, symbol, and instruction counts.
- `--stats-mem` attributes retained and peak memory to actionable compiler subsystems.
- Disabled-vs-enabled A/B runs use the T-004 campaign and document an accepted overhead budget.
- The dedicated Stats configuration remains a validation mode rather than the only observable build.

**Related:** T-004, T-005.

### T-005 — Compiler memory has no attributed, enforced budget

**Intent.** Use T-123 attribution and T-004 workloads to reduce retained AST, semantic, Micro, and temporary state, then turn the agreed memory targets into regression checks.

**Complete when.**

- A full core fast-debug build peaks below 250 MiB and a hello-world build below 40 MiB on the campaign host.
- Every campaign workload stays within twice the best comparable compiled-language implementation measured by the same harness, or records a reviewed exception.
- Thresholds, host normalization, and variance policy are stored with the campaign.
- The remaining peak is attributed well enough that a regression report names the responsible subsystem.

**Related:** T-004, T-007, T-123.

## Tier B — Reused and parallel compiler work

### T-006 — Every process rebuilds the prelude state

**Intent.** Serialize and reuse the prelude through the same module-interface mechanism as ordinary dependencies, rather than maintaining a special prelude cache.

**Complete when.**

- A warm hello-world build and a warm script launch load the prelude interface without lexing, parsing, or semantically rebuilding the prelude.
- Prelude source, compiler version, target, and relevant configuration changes invalidate the interface.
- Fresh and reused prelude paths produce identical diagnostics and artifacts.
- The T-004 campaign demonstrates the reduced fixed startup floor.

**Related:** T-001, T-004, T-125.

### T-007 — Workspace front ends and code generation run serially

**Evidence.** The workspace computes dependency order, but module front-end and code-generation work is still consumed serially. The current depth-one pipeline can overlap one background link with compilation of the next module; it does not schedule independent ready modules concurrently.

**Intent.** Schedule ready modules concurrently on the dependency DAG through a shared worker pool with explicit memory and CPU limits.

**Complete when.**

- Independent sibling modules overlap front-end and code-generation work, while consumers wait for the required interface or link artifact.
- Compiler and linker work share a bounded concurrency policy and do not oversubscribe the host.
- Logs, manifests, diagnostics, and emitted artifacts remain deterministic.
- The concurrency cap accounts for the memory measurements and budget from T-005.
- Workspace tests cover a diamond graph, concurrent failures, cancellation, and deterministic repeated builds.

**Related:** T-004, T-005.

## Tier C — Language-server capabilities

### T-008 — There is no persistent language-server process

**Intent.** Add a compiler-hosted LSP transport and session layer: initialization and shutdown, workspace discovery, document open/change/close notifications, versioned snapshots, request cancellation, and orderly teardown. Requests must call compiler-library services instead of launching a compiler process per operation.

**Complete when.**

- A standard LSP client can open a workspace, edit unsaved buffers, cancel obsolete requests, and shut down cleanly.
- Responses are computed from the requested document version and stale work cannot publish newer state.
- The session reuses persisted compiler state from T-001 and T-002 when available.
- Protocol integration tests run independently of the VSCode extension.

**Related:** T-001, T-002, T-337, T-338, T-339, T-340, T-381, T-382.

### T-381 — Open documents have no incremental diagnostics

**Intent.** Publish parser and semantic diagnostics for the accepted version of every open document, including affected dependents, without requiring a workspace build.

**Complete when.**

- Opening a file with an error publishes diagnostics, correcting it clears them, and closing it restores the on-disk view.
- A stale analysis job never overwrites diagnostics for a newer document version.
- Diagnostic identifiers, severity, primary and related locations, source snippets, and normalized paths survive the protocol conversion.
- A multi-file protocol test covers an edit that introduces and then repairs a dependent-file error.

**Related:** T-002, T-008.

### T-337 — The editor has no semantic completion service

**Intent.** Provide completion candidates from the semantic snapshot at a source position, including local scope, members, visible imports, generic parameters, and applicable language constructs.

**Complete when.**

- Completion operates on unsaved, syntactically incomplete buffers and honors shadowing and visibility.
- Items include stable kind, insertion text, signature/detail, and documentation fields where available.
- Results are deterministic and cancellable, and a stale request cannot populate a newer buffer.
- Protocol tests cover local, member, import, generic, incomplete-expression, and inaccessible-symbol cases.

**Related:** T-008, T-338, T-339.

### T-338 — The editor cannot navigate to definitions

**Intent.** Resolve the symbol referenced at a source position and return its canonical declaration location, including declarations in dependencies represented by persisted interfaces.

**Complete when.**

- Navigation covers locals, parameters, members, overloads after resolution, generics, aliases, generated declarations with an available source origin, and imported symbols.
- Ambiguous or unresolved positions return no misleading location.
- Paths and ranges are valid for open snapshots and on-disk dependency sources.
- Protocol tests cover same-file, cross-file, cross-module, overload, and no-result cases.

**Related:** T-001, T-008, T-382.

### T-382 — The editor cannot find semantic references

**Intent.** Enumerate references to the resolved declaration at a source position across the workspace, distinguishing declarations from uses and excluding textually identical but semantically different symbols.

**Complete when.**

- Results cover locals, members, overloads, generics, aliases, and cross-module references.
- The request supports including or excluding the declaration and uses versioned open-document snapshots.
- Shadowed names, comments, strings, and unrelated overloads do not appear.
- Results are deterministic, deduplicated, cancellable, and covered by same-file and cross-module protocol tests.

**Related:** T-008, T-338, T-340.

### T-339 — The editor has no semantic hover service

**Intent.** Render concise semantic information for the resolved entity at a source position: declaration signature, inferred type or constant value, ownership and relevant attributes, and public documentation.

**Complete when.**

- Hover covers values, types, functions and selected overloads, generic parameters, fields, aliases, and literals with inferred types.
- Output uses stable Markdown escaping and does not expose internal compiler-only names.
- Unknown or ambiguous positions return no misleading result.
- Protocol tests cover imported documentation, inferred values, overload resolution, and no-result cases.

**Related:** T-008, T-337, T-338.

### T-340 — The editor cannot rename a symbol semantically

**Intent.** Validate a requested identifier at a resolved declaration, reuse the semantic reference set, and produce a versioned workspace edit without changing unrelated text.

**Complete when.**

- Prepare-rename rejects keywords, compiler-generated or immutable declarations, ambiguous positions, and names that would create a known collision.
- Rename covers declarations and references across open and on-disk workspace files while preserving comments and strings.
- Edits are sorted, non-overlapping, versioned where required, and rejected when snapshots become stale.
- Protocol tests cover shadowing, members, overloads, aliases, cross-module use, collision, and cancellation.

**Related:** T-008, T-382.

## Tier C — Command-line and script workflows

### T-124 — The VSCode task provider emits obsolete command lines

**Evidence.** `vscode/src/providers.js` currently constructs `swag build -w:${workspaceFolder}` and `swag format -f:${file}` as command strings. These spellings do not match the current long-form CLI and string concatenation makes paths with spaces shell-dependent. The module-level task array can also accumulate duplicates across repeated provider calls.

**Intent.** Build tasks from the current compiler argument contract and pass executable plus argument vector through VSCode's task API.

**Complete when.**

- Build, rebuild, and format tasks invoke the intended compiler command with the correct current arguments.
- Workspace and file paths containing spaces or shell metacharacters reach the compiler as one argument.
- Repeated task discovery returns a stable set without duplicates.
- An automated extension test, or an injectable command-builder test, asserts the exact executable and argument vector.

**Related:** T-008.

### T-102 — Bare `.swgs` execution has no supported shell contract

**Evidence.** `tools/setup.swgs` installs the current-user file association used by double-click launch, but its own guidance still requires elevated `assoc`/`ftype` configuration for bare script execution in a shell.

**Intent.** Define and implement the supported Windows behavior for double-click and bare command-line execution, with machine-wide mutation remaining explicit and opt-in.

**Complete when.**

- Setup reports whether bare execution is supported for the current shell and either configures it safely or prints the exact remaining elevated step.
- A fresh `cmd.exe` and Windows PowerShell 5.1 session execute a representative bare `.swgs` script according to that contract.
- Existing double-click behavior remains intact.
- Moving the checkout and rerunning setup refreshes stale interpreter paths, and removal instructions undo installed associations.

**Related:** T-125.

### T-125 — Tool scripts recompile on every invocation

**Intent.** Persist compiled script artifacts using a dependency-complete key over loaded source files, imported public interfaces, compiler version, target, and relevant build configuration.

**Complete when.**

- A second unchanged invocation skips script lexing, parsing, semantic analysis, and code generation before launching the cached artifact.
- Changes in the main script, `#load` inputs, imported public APIs, compiler version, target, or relevant configuration invalidate the artifact.
- Cached and fresh paths preserve diagnostics, forwarded arguments, environment handling, output, and exit code.
- Tests cover direct source changes, transitive loads, imports, configuration changes, corrupt entries, and concurrent cache population.

**Related:** T-001, T-002, T-006, T-102.

## Deliberately out of scope

- **An LLVM back end.** The native and Micro back ends are the supported architecture. Reconsider only if a concrete platform or optimization requirement cannot be met within them.
- **A second language front end.** The compiler architecture is optimized for Swag; a second parser and semantic model would dilute the persisted-state and tooling work above.
- **A package registry inside the compiler roadmap.** Path and workspace dependencies remain compiler responsibilities. Registry identity, trust, lockfiles, acquisition, and publishing need a separate product roadmap once their scope and owner are defined.
