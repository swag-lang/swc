---
name: modify-swag-codebase
description: Modify, refactor, fix, test, and validate the Swag compiler repository. Use whenever changing C++ compiler sources, Swag language features, unit tests, examples, build scripts, or other code in this repository; it enforces root-cause fixes, project C++ rules, test placement, and agent-to-agent build and test serialization.
---

# Modify The Swag Codebase

Fix the root cause of every problem. Do not introduce hacks or workarounds.

The repository is written in English. Every comment, identifier, message, and
documentation line — in the compiler sources, in `bin/`, and in every other file —
is English; never leave French (or any other language) in the tree, whatever the
language of the conversation.

## Serialize Agent Builds And Tests Across Worktrees

All AI agents and worktrees share one machine. Compiler builds and test runs launched by AI agents,
including Codex and Claude, are exclusive with one another, not per-worktree resources. Coordinate
with the other agents and inspect agent-owned running processes before taking either slot; a
different worktree does not make parallel agent work safe.

An IDE build or test, or a command launched manually by the user, does not occupy the agent slot.
Rider, Visual Studio, and user-owned shell processes may overlap an agent command. Classify a
process by its parent/session or by known agent activity instead of treating every `cl`, `MSBuild`,
`swc`, or test process on the machine as agent-owned. Never terminate or interfere with an IDE or
user process.

- Only one AI agent may compile a new `swc` or `swc_devmode` at a time. Before invoking MSBuild or
  any other command that rebuilds either compiler, wait for any compiler build launched by another
  agent to finish. Never overlap DevMode and Release builds owned by different agents.
- Only one AI agent may run project tests at a time, whether the tests use `swc.exe` or
  `swc_devmode.exe`. Before starting a test command, wait for the test run of another agent to
  finish. This includes focused tests as well as heavy aggregate campaigns, so a small agent run
  never piles onto another agent's expensive one.
- When a test run exposes a problem, stop the remaining tests and release the test slot immediately;
  investigate or report the first problem before starting more validation. Stop only the processes
  started by the current agent—never terminate another agent's, IDE's, or user's build or tests to
  take the slot.
- Waiting for an occupied slot is the required behavior. Do not bypass it by changing configuration,
  executable, shell, output directory, or worktree.

## Bump The Compiler Version With Every Change

[src/Main/Version.h](../../../src/Main/Version.h) carries the compiler's identity, and that
identity is part of the key of every cache the compiler fills — the script dependency cache keys
its directory on it. Increment `SWC_BUILD_NUM` (`0.0.1` → `0.0.2` → `0.0.3`) in the same change
that touches any compiler source under `src/`.

The point is not release numbering; it is that a build produced by one compiler is never read back
by another. A version that does not move lets a cache filled by the previous binary look valid to
the next one, and the failure surfaces far from its cause — as a syntax error inside a dependency,
or as a link against an artifact nothing can explain.

- Bump it for any change under `src/`, however small; a change that cannot alter output is not
  worth the exception.
- Do not bump it for a change that only touches `bin/`, `backlog/`, or documentation.
- One bump per change, not one per file.

## Improve The Platform Along The Way

Treat every repository task, especially every Swag programming task, as an opportunity to
improve, debug, or optimize `bin/std`, the compiler, and the language itself. Do not normalize an
awkward library API, a compiler defect, a missed optimization, or a suspicious language rule as a
local workaround merely because the original request exposed it indirectly.

- Investigate the underlying platform when Swag code is unexpectedly awkward, fragile, slow, or
  impossible to express cleanly.
- Fix a discovered issue in the current change when it is sufficiently understood, relevant to
  the task, and can be validated without making the change unsafe or incoherent.
- Record the issue in the matching `backlog/findings.<area>.md` when it is uncertain, requires
  broader design work, or should be handled separately. Include evidence and a concrete next
  investigation step; do not record vague wishes.
- Search every `backlog/findings.*` file before adding an entry. Enrich an existing item instead of
  creating a duplicate.
- Give the new entry the identifier the `Next identifier` line in
  [backlog/README.md](../../../backlog/README.md) names, then advance that line. See the rule below.

The discovery backlog is not a promise that every item will be implemented, and not a substitute
for fixing a root cause that is already safe and in scope.

## Number Every Entry

Every backlog entry — finding or todo — carries a permanent identifier in its heading:

```
### F-023 — A menu bar does not follow a live language switch
### T-054 — No vector output
```

The identifier is how an entry is named everywhere else — in conversation, in a commit message, in
another backlog entry, in a code comment. A title gets rewritten, a position moves, and an entry
changes file; the identifier does not.

- Take the next identifier of the matching kind from the `Next identifier` lines in
  [backlog/README.md](../../../backlog/README.md), then advance that line. Each is a counter, not
  an entry count: it keeps rising as entries are deleted. The `F` counter is shared by every
  `findings.*` file, the `T` counter by every `todo.*` file.
- Never renumber and never reuse. A deleted entry takes its identifier with it, so `F-012` in an
  old commit message still means what it meant.
- Keep each `findings.*` file sorted by identifier, ascending. A new entry always carries the
  highest identifier of its file, so it goes at the end; a deleted one leaves a gap, and the gap
  stays. Position is mechanical and carries no priority — it only makes an entry findable by its
  number. In a `todo.*` file, position IS priority: entries stay ordered by decreasing value, and
  identifiers appear out of order.
- A finding that graduates into a plan becomes a todo entry and takes a fresh `T` identifier; its
  `F` identifier retires with it. Name the finding it came from in the new entry.

## Keep Findings And Roadmaps Apart

The whole backlog lives in [backlog/](../../../backlog/) — nowhere else. Two kinds of file, two
different jobs. Write to the right one, and read
[backlog/README.md](../../../backlog/README.md) for the full layout and the entry format.

- `backlog/findings.<area>.md` holds **evidence**: something observed, with a reproduction and a
  next investigation step. Split by the area the issue will be *fixed* in — `compiler`,
  `optimization`, `safety`, `gui`, `tooling` — not by the task that noticed it.
- `backlog/todo.<unit>.md` holds **intent**: what a unit should become, and in which order.
  One file per unit: `compiler`, `language`, `doc`, `format`, `runtime`, each `bin/std` module,
  each application. Entries are ordered by decreasing value and measured against the competition.

Create a new file only when a real cluster forms; a category holding one entry costs more to
navigate than it saves.

Both hold only what is *not done*. When a task resolves, invalidates, or completes the
investigation of an entry, delete that entry — or cut it down to the part that genuinely remains.
Never keep done or investigated material as a record: history lives in git. A finding that
graduates into a plan moves to the matching `backlog/todo.*` file and disappears from the
`findings.*` one.

## Establish The Applicable Rules

1. Read [references/cpp-coding-rules.md](references/cpp-coding-rules.md) before designing or editing C++.
2. Read [../write-swag-compiler-messages/SKILL.md](../write-swag-compiler-messages/SKILL.md) before changing any English text emitted to users.
3. Inspect nearby code and tests before deciding where the change belongs.
4. Preserve unrelated working-tree changes.

## Add Tests At The Correct Boundary

Three test surfaces exist, and they are not interchangeable:

| Surface | Location | What belongs there |
| --- | --- | --- |
| Language suites | `bin/unittests/<suite>/` | The language and the compiler, reduced to a standalone source |
| C++ unit tests | `src/Unittest/` | Compiler internals reachable from C++ alone |
| Module tests | `<module>/src/tests/` | The behavior a `bin/` module or application publishes |

`unittests` names the language suites and nothing else. A module never has one: its tests live in
`src/tests`, whether the module sits under `bin/std/modules` or under `bin/apps`.

- Add relevant tests for every new Swag language feature under the appropriate `bin/unittests` folder.
- Put C++ unit tests in `src/Unittest`.
- Keep each individual test below 40 seconds of runtime, excluding compilation time.
- Exercise behavior at its real boundary instead of manufacturing a source test for a command-line, linker, backend, runtime, or internal-only path.

### Lay Out A Module's Tests The Same Way Every Time

Every module under `bin/` — standard library and application alike — uses one
layout. A new module copies it without deciding anything:

```
<module>/
    module.swg
    datas/                     Resources the built program loads at run time (icons, lang, ...)
    src/                       The implementation
        <area>/...
        testing/               PUBLIC test-support API, shipped and documented like the rest
        tests/                 Test-only sources; never shipped
            <name>.test.swg    The '#test' bodies
            helpers.swg        Helpers shared by this suite
            datas/             Immutable input fixtures
            goldens/           Recorded expectations, '.txt' and '.png'
```

- **`src/tests/` is the only test root.** Do not nest a `unittests/` folder inside it, and do not
  put tests directly under `src/`. A module with many test areas may mirror `src/` one level deep
  (`src/tests/collections/array.test.swg`); anything flatter than that stays flat.
- **`*.test.swg` is the only name for a file holding `#test` bodies**, and each opens with
  `#global if #command == Swag.CompilerCommand.Test`. Every source below `src/` is compiled, so a
  test file without that guard is built into the shipped module.
- **`helpers.swg` is the only name for test-only shared code**, under the same guard. One per test
  folder is enough; do not invent `*.testutils.swg` or a parallel `fixtures/` tree.
- **`src/testing/` holds test support that is part of the module's public API** — the `Testing`
  namespace consumers import, such as `Gui.Testing` and `Pixel.Testing`. It carries no `#command`
  guard, ships in every configuration, and is documented like any other family. Keeping it out of
  `src/tests/` is what makes `src/tests/` mean exactly "not shipped".
- **`datas/` beside a module's `module.swg` is the program's own resources, never test data.**
  Test data is `src/tests/datas/`. The two never merge.

### Keep Module Test Data Flat And Self-Contained

- Put immutable fixture files used by a module's tests in that suite's `datas/` directory. `datas/`
  is the canonical fixture location; do not create a competing `files/` or `fixtures/` directory.
- Keep fixture files directly in `datas/`. Do not add format or provenance subdirectories such as
  `datas/html/` or `datas/svg-wpt/`; use descriptive file-name prefixes when grouping helps.
- Keep generated expectations in `goldens/`. A source document, image, font, archive, or other
  input remains test data even when a golden image is produced from it.
- Resolve fixture paths from `#curlocation.fileName` so focused module tests work from every
  worktree and current directory.
- **A test reads fixtures only from its own module's `datas/`.** Reaching across modules or
  workspaces with `../..` couples two suites' file layouts and makes a rename in one break the
  other; copy the fixture instead, and let the copy be a fixture rather than a shared asset.
- **A fixture is never present-or-absent.** A test that returns early when its fixture is missing
  reports success while proving nothing; a missing fixture must fail the test.
- **`datas/` holds no `.swg` or `.swgs` file.** The compiler collects every Swag source below `src/`
  recursively, with no exception for a test folder, so such a fixture is compiled into the module
  and its public declarations join the module's API. When a test needs a Swag source as *input*,
  write it to a temporary file at run time.

## Close Every Downstream Regression With A Suite Test

`bin/unittests` is the net. A compiler defect that a script, an example, an application or a
`bin/std` module exposed is a defect the suites should have caught first, and the fix is not
finished until they would.

- Add the test to the suite that could have seen it: `lexer`, `parser` and `sema` for a
  diagnostic, `jit` for compile-time execution, `safety` and `sanity` for a guard, `native` for
  emitted code, `workspace` for anything crossing a module boundary.
- Watch it fail without the fix before keeping it. A test that passes either way records nothing.
- Reduce it to the language construct. A suite source is standalone: a case that still needs
  `gui` to reproduce is a `bin/std` test, not a suite test.
- Record an `F-0xx` in [backlog/findings.compiler.md](../../../backlog/findings.compiler.md) when
  the case genuinely does not reduce, saying why. That is the only accepted outcome other than a
  new test.

This is also what makes validation cheaper over time. As long as a class of regression can only be
caught by running thirty-one examples for seven minutes, that is what every campaign has to keep
doing; once the suites hold it, twenty seconds answer the same question.

## Select Validation From Behavior

Before choosing or running any build, test, program configuration, consumer, smoke, or golden
check, read and follow
[validate-swag-changes](../validate-swag-changes/SKILL.md). It owns the validation matrix and the
stopping rule.

`tools/tests.swgs` is a deliberate full campaign. It does not inspect the working tree. Use the
focused repository tools and their `--file-filter` or `--test-file` controls for change validation,
and reserve the full campaign for a genuinely cross-cutting change or an explicitly requested
periodic pass.

## Launch Every Executable Through Its Tool

Never start a built binary by its path. `bin/std` compiles to shared libraries — `core.dll`,
`pixel.dll`, `gui.dll` and the rest — and the compiler leaves the executable in its output
directory *without* them. Run it from there and it dies before `main`, with no window and no
diagnostic, which reads exactly like the bug you were about to investigate.

The tools place the runtime files first, then launch:

```
swc tools/examples.swgs [dm] run -m <example>
swc tools/apps.swgs [dm] run <module>
swc tools/scripts.swgs [dm] run <script>
```

The same rule holds when driving a program from a helper script, a debugger, or a screenshot
harness: point it at the tool, not at the `.exe`. An application under `bin/apps` is the one
exception: its module file sets `publishDependencies`, so every link places the shared libraries it
needs beside it and the executable runs on its own. That state no longer depends on which command
ran last.

## Measure Windows From A DPI-Aware Probe

Swag surfaces are per-monitor DPI aware, so their rectangles are physical pixels. A probe that
is not aware reads them back divided by the display scale, because Windows virtualizes window
coordinates for unaware callers. On a 150% display a correct 1650x1185 window then reads as
1100x790 — exactly the logical size the application asked for, which reads like a scaling bug
that is not there.

Call `user32!SetProcessDPIAware()` before the first measurement in any PowerShell, script, or
tool that queries `GetWindowRect`, captures a window, or compares a size against what the code
requested. `GetDpiForWindow` is not a control: it answers the window's own DPI whatever the
caller's awareness, so it reads 144 next to a virtualized rectangle and makes the pair look
consistent.

Match the marshalling too when enumerating windows: `GetClassNameW` through an ANSI-marshalled
buffer returns the first character only, so `Swag.Gui.Surface` arrives as `S`.

## Finish Cleanly

Remove temporary files and folders created during investigation or validation.

At the end of every work session, explicitly inspect test source trees for ignored build
artifacts, because `git status` does not report them. Remove test-created folders that landed
outside the intended output or temporary roots. Both `bin/unittests/.output` and
`bin/unittests/workspace/.output` are canonical output roots owned by the test tooling; keep them.
Only investigate other nested `.output` folders under test fixtures or source directories, and
confirm that each candidate is misplaced generated output rather than an intentional fixture
before deleting it.

```powershell
Get-ChildItem bin/unittests -Directory -Recurse -Force -Filter .output
```

Before returning control, prune noise from the working tree so the modified-file list only
contains real changes:

- Revert any file you touched that ended up with no intended content change.
- Revert any file whose ONLY difference is line endings (a CRLF file that became LF-only).
  Bulk tools run here — `sed -i`, some formatters — silently rewrite CRLF to LF, which shows
  up as a spurious modification.

Detect the line-ending-only cases and restore them. Note the trap: `git diff` NORMALIZES
line endings (this repo checks out CRLF via `.gitattributes eol=crlf`), so a file that is
only CRLF-vs-LF different is INVISIBLE to `git diff` yet still shows in `git status`. Detect
via `git status`, not `git diff`:

```bash
# Modified per `git status` MINUS files with a real content diff == line-ending-only.
# Restore those with checkout (safe: they carry no content change).
git status --porcelain | grep -E '^ ?M ' | sed 's/^...//' | sort > /tmp/_mod
git diff --name-only | sort > /tmp/_real
comm -23 /tmp/_mod /tmp/_real | tr '\n' '\0' | xargs -0 -r git checkout --
```

Do this in one batched `git checkout` (per-file git calls over a large tree time out).

Then report the validations run and any checks that could not be completed.
