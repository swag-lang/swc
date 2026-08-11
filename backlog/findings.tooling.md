# Findings — Tooling

The build, the sandbox, and the test harness — everything that surrounds the compiler rather than
being compiled by it.

Conventions, the identifier counter, and the rest of the backlog are in [README.md](README.md).
Entries are sorted by identifier, ascending; position carries no priority.

## Tool execution boundaries

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
- Still live 2026-08-11, and it is not only a reporting problem: an agent working in a worktree
  cannot format at all, so the only way to check a change against the canonical style is to copy
  the files to a path with no dot segment, copy `bin/.swc-format` beside them, format there, and
  copy the result back.

### F-118 — A test executable that outlives its run changes the next run's result

- Area: tooling
- Found while: A/B measuring the sCapture suite, where `scapture.surface` failed on one run and
  passed on the next with no source change in between
- Observation: `sCapture.test.exe` from an earlier run was still alive, and it still held the
  global `PrintScreen` hotkey. The next run's application therefore failed to register it, put an
  error bar across the top of its window — "Cannot register global shortcut 'PrintScreen'" — and
  the golden comparison saw 27 560 pixels outside tolerance. Nothing in the failure names the
  cause: it reads as a rendering regression in whatever change is being tested.
- Evidence: `Get-Process sCapture.test` showed pid 9604 from the previous run; killing it and
  re-running turned the same working tree from `1 did not pass` to `149 tests` green. The two
  golden images differ by the error bar alone.
- Why it matters: this is a false failure that points at the change under test, and it is
  self-perpetuating — the run that leaks the process is usually the run that was interrupted, so
  the next one fails for a reason that no longer exists in the sources.
- Next step: two halves. The runner should not leave a bounded run behind: `runGeneratedArtifact`
  already kills on `--run-timeout`, but a run stopped by a failing test, or by the tool being
  interrupted, can leave the child alive — it should be killed on every exit path. And a headless
  test that needs an exclusive machine-wide resource should either not take it or not fail the
  picture when it cannot; the sandbox already isolates the filesystem, and a global hotkey is
  exactly the kind of thing it does not cover.

### F-119 — Nothing records where a campaign's time goes

- Area: tooling
- Found while: asking why `tests.swgs dm --all-cfg` takes about fifty minutes
- Observation: `swc` already times every stage and prints one line per module
  (`ScopedTimedLog`), but `tests.swgs` launches a hundred of those processes per configuration and
  keeps none of the numbers. There is no per-step total, no ranking, and no record at the end of a
  run, so the only way to learn which rung costs what is to reconstruct it from the modification
  times of the artifacts in `.output` while a campaign is running.
- Evidence: one measured run, 2026-08-11, `dm --all-cfg`, 48 min 57 s wall — rungs 1+2 3 min 25,
  rung 3 (std) 6 min 46, rung 4 (apps + reference) 18 min 33, rung 5 (smoke) 20 min 13. Reaching
  those four numbers took an hour of observation that a five-line summary would have printed for
  free.
- Also: wall time on a developer machine is not a usable A/B signal at this granularity. The same
  sCapture suite, same binary, measured 2 min 00, 2 min 43, 3 min 11 and 3 min 34 across four
  consecutive runs with an IDE open. Anything measuring a campaign change needs either a
  deterministic counter or many alternated rounds.
- Next step: have `Context.runCompiler` time each invocation and accumulate `(label, seconds)`,
  then print a table ordered by cost at the end of `runTests`. The labels already exist — the rung,
  the configuration, and the workspace or suite name are all known at the call site.
