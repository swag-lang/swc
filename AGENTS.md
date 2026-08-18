# Agents Guide

All AI instructions for modifying this repository live in `.agents/skills/`.

Before changing code, tests, examples, or build files, read and follow
[modify-swag-codebase](.agents/skills/modify-swag-codebase/SKILL.md).

Before compiling `swc` or `swc_devmode`, or running any project test, read and follow the
agent-to-agent build and test serialization rules in that skill, including when working from a
different worktree. IDE and manually launched user commands do not occupy the agent slot.

Before selecting or running builds, tests, configurations, consumers, smokes, or golden checks,
also read and follow
[validate-swag-changes](.agents/skills/validate-swag-changes/SKILL.md). Validation is chosen from
the behavior changed; `tools/tests.swgs` no longer derives a campaign from the working tree.

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
palette, and the 45 degree cut are one system.

When the change touches a GUI theme — a palette token, a semantic color, the way a widget
picks its colors, or a theme sheet — also read and follow
[design-swag-themes](.agents/skills/design-swag-themes/SKILL.md): every color is derived
from a small set of tokens, and the `gui10` inspector is how the result is judged.

When the change touches a modal box — a dialog under `bin/std/modules/gui/src/dialogs`, a
composite hosted in one, or an application's own modal — also read and follow
[design-swag-dialogs](.agents/skills/design-swag-dialogs/SKILL.md): the inset, the gap, the
action bar, and the way a box fits itself to its content are one composition.

When adding, migrating, renaming, styling, packaging, or testing an official application under
`bin/apps`, also read and follow
[build-swag-standard-apps](.agents/skills/build-swag-standard-apps/SKILL.md): every shipped app
uses the two-word `sName` product convention, a specific generated icon, the standard Swag surface,
and the application-workspace validation flow.

Everything this repository intends to do, and every lead it has recorded and not yet explained,
lives in [backlog/](backlog/): `todo.<unit>.md` for intent, `findings.<area>.md` for evidence.
[backlog/README.md](backlog/README.md) states which file a new entry goes in and how it is
numbered.
