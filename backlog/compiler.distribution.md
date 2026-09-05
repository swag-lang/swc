# Compiler Distribution And First-Use Backlog

This backlog owns the release artifact a programmer receives, its resource payload, first-use
workflow, local learning material, and machine-consumable discovery surface. It does not own the
compiler's semantic services, the documentation renderer, the Windows shell implementation, or
the standard library itself; it turns their published outputs into one coherent product.

## Terms that this backlog uses precisely

An **installation** is a complete `bin/` directory: it contains `swc.exe`, `runtime/`, and `std/`
from one release, with every file those trees need. It may be a repository's `bin/`, an extracted
release, or a copied complete directory. `swc.exe` already recognizes this layout. A complete
`bin/` installation can be placed on `PATH` or selected by `SWAG_PATH`, but neither action makes
an incomplete directory complete.

A **single-file delivery** is one downloaded `swc.exe` in an otherwise empty directory. It is not
an installation and must not require one before a programmer can create, read, check, and run a
first script. It carries its own compatible runtime, standard workspace, documentation, templates,
and examples. If it materializes those resources locally, that directory is an **activation cache**:
private, versioned, integrity-checked data owned by the executable, not an installation the user
must discover or configure.

**Shell registration** is the optional act of adding a complete `bin/` installation to `PATH` or
claiming `.swgs`. It is neither delivery nor activation. It must never happen as a side effect of
running `swc`, `doctor`, `new`, `help`, or an example.

These words are deliberately not interchangeable in command output, documentation, or diagnostics.
In particular, a lone `swc.exe` must never tell its user to "install `bin/`"; it must either activate
its embedded payload or diagnose a damaged delivery. Conversely, guidance for an existing complete
`bin/` installation must not describe extraction, payload caching, or a bootstrap download.

## Delivery contract

### compiler.distribution.001 — One downloaded executable has no finished product contract

- Evidence: the repository explicitly publishes no binary release today. `swc` resolves `runtime/`
  beside its executable and resolves `std/` beside it or through `SWAG_PATH`; a copied lone
  executable therefore cannot compile an ordinary program. `tools/setup.swgs` currently changes
  the user environment and file association, which is useful only after a complete `bin/` directory
  exists.
- Intent: publish a release contract with two supported entrances, named consistently everywhere:
  the complete `bin/` installation above and the single-file delivery above. Define exactly which
  release files, generated documentation, examples, license notices, signatures, hashes, and
  supported host/target facts belong to each. State which data is immutable release content and
  which data is a user project or cache.
- Next: write the release manifest schema and a packaging inventory from the existing `bin/runtime`,
  `bin/std`, reference, templates, and example inputs. Decide whether the distribution includes all
  published examples or a documented complete subset; no included example may refer to a checkout
  file or network asset absent from its payload.
- Complete when: a versioned release specification names both contracts, every command and guide
  uses the terms above, and an automated inventory proves that each promised payload file is present
  with a compatible compiler build number.
- Related: compiler.distribution.002, compiler.distribution.005, compiler.distribution.010,
  platform.portability.080.

### compiler.distribution.002 — A single-file delivery cannot materialize its compatible resources

- Evidence: `CompilerInstance` collects `runtime` from the compiler resource root unconditionally,
  while the standard-library resolver requires a `std` directory beside the compiler or a separately
  configured `SWAG_PATH`. The present resource-root lookup intentionally serves a checkout or a
  complete `bin/` installation, not a lone executable.
- Intent: embed a compressed, signed manifest and the complete single-file payload in `swc.exe`.
  Before a command needs a resource, verify the archive and materialize it under a release-hash
  activation cache. Use an explicit, documented home override for hermetic environments; do not
  reuse another release's cache and do not silently adopt a foreign `SWAG_PATH` as the payload for
  a single-file delivery.
- Constraints:
  - Extraction is lazy where that improves startup, atomic, lock-safe across concurrent `swc`
    processes, and recoverable after interruption.
  - Every archive path is validated before writing; no entry may escape its activation root.
  - A corrupt, incomplete, or stale cache is discarded only within its own versioned root and is
    rebuilt from the verified executable payload.
  - The compiler, runtime, standard-library source, generated APIs, documentation, and examples
    used together always originate from one manifest and compiler identity.
  - An installed complete `bin/` continues to run in place without an activation cache and keeps
    taking its colocated `runtime/` and `std/` as one unit.
- Complete when: on a clean offline Windows profile, a lone release `swc.exe` can run `swc help`,
  `swc new script hello`, and `swc hello.swgs`; the same release works after moving the executable,
  after a killed first activation, and with two simultaneous first invocations. A complete `bin/`
  installation passes the same workflows without extraction or `SWAG_PATH`.
- Related: compiler.distribution.001, compiler.distribution.003, compiler.distribution.010.

### compiler.distribution.003 — An unsupported host can fail before it can explain itself

- Evidence: the current compiler and generated programs require Windows x86-64-v3, including AVX2.
  A processor that cannot execute the compiler's earliest instructions cannot reach `swc help` or a
  diagnostic that explains this prerequisite.
- Intent: make the release entry point validate Windows version, architecture, and CPU baseline
  before entering code that assumes the baseline. It must name the observed host fact, the required
  fact, the supported release/target boundary, and the compatible action. The path must be available
  equally to a lone executable and a complete `bin/` installation.
- Next: decide whether `swc.exe` is a baseline-compatible bootstrap hosting an optimized compiler
  payload, or whether the release policy supplies another equally single-file preflight mechanism.
  Do not promise an error path that the host cannot execute.
- Complete when: supported hosts retain the existing fast path, and every unsupported supported-OS
  host receives one deterministic, non-crashing, non-networked prerequisite report before runtime,
  allocator, or compiler initialization.
- Related: compiler.distribution.001, platform.portability.001.

### compiler.distribution.004 — Readiness is discovered only during a failed workflow

- Evidence: `--show-config` can show resolved paths and reports missing MSVC or Windows SDK library
  directories for native artifacts, but it is attached to a compilation command. A new programmer
  must first understand inputs and backend selection to learn whether the machine can link a native
  executable.
- Intent: add a read-only `swc doctor` that reports a versioned capability matrix: executable and
  payload integrity, activation-cache status, host OS/architecture/CPU, writable project and cache
  roots, JIT-script readiness, native-build readiness, MSVC import libraries, Windows SDK UM/UCRT
  libraries, debugger support, and optional shell registration. It must distinguish a missing
  prerequisite from a damaged payload and state exactly which workflows remain available.
- Next: define text and JSON schemas for `doctor`, then have one shared discovery implementation
  feed it, `--show-config`, and native-link diagnostics. Include canonical prerequisite URLs or
  commands only where they are versioned and safe to display; `doctor` itself never downloads,
  installs, elevates, or edits user settings.
- Complete when: on a clean host without native libraries, `doctor` says that scripts are ready or
  what blocks them, says native artifacts are unavailable and why, and gives one actionable next
  step. On a ready host, it identifies every selected library root. Tests cover absent, partial,
  conflicting, inaccessible, and non-ASCII path cases.
- Related: compiler.distribution.002, compiler.distribution.008, platform.portability.080.

## First program, local learning, and examples

### compiler.distribution.005 — The first command does not close the first-program loop

- Evidence: `swc help` already shows `new script`, `new module`, and their follow-up commands, but
  its links lead to a website and GitHub's moving `master` branch. A user holding only the executable
  has no local route from a command, an error, or a generated starter to version-matched explanation.
- Intent: make the default help a short, executable first-use route and add discoverable commands
  for learning, project creation, checking, running, formatting, testing, and inspecting what a
  command would do. Keep the existing workspace model; this is not a request for a package manifest
  or registry.
- Required behaviour:
  - `swc` and `swc help <command>` give a short human-oriented route, examples, defaults, side
    effects, destructive behavior, and a local documentation topic for every command.
  - `swc new` offers named embedded starter templates for a script, workspace executable, tests,
    command-line arguments, files, errors, and a minimal GUI where its prerequisites are met.
  - Creation never overwrites a file or module. Its result prints the exact next command, source
    locations, expected output, and the local topic to continue with.
  - A non-writing planning mode describes selected inputs, imports, generated files, native tools,
    code that would execute, and the output directory before the action runs.
- Complete when: an offline newcomer can complete a script and workspace tutorial from `swc` alone,
  deliberately inspect a build before it runs, and recover from an intentional syntax and missing-
  toolchain error without a browser or repository.
- Related: compiler.distribution.004, compiler.distribution.006, compiler.distribution.007,
  compiler.command.doc.001.

### compiler.distribution.006 — Documentation is not available as version-matched local data

- Evidence: the language reference and standard-library documentation are maintained in the
  repository and the website is generated from them, but the command help points at remote pages.
  The `doc` pipeline has no serializable documentation model yet (compiler.command.doc.003), so an
  agent or offline command cannot ask a stable local semantic question without scraping HTML.
- Intent: publish the release's documentation as local, immutable, version-tagged data, with both
  concise terminal rendering and structured retrieval. It includes the language tour, command-line
  reference, runtime and standard-module APIs, ownership/lifetime rules, platform limits, and the
  source-backed examples needed by first use. A release may also offer browser-opening HTML, but no
  task may require a browser or Internet connection.
- Next: make compiler.command.doc.003's documentation serialization the source of a release index;
  define `swc docs show <topic>`, `swc docs search <terms>`, and API/module lookup around that
  index. Every returned item carries a release version, stable identifier, local source/topic
  reference, signatures, imports, platform requirements, and a minimal compilable example where
  one exists.
- Complete when: the compiler can answer an offline query for a language feature, a standard symbol,
  an import, a lifetime contract, and a command option from data built by the same release. A query
  cannot accidentally combine documentation, runtime, or standard-library data from different
  compiler builds.
- Related: compiler.command.doc.001, compiler.command.doc.002, compiler.command.doc.003,
  compiler.distribution.005, compiler.distribution.008.

### compiler.distribution.007 — Examples are repository files, not a runnable catalogue

- Evidence: useful scripts, module demonstrations, applications, and tested reference pages exist
  below `bin/examples` and `bin/reference`, but their discovery depends on the repository tree and
  GitHub. Names alone do not tell a beginner whether an example writes files, opens a window,
  requires assets, imports native libraries, or is the right minimum for one concept.
- Intent: turn release examples into a local catalogue with `list`, `show`, `copy`, `run`, and
  `test` operations. Each example names its learning goal, difficulty, required modules and host
  capabilities, source/assets, expected output, runtime bound, and exact verification command.
- Constraints:
  - The release embeds every asset an advertised example requires; an example never reaches back
    into a checkout, a temporary developer path, or the network.
  - `copy` creates a user-owned project and refuses collisions; `show` is read-only; `run` makes
    its execution and output location explicit.
  - The catalogue begins with small composable examples before games and applications. Every
    advertised example is built or tested by release validation with the compiler and payload that
    ship together.
- Complete when: a user can find, inspect, copy, run, and test one example for scripts, workspaces,
  imports, tests, errors, compile-time execution, core collections, and GUI without cloning the
  repository. The catalogue gives a useful prerequisite report rather than attempting an impossible
  native or GUI example.
- Related: compiler.distribution.005, compiler.distribution.006, compiler.command.doc.001.

## Agent-grade command contract

### compiler.distribution.008 — The command line has no authoritative machine interface

- Evidence: current help and diagnostics are high-quality terminal text, with options for one-line
  diagnostics and suppressed colors, but no stable structured schema for commands, options, docs,
  examples, capability checks, progress, or source diagnostics. An AI must scrape prose, infer
  option arity and side effects, and can easily use documentation from a different compiler build.
- Intent: make `swc` self-describing to both people and programs. Text remains the concise human
  interface; a versioned JSON/JSONL interface is the authoritative machine contract and is generated
  from the same command, diagnostic, documentation, example, and capability definitions.
- Required structured surfaces:
  - `help`: command hierarchy, aliases, positional grammar, option value types, defaults, choices,
    repeatability, applicability, incompatibilities, deprecations, examples, and side effects.
  - `doctor`, documentation/API lookup, example catalogue, project inspection, and dry-run plans.
  - Compilation and test diagnostics: stable id, severity, message, primary and related spans,
    notes, actionable help, phase, affected artifact, and normalized paths.
  - Command lifecycle: schema version, compiler/language/build/payload versions, requested and
    resolved configuration, ordered stage events, summary, and documented exit category.
- Constraints: machine mode has no ANSI sequences, animation, localized alignment padding, or
  human log interleaved with data. Define stdout/stderr ownership and one record framing; never
  require a consumer to parse a sentence. Preserve existing exit-code meanings and version any
  extension explicitly.
- Complete when: a small independent client can discover a command, create a project, run a safe
  plan, interpret an intentional compiler error, locate the matching local reference entry, and
  distinguish a source error from an unavailable host capability without hard-coded Swag knowledge.
- Related: compiler.command.doc.003, compiler.distribution.004, compiler.distribution.006,
  compiler.distribution.009, compiler.core.008, compiler.core.009.

### compiler.distribution.009 — An autonomous caller cannot tell what a command may execute or change

- Evidence: compiling Swag can execute `#run` and JIT code; `run`, `test`, format, clean, tool
  setup, and example commands have different filesystem, process, and machine-configuration effects.
  An AI that treats every compiler command as a harmless query can execute untrusted project code
  or alter data before it has established scope.
- Intent: give all callers an explicit effect model. Read-only discovery and parsing have a defined
  no-execution contract; planning reports what would execute or change; mutation and launch commands
  name their targets before acting. Existing safe defaults such as `new` refusing collisions become
  part of the public contract.
- Next: inventory each command's reads, writes, process launches, compile-time execution, native
  linking, cache use, and shell/registry changes. Define safe inspection modes and the boundary at
  which semantic analysis necessarily requires user code. Connect the report to compiler.distribution.008
  rather than maintaining a second, prose-only safety table.
- Complete when: an autonomous caller can enumerate a command's effects without executing user
  code, choose a documented non-executing inspection path, and receive a precise report before a
  command writes outside the project or activation-cache roots, launches an artifact, contacts a
  network endpoint, or edits user shell configuration.
- Related: compiler.distribution.005, compiler.distribution.008, platform.portability.009,
  platform.portability.080.

### compiler.distribution.010 — The distributed compiler does not expose a ready editor/agent endpoint

- Evidence: the compiler-core backlog already owns the persistent LSP process and semantic editor
  services, but a programmer who receives only a release has no documented, discoverable way to
  launch that endpoint, identify its version, or ensure that its hover documentation and imported
  standard APIs match the shipped payload.
- Intent: once compiler.core.008 through compiler.core.014 exist, package them as a documented
  `swc lsp` release command. Its initialization response and diagnostics identify the compiler and
  payload versions; its document links resolve to the same local documentation index used by CLI
  and agent queries. An editor remains optional: a text editor and the normal CLI always suffice.
- Complete when: an LSP client can start from a lone executable or complete `bin/` installation,
  discover the exact endpoint/version without repository files, open an unsaved workspace document,
  receive diagnostics/completion/hover with local documentation, and shut down without leaving
  release or cache state ambiguous.
- Related: compiler.core.008, compiler.core.009, compiler.core.010, compiler.core.011,
  compiler.core.013, compiler.core.014, compiler.distribution.006, compiler.distribution.008.

## Release confidence and lifecycle

### compiler.distribution.011 — No release gate proves the first-use contract

- Evidence: repository validation can build compiler, runtime, standard modules, examples, and the
  reference, but no release artifact is exercised from a clean machine as a lone executable and as
  a complete `bin/` installation. A release can therefore contain individually valid files that
  cannot start together, or documentation and examples that describe another build.
- Intent: add a release-only acceptance matrix that stages the final artifact exactly as users
  receive it and verifies both delivery contracts without relying on the source checkout. The test
  is responsible for its clean sandbox, never user-wide configuration.
- Required cases:
  - Offline first run, restart, move, concurrent activation, cache interruption/corruption, and
    non-ASCII/spaced paths for a lone executable.
  - In-place operation of a complete `bin/` installation without activation or `SWAG_PATH`.
  - JIT script creation/run without native prerequisites; clear `doctor` and build failure when
    MSVC/SDK libraries are absent; native workspace build/run when they are present.
  - Local docs/API/example discovery, example copy/run/test, text help, JSON schemas, diagnostic
    spans, exit categories, no unintended network access, and no global shell mutation.
  - Manifest signatures, hashes, licences, release version coherence, and recovery from an altered
    payload or cache.
- Complete when: every published release is blocked on this matrix in clean disposable Windows
  environments, and its report identifies the artifact manifest and every externally supplied
  prerequisite. A passing repository campaign alone is no longer accepted as release evidence.
- Related: compiler.distribution.001, compiler.distribution.002, compiler.distribution.004,
  compiler.distribution.005, compiler.distribution.006, compiler.distribution.007,
  compiler.distribution.008, compiler.distribution.009, compiler.distribution.010.

