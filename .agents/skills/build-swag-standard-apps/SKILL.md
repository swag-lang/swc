---
name: build-swag-standard-apps
description: Build, migrate, rename, review, style, package, and test official Swag desktop applications under bin/apps. Use whenever adding or changing an app shipped with the compiler, promoting an external Swag app into bin/apps, changing an official app name or icon, revising its GUI, or integrating its build, smoke, unit, packaging, or privileged integration tests.
---

# Build Swag Standard Apps

Make every application recognizable as part of Swag before its title is read. Keep the family
strict and quiet: one generated product glyph, one voltage signature over one ink ground, measured
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

- Name every shipped application with a lowercase `s` followed by exactly two semantic
  UpperCamelCase words: `sSnapForge`, `sVaultDrive`, `sFileScope`. The `s` identifies the Swag
  family and does not count as one of the words.
- Make the pair vivid enough to suggest an action or an image, while still saying what the product
  does. Prefer a concrete compound such as `SnapForge` over a flat category such as `Capture`,
  `Crypt`, or `Viewer`; never pad a generic noun with `App`, `Tool`, `Studio`, or `Pro` merely to
  satisfy the two-word rule.
- Before accepting a name, search exact and unprefixed spellings across current software products,
  platform features, package registries, and repositories. Reject a name dominated by an existing
  product or operating-system feature even when capitalization differs.
- Use the complete spelling for the application workspace, primary module directory,
  `BuildCfg.name`, resource application name, executable, title, registration identity,
  documentation, and URLs.
- Derive new lowercase technical suffixes from the two-word product stem only where a platform
  convention needs them, such as `.filescope`. Preserve an already published file extension,
  format marker, cryptographic domain separator, or ABI spelling when changing it would strand
  user data or third-party integrations;
  label that spelling as legacy and add an explicit migration or compatibility path.
  Keep namespaces UpperCamelCase and functions lowerCamelCase.
- Do not wrap private application code in a namespace that repeats the module or product name; the
  module already provides that boundary. Add a namespace only for a real subsystem vocabulary,
  and name it after that subsystem, such as `WinFsp`, rather than after the application.
- Except for the workspace and primary module directories that carry the exact product spelling,
  never put `_` or uppercase letters in an app-owned folder or file name. Concatenate the words of
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
       --png bin/apps/sName/modules/sName/datas/appicon.png `
       --ico bin/apps/sName/modules/sName/datas/appicon.ico
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

   The caption draws one of **two cuts** of that icon, decided by contrast against its own band:
   on a dark bar the ink tile is keyed out and the glyph floats free; on a light bar the tile
   stays, because a Voltage glyph on paper is a mark nobody sees. That is why the master must be
   exactly the two declared colors — a mark cut from a third color keys out wrong and reads as a
   grey square in the light theme.
8. Inspect the PNG and the 16, 32, 48, and 256 pixel ICO entries. Regenerate the glyph when its
   negative space closes or its product meaning disappears; do not repair a weak concept with text.

## Build The Standard Surface

- Default to `ThemeColors.setSwagDark()`. Offer `setSwagLight()` only when the app exposes a real
  theme choice. Never invent an app-local accent.
- Use Voltage only for focus, the primary action, and the active state, plus exactly one
  four-pixel accent rail across the top edge of the application surface. One rail per window, not
  one per group: three parallel accent bars accent nothing and read as scaffolding. Never place
  Voltage text on a light ground — the theme's own mark is already a deepened Voltage there, so
  take `hilight` and never the raw brand color.
- **When a second color is genuinely needed, it is the theme's second tone and nothing else.**
  A page the reader can leave to, a link, a mode that is not the work of the surface: those take
  the alternate tone — `PushButtonForm.Alternate` for a filled action, `theme.palette.alternate`
  for anything drawn by hand. Borrowing a status color for it is the mistake to avoid: sSnapForge
  dressed its Library button in the informational notice palette, which said "notice" in a place
  nothing was being reported and left the app answering for nine colors the theme should have
  answered for. One strong action and at most one alternate per surface.
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
  the app edits or displays curved content. Two things round, and only these two: the outline of
  the window itself, softened by `surfaceWnd_CornerRadius` so the application sits on the desktop
  instead of being dropped on it, and a repeated cell that holds content — a thumbnail strip, a
  swatch grid, a preview tile — at the corner the theme already gives a raised cell
  (`ThemeImageRects.btnIcon_RoundSquareBk.radius`). Read the radius from the theme rather than
  naming a number; the chrome between those cells does not follow either of them.
- Avoid card soup, repeated shadows, and ornamental illustrations. The one gradient the chart
  admits is the wash the title bar carries to say the window has the focus, and the toolkit draws
  it — an application that adds a second one has decorated a surface rather than informed it. See
  the gradient clause in [design-swag-identity](../design-swag-identity/SKILL.md).
- Keep one dominant action per task area. Give destructive actions distance and explicit wording.
  Show progress where work is not immediate, preserve keyboard focus, and keep failure text beside
  the operation that stopped.
- Level a glyph with the word beside it, not with the middle of the box around it. A line box
  reaches from the ascender to the descender while a word is read on its capitals, and the gap
  between those two middles belongs to the face, so a glyph centered on the cell reads as having
  slipped off its label. Two places own that rule and there is never a third: `Gui.opticalTop`
  levels a glyph with a line whose *box* is centered, and `Pixel.Font.opticalLineTop` centers the
  line on its capitals instead — which is what a control drawing a frame around one line does, so
  that the same field reads the same whichever family it is set in. Never hand-tune a padding to
  compensate for either.
- Design both palettes together, verify narrow and minimum-size layouts, and inspect a real native
  surface rather than trusting constants alone.

## Put Theme And Language In The Caption

Every standard application exposes presentation choices through one
`Gui.AppearanceButton.create(surface)` action in the title bar. The toolkit positions its dedicated
Appearance glyph immediately to the left of minimize, maximize, and close; never reproduce that
placement in application layout code.

- Register the application string tables and every supported `Gui.Language` before creating the
  button, so its language submenu is complete on the first opening.
- Offer both shipped Swag palettes and every registered language, plus the system-language choice,
  through this menu. Do not keep a second theme picker, language combo, property-grid row, or
  options-menu entry in the application body.
- Restore the persisted choices while the main window is still hidden with
  `setAppearanceTheme` and `setAppearanceLanguage`. Persist the control's `appearanceTheme` and
  `language` from `sigThemeChanged` and `sigLanguageChanged`; an empty language means follow the
  account, while `Gui.ReferenceLanguage` means explicitly use English.
- The control applies the choice and sends the application notification before its signal. Use the
  signal only for persistence and for application-owned derived state such as cached artwork; do
  not apply the palette or language a second time.
- A language switch must retranslate text assigned at construction and re-run any layout whose
  measurements depend on that wording. Test the caption action, both palettes, the system choice,
  and every language the application ships.

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
- **A small horizontal icon bar frames its active cell.** Use
  `IconButtonCheckIndicator.Frame`: its slight themed fill and rounded hairline surround the glyph
  without looking like part of it. A vertical tool rail may instead keep a leading `Left` rule,
  as sSnapForge does, because the rule then reads beside the column. Make the indicator an
  explicit choice; never use a bottom underline on compact horizontal icons, and reserve the
  rail's lane in every state so vertical content never moves when it is checked.
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

## Let An Option Carry Its Own Wording

A form is a column of named fields, and an option is not one of them. A check box already says what
checking it does, so a name beside it repeats the sentence the box carries and a blank label above
it reserves the height of a name that is not there — which reads as the option having drifted away
from the field it qualifies.

- Add it with [[Gui.FormLayoutCtrl.addOptionField]], which leaves the label column empty and spends
  no line on it. The box then lines up under the fields rather than under their names, which is
  where the reader is already looking.
- Put it under the field it qualifies, not at the bottom of the card. An option about what a drive
  *will be* belongs under the letter it takes, not beside the password that opened it.
- Give it the same help paragraph a field gets when what it does is not obvious from four words.
  The wording on the box says what it is; the paragraph says what it costs.

## Ship A Feature In Every Language It Will Be Read In

A feature that puts words on a surface is not finished when it works in English. The wording is
part of the layout, and a translation is longer — French runs 15 to 25 percent longer than English
on ordinary interface prose, and one sentence in ten needs a whole extra line. **Check every
shipped language before calling the feature done**, and check it at the window's declared minimum
size, which is the width the text has least room in.

- **Look at the picture, in each language.** An assertion cannot see a caption cut in half or a
  help paragraph missing its last line. Render the surface headlessly per language while reviewing
  by hand, and keep the one language-independent assertion the module already has — see
  `Testing.assertContentFits`, which fails when a window is arranged smaller than its content.
- **Assert the containment the check cannot infer.** `assertContentFits` compares a window against
  its own measure, so a band sized by that same measure always "fits" itself. What breaks is a
  band overflowing its parent, and no generic check sees it: a card whose height comes from a grid
  row does not grow for a longer form, it clips it. Write that comparison down for each card the
  feature touches — sVaultDrive's `assertFormEndsInsideCard` is the worked example — and run it over
  every entry of `Gui.languages()`.
- **Prefer adapting the text to adapting the interface.** Shortening a sentence is one edit in two
  files and costs nothing; reflowing a card changes the layout for every language including the
  ones that were fine. Say the same thing in fewer words first. Only when the wording is already
  as short as it can be honestly get is it the layout's turn — and then fix the measurement rather
  than adding room: a height that has to be re-tuned per language is a height that was authored
  where it should have been measured.
- **Translate at the same time as you write.** A key added to the reference table and left out of
  `datas/lang/<tag>/*.tweak` silently falls back to English, so the feature ships half translated
  and nothing reports it. The `#run` validation catches a mistyped key, never a missing one.

## Look At The Surface, Not Only At Its Assertions

An application's tests read its window — what a button says, whether a form can act, whether the
layout survives a language. None of that can see it. A color that stopped reading, a control that
lost its ground, a row that drifted out of its column: an assertion never catches any of it,
because nothing about it is wrong enough to fail.

Photograph the window instead. `Gui.Testing.HeadlessHost` renders a real window tree without a
desktop, so the picture costs a test rather than a screenshot session — and it keeps working when
the desktop is unavailable, which is exactly when a screenshot session is not.

```swag
var host: Testing.HeadlessHost
let window = testSetupMainWindow(&host)
defer host.shutdown()

host.theme.setSwagDark()
host.theme.metrics.surfaceWnd_ShadowSize   = 0     // No desktop under it: the shadow falls on
host.theme.metrics.surfaceWnd_CornerRadius = 0     // nothing and the corner punches holes.
host.notify(.ThemeChanged)
window.applyLayout()
host.settleAnimations(window, 6)

var image = host.render(window)
Pixel.Testing.assertImageGolden(&image, "sname.surface")
```

Three things this gets wrong if they are not said:

- **One host per palette, never one host repainted.** A render target keeps what the last paint
  left, and a fill the theme makes translucent then composites over the palette before it. Two of
  four images came out that way once, and they were wrong in the direction that reads as a defect
  of the palette rather than of the harness.
- **A theme change is not only an event.** A style carrying a font or a sheet keeps a private copy
  of the theme it was computed against, and `Application.notifyThemeChanged` walks the surfaces the
  application created — not the one a headless host builds by hand. `HeadlessHost.notify` is what
  reaches it.
- **Commit one image, not one per palette.** A full repaint of a large surface is minutes on the
  default configuration, and the palettes themselves are pinned by the toolkit's own tests. Shoot
  the palette the application ships on, and put the others on their own hosts only while reviewing
  by hand.

## Keep The Workspace Shippable

- Give every application its own workspace at `bin/apps/sName/`. Put the primary executable in
  `bin/apps/sName/modules/sName` with `module.swg`, `src/`, `src/tests/*.test.swg`, and a root-level
  `datas/` for icons and other immutable app resources. Never put `datas/` under `src/`.
- Put every additional application module directly under the same `modules/` directory. A plugin,
  helper library, or optional backend is a normal workspace module, never a nested module hidden
  under the executable and never a special standalone build in `tools/apps.swgs`.
- Make a module that normally emits a library select an executable backend for `#test` when its
  tests need to run natively. The workspace's ordinary `build`, `test`, and `smoke` commands must
  cover the whole application without a module-specific compilation path in the tool.
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
- Make `tools/apps.swgs` build, test, run, or smoke the application's own workspace. Its positional
  name selects an application, not one module inside it. Package runtime dependencies after a
  normal workspace build when the executable is not functional without them.

## Prove The Application

For each changed app:

1. Build it with `swc tools/apps.swgs dm build sName`.
2. Run its tests with `swc tools/apps.swgs dm test sName`.
3. Run its bounded startup with `swc tools/apps.swgs dm smoke sName`.
4. Run any dedicated integration script. Keep tests that need UAC, drivers, hardware, or visible
   interaction in an explicit `tools/test-<name>-integration.swgs`; do not surprise the ordinary
   aggregate suite with a privilege prompt.
5. Inspect packaged output for the executable, runtime dependencies, icon, licenses, and absence
   of installer or test debris.
6. Run the combined repository validation required by `modify-swag-codebase` for every other
   workspace touched by the change.

Finish by searching for obsolete names and absolute paths, inspecting ignored `.output` folders
under test trees, and reducing `git status` to intentional source and asset changes.
