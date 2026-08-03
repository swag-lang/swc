# Agents Guide

All AI instructions for modifying this repository live in `.agents/skills/`.

Before changing code, tests, examples, or build files, read and follow
[modify-swag-codebase](.agents/skills/modify-swag-codebase/SKILL.md).

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

When adding, migrating, renaming, styling, packaging, or testing an official application under
`bin/apps`, also read and follow
[build-swag-standard-apps](.agents/skills/build-swag-standard-apps/SKILL.md): every shipped app
uses the `sName` product convention, a specific generated icon, the standard Swag surface, and the
applications workspace validation flow.
