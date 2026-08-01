# Publication sources

The source material specific to generated website assets lives here. Project-owned batch
entry points are centralized in the repository-level `tools/` directory.

| Tool | Produces |
| --- | --- |
| `../../tools/generate-web-documentation.bat` | Everything: it cuts the brand assets, then runs `swc doc` over the `bin/std` and `bin/reference` workspaces |
| `brand.swgs` | The mark, the icons, and the favicons, cut from one geometric definition |
| `syntax/` | The page captured into `imgs/syntax.png`, colored by the compiler itself |

`generate-web-documentation.bat` accepts the same `dm` first argument as the other compiler
tools.

A tool here owns its subject and nothing else. `brand.swgs` owns the geometry of the mark;
rasterizing it, writing SVG, and encoding an icon are general problems, so they live in
`Pixel` where any program can reach them. When a tool starts growing a helper that is not
about its own subject, move the helper into `bin/std` instead.

Before changing anything under this directory, read
[design-swag-identity](../../.agents/skills/design-swag-identity/SKILL.md).
