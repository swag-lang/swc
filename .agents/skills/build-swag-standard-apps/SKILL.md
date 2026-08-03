---
name: build-swag-standard-apps
description: Build, migrate, rename, review, style, package, and test official Swag desktop applications under bin/apps. Use whenever adding or changing an app shipped with the compiler, promoting an external Swag app into bin/apps, changing an official app name or icon, revising its GUI, or integrating its build, smoke, unit, packaging, or privileged integration tests.
---

# Build Swag Standard Apps

Make every application recognizable as part of Swag before its title is read. Keep the family
strict and quiet: one generated product glyph, one voltage accent, one ink ground, measured
45-degree cuts, square structure, and no decoration without information.

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
- Never put `_` in an app-owned folder or file name. Use lower camel case for source and support
  names, such as `winfspAbi.win32.swg` and `winfspCallbacks.test.swg`; keep dots for Swag platform
  and test suffixes. Normalize imported filenames at the module boundary when an upstream package
  uses underscores, and record the upstream name in its notice when provenance would be unclear.
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

6. Set `BuildCfg.resAppIcoFileName` from `module.init.swg`. Decode `appicon.png`, pass it to
   `Application.setAppIcon` before creating the first surface, and reuse it for product-specific
   icon placements.
7. Inspect the PNG and the 16, 32, 48, and 256 pixel ICO entries. Regenerate the glyph when its
   negative space closes or its product meaning disappears; do not repair a weak concept with text.

## Build The Standard Surface

- Default to `ThemeColors.setSwagDark()`. Offer `setSwagLight()` only when the app exposes a real
  theme choice. Never invent an app-local accent.
- Use Voltage only for focus, the primary action, the active state, and one four-pixel brand rail
  per major surface or group. Never place Voltage text on a light ground.
- Use system sans for interface prose and the fixed-width theme family for compiler-known names,
  paths, formats, identifiers, compact badges, and status data.
- Use a spacing rhythm based on 4, 8, 16, 24, and 32 logical pixels. Align related labels and
  controls to one grid and keep the primary task visible without scrolling at the minimum size.
- Prefer square frames, hairlines, flat controls, whitespace, and clear grouping. Avoid card soup,
  repeated shadows, gradients, ornamental illustrations, and rounded chrome. Curves remain valid
  inside user content when the app edits or displays curved content.
- Keep one dominant action per task area. Give destructive actions distance and explicit wording.
  Show progress where work is not immediate, preserve keyboard focus, and keep failure text beside
  the operation that stopped.
- Design both palettes together, verify narrow and minimum-size layouts, and inspect a real native
  surface rather than trusting constants alone.

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
- Make `tools/manage-applications-workspace.bat` build, test, run, or smoke the module through the
  shared workspace. Package runtime dependencies after a normal app build when the executable is
  not functional without them.

## Prove The Application

For each changed app:

1. Build it with `tools/manage-applications-workspace.bat dm build -m sName`.
2. Run its tests with `tools/manage-applications-workspace.bat dm test -m sName`.
3. Run its bounded startup with `tools/manage-applications-workspace.bat dm smoke -m sName`.
4. Run any dedicated integration script. Keep tests that need UAC, drivers, hardware, or visible
   interaction in an explicit `tools/test-<name>-integration.bat`; do not surprise the ordinary
   aggregate suite with a privilege prompt.
5. Inspect packaged output for the executable, runtime dependencies, icon, licenses, and absence
   of installer or test debris.
6. Run the combined repository validation required by `modify-swag-codebase` for every other
   workspace touched by the change.

Finish by searching for obsolete names and absolute paths, inspecting ignored `.output` folders
under test trees, and reducing `git status` to intentional source and asset changes.
