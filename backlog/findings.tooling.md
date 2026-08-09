# Findings — Tooling

The build, the sandbox, and the test harness — everything that surrounds the compiler rather than
being compiled by it.

Conventions, the identifier counter, and the rest of the backlog are in [README.md](README.md).
Entries are sorted by identifier, ascending; position carries no priority.

### F-018 — A sandbox root is never removed, and the process id does not make it private

- Area: bin/std
- Found while: validating a runtime allocator rewrite, where `swc tools/scripts.swgs smoke` failed
  intermittently; the fatal half of that failure is fixed, this half is not
- Observation: nothing ever removes a sandbox root, and the root is named after the process id,
  which the operating system reuses. A run whose id matches a dead run's therefore adopts that
  run's leftover files instead of starting on an empty private root — the opposite of what the
  sandbox promises. `createDirectoryTree` accepts an existing directory silently, so nothing
  reports it.
- Evidence: `%TEMP%/swag-sandbox` holds 4125 `run-<pid>` directories, 846 of them non-empty. Id
  reuse is not theoretical at that density: one `swc tools/scripts.swgs dm smoke` pass of 21 scripts
  handed pid 29356 to two different script processes. A stale root can change behavior rather
  than just waste space, which is what
  [F-017](findings.scapture.md#f-017--scapture-keeps-a-dark-editor-matte-after-switching-to-the-light-theme)
  shows for a persisted option.
- Also: this now gates work rather than merely wasting space. The campaign's remaining cost is
  fifty-three programs launched one at a time, each holding roughly one core for one to five
  seconds, and overlapping them is the only lever left on it. Two live runs cannot share an id, so
  concurrency does not raise the collision rate per run; what it removes is the ability to
  attribute the failure when one does collide, since the runs no longer stand in a sequence.
  Fixing this is what makes the campaign safe to parallelize, not merely tidier.
- Next step: make a default root start empty, and keep the two deletion questions apart. Clearing
  a *default* root at arming time is the safe half — no live process can hold that id, the
  launcher did not name the directory, and an explicit root (the golden-recording flow, which
  points the sandbox at the repository) must never be touched. Removing the root at exit is the
  separate half and needs the `#drop` ordering checked first, since another module's drop hook may
  still write inside it. Neither may become an enumerate-and-delete sweep over `swag-sandbox`.
- Related: the fatal half — the hook arming a second time and being rejected with "the sandbox
  root cannot change once armed" — was `defaultSandboxRoot` reading `getSpecialDirectory(.Temp)`,
  which answers *inside* an armed sandbox, so the second pass computed a root nested under the
  first (`<root>/Temp/swag-sandbox/run-<pid>`). It now reads `realSpecialDirectory(.Temp)`, which
  makes a repeated arming the no-op `enterSandbox` documents.

### F-037 — Source duplication is nearly free in the executable, and templating it costs

- Area: build
- Found while: two rounds of factoring roughly 1600 lines of duplicated helpers out of the
  compiler sources
- Observation: the Release link runs `/OPT:ICF` (`EnableCOMDATFolding`) on top of LTCG, so two
  byte-identical function bodies in different translation units cost two source copies but a
  single copy in the image. Deleting them is worth doing for the sources; it is not a lever on the
  binary. The reverse also holds, and is the sharper half: collapsing near-identical functions into
  a template gives every instantiation its own body, and folding only reclaims the instantiations
  that come out identical — which the interesting ones, differing by a constant, never do.
- Evidence: round one removed 1398 net source lines across 85 files (verbatim twins such as
  `builtinTypeRef`, `canReflectTypeRef`, `emitCStringCountReg`, `applyAction`, `collectLoopBody`,
  plus the token classification moved into `Tokens.Def.inc`) and moved `bin/swc.exe` by only
  10 240 bytes, 0.2% — of which 1 536 bytes came not from deleting anything but from putting two
  helpers back inline in their headers after sharing them had cost them their inlining. Round two
  removed a further 210 lines, mostly by templating families of two and three near-identical
  functions, and the executable grew 3 072 bytes. The Release configuration already carries `/O2`,
  `/GL`, `/Gy`, `/OPT:REF`, `/OPT:ICF` and `RuntimeTypeInfo=false`, so the usual size switches are
  all on. Compile time and peak memory were unchanged throughout: identical CPU median over twelve
  order-alternated rounds.
- Next step: measure where the image actually goes before spending more on it. Dump the section
  sizes and the largest COMDATs (`link /dump /headers`, `/dump /disasm`, or a map file with
  `/MAP`), and separate code from the read-only data the diagnostic, token, and instruction tables
  contribute. Only two levers are likely to matter and both must be weighed against the rule that
  the compiler may never get slower: cutting template instantiation in the hot headers, and
  trimming inlining pressure (`/Ob1` on the cold command/report/doc translation units only, never
  on sema, codegen, or the micro passes).

### F-070 — The test command opts out of artifact reuse, so every campaign rebuilds everything

- Area: compiler
- Found while: measuring the repository campaign in order to scope it to what changed
- Observation: `shouldTryReuseWorkspaceArtifacts` returns false for `Test` and `Doc`
  ([CompilerInstance.Module.cpp:1086-1092](../src/Main/CompilerInstance.Module.cpp#L1086-L1092)),
  so a test invocation recompiles its module even when nothing has changed since the last one.
  `build` and `smoke` reuse. The exclusion may now be vestigial: the comment just above it
  ([lines 1070-1071](../src/Main/CompilerInstance.Module.cpp#L1070-L1071)) records that build modes
  no longer share an artifact name, which was the reason a test artifact could not be trusted.
- Evidence: on an unchanged tree, `swc tools/std.swgs build` reports every module `up-to-date` in
  1.4 s, while `swc tools/std.swgs test` over the same sources costs more than two minutes. The
  campaign runs `test` for the source suites, the standard library, the applications and the
  reference, so this is most of its cost, repeated in each of the three configurations.
- Next step: check whether dropping `CommandKind::Test` from that exclusion is now safe, keeping
  two things forced whatever the artifact's freshness — the tests must still *run*, and the
  source-driven `Verify` directives must still be evaluated. Reuse here means skipping the
  compile, never skipping the execution. Measure a second `swc tools/tests.swgs` pass on an untouched
  tree before and after.
- Related: [T-002](todo.compiler.md#t-002--frontend-incrementality-stops-at-the-module), which is the same problem one level
  down — the unit of reuse is the module, so even a reusing command rebuilds all of `core` for a
  one-line edit.

### F-071 — Every #test runs twice, and only an all-or-nothing flag says otherwise

- Area: compiler
- Found while: the same measurement
- Observation: `finishTestCommand` runs the JIT pass and then the native artifact
  ([Command.Test.cpp:624-652](../src/Main/Command/Command.Test.cpp#L624-L652)). Two backends
  executing the same assertions is real coverage, and it is the point. What is missing is any way
  to ask for one of them per *suite* or per *configuration*: `--no-test-jit` is the only lever,
  it covers a whole invocation, and the campaign is inconsistent about it — the applications and
  the workspace suite pass it, the standard library, the source suites and the reference do not.
- Evidence: `core` tested with both passes costs 9.02 s against 5.02 s with `--no-test-jit`, so
  the JIT pass is 44% of that module's test cost. Multiplied by eleven modules and three
  configurations, that is the single largest repeated item in the campaign, and the JIT half of it
  is already covered for the language itself by the `jit` suite — 310 files in 3.2 s.
- Next step: decide what the second execution is for, per corpus rather than globally. The
  language suites need both because the two backends disagreeing *is* the defect they hunt; a
  `bin/std` module may only need both in the configuration where inlining is most aggressive.
  Whatever is decided has to be expressible, which today it is not.

### F-073 — `swc format` silently skips every path under a dot directory

- Area: tooling
- Found while: validating a `bin/std` change made in a git worktree under `.claude/worktrees/`
- Observation: the file discovery behind `swc format` drops any path holding a segment that starts
  with a dot, and it drops it without a word. `swc tools/format.swgs` run from such a checkout reports
  `formatted 0 files` then `clean`, which reads exactly like a conformant tree. Nothing was read.
- Evidence: with the same `bin/.swc-format` and the same badly formatted source in both places:
  - `swc format -d <scratch>/fmt` reports `1 file • 1 rewritten file` and fixes the file.
  - `swc format -d <scratch>/.dotdir` reports `0 files`. Only the directory name differs.
  - From a worktree at `swc/.claude/worktrees/<name>`, `-d bin`, `-d bin/std`,
    `-d bin/std/modules/truetype/src` and `-f <one file>` all report `0 files`, against a source
    deliberately given six-space indentation and padded `=` signs.
- Why it matters beyond worktrees: the skip is silent and it applies to `-f` as well as to `-d`,
  so a file named explicitly is discarded rather than refused. A tool asked to format one file by
  name that answers `clean` without opening it reports the opposite of what happened.
- Next step: separate two rules that are currently one. Traversal should keep skipping dot
  directories, because `.output`, `.tmp`, `.dep` and `.git` are exactly what it must not walk
  into. A path named explicitly through `-f` should never be filtered. And a run that ends with
  zero inputs should say so: `format.swgs` on an empty selection and `format.swgs` on a conformant
  tree print the same thing today, which is what let this go unnoticed.
