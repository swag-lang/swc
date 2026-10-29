---
name: build-swag-standard-apps
description: Build, migrate, rename, review, style, package, and test official Swag desktop applications under bin/apps to the Silence charter. Use whenever adding or changing an app shipped with the compiler, promoting an external Swag app into bin/apps, changing an official app name, icon or command wording, revising its window, its lens commands, its shared components (lens, sheet, inspector, mini-bar, dock) or its layout, or integrating its build, smoke, unit, golden, packaging, or privileged integration tests.
---

# Build Swag Standard Apps

Every application should be recognizable as part of Swag before its title is read, and
recognizable by what it leaves out. The four standard applications, Swag Scope, Swag Capture,
Swag Prism and Swag Vault, follow the **Silence** charter:
[backlog/design/README.md](../../../backlog/design/README.md), with its pictures in
[backlog/design/imgs/](../../../backlog/design/imgs/). The charter's Window chrome, Shared
components and Applications sections describe each screen. This skill says how an application
is built to match them. What each application still lacks is tracked in
[design.silence.md](../../../backlog/design/design.silence.md).

## Establish The Change

1. Read `../modify-swag-codebase/SKILL.md` and `../write-idiomatic-swag-code/SKILL.md`.
2. Before touching UI, colour, layout or icons, read `../design-swag-identity/SKILL.md` (the six
   laws, the tile) and `../design-swag-themes/SKILL.md` (tokens, roles, measures, type,
   controls). Before touching a modal box, read `../design-swag-dialogs/SKILL.md`.
3. Open the charter pictures of the surface you change, in both themes, and keep them open.
4. Before changing visible English text, read `../write-swag-compiler-messages/SKILL.md`. Before
   changing a command label, read *Word The Commands* below.
5. When a public `bin/` declaration changes, read `../design-swag-bin-modules/SKILL.md` and
   `../write-swag-public-api-docs/SKILL.md`.
6. Before choosing the migration boundary, look at the whole application: its tests, resources,
   licences, workspace scripts, artifact layout, and every reference to it in the repository.

## Make Standard Applications Language Showcases

An application shipped with the compiler is executable language documentation. Its source must
show how a substantial Swag program handles ownership, controls, callbacks, failure and cleanup,
without hiding those contracts behind framework ceremony.

- Make a main `create` function read as the ordered outline of the window: initialize the root,
  create each visual region, connect the routing between regions, register the lens commands,
  apply derived state, and return. When one region's construction interrupts that outline, move
  it into a private receiver method or a real component type.
- Name each construction method after the thing it creates (`createDock`,
  `createReadingColumn`), not after a vague phase such as `setupUi`.
- Do not split one window type across `*.layout.swg` or `*.events.swg` aspect files to make a
  large file look smaller. Extract a component, model, operation or lifecycle owner when it has a
  contract of its own.
- Use data-driven construction only for repetitions that really are the same, such as lens
  entries. A short set of tools with distinct behaviour is clearer as typed Swag code.
- Treat precedent as evidence, not permission. Another application's long constructor may be the
  same debt.
- Prefer ordinary language features: typed fields, receiver methods, `with` construction,
  contextual conversion, direct returns, scope-bound cleanup.
- Treat application work as a probe of `bin/std`. If a clean implementation needs an app-local
  workaround, copied control behaviour, or glue that other applications would also need, improve
  the standard module and its tests first. **The lens, the sheet, the inspector, the mini-bar, the
  dock, the hint line, the toast, the section label and the quiet menu are toolkit components. An
  application composes them and never re-implements one.**
- Protect the composition at both boundaries. Structural tests assert parentage, order,
  alignment and visibility, and a focused golden in each theme proves the result reads correctly.

## Name The Product Once

- Give every shipped application a two-word display name: `Swag` followed by one concrete word,
  as in `Swag Capture`, `Swag Vault` and `Swag Scope`. Do not abbreviate the family name.
- The word should suggest an action or an image while still saying what the product does. Avoid
  padding words such as `App`, `Tool`, `Studio` or `Pro`.
- Before accepting a name, search for exact and unprefixed spellings across software products,
  platform features, package registries and repositories. Reject a name that an existing product
  already dominates.
- Concatenate and lowercase the display words for technical identities (`swagcapture`). Use that
  stem for the module directory, `BuildCfg.name`, the executable, the packaging directory, the
  module selector, the registration key and the source URL. Use the spaced display name only for
  user-visible text.
- Prefer role-based private identities (`capture.file.open`, `Swag/Capture`) over either
  spelling. An API an application publishes to its own extensions is named after what it
  describes (`Viewer` in Swag Scope).
- Treat published file extensions, format markers, cryptographic domain separators and ABI names
  as migration decisions. Keep them under an explicit compatibility contract, or make a clean
  break when one is requested, with no alias left behind.
- Do not wrap private application code in a namespace that repeats the module name. Add a
  namespace only for a real subsystem (`WinFsp`).
- App-owned folder and file names have no spaces, `_` or uppercase letters. Use dots between the
  named parts of a file family (`app.operations.swg`). Normalize imported names at the module
  boundary and record the upstream name in the notice when needed.
- Complete a rename in one pass: persisted files, clipboard and IPC names, metadata, tags, tests,
  comments, examples and string lookups. Search for every capitalization of the old name.

## Generate A Specific Icon

An application is not complete without its own generated icon. Do not reuse the Swag mark, a
theme-atlas glyph, another app's icon or a letter tile.

1. Use image generation to create one square raster master per app. Give each app a distinct,
   function-specific silhouette that still reads at 16 pixels.
2. Use exactly two colours: Ink `#0B0B0D` for the ground and Voltage `#F7F900` for the glyph.
   Antialiasing at the edges is the only interpolation allowed.
3. Build the glyph on a strict grid. Cut exposed corners and terminals at 45 degrees. Keep bold
   negative space and generous optical margins.
4. Reject text, letters, gradients, shadows, glow, bevel, texture, decorative borders, and generic
   shields or sparkles. Keep the master square.
5. Run `scripts/package_app_icon.py`. It flattens the master to the two colours, puts it on the
   ink tile with the small shared corner (4 px at 48), and writes the PNG and the
   multi-resolution ICO:

   ```powershell
   py -3 .agents/skills/build-swag-standard-apps/scripts/package_app_icon.py `
       generated-master.png `
       --png bin/apps/modules/<application>/datas/appicon.png `
       --ico bin/apps/modules/<application>/datas/appicon.ico
   ```

6. Set `BuildCfg.resAppIcoFileName` in `module.swg`, with a path relative to the module folder.
   Decode `appicon.png` and pass it to `Application.setAppIcon` before creating the first surface.
7. **The tile is for the desktop and the About box. The window carries the glyph.** The toolkit
   draws the glyph monochrome in `wnd_CaptionMark`, 18 px, at the top-left corner of the window,
   and the About box shows the tile at `dialog_TileSize`. `setAppIcon` feeds both, so never place
   or tint the window glyph by hand. Because the window lifts the glyph off its ink ground, the
   master must use exactly the two declared colours.
8. Inspect the PNG, the 16, 32, 48 and 256 pixel ICO entries, and the window glyph in both themes.
   If the negative space closes or the meaning disappears, regenerate the glyph. Do not repair a
   weak concept with text.

## Leave The Window To The Work

The six laws (see [design-swag-identity](../design-swag-identity/SKILL.md#the-gui-follows-silence))
bind an application like this:

- **No permanent toolbar, menu bar, status bar, ribbon, side panel, information band or options
  band.** The window is the document, the image, the list.
- **Readings, outlines, metadata and settings are asked for.** They live in the sheet, the
  inspector, the lens or a hover veil. They are moved there, never deleted on the way.
- **`Space`, or `Ctrl K` where Space types text, opens the lens, and every command is in it.**
- **One accent at a time**: one primary action per surface, and everything chosen is Arc (see
  [design-swag-themes](../design-swag-themes/SKILL.md#voltage-acts-arc-chooses)).
- **Air before lines**: measured columns, reading margins, nothing flush with an edge, nothing
  boxed that space can separate.
- **Encre and Papier, with Dark, Light and System offered.** An application never invents an
  app-local accent. A different look is a theme sheet layered on top (see
  [design-swag-themes](../design-swag-themes/SKILL.md#theme-sheets)).

### The window chrome

The charter's Window chrome section, with [`scope.read`](../../../backlog/design/imgs/scope.read.png)
as its picture, describes the window. The toolkit's `SurfaceWnd` draws all of it: the glyph, the
centred title and the faint window buttons. An application adds nothing to it.

- The strip (`ThemeMetrics.wnd_StripHeight`, 52) floats over the view, and the view takes the
  whole body. `SurfaceWnd.hitTestCaption` drags the window from the strip's ground and from
  content passing under it. It leaves clicks to any control that lies within the strip.
- A part that must keep clear of the strip (a page header, a form, a band of controls) insets its
  top by `Wnd.stripInset()` and reads it again in its resize handler, because the strip comes and
  goes in full screen. A document, a picture or a list that scrolls under the title ignores it.
- **The hint line** is `Gui.HintLine`: `HintLine.create(view)`, then
  `.addHint(strings().key_Space, words)` and `.setReading(text)` for a faint reading, such as a
  canvas size, on the same line. It teaches the keys of the mode in force, with `Space` last. Hide
  it once the reader knows the door.
- **Keys are named one way** everywhere: in the hint line, at the foot of the lens, at the end of
  a menu or lens row. Use `Input.formatKeyShortcut` and the key names of `Gui.strings()`
  (`key_Space`, `key_Enter` (`↵`), `key_CtrlEnter`, `key_Escape`). A chord is written as its keys
  separated by spaces (`Ctrl Shift S`). What a key does is a few lowercase words after it.

### Compose the shared components

The charter's Shared components section and the pictures describe what each component looks
like. The toolkit types live in `bin/std/modules/gui/src/controls/lens` and
`controls/floating`, are shown together on the Components page of `gui10`, and are covered by
`lens.test.swg` and `floating.test.swg`:

| Component | Type | The application calls |
| --- | --- | --- |
| Lens | `Gui.Lens.View` | `Lens.View.create(owner)`; `addCommands(family, ids)` for every command; `addSource(prefix, provider)` for lines, files, symbols; `addRestSource(provider)` for the actions of the object in hand; `open(query)` from its key |
| Sheet (`I`) | `Gui.InfoSheet` | `InfoSheet.create(view)`; `setTitle`, `setIdentity`, `setPicture`, `addFact`, `addReading`, `addSection`, `addText`, `addLink`, `setAction`, `setSecondaryAction`, `clear`; `toggle()` on `I` |
| Inspector | `Gui.Inspector` | `Inspector.create(view)`; `setTitle(title, detail)`, `addAction`, `addSection`, `addRow(label, editor, fill)`, `addWideRow`, `setContent(grid)`, `clear`; `toggleFolded()` on its key |
| Mini-bar | `Gui.MiniBar` | `MiniBar.create(canvas)`; `addButton`, `addTextButton`, `addItem`, `addSeparator`; `showNear(selection)` when the selection moves, hide it when nothing is selected |
| Dock | `Gui.ToolDock` | `ToolDock.create(view)`; `addTool(icon, id, toolTip)`, `addToGroup`; `setActiveTool`, `selectTool`; `sigToolChanged` |
| Hint line | `Gui.HintLine` | `HintLine.create(view)`; `addHint(key, words)`, `setReading` |
| Toast | `Gui.Toast` | `Toast.create(view)`; `show(message, detail, tone, action)`; `sigAction` |
| Section label | `Gui.SectionLabel` | `SectionLabel.create(parent, text, rect)` wherever a group is labelled |
| Quiet menu | `Gui.IconButton` | `IconButton.createQuiet(parent, id)` and `setQuietText(words)` for a header's quiet text menu ("Name ▾") |
| Any other floating content | `Gui.FloatingPanel` | `FloatingPanel.create(parent, rect)` for a find bar, a transport, a list; the application places it; `setShadow(false)` when docked beside the work |

- **The floating components place themselves.** The dock, the sheet, the inspector, the hint
  line and the toast use `DockStyle.Float`: they take no room from the work and follow their
  parent through `IWnd.onLayout`. The mini-bar follows the selection through `showNear`.
- **Commands reach the lens by identifier.** `addCommand(family, id)` reads the label, glyph,
  shortcut, and disabled and hidden state from the owner's command routing each time the lens
  opens (the same `CommandStateEvent` a menu asks), and posts the command when it is chosen. Pass
  the family as a `MenuLabelResolver` so it follows the language. A command that cannot run now
  stays listed, faint.
- **Sources answer queries.** A `Lens.Provider` receives `*Lens.Results` and adds sections with
  `addSection(label, count)` and rows with `Section.addEntry(title)`. A row sets `lead`, `glyph`,
  `detail`, `monoTitle`, `monoDetail`, `checked`, `checkable`, `disabled`, and either `id` or
  `run`. `Lens.match(query, text)` is the ranking the lens uses. A section with `inline` shows an
  exclusive choice as one row of segments, and `addPicture` adds a strip of pictures such as
  recent documents.
- **The application binds the keys.** Register `Space`, `Ctrl K` and `I` with
  `registerKeyShortcut`, and open the lens, toggle the sheet or fold the inspector on those
  commands.
- **Use a toast** for a short confirmation of what the hand just did, or for a failure that needs
  no answer. Anything that needs an answer is a dialog.

### Put every command in the lens

The test is simple: **list the application's commands, open the lens, and find each one.** That
includes open, save, export, every view switch, go to, search, full screen, capture modes, recent
files, the library, options, the theme and the language, and About.

- A shortcut is shown at the end of its entry in faint mono, so the lens also teaches it.
- A context menu or a mini-bar may offer a subset for the selection. It never holds a command the
  lens lacks.
- An application that had a menu bar or a toolbar migrates by moving each item to the lens, to
  the mini-bar (if it applies to a selection) or to the sheet (if it is a reading). Nothing is
  deleted on the way.

## Word The Commands

Command labels use **title-style capitalization in the English reference strings**: menu items,
lens entries, button and dialog action captions, tab titles, tooltips that name a command, and
quick-style names.

- Capitalize every word except **articles** (a, an, the), **coordinating conjunctions** (and,
  but, or, nor, for, so, yet) and **prepositions of four letters or fewer** (as, at, by, for,
  from, in, into, of, off, on, onto, to, up, via, with), unless the word is first or last: "Add
  Cursor to Line Ends", "Save as Image…", "Open With…", "Show in Folder".
- **Sentences keep sentence case**: help text, descriptions, messages, notices, placeholders that
  are sentences, the words of the hint line, a dialog title that reports a situation.
- **Translations follow their own language.** French stays in sentence case ("Enregistrer comme
  image…").
- **An ellipsis `…` marks a command that asks for more before acting.** Use the single
  character, not three dots.

The same rule governs the toolkit's `Strings` and every application's reference table.

## Build The Standard Surface

- Take every colour from the theme's roles and every number from `ThemeMetrics`. Never invent an
  app-local accent, and never borrow a status colour for emphasis.
- **Selection is a ground.** Lists, menus, grids and property rows select with the Arc selection
  ground. A chosen thumbnail is ringed in Arc at a 2 px gap. Hover uses the raised ground. There
  is no rule or rail beside a row.
- Type follows [design-swag-themes](../design-swag-themes/SKILL.md#type): Inter for words, Roboto
  Mono for measures, large light figures for the facts a reader came for, and `Gui.SectionLabel`
  for every section label.
- **Separate a group by space first**, a fill second, and one hairline last. Never put a border,
  a rule and a fill around the same group.
- **No gradient** on an application surface. The only shading is the floating shadow, the dim
  behind the lens or a dialog, and a hover veil over a picture.
- **Nothing moves unprompted.** A mark that pulses, glows or loops at rest breaks the charter's
  Motion section. Only progress and activity move by themselves.
- Keep one dominant action per task area. Give destructive actions distance and explicit wording.
  Show progress where work is not immediate (an Arc line, a large light percentage), keep the
  keyboard focus, and keep failure text beside the operation that stopped.
- Level a glyph with the word beside it, not with the middle of its box. `Gui.opticalTop` levels
  a glyph with a line whose *box* is centred. `Pixel.Font.opticalLineTop` centres the line on its
  capitals, which is what a control drawing a frame around one line needs. Never hand-tune a
  padding to compensate for either.
- Design both themes together, check narrow and minimum-size layouts, and inspect a real native
  window rather than trusting constants alone.

## Lay Out Each Application

The charter's Applications section describes each application screen by screen, with one picture
per screen. Build to those pictures, and check the application's entry in
[design.silence.md](../../../backlog/design/design.silence.md) for what is known to differ. What
the four share:

- **Swag Scope**: the lens holds the viewers' commands, the sheet (`I`) holds the readings, and
  viewer controls stand on a floating bar. Explorer pages use a page title with quiet sort and
  view menus, and the cells take the shape of what the folder holds.
- **Swag Capture**: the editor composes the dock, the mini-bar, the inspector and the hint line.
  There are no menus. The charter's key table is the contract for its keys.
- **Swag Prism**: two columns parted by one hairline, with quiet text menus above each one and
  readings in the sheet.
- **Swag Vault**: a list of vaults under a page title, the live dot (`ThemeColors.live`) for a
  mounted vault and a soft ring for a locked one, and pages with a back link instead of tabs.

## Make Space Describe Relationships

This applies to application surfaces, shared controls and composites. Modal boxes keep the
measurements in [design-swag-dialogs](../design-swag-dialogs/SKILL.md).

- Identify the task groups before choosing their gaps. An icon and its label, a field and its
  help, or the actions on one object sit closer to each other than to the next group. Equivalent
  siblings get equal gaps, and a larger gap marks a change of task. Do not use a divider to make
  up for missing space.
- Take gaps from the charter's scale (4 · 8 · 12 · 16 · 20 · 24 · 32 · 48) through `ThemeMetrics`.
  Measure the *visible* gap after parent padding, child margins, cell bounds and internal control
  padding have all been applied.
- Measure a row of icon buttons from cell edge to cell edge. Centre glyphs in their cells, align
  labels on their text line, and align repeated rows by their content edges.
- At minimum width, with longer translations, and when optional controls hide, keep the order,
  the grouping and a usable target for every visible control. Let content wrap or adapt before
  allowing clipping or overlap.
- Review the real surface at normal and minimum sizes, in both themes and at a non-default
  display scale. Test the meaningful group boundaries, alignment, visibility and fit, so a later
  change cannot silently undo them.

## Offer Appearance And About Through The Lens

The theme (Dark, Light, System), the language and About are commands like any other: they are
lens entries, and nothing draws them on the window permanently. `Gui.AppearanceButton` is the one
owner of the choice, its persistence and its signals. A hidden appearance button keeps working
and takes no room. No application keeps a second theme picker or language combo.

- Register them with `appearanceButton.addToLens(lens)` once the lens exists. It answers with the
  themes and the languages (the choice in force checked), and with About when
  `sigAboutRequested` has a callback.
- Register the application string tables and every supported `Gui.Language` before the choices
  are first offered.
- Connect `sigAboutRequested` to one `Gui.AboutDlg.createApplication` box. Supply the product
  name, the compiler-derived version, the build date, the repository source URL and the
  copyright holder. The shared dialog supplies everything else (see
  [design-swag-dialogs](../design-swag-dialogs/SKILL.md#the-predefined-boxes)).
- Restore the persisted choices while the main window is still hidden, with `setAppearanceTheme`
  and `setAppearanceLanguage`. Persist `appearanceTheme` and `language` from `sigThemeChanged` and
  `sigLanguageChanged`. An empty language means follow the account, and `Gui.ReferenceLanguage`
  means English explicitly.
- The control applies the choice before it sends its signal. Use the signal only for persistence
  and for application-owned derived state. Do not apply the theme or language a second time.
- A language switch must retranslate text assigned at construction and re-run any layout that
  depends on that wording.

## Keep The Chrome Small And The Air Large

An oversized glyph reads as a toy: it fills its cell, crowds its neighbour, and forces every
surface around it to grow. The interface should read as an instrument at arm's length.

- **Interface icons are outline glyphs** (see
  [design-swag-identity](../design-swag-identity/SKILL.md#draw-the-interface-icons)), drawn in
  soft ink.
- **A glyph takes at most half of its cell.** The rest is what separates one control from the
  next. Take it away and the surface needs a border to show where a control ends.
- **Take every cell and glyph size from `ThemeMetrics`**: `menuPopup_IconSize` and
  `menuPopup_ItemHeight` for menu and list rows, `lens_RowHeight` for a lens row,
  `miniBar_ButtonSize`, `toolDock_CellSize` and `toolDock_Glyph`, `wnd_CaptionIconSize` for the
  window glyph, `corner_Chip` for swatches and chips. Inspect the real 16- and 18-pixel raster,
  not only the vector cell.
- **A checked icon button is Arc** (the selection ground, an Arc glyph, a faint Arc ring). This is
  the same in a row, the mini-bar and the dock, and the cell keeps its size in every state.
- **Do not stack a label under a glyph.** It doubles the height of every control and turns a
  toolbar into a ribbon. If a label is needed, put it beside the glyph.
- **Nothing sits against an edge.** The dock, the inspector and the sheet float
  `floating_Inset` from the window edges, and content keeps its reading margins.
- **Chrome shrinks to nothing so content grows.** At the window's minimum size, the work holds
  the whole surface, and the inspector folds to its edge tab.
- **A dense surface is not an efficient one.** A control shown at all times to set a preference,
  a second title above a panel that already names itself, a duplicated readout: each costs
  permanent room to save an occasional click. Move it to the lens, the sheet or the inspector.

## Let An Option Carry Its Own Wording

A check box or a switch already says what turning it on does. A name beside it repeats that
sentence, and a blank label above it reserves height for nothing.

- Add it with `Gui.FormLayoutCtrl.addOptionField`, which spends no line on a label.
- Put it under the field it qualifies, not at the bottom of the form.
- Give it a help paragraph when four words cannot say what it costs. Vault's options page is the
  pattern: a title, a help paragraph, an Arc switch.

## Ship A Feature In Every Language It Will Be Read In

French runs 15 to 25 % longer than English on ordinary interface text. **Check every shipped
language before calling a feature done**, at the window's declared minimum size.

- **Look at the picture in each language.** Keep the language-independent check
  `Testing.assertContentFits`, which fails when a window is arranged smaller than its content.
- **Assert the containment the generic check cannot see**, such as a block overflowing its
  parent, and run it over every entry of `Gui.languages()`. Swag Vault's `assertColumnFits` in
  `src/tests/mainwindow.test.swg` is the worked example.
- **Shorten the text before changing the layout.** If the wording is already as short as it can
  honestly be, fix the measurement rather than adding room.
- **Translate as you write.** A key added to the reference table but missing from
  `datas/lang/<tag>/*.tweak` silently falls back to English.

## Tell A Reader What Went Wrong, Not How

A message a reader sees is a plain sentence in their language, never a technical one. "The
capture file is damaged." is a message. "capture SCC has no document model chunk" is not.

- **No English prose in application sources outside the string tables.** Product names, legal
  notices, format identifiers a specification spells (`DT_NEEDED`) and protocol constants are not
  prose.
- **Errors carry an identity, not a sentence.** An error is a type or a kind plus data, and the
  presenter maps it to a sentence from the table (Swag Vault's `ErrorKind` and `kindMessage`,
  Swag Scope's `Viewer.failureText`). Raise with `fail volumeError(.Corrupted)`.
- **The technical part is a second line at most**, on a mono faint line under the sentence. In a
  dialog the failure takes the critical dot before its title. In a form it takes a critical ring
  and a critical-dot line under the field. In passing, a failure is a toast with a critical dot.
- **Developer diagnostics never reach a surface**, so they need no translation.

## Look At The Surface, Not Only At Its Assertions

Tests can read what a button says or whether a form can act. They cannot see a colour that
stopped reading, a control that lost its ground, or a row that drifted out of its column.
Photograph the window with `Gui.Testing.HeadlessHost`, and **judge the photograph as a whole
screen against the charter picture of the same surface, in both themes.**

Mark the test with `#[Swag.TestTag("golden")]`:

```swag
var host: Testing.HeadlessHost
let window = testSetupMainWindow(&host)
defer host.shutdown()

host.theme.setDark()                               // Encre; a second host shoots setLight() for Papier.
host.theme.metrics.surfaceWnd_ShadowSize   = 0     // No desktop under it: the shadow falls on
host.theme.metrics.surfaceWnd_CornerRadius = 0     // nothing and the corner punches holes.
host.notify(.ThemeChanged)
window.applyLayout()
host.settleAnimations(window, 6)

var image = host.render(window)
Pixel.Testing.assertImageGolden(&image, "surface.encre")
```

- **Use one host per theme, never one host repainted.** A render target keeps what the last
  paint left behind.
- **A theme change is not only an event.** `HeadlessHost.notify` reaches the styles that keep a
  private copy of the theme.
- **Commit one image per theme, at a bounded size.** Shoot at the window's minimum size, or at the
  region that changed, rather than dropping a theme. A floating component that is part of the
  change (the lens open, the sheet shown, the inspector unfolded) gets its own pair.
- **Shoot the window in its shipped frame**, with the strip, as the charter pictures show it.

## Keep The Workspace Shippable

- Keep every standard application in the `bin/apps` workspace, as
  `bin/apps/modules/<application>` with `module.swg`, `src/`, `src/tests/*.test.swg` and a
  root-level `datas/` for icons and other immutable resources. Test fixtures go in
  `src/tests/datas/`. Lay out tests as described in
  [modify-swag-codebase](../modify-swag-codebase/SKILL.md).
- Put a genuinely shared application helper directly under `bin/apps/modules`. Compile one
  application's viewers and optional backends into its own module. Do not create loadable plugin
  modules or a special build path in `tools/apps.swgs`.
- A module that normally emits a library selects an executable backend for `#test` when its
  tests must run natively.
- Put external components under `vendor/<product>/` inside the module, with their licence, and
  keep repository-level notices beside `module.swg` (version, origin, terms, filename
  normalization).
- Never commit generated `.dep`, `.output` or `.tmp` files, or copied compiler binaries.
- Keep a module README when setup, packaging, privileges or third-party deployment needs
  explaining. Add reusable entry points under `tools/`, with no personal absolute paths.
- `tools/apps.swgs` builds, tests, runs and smokes the workspace. Its positional name selects one
  application.

## Prove The Application

Apply [validate-swag-changes](../validate-swag-changes/SKILL.md) to each changed behaviour:

1. While iterating, run the owning test file:
   `swc tools/apps.swgs dm test <application> --test-file <name>.test.swg`.
2. Run the whole application's tests only when shared application state or several test families
   changed.
3. For a visible change, review **every** `.actual.png` the run left as a whole screen against its
   charter picture, in Encre and in Papier. Do not review only the diff or only the part you
   meant to change. A golden that changed in a part you did not touch is a finding. Promote each
   reviewed snapshot on its own by moving it over its golden. Never run
   `swc tools/goldens.swgs accept`, which promotes every snapshot on disk.
4. Build with `swc tools/apps.swgs dm build <application>` when module setup, linking, resources
   or packaging changed.
5. Run `swc tools/apps.swgs dm smoke <application>` when startup, the main loop or packaged
   runtime behaviour changed.
6. Run any dedicated integration tool that applies, such as `swc tools/vault.swgs dm` for Swag
   Vault and WinFsp. Keep tests that need UAC, drivers, hardware or visible interaction behind
   these tools.
7. When packaging changed, inspect the packaged output for the executable, its runtime
   dependencies, the icon and the licences, and check it carries no installer or test debris.

Finish by listing the application's commands and finding each one in the lens. Then search for
obsolete names and absolute paths, and reduce `git status` to the intended changes.
