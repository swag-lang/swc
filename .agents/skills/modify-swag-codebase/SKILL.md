---
name: modify-swag-codebase
description: Modify, refactor, fix, test, and validate the Swag compiler repository. Use whenever changing C++ compiler sources, Swag language features, unit tests, examples, build scripts, or other code in this repository; it enforces root-cause fixes, project C++ rules, test placement, agent-to-agent build and test serialization, and scoped validation workflows.
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

- Add relevant tests for every new Swag language feature under the appropriate `bin/unittests` folder.
- Put C++ unit tests in `src/Unittest`.
- Keep each individual test below 40 seconds of runtime, excluding compilation time.
- Exercise behavior at its real boundary instead of manufacturing a source test for a command-line, linker, backend, runtime, or internal-only path.

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

## Validate What The Change Touches

Ask the tooling which surfaces a change reaches instead of running everything by reflex:

```
swc tools/tests.swgs plan          what the working tree selects, without running it
swc tools/tests.swgs changed       run exactly that
```

The selection maps each changed path to a surface, adds whatever imports a selected `bin/std`
module, and runs the union. Naming a path answers the same question about a file *before* touching
it — `swc tools/tests.swgs plan bin/std/modules/gui/src/widgets/tab.swg` — which is how the cost of a
change is known in advance.

A path matching no surface selects the whole set, so an unmapped file costs time rather than
coverage. When that happens, add the surface to [tools/src/scope.swg](../../../tools/src/scope.swg)
rather than leaving the next change to pay for it again.

## Validate C++ Changes

Sema, code generation, the micro backend, the JIT, the runtime support and the driver sit under
every compiled program, so a change to any of them selects the whole set — `tests.swgs plan` says
so, and this sequence is what running it means. Fix every failure before continuing to the next
step.

1. Compile a DevMode build.
2. Run `swc tools/tests.swgs dm`.
3. Run `swc tools/tests.swgs dm --all-cfg`.
4. Compile the Release build, including `swc.exe`.
5. Run `swc tools/tests.swgs`.

Do not run `tests.swgs --all-cfg` in Release mode as part of the default workflow.

The compiler areas that do *not* sit under every program have their own narrower workflow:
`src/Doc` and `src/Format` below, `src/Unittest` in the C++ suite alone, and `src/Backend/Linker`
and `src/Backend/Debug` in the suites that emit a real image plus the applications and the
reference. Run `swc tools/tests.swgs changed` and it picks the right one.

## Validate Documentation-Only Changes

When a compiler change affects only the `doc` command, including refactoring shared helpers
for its implementation:

1. Compile a DevMode build.
2. Regenerate the repository documentation with `swc tools/web.swgs dm`.
3. Inspect the generated HTML and its diff for correctness.

Do not run `tests.swgs`, `tests.swgs --all-cfg`, or the Release validation workflow for a
documentation-only change. `tests.swgs changed` reports the regeneration as a step to take rather
than taking it: a test command must never rewrite a tracked file.

## Validate Formatter-Only Changes

When a compiler change affects only the `format` command:

1. Compile a DevMode build.
2. Run the C++ formatter suite with `swc tools/unittests.swgs dm cpp`.
3. Format the repository with `swc tools/format.swgs dm`.
4. Inspect the resulting diff for correctness.

Do not run `tests.swgs`, `tests.swgs --all-cfg`, or the Release validation workflow for a
formatter-only change. `tests.swgs changed` runs step 2 and reports step 3, for the same reason:
`format.swgs` rewrites tracked sources, so it is a maintenance step and never a test.

## Validate Swag-Only Changes

After changing sources under `bin/` without changing C++, `swc tools/tests.swgs changed --all-cfg` is
the whole workflow: it runs the changed example, script or application, the `bin/std` module and
everything that imports it, and nothing else.

Reach for one tool directly only to iterate on a single failure. An example declares no `#test`,
so it is smoked rather than tested — `swc tools/examples.swgs dm smoke <example> -bc <config>` — while
a `bin/std` module and an application carry both.

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
harness: point it at the tool, not at the `.exe`. An application packaged by
`swc tools/apps.swgs build <module>` is the one exception — packaging copies its dependencies beside
it, so the packaged executable runs on its own, which is what makes it shippable. That state is
fragile: a later `apps.swgs test <module>` strips those files again, so re-run the build before
any visual session that follows a test pass.

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
