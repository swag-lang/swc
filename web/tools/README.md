# Publication tools

Everything that produces what ships in `web/` lives here, and nothing else does. Each
tool is run by hand from the repository root, never by a test suite.

| Tool | Produces |
| --- | --- |
| `web.bat` | Everything: it cuts the brand assets, then runs `swc doc` over the `bin/std` and `bin/reference` workspaces |
| `brand.swgs` | The mark, the icons, and the favicons, cut from one geometric definition |
| `syntax/` | The page captured into `imgs/syntax.png`, colored by the compiler itself |

`web.bat` takes the same `dm` first argument as the batch files under the repository-level
`tools` directory, which is where it reads its shared helpers from.

A tool here owns its subject and nothing else. `brand.swgs` owns the geometry of the mark;
rasterizing it, writing SVG, and encoding an icon are general problems, so they live in
`Pixel` where any program can reach them. When a tool starts growing a helper that is not
about its own subject, move the helper into `bin/std` instead.

Before changing anything under this directory, read
[design-swag-identity](../../.agents/skills/design-swag-identity/SKILL.md).
