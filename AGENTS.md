# Agents Guide

All AI instructions for modifying this repository live in `.agents/skills/`.

## Working Checkout

Work in the main local checkout on `master` by default. Do not create a task branch or worktree
unless the user explicitly asks for one. Preserve unrelated uncommitted changes, and stage only
the task's files when committing. When the checkout is on another branch, return to `master`
without discarding or relocating those changes; ask the user if that cannot be done safely.

## Start Here

The compiler lives in [src/](src): `src/Compiler/` handles the language pipeline, `src/Backend/`
handles JIT/native execution and artifacts, and `src/Main/`, `src/Doc/`, and `src/Format/` own
orchestration, documentation, and formatting. The consumer workspaces live in [bin/](bin):
runtime, standard modules, examples, applications, and language-reference tests.

Use [tools/README.md](tools/README.md) for the authoritative tool syntax and focused commands.
Build/test guidance and shared-machine load admission rules are in the two skills named below;
prefer a focused command for the changed behavior over the full campaign in `tools/tests.bat`.
For routine `bin/std` development feedback, use `tools/coverage.bat -DevMode` (`fast` by default),
narrowed with `-Workspace` and `-Module` as needed. For `bin/apps` iteration, use `swc.exe` by
default: omit `-DevMode` from `tools/coverage.bat` and omit `dm` from `tools/apps.bat` commands.
Reserve `swc.dm.exe` for debugging compiler problems. `-Configuration` and `-bc` select the
compiled program configuration independently of the compiler executable. Keep large scale-boundary
tests in `stress`; run `goldens`, `parity`, and `full` only for the validation needs described in
`validate-swag-changes`.
Visual tests cover Encre and Papier across each application and shared control family. Use one
palette per screenshot scenario and rotate palettes across sibling cases. Do not duplicate the
same composition in both themes; test palette roles and contrast with assertions instead.
Choose the theme arbitrarily once when writing each golden test and keep that choice fixed.
Cover the other theme in different tests, never in a palette loop within the same golden test.
Use the checkout-local `bin\\swc.exe` or `bin\\swc.dm.exe` when multiple worktrees may be
present. Treat [bin/help/](bin/help/) as generated output: edit its source under `bin/reference` or the
relevant module, then regenerate it through `tools/help.bat`.

Keep `SWC_BUILD_NUM` in [src/Main/Version.h](src/Main/Version.h) at its current value during
ordinary compiler changes. Change it only for an explicit release or cache-identity decision.
Because it participates in compiler cache identity, isolate or clear affected caches before
validating changed compiler behavior against artifacts from an older binary.

Before changing code, tests, examples, or build files, read and follow
[modify-swag-codebase](.agents/skills/modify-swag-codebase/SKILL.md).

Before compiling `swc` or `swc.dm`, or running any project test, read and follow the
CPU and memory admission rules in that skill, including when working from a different worktree.
Builds and tests may overlap only while the shared machine has enough measured headroom.

Before selecting or running builds, tests, configurations, consumers, smokes, or golden checks,
also read and follow
[validate-swag-changes](.agents/skills/validate-swag-changes/SKILL.md). Validation is chosen from
the behavior changed; `tools/tests.bat` no longer derives a campaign from the working tree.

Before adding or changing any Swag source (`.swg` or `.swgs`), including tests,
examples, scripts, and documentation code samples, also read and follow
[write-idiomatic-swag-code](.agents/skills/write-idiomatic-swag-code/SKILL.md).

When adding, changing, reviewing, or normalizing a public module API under `bin/`, also read
and follow [design-swag-bin-modules](.agents/skills/design-swag-bin-modules/SKILL.md): module
boundaries, naming, ownership, failure behavior, operation families, and compatibility must be
reviewed as one contract.

When the change affects English text emitted to users, also read and follow
[write-swag-compiler-messages](.agents/skills/write-swag-compiler-messages/SKILL.md).

When the change adds, removes, or renames language surface syntax (a keyword, `#` modifier,
`@` intrinsic, operator, or token spelling), also read and follow
[reflect-swag-syntax-changes](.agents/skills/reflect-swag-syntax-changes/SKILL.md): the
language reference and the VSCode extension must be updated to match.

When the change adds or updates public declarations or documentation comments under `bin/`,
also read and follow
[write-swag-public-api-docs](.agents/skills/write-swag-public-api-docs/SKILL.md).

When the change touches a brand asset, a stylesheet, a page layout, an icon, a color, or
the editor theme, also read and follow
[design-swag-identity](.agents/skills/design-swag-identity/SKILL.md): the mark, the
palette, and the 45 degree cut are one system. Every GUI surface under `bin/` follows the Silence
charter in [backlog/design/README.md](backlog/design/README.md), whose six laws that skill states.

When the change touches a GUI theme or a control's look — a palette token, a semantic color,
a measure, the way a widget picks its colors or draws a state, the property grid's marks, or a
theme sheet — also read and follow
[design-swag-themes](.agents/skills/design-swag-themes/SKILL.md): two palettes, Encre and Papier,
every color derived from their tokens, and the result judged in `gui10` and against the charter
pictures.

When the change touches a modal box — a dialog under `bin/std/modules/gui/src/dialogs`, a
composite hosted in one, or an application's own modal — also read and follow
[design-swag-dialogs](.agents/skills/design-swag-dialogs/SKILL.md): the floating sheet, its
inset, its title, its actions, and the way a box fits itself to its content are one composition.

When adding, migrating, renaming, styling, packaging, or testing an official application under
`bin/apps`, also read and follow
[build-swag-standard-apps](.agents/skills/build-swag-standard-apps/SKILL.md): every shipped app
uses a two-word `Swag Name` display identity and a lowercase technical stem, a specific generated icon, the Silence window
(nothing on screen but the work, every command in the lens), and the application-workspace
validation flow.

Everything this repository intends to do, and every lead it has recorded and not yet explained,
lives in one file per domain under [backlog/](backlog/). Evidence, open decisions, and committed
outcomes stay together so an entry can mature without moving or changing identity.
[backlog/README.md](backlog/README.md) states which file a new entry goes in and how it is numbered.
