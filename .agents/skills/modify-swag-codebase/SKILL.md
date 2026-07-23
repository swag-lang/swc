---
name: modify-swag-codebase
description: Modify, refactor, fix, test, and validate the Swag compiler repository. Use whenever changing C++ compiler sources, Swag language features, unit tests, examples, build scripts, or other code in this repository; it enforces root-cause fixes, project C++ rules, test placement, and the required DevMode and Release validation workflows.
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

After changing any compiler C++ file, complete this sequence. Fix every failure before continuing to the next step.

1. Compile a DevMode build.
2. Run `tests.bat dm`.
3. Run `alltests.bat dm`.
4. Compile the Release build, including `swc.exe`.
5. Run `tests.bat`.

Do not run `alltests.bat` in Release mode as part of the default workflow.

## Validate Example-Only Changes

After changing an example under `bin/examples` without changing C++:

1. Compile a DevMode build.
2. Run only the changed example in every configuration with `examples.bat dm test -m <example> -bc <config>`.

For other change types, run the narrowest relevant checks that demonstrate the modified behavior.

## Finish Cleanly

Remove temporary files and folders created during investigation or validation. Report the validations run and any checks that could not be completed.
