---
name: modify-swag-codebase
description: Modify, refactor, fix, test, and validate the Swag compiler repository. Use whenever changing C++ compiler sources, Swag language features, unit tests, examples, build scripts, or other code in this repository; it enforces root-cause fixes, project C++ rules, test placement, and scoped validation workflows.
---

# Modify The Swag Codebase

Fix the root cause of every problem. Do not introduce hacks or workarounds.

The repository is written in English. Every comment, identifier, message, and
documentation line — in the compiler sources, in `bin/`, and in every other file —
is English; never leave French (or any other language) in the tree, whatever the
language of the conversation.

## Improve The Platform Along The Way

Treat every repository task, especially every Swag programming task, as an opportunity to
improve, debug, or optimize `bin/std`, the compiler, and the language itself. Do not normalize an
awkward library API, a compiler defect, a missed optimization, or a suspicious language rule as a
local workaround merely because the original request exposed it indirectly.

- Investigate the underlying platform when Swag code is unexpectedly awkward, fragile, slow, or
  impossible to express cleanly.
- Fix a discovered issue in the current change when it is sufficiently understood, relevant to
  the task, and can be validated without making the change unsafe or incoherent.
- Record the issue in [FINDINGS.md](../../../FINDINGS.md) when it is uncertain, requires broader
  design work, or should be handled separately. Include evidence and a concrete next investigation
  step; do not record vague wishes.
- Search `FINDINGS.md` before adding an entry. Enrich an existing item instead of creating a
  duplicate.
- Give the new entry the identifier the `Next identifier` line at the top of `FINDINGS.md` names,
  then advance that line. See the rule below.

The discovery backlog is not a promise that every item will be implemented, and not a substitute
for fixing a root cause that is already safe and in scope.

## Number Every Finding

Every `FINDINGS.md` entry carries a permanent identifier in its heading:

```
### F-023 — A menu bar does not follow a live language switch
```

The identifier is how a finding is named everywhere else — in conversation, in a commit message, in
a `TODO.md` entry, in a code comment. A title gets rewritten and a position moves; the identifier
does not.

- Take the next identifier from the `Next identifier` line at the top of `FINDINGS.md`, then
  advance that line. It is the counter, not the entry count: it keeps rising as entries are
  deleted.
- Never renumber and never reuse. A deleted entry takes its identifier with it, so `F-012` in an
  old commit message still means what it meant.
- Keep the entries sorted by identifier, ascending. A new entry always carries the highest
  identifier, so it goes at the end; a deleted one leaves a gap, and the gap stays. Position is
  mechanical and carries no priority — it only makes an entry findable by its number.

## Keep Findings And Roadmaps Apart

Two kinds of file, two different jobs. Write to the right one.

- `FINDINGS.md` (repository root) holds **evidence**: something observed, with a reproduction and a
  next investigation step. One file for the whole repository.
- `TODO.md` holds **intent**: what a unit should become, and in which order. The root
  [TODO.md](../../../TODO.md) covers the compiler, its `doc` and `format` commands, and the
  language; `bin/std/modules/<module>/TODO.md` and `bin/apps/modules/<app>/TODO.md` cover their own
  module. Entries are ordered by decreasing value and measured against the competition.

Both hold only what is *not done*. When a task resolves, invalidates, or completes the
investigation of an entry, delete that entry — or cut it down to the part that genuinely remains.
Never keep done or investigated material as a record: history lives in git. A finding that
graduates into a plan moves to the matching `TODO.md` and disappears from `FINDINGS.md`.

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

## Validate C++ Changes

Use one of the narrower workflows below when the change only affects the `doc` or `format`
command. Otherwise, after changing any compiler C++ file, complete this sequence. Fix every
failure before continuing to the next step.

1. Compile a DevMode build.
2. Run `tools/tests.bat dm`.
3. Run `tools/tests.bat dm --all-cfg`.
4. Compile the Release build, including `swc.exe`.
5. Run `tools/tests.bat`.

Do not run `tests.bat --all-cfg` in Release mode as part of the default workflow.

## Validate Documentation-Only Changes

When a compiler change affects only the `doc` command, including refactoring shared helpers
for its implementation:

1. Compile a DevMode build.
2. Regenerate the repository documentation with `tools/web.bat dm`.
3. Inspect the generated HTML and its diff for correctness.

Do not run `tests.bat`, `tests.bat --all-cfg`, or the Release validation workflow for a
documentation-only change.

## Validate Formatter-Only Changes

When a compiler change affects only the `format` command:

1. Compile a DevMode build.
2. Format the repository with `tools/format.bat dm`.
3. Inspect the resulting diff for correctness.

Do not run `tests.bat`, `tests.bat --all-cfg`, or the Release validation workflow for a
formatter-only change.

## Validate Example-Only Changes

After changing an example under `bin/examples` without changing C++:

1. Compile a DevMode build.
2. Run only the changed example in every configuration with `tools/examples.bat dm test <example> -bc <config>`.

For other change types, run the narrowest relevant checks that demonstrate the modified behavior.

## Launch Every Executable Through Its Tool

Never start a built binary by its path. `bin/std` compiles to shared libraries — `core.dll`,
`pixel.dll`, `gui.dll` and the rest — and the compiler leaves the executable in its output
directory *without* them. Run it from there and it dies before `main`, with no window and no
diagnostic, which reads exactly like the bug you were about to investigate.

The tools place the runtime files first, then launch:

```
tools/examples.bat [dm] run -m <example>
tools/apps.bat [dm] run <module>
tools/scripts.bat [dm] run <script>
```

The same rule holds when driving a program from a helper script, a debugger, or a screenshot
harness: point it at the tool, not at the `.exe`. An application packaged by
`tools/apps.bat build <module>` is the one exception — packaging copies its dependencies beside
it, so the packaged executable runs on its own, which is what makes it shippable. That state is
fragile: a later `apps.bat test <module>` strips those files again, so re-run the build before
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
