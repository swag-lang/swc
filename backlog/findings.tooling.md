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

### F-118 — A test executable can outlive the run that started it

- Area: tooling
- Found while: A/B measuring the sCapture suite, where `scapture.surface` failed on one run and
  passed on the next with no source change in between
- Observation: `sCapture.test.exe` from an earlier run was still alive. `runGeneratedArtifact`
  kills a bounded run on `--run-timeout`, but a run stopped by a failing test, or by the tool being
  interrupted, can leave the child behind.
- Evidence: `Get-Process sCapture.test` showed pid 9604 from a previous run, hours after the
  command that started it had returned.
- Why it matters: the survivor holds its own sandbox directory, keeps consuming CPU, and — because
  Windows locks a running image — makes the next build of the same artifact unable to overwrite its
  own executable. The leak also accumulates: the run that leaks is usually the interrupted one, and
  nothing reports the survivor.
- Note: the *symptom* that originally made this findable is closed. The leftover process held the
  global `PrintScreen` hotkey, the next run's application failed to register it, painted "Cannot
  register global shortcut 'PrintScreen'" across its window, and the golden comparison saw 27 560
  pixels outside tolerance. `registerNativeHotKey` now takes no system hot key under a sandbox, so a
  survivor no longer corrupts a later picture — which makes the leak quieter, not rarer.
- Next step: kill the generated artifact on every exit path of `runGeneratedArtifact`, not only on
  the timeout one, and report a survivor rather than leaving it to be found by hand.

### F-123 — A dependency mirror copy fired for a file that already matched its source

- Area: build
- Found while: `swc test -w bin/apps -m sCrypt --rebuild`, one run out of three, failing with
  "cannot synchronize workspace dependency '…\std\.dep\…\core.dll': access is denied; the file is
  in use by this compiler process"
- Observation: during a nested standard-library build, the `truetype` compile setup tried to
  replace `.dep/…/core.dll` while this process held it — the `ogl` compile before it had loaded
  that very file for JIT execution, and ogl's deferred link was still running in the background.
  The copy should never have been attempted: `shouldCopyWorkspaceDependencyFile` copies only on a
  size or timestamp difference, yet post-mortem the destination matched the source to the exact
  100 ns tick. Either a transient stat failure took the "cannot compare, so copy" path, or the
  compare raced the deferred link finishing `core.dll` and the manifest beside it.
- Evidence: run of 2026-08-12 09:52 — `.dep` core.dll, core.lib, core.pdb and `.swc-artifacts`
  all carried the source's exact ticks after the failure, so the last write of the destination was
  a successful copy of the current source, and the failed rename had nothing left to install. Two
  sibling runs with the same command did not reproduce. The failed replace now self-heals
  (`copyWorkspaceDependencyFile` re-checks the pair when the rename fails and succeeds when the
  destination already matches), so the race no longer aborts a build; the trigger remains
  unexplained.
- Next step: when the rename fails and the re-check says the pair matches, log or capture which
  of the earlier stats made `shouldCopyWorkspaceDependencyFile` answer "copy" — the error codes
  of both stat sequences are the fact the post-mortem cannot recover.
