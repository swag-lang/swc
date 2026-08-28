---
name: modify-swag-codebase
description: Modify, refactor, fix, test, and validate the Swag compiler repository. Use whenever changing C++ compiler sources, Swag language features, unit tests, examples, build scripts, or other code in this repository; it enforces root-cause fixes, project C++ rules, test placement, and load-aware build and test admission.
---

# Modify The Swag Codebase

Fix the root cause of every problem. Do not introduce hacks or workarounds.

The repository is written in English. Every comment, identifier, message, and
documentation line — in the compiler sources, in `bin/`, and in every other file —
is English; never leave French (or any other language) in the tree, whatever the
language of the conversation.

## Admit Agent Builds And Tests By Machine Load

All AI agents and worktrees share one machine. Compiler builds and project tests launched by AI
agents, including Codex and Claude, may overlap in any combination: build with build, test with
test, or build with test. Admit each new command from the machine's current CPU and memory
headroom, not from a global build or test slot. A different worktree does not provide different
resources.

Before invoking MSBuild or another command that rebuilds `swc` or `swc_devmode`, and before every
project test command, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .agents/skills/modify-swag-codebase/scripts/check-machine-load.ps1
```

The check samples CPU instead of trusting an instantaneous reading. It reports `ready` only when
average CPU use is at most 65%, available physical memory is at least both 8 GiB and 25% of
installed memory, and commit headroom is at least both 8 GiB and 20% of the commit limit. These are
admission thresholds, not targets for a running machine.

- A `ready` result admits one command. Start it promptly; if the start is delayed materially,
  check again.
- Check every additional command independently. After starting work, allow at least one complete
  sampling window for its load to become visible before using a new check to admit more work. Do
  not launch a batch of parallel commands from one result.
- A `wait` result means do not start more build or test work. Wait in short intervals, keep the
  user informed during a long wait, and rerun the check until it reports `ready`.
- Existing agent, IDE, user-shell, and system processes all count toward measured pressure. Process
  ownership matters only for control: never terminate, suspend, reprioritize, or otherwise
  interfere with another agent's, an IDE's, or the user's processes to create headroom.
- When a command is known to need unusually high memory, raise the check's memory thresholds for
  that command. Never lower the defaults or evade a `wait` result by changing configuration,
  executable, shell, output directory, or worktree.
- When parallel validation exposes a problem, stop only commands launched by the current agent
  whose remaining results would be invalid or misleading, then investigate or report the first
  problem before starting more validation.

## Bound Agent Compiler CPU Usage

Every compiler invocation launched by an AI agent for compilation or testing must cap Swag's own
worker pool at six with `--num-cores 6`. This is separate from `/MP6`, which limits the C++
compiler only while building `swc` itself.

- Apply the cap to both checkout-local executables: `bin\swc.exe` and
  `bin\swc_devmode.exe`.
- For a direct compiler command, pass one cap, for example
  `bin\swc_devmode.exe sema ... --num-cores 6`.
- A repository tool script starts by being compiled by `swc`, then commonly launches another
  compiler. Bound both levels: put one option before the script path and forward another through
  the tool, for example
  `bin\swc_devmode.exe --num-cores 6 tools\unittests.swgs dm cpp --num-cores 6`.
- Preserve an explicit lower limit. `--randomize` and `--seed` already force one compiler worker.
  Exceed six only when the user explicitly requests it or a concurrency reproducer genuinely
  requires it, and state that exception before launching the command.

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
- Record the issue in the matching `backlog/<area>.md` when it is uncertain, requires broader
  design work, or should be handled separately. Include evidence and a concrete next action; do not
  record vague wishes.
- Search the whole backlog before adding an entry. Enrich an existing item instead of creating a
  duplicate.
- Give the new entry the identifier the `Next identifier` line in
  [backlog/README.md](../../../backlog/README.md) names, then advance that line. See the rule below.

The backlog is not a promise that every observed lead will be implemented, and not a substitute for
fixing a root cause that is already safe and in scope.

## Number Every Entry

Every backlog entry carries a permanent identifier in its heading:

```
### B-023 — A menu bar does not follow a live language switch
```

The identifier is how an entry is named everywhere else — in conversation, in a commit message, in
another backlog entry, in a code comment. A title, position, or next action can change; the
identifier does not.

- Take the `B` identifier from the `Next identifier` line in
  [backlog/README.md](../../../backlog/README.md), then advance that line. It is a counter, not an
  entry count: it keeps rising as entries are deleted.
- Never renumber and never reuse. A deleted entry takes its identifier with it, so `F-012` in an
  old commit message still means what it meant.
- Existing identifiers below `F-203` and `T-572` are permanent legacy identifiers. Their prefixes
  no longer determine file, shape, ordering, or maturity; those families are closed and every new
  entry uses `B-*`.
- Position expresses expected value where entries are comparable. Put an untriaged lead at the end
  of the closest relevant section until its priority is understood, then move it without changing
  its identifier.
- When investigation becomes implementation, update `Next` and `Complete when` in place. Never
  mint a second entry merely to represent the same work at a later maturity.

## Keep One Backlog Per Domain

The whole backlog lives in [backlog/](../../../backlog/) — nowhere else. Each domain has one file
that keeps evidence, open decisions, and committed outcomes together. Read
[backlog/README.md](../../../backlog/README.md) for the inventory and entry format.

- `backlog/compiler.md`, `optimization.md`, `safety.md`, `gui.md`, and their peers are split by the
  domain where the issue will be investigated or fixed, not by the task that noticed it.
- Evidence and intent are properties of an entry, not different storage classes. Use `Next:` to
  state the smallest useful investigation or implementation step and `Complete when:` to state
  when the entry can be deleted or its next action rewritten.

Create a new file only when a real cluster forms; a category holding one entry costs more to
navigate than it saves.

The backlog holds only what is *not done*. When a task resolves, invalidates, or completes an
entry, delete it — or cut it down to the part that genuinely remains. Never keep completed work as
a record: history lives in Git. When evidence changes the next action, rewrite the same entry in
place and keep its identifier.

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
- Record a `B-0xx` in [backlog/compiler.md](../../../backlog/compiler.md) when
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
