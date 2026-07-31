---
name: modify-swag-codebase
description: Modify, refactor, fix, test, and validate the Swag compiler repository. Use whenever changing C++ compiler sources, Swag language features, unit tests, examples, build scripts, or other code in this repository; it enforces root-cause fixes, project C++ rules, test placement, and scoped validation workflows.
---

# Modify The Swag Codebase

Fix the root cause of every problem. Do not introduce hacks or workarounds.

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
2. Run `tests.bat dm`.
3. Run `alltests.bat dm`.
4. Compile the Release build, including `swc.exe`.
5. Run `tests.bat`.

Do not run `alltests.bat` in Release mode as part of the default workflow.

## Validate Documentation-Only Changes

When a compiler change affects only the `doc` command, including refactoring shared helpers
for its implementation:

1. Compile a DevMode build.
2. Regenerate the repository documentation with `web/tools/web.bat dm`.
3. Inspect the generated HTML and its diff for correctness.

Do not run `tests.bat`, `alltests.bat`, or the Release validation workflow for a
documentation-only change.

## Validate Formatter-Only Changes

When a compiler change affects only the `format` command:

1. Compile a DevMode build.
2. Format the repository with `tools/format.bat dm`.
3. Inspect the resulting diff for correctness.

Do not run `tests.bat`, `alltests.bat`, or the Release validation workflow for a
formatter-only change.

## Validate Example-Only Changes

After changing an example under `bin/examples` without changing C++:

1. Compile a DevMode build.
2. Run only the changed example in every configuration with `examples.bat dm test -m <example> -bc <config>`.

For other change types, run the narrowest relevant checks that demonstrate the modified behavior.

## Finish Cleanly

Remove temporary files and folders created during investigation or validation.

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
