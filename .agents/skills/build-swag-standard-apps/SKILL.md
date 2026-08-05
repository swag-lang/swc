---
name: build-swag-standard-apps
description: Build, migrate, rename, review, style, package, and test official Swag desktop applications under bin/apps. Use whenever adding or changing an app shipped with the compiler, promoting an external Swag app into bin/apps, changing an official app name or icon, revising its GUI, or integrating its build, smoke, unit, packaging, or privileged integration tests.
---

# Build Swag Standard Apps

Make every application recognizable as part of Swag before its title is read. Keep the family
strict and quiet: one generated product glyph, one voltage accent, one ink ground, measured
45-degree cuts, square structure, small chrome around generous air, and no decoration without
information.

## Establish The Change

1. Read `../modify-swag-codebase/SKILL.md` and `../write-idiomatic-swag-code/SKILL.md`.
2. Read `../design-swag-identity/SKILL.md` before touching UI, color, layout, or icon assets.
3. Read `../write-swag-compiler-messages/SKILL.md` before changing visible English text.
4. Read `../design-swag-bin-modules/SKILL.md` and `../write-swag-public-api-docs/SKILL.md`
   when a public `bin/` declaration changes.
5. Inspect the complete app, its tests, external resources, licenses, workspace scripts, generated
   artifact layout, and every repository reference before choosing the migration boundary.

## Name The Product Once

- Name every shipped application `sName`: lowercase `s`, then a concise UpperCamelCase product
  noun. Examples include `sCapture` and `sCrypt`.
- Use that spelling for the module directory, `BuildCfg.name`, resource application name,
  executable, title, registration identity, documentation, and URLs.
- Derive lowercase technical suffixes from it only where the platform convention needs them,
  such as `.scapture`. Keep namespaces UpperCamelCase and functions lowerCamelCase.
- Do not wrap private application code in a namespace that repeats the module or product name; the
  module already provides that boundary. Add a namespace only for a real subsystem vocabulary,
  and name it after that subsystem, such as `WinFsp`, rather than after the application.
- Never put `_` or uppercase letters in an app-owned folder or file name. Concatenate the words of
  one symbol or indivisible concept, and use dots between the named parts of a coherent file
  family, such as `app.operations.swg`, `winfsp.abi.win32.swg`, and
  `winfsp.callbacks.test.swg`. Platform and test suffixes use this notation but do not reserve it.
  Normalize imported filenames at the module boundary when an upstream package uses underscores,
  and record the upstream name in its notice when provenance would be unclear.
- Complete a rename in one pass. Migrate persisted filenames, clipboard and IPC names, file
  metadata, compiler tags, tests, comments, examples, and string-based lookups. Search the whole
  repository for every capitalization of the old name before finishing.

## Generate A Specific Icon

An app is incomplete without its own generated icon. Do not reuse the Swag mark, a theme-atlas
glyph, another app's icon, or a letter tile.

1. Use image generation to create one square raster master per app. Give each app a distinct,
   function-specific silhouette that still reads at 16 pixels.
2. Use exactly two base colors: Ink `#0B0B0D` for the ground and Voltage `#F7F900` for the glyph.
   Antialiasing at the edge is the only permitted interpolation.
3. Build the glyph on a strict grid. Cut exposed corners and terminals at 45 degrees. Use bold
   negative space and generous optical margin.
4. Reject text, letters, gradients, shadows, glow, bevel, texture, rounded corners, decorative
   borders, and generic shields or sparkles.
5. Run `scripts/package_app_icon.py` to flatten the generated master and derive the PNG and
   multi-resolution ICO:

   ```powershell
   py -3 .agents/skills/build-swag-standard-apps/scripts/package_app_icon.py `
       generated-master.png `
       --png bin/apps/modules/sName/datas/appicon.png `
       --ico bin/apps/modules/sName/datas/appicon.ico
   ```

6. Set `BuildCfg.resAppIcoFileName` in `module.swg`, using a path relative to the module folder.
   Decode `appicon.png`, pass it to `Application.setAppIcon` before creating the first surface,
   and reuse it for product-specific icon placements.
7. **The mark belongs in the title bar too.** A window says which application it is before its
   title is read. `setAppIcon` covers both places at once: the native icon of the taskbar and the
   task switcher, and the mark a drawn caption shows on its leading edge. Do not place it there by
   hand, and do not tint it — the caption honors the icon's own colors so the two-color glyph
   survives. A window that draws its own bar inside the caption, such as a menu bar, starts that
   bar past the mark rather than over it.
8. Inspect the PNG and the 16, 32, 48, and 256 pixel ICO entries. Regenerate the glyph when its
   negative space closes or its product meaning disappears; do not repair a weak concept with text.

## Build The Standard Surface

- Default to `ThemeColors.setSwagDark()`. Offer `setSwagLight()` only when the app exposes a real
  theme choice. Never invent an app-local accent.
- Use Voltage only for focus, the primary action, and the active state, plus exactly one
  four-pixel accent rail across the top edge of the application surface. One rail per window, not
  one per group: three parallel accent bars accent nothing and read as scaffolding. Never place
  Voltage text on a light ground.
- Use system sans for interface prose and the fixed-width theme family for compiler-known names,
  paths, formats, identifiers, compact badges, and status data.
- Use a spacing rhythm based on 4, 8, 16, 24, and 32 logical pixels. Align related labels and
  controls to one grid and keep the primary task visible without scrolling at the minimum size.
- Separate a group by what it sits on, not by what is drawn around it. A raised fill is the first
  tool, whitespace the second, and a rule the last. Every border and every divider is one more
  line a reader has to step over, so a surface that answers each grouping question with another
  line ends up as a grid of boxes. Never put a border, a rule, and a fill around the same group.
- Refuse rounded chrome, not craft. Square means no control is a capsule or a pill, and that a
  button carries the same corner and the same hairline stroke as the field beside it. It does not
  mean a hard right angle and a heavy outline on everything: a surface hacked out of a slab has
  missed the identity as badly as an upholstered one. Curves remain valid inside user content when
  the app edits or displays curved content. The one piece of chrome that does round is the outline
  of the window itself, softened by `surfaceWnd_CornerRadius` so the application sits on the
  desktop instead of being dropped on it; nothing inside the window follows it.
- Avoid card soup, repeated shadows, gradients, and ornamental illustrations.
- Keep one dominant action per task area. Give destructive actions distance and explicit wording.
  Show progress where work is not immediate, preserve keyboard focus, and keep failure text beside
  the operation that stopped.
- Level a glyph with the word beside it, not with the middle of the box around it. A line box
  reaches down to the descenders while a word is read on its capitals, so a centered icon reads as
  having slipped under its label. `Gui.opticalTop` is the one place that rule lives; use it for
  every icon, check mark, and arrow that shares a line with text, and never hand-tune a padding to
  compensate for it.
- Design both palettes together, verify narrow and minimum-size layouts, and inspect a real native
  surface rather than trusting constants alone.

## Keep The Chrome Small And The Air Large

A Swag application is quiet, and quiet is mostly a question of size. An oversized glyph reads as a
toy: it fills its cell, it crowds its neighbour, and it forces every surface around it to grow to
hold it. The interface must read as an instrument at arm's length, never as a touch launcher.

- **A glyph takes at most half of its cell.** The rest is not spare room to reclaim; it is what
  separates one control from the next. Take it back and the surface immediately needs a border to
  say where a control ends, which is the failure the previous section describes.
- **Use one size table for the whole family.** These are logical pixels, and they are ceilings.

  | Placement | Glyph | Cell |
  | --- | --- | --- |
  | Menu entry, list row, tree row, breadcrumb | 16 | 24 |
  | Tool rail, command bar, toolbar, primary action | 20 | 36 |
  | Flat swatch — one color, one pattern | — | 24 |
  | Rendered sample — a real preview of what the preset produces | — | 36 |
  | Inline badge, status readout, indicator | 12 | 16 |

- **Do not stack a label under a glyph.** It doubles the height of every control to carry a word
  the tooltip already carries, and turns a toolbar into a ribbon. A label belongs beside the glyph
  when it is needed at all, on the same line and starting right after it — a word pushed to the
  far edge of a wide cell reads as a second column, not as the name of the glyph.
- **The rule marking the active item is a mark, not a bar.** Run edge to edge at full weight it
  competes with the very glyph it points at. Keep it thin, stop it short of both ends of the edge
  it runs along, and give it a lane of its own: the content of a cell never touches it, and never
  shifts sideways as the cell is checked. Reserve that lane whatever the state, and count it in
  the width of the column, not out of the glyph's cell.
- **Nothing sits against the edge of its cell.** A glyph flush with the window edge and a label
  flush with the other side is not a dense toolbar, it is an unfinished one. Give every cell of a
  rail or a command bar the same padding on both sides, and let the column be as wide as that
  needs.
- **Chrome shrinks so content grows.** The document, image, list, or editor is the interface;
  everything else is a thin frame around it. Measure it: at the window's declared minimum size,
  the primary content must hold the clear majority of the surface. Any panel that cannot justify
  its width in information is too wide.
- **Air is the first separator, and it is generous.** Group with 16 or 24 pixels between blocks
  and 8 within a block, and let a panel keep its outer padding at its narrowest width. Two
  controls that need a divider to look separate are simply too close together.
- **A dense surface is not an efficient one.** A control that is present at all times to set a
  preference, a second title above a panel that already announces itself, a duplicated readout —
  each costs permanent room and buys one occasional click. Move it to a menu, a context menu, or a
  modifier gesture, and give the space to the content.

## Keep The Module Shippable

- Put the app at `bin/apps/modules/sName` with `module.swg`, `src/`, `src/tests/*.test.swg`, and a
  root-level `datas/` for icons and other immutable app resources. Never put `datas/` under `src/`.
- Put every externally sourced component under `vendor/<product>/` inside the module. Use
  `vendor/<product>/runtime` for redistributable binaries, keep the upstream license in the product
  folder, and keep repository-level notices beside `module.swg`. Preserve upstream version,
  download origin, redistribution terms, and local filename normalization in those notices. Do not
  use `third_party`, `thirdParty`, or one-off external-dependency folder names.
- Never commit generated `.dep`, `.output`, `.tmp`, or copied compiler binaries.
- Keep a module README when setup, packaging, privileges, security, or third-party deployment needs
  explanation. Use repository-relative commands and paths.
- Add reusable build, package, and integration entry points under `tools/`; do not leave personal
  absolute paths or root-level app scripts behind.
- Make `tools/apps.bat` build, test, run, or smoke the module through the
  shared workspace. Package runtime dependencies after a normal app build when the executable is
  not functional without them.

## Prove The Application

For each changed app:

1. Build it with `tools/apps.bat dm build sName`.
2. Run its tests with `tools/apps.bat dm test sName`.
3. Run its bounded startup with `tools/apps.bat dm smoke sName`.
4. Run any dedicated integration script. Keep tests that need UAC, drivers, hardware, or visible
   interaction in an explicit `tools/test-<name>-integration.bat`; do not surprise the ordinary
   aggregate suite with a privilege prompt.
5. Inspect packaged output for the executable, runtime dependencies, icon, licenses, and absence
   of installer or test debris.
6. Run the combined repository validation required by `modify-swag-codebase` for every other
   workspace touched by the change.

Finish by searching for obsolete names and absolute paths, inspecting ignored `.output` folders
under test trees, and reducing `git status` to intentional source and asset changes.
