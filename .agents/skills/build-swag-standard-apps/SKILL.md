---
name: build-swag-standard-apps
description: Build, migrate, rename, review, style, package, and test official Swag desktop applications under bin/apps to the Silence charter. Use whenever adding or changing an app shipped with the compiler, promoting an external Swag app into bin/apps, changing an official app name, icon or command wording, revising its window, its lens commands, its shared components (lens, sheet, inspector, mini-bar, dock) or its layout, or integrating its build, smoke, unit, golden, packaging, or privileged integration tests.
---

# Build Swag Standard Apps

Make every application recognizable as part of Swag before its title is read, and recognizable by
what it leaves out. The four standard applications — Swag Scope, Swag Capture, Swag Prism, Swag
Vault — follow one charter, **Silence**: [backlog/design/README.md](../../../backlog/design/README.md)
and its pictures in [backlog/design/imgs/](../../../backlog/design/imgs/). The window is the
document, the image, the list of vaults; everything else is asked for and then leaves. The pictures
are the visual target and the text states their rules; where the two disagree, the rule wins.

## Establish The Change

1. Read `../modify-swag-codebase/SKILL.md` and `../write-idiomatic-swag-code/SKILL.md`.
2. Read `../design-swag-identity/SKILL.md` (the six laws, the icon tile) and
   `../design-swag-themes/SKILL.md` (palettes, roles, measures, type, controls) before touching UI,
   color, layout, or icon assets; `../design-swag-dialogs/SKILL.md` before touching a modal box.
3. Open the charter pictures of the surface you change, in both themes, and keep them open.
4. Read `../write-swag-compiler-messages/SKILL.md` before changing visible English text, and
   *Word The Commands* below before changing a command label.
5. Read `../design-swag-bin-modules/SKILL.md` and `../write-swag-public-api-docs/SKILL.md`
   when a public `bin/` declaration changes.
6. Inspect the complete app, its tests, external resources, licenses, workspace scripts, generated
   artifact layout, and every repository reference before choosing the migration boundary.

## Make Standard Applications Language Showcases

An application shipped with the compiler is executable language documentation. Its source must
show how a substantial Swag program composes ownership, controls, callbacks, failure, and cleanup
without hiding those contracts behind framework ceremony.

- Make a main `create` function read as the ordered outline of the surface: initialize the root,
  create each named visual region, connect cross-region routing, register the lens commands, apply
  derived state, and return. When one region's construction and signal wiring interrupts that
  outline, move it to a private receiver method or give the region a real component type.
- Let each extracted construction method own one coherent visual region and its local callbacks.
  Name it for the thing it creates (`createDock`, `createReadingColumn`), not for a vague phase
  such as `setupUi`, `buildControls`, or `initializePart`.
- Do not split one window type across `*.layout.swg`, `*.events.swg`, or other aspect files to make
  a large file look smaller. Extract a component, model, operation, or lifecycle owner when it has
  a contract of its own; otherwise keep the receiver's methods in its type file, as required by
  `write-idiomatic-swag-code`.
- Use data-driven construction only for genuinely homogeneous repetitions whose data fully states
  their behavior, such as lens entries or a registry of equivalent choices. A short set of tools
  whose buttons have distinct fields, enablement, toggle rules, callbacks, and ownership is clearer
  as typed Swag code. Do not replace those contracts with identifiers, casts, callback switches, or
  a generic property bag merely to reduce line count.
- Treat precedent as evidence, not permission. Another standard application's long constructor or
  broad window type may be the same debt; compare contracts and improve the pattern instead of
  copying its shape.
- Prefer ordinary language features in the public example: typed fields, receiver methods, `with`
  construction, contextual conversion, direct returns, and scope-bound cleanup. Add a builder,
  declarative schema, or reflection layer only when it makes ownership and failure more explicit
  across several real consumers.
- Treat application work as a probe of `bin/std`. Start from the standard module that should own
  the interaction or presentation. If a clean implementation requires an app-local workaround,
  copied control behavior, access to internals, or repeated glue that other applications would
  also need, improve that module's public contract and tests first, then make the application its
  reference consumer. **The lens, the sheet, the inspector, the mini-bar and the dock are toolkit
  components; an application composes them and never re-implements one.** Do not preserve a weak
  standard API merely to keep the application diff local; do not generalize a product-specific
  policy that has no coherent module-level contract.
- Protect the composition at both boundaries: structural tests assert parentage, order, alignment,
  and visibility; a focused golden in each theme proves the resulting hierarchy reads correctly. A
  refactor of construction must preserve both unless the intended surface changes.

## Name The Product Once

- Give every shipped application a two-word display name: the family name `Swag`, followed by one
  concrete semantic word, as in `Swag Capture`, `Swag Vault`, and `Swag Scope`. Do not abbreviate
  the family to a lowercase prefix: the full word is the shared identity users can read.
- Make the semantic word vivid enough to suggest an action or an image while still saying what the
  product does. Prefer `Capture`, `Vault`, or `Scope` over padding such as `App`, `Tool`, `Studio`,
  or `Pro`.
- Before accepting a name, search exact and unprefixed spellings across current software products,
  platform features, package registries, and repositories. Reject a name dominated by an existing
  product or operating-system feature even when capitalization differs.
- Concatenate and lowercase the display words for technical identities: `swagcapture`, `swagvault`,
  and `swagscope`. Use that stem for the module directory, `BuildCfg.name`, executable, packaging
  directory, command-line module selector, registration key, and source URL. Use the spaced display
  name only for resources, titles, labels, prose, and other user-visible text.
- Prefer role-based private identities over either spelling: `capture.file.open`, `settings.scc`,
  and `Swag/Capture` survive a display-name change better than an identifier copied from a title.
  An API an application publishes to its own extensions uses the vocabulary of what it describes,
  such as `Viewer` for Swag Scope's viewer contract, rather than the host application's name.
- Treat published file extensions, format markers, cryptographic domain separators, and ABI names
  as migration decisions. Preserve them with an explicit compatibility contract when compatibility
  is required. When a caller explicitly requests a clean break, migrate the owned data, reset the
  format identity, and remove the obsolete spelling instead of leaving an alias behind.
  Keep namespaces UpperCamelCase and functions lowerCamelCase.
- Do not wrap private application code in a namespace that repeats the module or product name; the
  module already provides that boundary. Add a namespace only for a real subsystem vocabulary,
  and name it after that subsystem, such as `WinFsp`, rather than after the application.
- Never put spaces, `_`, or uppercase letters in an app-owned folder or file name. Concatenate the words of
  one symbol or indivisible concept, and use dots between the named parts of a coherent file
  family, such as `app.operations.swg`, or `abi.win32.swg` and `callbacks.test.swg` inside a
  `winfsp/` directory. Platform and test suffixes use this notation but do not reserve it.
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
   borders, and generic shields or sparkles. The master stays square; a surface that shows the
   tile rounded (About, corner 12) clips it there.
5. Run `scripts/package_app_icon.py` to flatten the generated master and derive the PNG and
   multi-resolution ICO:

   ```powershell
   py -3 .agents/skills/build-swag-standard-apps/scripts/package_app_icon.py `
       generated-master.png `
       --png bin/apps/modules/<application>/datas/appicon.png `
       --ico bin/apps/modules/<application>/datas/appicon.ico
   ```

6. Set `BuildCfg.resAppIcoFileName` in `module.swg`, using a path relative to the module folder.
   Decode `appicon.png`, pass it to `Application.setAppIcon` before creating the first surface,
   and reuse it for product-specific icon placements.
7. **The tile is for the desktop; the window carries the glyph.** The two-colour tile is what the
   taskbar, the task switcher and the About box show. Inside the window the glyph is drawn
   **monochrome**, in the soft colour at about 55 % opacity, 18 px at (18, 16) — a quiet signature
   in the corner, not a block of brand at the top of the work. `setAppIcon` feeds both; the toolkit
   draws the window glyph, so never place or tint it by hand. That is also why the master must be
   exactly the two declared colours: the window lifts the glyph off its ink ground, and a mark cut
   from a third colour comes off wrong.
8. Inspect the PNG and the 16, 32, 48, and 256 pixel ICO entries, and the monochrome glyph in the
   window in both themes. Regenerate the glyph when its negative space closes or its product
   meaning disappears; do not repair a weak concept with text.

## Leave The Window To The Work

The six laws of the charter, as they bind an application (the reasons are in
[design-swag-identity](../design-swag-identity/SKILL.md#the-gui-follows-silence)):

1. **Nothing on screen but the work.** No permanent toolbar, menu bar, status bar, ribbon, side
   panel, information band or options band. The window is the document.
2. **Information is asked for.** Readings, outlines, metadata and settings appear on a key, a
   hover or a selection, then leave. They are never removed from the product: they move behind a
   gesture — the sheet, the inspector, the lens, a hover veil.
3. **One door.** `Space` (or `Ctrl K` where Space types text) opens the lens, and **every command
   of the application is reachable from it.**
4. **One accent at a time.** Voltage acts, Arc chooses; see
   [design-swag-themes](../design-swag-themes/SKILL.md#voltage-acts-arc-chooses).
5. **Air is a material.** Measured columns, reading margins, nothing flush with an edge, nothing
   boxed that space can separate.
6. **The default theme carries the hand.** An application starts on Encre and offers Dark, Light
   and System. It never invents an app-local accent; a different look is a theme sheet of its own,
   layered on top — see [design-swag-themes](../design-swag-themes/SKILL.md#theme-sheets).

### The window chrome

[`scope.read`](../../../backlog/design/imgs/scope.read.png) is the reference.

- **No caption band, no menu bar, no accent rail, no caption glow, no status bar.** The toolkit's
  `SurfaceWnd` draws the chrome; an application adds nothing to it.
- **The top 52 px belong to the content and are draggable** wherever no control sits;
  double-click maximizes. Content may start there; a control placed there stays clickable.
  The view of an application window takes the whole body and the strip
  (`ThemeMetrics.wnd_StripHeight`) floats over it; `SurfaceWnd.hitTestCaption` drags the
  window over the strip's ground and over content passing under it, and leaves its clicks to a
  control lying within the strip (a window that takes the focus, a button, a menu-bar entry). A
  part that must keep clear of the glyph, the title and the window buttons — a band of controls, a
  page header, a form — insets its top by `Wnd.stripInset()`, read in its resize handler (the view
  is resized whenever the strip appears or goes, as in full screen); a document, an image or a
  list scrolled under the title ignores it. `SurfaceWnd.stripHeight()` gives the strip itself.
- **The application glyph** sits at (18, 16), 18 px, about 55 % opacity, monochrome soft.
- **The document's name** is centred at the top, 12 px, faint. Nothing else is written there.
- **The window buttons** are faint glyphs at the top right; they reach full contrast on hover.
- **Position is a thread, not a scrollbar.** A document shows where the reader is with a 1 px
  thread on the right edge and a short mark; a thin 6 px scrollbar appears while scrolling or on
  hover.
- **The hint line.** A faint line — the `Space` keycap and what it opens ("Space — everything
  else", "Space — capture, open, library") — may sit 24 px above the bottom edge while the reader
  is new to the window or the surface is empty. A faint mono reading of the canvas (size, zoom)
  may share that line, as Capture's does; it is text on the ground, not a bar. It is
  `Gui.HintLine`: `HintLine.create(view)`, `.addHint(strings().key_Space, words)`,
  `.setReading(text)`; hide it once the door is known.

### Compose the shared components

Five floating components replace every band and panel an application used to keep on screen. Each
is a toolkit control; the application supplies its content.

The toolkit types, all in `bin/std/modules/gui` (`controls/lens` and `controls/floating`), shown
together on the Components page of `gui10`:

| Component | Type | The application calls |
| --- | --- | --- |
| Lens | `Gui.Lens.View` | `Lens.View.create(owner)`; `addCommands(family, ids)` for every command; `addSource(prefix, provider)` for lines, files, symbols, recent items; `open(query)` from its key |
| Sheet | `Gui.InfoSheet` | `InfoSheet.create(view)`; `setTitle`, `setIdentity`, `addFact`, `addReading`, `addSection`, `addText`, `addLink`, `setAction`, `clear`; `toggle()` on `I` |
| Inspector | `Gui.Inspector` | `Inspector.create(view)`; `setTitle(title, detail)`, `addAction`, `addSection`, `addRow(label, editor, fill)`, `addWideRow`, `clear`; `toggleFolded()` on its key |
| Mini-bar | `Gui.MiniBar` | `MiniBar.create(canvas)`; `addButton`, `addTextButton`, `addItem`, `addSeparator`; `showNear(selection)` when the selection moves, `hide()` when it goes |
| Dock | `Gui.ToolDock` | `ToolDock.create(view)`; `addTool(icon, id, toolTip)`; `setActiveTool`; `sigToolChanged` |
| Hint line | `Gui.HintLine` | `HintLine.create(view)`; `addHint(key, words)`, `setReading` |

- **The floating ones place themselves.** The dock, the sheet, the inspector, the hint line and the
  lens take `DockStyle.Float`: they take no room from the work, and they follow their parent
  through `IWnd.onLayout` each time it arranges its children. The mini-bar follows the selection,
  so the application places it with `showNear`.
- **Commands reach the lens by identifier.** `addCommand(family, id)` reads the label, glyph,
  shortcut, disabled and hidden state from the owner's command routing each time the lens opens —
  the same `CommandStateEvent` a menu asks — and posts the command when it is chosen. Pass the
  family as a `MenuLabelResolver` (`func()->string => appStrings().lens_File`) so it follows the
  language. A command the lens lacks is a command the reader cannot discover.
- **Sources answer queries.** A `Lens.Provider` receives `*Lens.Results` (its `query` without the
  prefix, and the `prefix`), adds sections with `addSection(label, count)` and rows with
  `Section.addEntry(title)`; a row sets `lead` (a line number), `glyph`, `detail`, `monoTitle`,
  `monoDetail`, and either `id` or `run`. `Lens.match(query, text)` is the ranking and marking the
  lens uses; a source that leaves `spans` empty gets its rows marked by the lens. A source answers
  the unprefixed query and the one of its `Lens.Prefix` (`:` `Line`, `/` `File`); commands answer
  the unprefixed query and `>`.
- **The application binds the keys.** Register `Space` (or `Ctrl K` where Space types) and `I` with
  `registerKeyShortcut` and open the lens, toggle the sheet or fold the inspector on those
  commands. Typing in the lens never reaches the shortcuts of the window behind it.

- **Lens** — [`scope.lens.paper`](../../../backlog/design/imgs/scope.lens.paper.png). Opened by
  `Space` (`Ctrl K` where Space types). 600–640 wide, near the top third, surface, corner 12,
  floating shadow; the document behind dims to about 16 % with a slight blur. A 64 px input with
  22 px light text and the faint `Esc` hint at its right; results grouped under section labels (in
  this file · count, symbol, open, view as, commands by family — set as uppercase section labels); rows of 38–40 px with a leading
  glyph or number, matched characters in the highlight colour, a faint trailing reading (a line, a
  path), the chosen row on the Arc selection ground with `⏎` at its end. A view switch may appear
  inline as text tabs. A footer lists the keys: `↑↓` choose, `⏎` go, `Tab` view as, and the
  prefixes `:` line, `/` files, `>` actions. `Esc` closes.
- **Sheet** (`I`) — [`scope.explorer`](../../../backlog/design/imgs/scope.explorer.png). A
  floating panel 300–360 wide, inset 24 from the window edges, surface, corner 12. Title 21/800, a
  mono line of identity, large light figures for facts, at most one primary action, links in Arc,
  sources at the bottom. It holds the readings an information band used to show.
- **Inspector** — [`capture.edit.arrow`](../../../backlog/design/imgs/capture.edit.arrow.png). The
  sheet's shape docked at the right, 304 wide, carrying a property grid: section labels, rows of a
  label (88) and an editor at the inspector height (28), no border around an individual setting.
  It folds to an edge tab ("Properties · I") so the work takes the full width.
- **Mini-bar** — [`capture.annotate`](../../../backlog/design/imgs/capture.annotate.png). A
  floating toolbar placed next to the selected object: 4 px padding, corner 8, surface, floating
  shadow, 28 px buttons, separators of 1 × 16. It carries only what applies to the selection, and
  `•••` opens the inspector.
- **Dock** — a vertical floating tool column at the left edge, vertically centred: surface,
  corner 10, 6 px padding, 36 px cells, glyphs 18. The active tool sits on the Arc selection ground
  with an Arc glyph. When the current tool is a mode the window is in, the dock is where Voltage
  may mark it — one mark, never a rail.

### Put every command in the lens

The lens is the one door, so the test of an application is simple: **list its commands, open the
lens, and find each one.** Open, save, export, every view switch, go to, search, full screen,
capture modes, recent files, the library, options, the theme and language, About — all are lens
entries. A command that exists only on a button, a context menu or a shortcut is a command the
reader cannot discover.

- A shortcut is shown beside its entry, in mono faint, so the lens also teaches it.
- A context menu or a mini-bar may offer a subset for the selection; it never holds a command the
  lens lacks.
- An application that had a menu bar or a toolbar migrates by moving each item to the lens, the
  mini-bar (if it applies to a selection) or the sheet (if it is a reading). Nothing is deleted on
  the way.

## Word The Commands

Command labels use **title-style capitalization in the English reference strings**: menu items,
lens entries, push-button and dialog action captions, tab titles, tooltips that name a command,
and quick-style or command names. A command is a name the reader picks from a set, and the set
reads as one family when every member is set the same way.

- Capitalize every word except **articles** (a, an, the), **coordinating conjunctions** (and, but,
  or, nor, for, so, yet) and **prepositions of four letters or fewer** (as, at, by, for, from, in,
  into, of, off, on, onto, to, up, via, with) — unless that word is the first or the last:
  "Add Cursor to Line Ends", "Save as Image…", "Open With…", "Show in Folder".
- **Sentences keep sentence case**: help text, descriptions, messages, notices, placeholders that
  are sentences, the hint line's description, a dialog title that reports a situation.
- **Translations follow their own language.** French stays in sentence case ("Enregistrer comme
  image…"). The rule is a property of the English reference table, not of the layout.
- **An ellipsis `…` marks a command that asks for more before acting** ("Open…", "Save as
  Image…"); a command that acts at once has none. Use the single character, not three dots.

The same rule governs the toolkit's own `Strings` and every application's reference table; check
both when a label is added.

## Build The Standard Surface

- Take every colour from the theme's roles and every number from `ThemeMetrics`; see
  [design-swag-themes](../design-swag-themes/SKILL.md). Never invent an app-local accent, and never
  borrow a status colour for emphasis: Swag Capture once dressed its Library button in the
  information notice palette, which said "notice" where nothing was being reported.
- **One accent at a time.** One primary action per surface (Voltage on Encre, ink on Papier); what
  is chosen — a row, a thumbnail, a tool, a tab — is Arc. Never Voltage text on Papier, never a row
  washed in Voltage, never a Voltage rail or band.
- **Lists, menus, popups, grids and property rows select with their ground**: the Arc selection
  ground, a chosen thumbnail ringed in Arc. Hover uses the raised ground. A stored value may add a
  `✓` in Arc. No rule or rail beside a row.
- Inter for words, Roboto Mono for every measure — offsets, sizes, counts, durations, paths, dates,
  hex values. Page titles 34–56/800; section labels small, uppercase, faint; a fact the reader came
  for large and light (Inter 200–300). See [design-swag-themes](../design-swag-themes/SKILL.md#type).
- **Separate a group by space first.** Whitespace is the first tool, a raised or surface fill the
  second, one hairline the last. Every border and every divider is one more line a reader has to
  step over; never put a border, a rule and a fill around the same group, and never box what
  space can separate.
- **Radii and shadows are measured.** Window 10, floating surfaces 12, menus 10, controls 6, chips
  4–5; a shadow only under a floating surface. Take them from the theme, never from a literal.
- **No gradient** on an application surface. The only shading is the floating shadow, the dim
  behind the lens or a dialog, and a hover veil that keeps text legible over a picture (Scope's
  video). See the gradient clause in [design-swag-identity](../design-swag-identity/SKILL.md).
- Keep one dominant action per task area. Give destructive actions distance and explicit wording.
  Show progress where work is not immediate (an Arc line, a large light percentage), preserve
  keyboard focus, and keep failure text beside the operation that stopped.
- Level a glyph with the word beside it, not with the middle of the box around it. A line box
  reaches from the ascender to the descender while a word is read on its capitals, and the gap
  between those two middles belongs to the face, so a glyph centered on the cell reads as having
  slipped off its label. Two places own that rule and there is never a third: `Gui.opticalTop`
  levels a glyph with a line whose *box* is centered, and `Pixel.Font.opticalLineTop` centers the
  line on its capitals instead — which is what a control drawing a frame around one line does, so
  that the same field reads the same whichever family it is set in. Never hand-tune a padding to
  compensate for either.
- Design both themes together, verify narrow and minimum-size layouts, and inspect a real native
  surface rather than trusting constants alone.

## Lay Out Each Application

The per-application rules of the charter. Every application follows the window chrome above, puts
its commands in the lens, and leaves the screen to its work.

### Swag Scope

- **Reading** ([scope.read](../../../backlog/design/imgs/scope.read.png)): the document in a
  centred reading column (~900 for code, ~640 for prose), faint line numbers, the position thread,
  the name at the top. Search, open, explore, view switch, go to, full screen and options are lens
  entries; readings — encoding, lines, size, outline — are in the sheet (`I`). There is no action
  bar, information band or options band.
- **Explorer** ([scope.explorer](../../../backlog/design/imgs/scope.explorer.png)): a page title
  (the folder name, 44–56/800) under its path as a faint breadcrumb, a mono count, quiet sort and
  view menus (`▾`), a contact-sheet grid with names and mono metadata, the chosen item ringed in
  Arc, and the sheet for the chosen item.
- **Video** ([scope.video](../../../backlog/design/imgs/scope.video.png)): the picture edge to edge;
  on hover a top veil with the title and a bottom veil with the timeline (Arc progress, white knob,
  chapter ticks, hover time), time in mono, chips for subtitles, audio and speed.
- **Markdown** ([scope.markdown.paper](../../../backlog/design/imgs/scope.markdown.paper.png)): a
  reading column, the table of contents in the left margin when the window is wide (active entry
  with an Arc left rule), reading progress as an Arc thread on the top edge.
- **Hex** ([scope.hex](../../../backlog/design/imgs/scope.hex.png)): structure as text tabs, an
  airy grid, Arc selection, a Voltage cursor byte, a floating inspector with the value under the
  cursor in large type.
- **Font** ([scope.font.paper](../../../backlog/design/imgs/scope.font.paper.png)): a large
  specimen, the family name, style tabs, a glyph grid with the chosen glyph on the Arc ground, a
  sample field and sizes with mono labels.

### Swag Capture

- **Editor** ([capture.annotate](../../../backlog/design/imgs/capture.annotate.png)): the capture on
  the ground, the dock of tools at the left, the mini-bar next to the selection, the inspector at
  the right (foldable). There are no menus: every command is in the lens, including capture modes,
  recent captures and the library. Canvas selection handles are Arc.
- **Area capture** ([capture.area](../../../backlog/design/imgs/capture.area.png)): the screen
  dimmed except the chosen zone, a 1 px Voltage edge, its size in a mono chip, a pixel loupe with a
  Voltage crosshair, the modes as text tabs on a floating bar.
- **Library** ([capture.library](../../../backlog/design/imgs/capture.library.png)): a page title,
  folders as text tabs with mono counts, tags as chips (chosen in Arc), a grid of captures, rating
  and dates in mono.
- **Shape editing, per kind**: arrow (curve handles, start and end glyph pickers, sizes), callout
  (inline text, tail handle, font, size and style "Aa" segments), masks (image, blur, pixelation,
  magnifier, capture as a radio list), step numbers (mini-bar with a number stepper and reset),
  multiple selection (common settings, align, arrange, group), the colour popover (recent, palette,
  exact value, opacity) and quick styles. Each has its picture under `capture.edit.*`.

### Swag Prism

- **Columns** ([prism.columns.paper](../../../backlog/design/imgs/prism.columns.paper.png)): two
  columns separated by one hairline — source and output; their settings are quiet text menus above
  each column (view, stage, optimisation level); compile with `Ctrl ⏎`; the compile time in mono at
  the bottom right. No frame around a pane.
- **Stages** ([prism.stages.paper](../../../backlog/design/imgs/prism.stages.paper.png)): a frieze
  of dots browsed with `← →`, the change since the previous stage shown as struck-out and
  Arc-marked lines, with counts in a margin.
- **Comparison** ([prism.compare](../../../backlog/design/imgs/prism.compare.png)): two outputs with
  their instruction counts in large light type and the gain in Arc; the loop marked by an Arc left
  rule in both.
- **2D render** ([prism.render](../../../backlog/design/imgs/prism.render.png)): source left, the
  image right, live statistics in mono, the live-edit switch.

### Swag Vault

- **List** ([vault.list](../../../backlog/design/imgs/vault.list.png)): the window is a list of
  vaults under a page title — name 20/600, a mono identity line, a state dot (mounted: green;
  locked: a ring). The mounted row may carry its own quiet action at its right. Choosing a locked
  vault unfolds it in place ([vault.unlock.paper](../../../backlog/design/imgs/vault.unlock.paper.png)):
  password, drive, a key-files link, read-only, and the primary "Mount". With privacy mode on, the
  list stays empty and vaults open through the lens.
- **Create, progress, options** are pages with a back link, not tabs: a calm form with the capacity
  in large type ([vault.create.paper](../../../backlog/design/imgs/vault.create.paper.png)); the
  randomisation progress as a huge percentage over an Arc line
  ([vault.progress](../../../backlog/design/imgs/vault.progress.png)); options as rows with a title,
  a help paragraph and an Arc switch ([vault.options](../../../backlog/design/imgs/vault.options.png)).

TODO(silence): name the theme part that carries Vault's mounted-state green once design.silence.010 lands; until then it must still come from the theme, not a literal.

## Make Space Describe Relationships

Apply this rule to application surfaces, shared controls, and composites; modal boxes retain the
measurements in [design-swag-dialogs](../design-swag-dialogs/SKILL.md). Carbon's
[spacing guidance](https://carbondesignsystem.com/building-blocks/foundations/spacing/overview)
and [relationship examples](https://v10.carbondesignsystem.com/guidelines/spacing/overview/)
explain why proximity, repetition, and alignment make a hierarchy legible.

- Identify the task groups before choosing their gaps. Keep an icon and its label, a field and its
  help, or actions on the same object closer to each other than to the next independent group.
  Give equivalent siblings equal gaps; use a larger gap to mark a change of task. Do not use a
  divider merely to compensate for missing space.
- Take gaps from the charter's scale — 4 · 8 · 12 · 16 · 20 · 24 · 32 · 48 — through
  `ThemeMetrics`: 4 for a tight internal relationship, 8 between related controls, 16 between
  groups or body pieces, 24 to 48 for major sections and outer breathing room. These are starting
  points, not additive margins: measure the visible gap after parent padding, child margins, cell
  bounds and any internal control padding have all been applied.
- A row of icon buttons is measured from cell edge to cell edge; the empty area inside each cell
  already separates its glyph from the next. Center glyphs in their cells, align labels on their
  text line using the shared optical rules, and align repeated rows and columns by their content
  edges. Do not fix an optical mismatch by moving one control's arbitrary margin.
- At minimum width, with longer translations, and when optional controls hide, preserve order,
  grouping and a usable target for every visible control. Collapse a gap belonging to a hidden
  group, not the space needed by its remaining neighbours. Measure content and let it wrap or
  adapt before allowing clipping or overlaps.
- Review the actual surface at normal and minimum sizes, in both themes and at a non-default
  display scale. Compare visual gaps and baselines as well as widget rectangles; test meaningful
  group boundaries, alignment, visibility and fit so a later layout change cannot silently undo
  them. Review shared controls in their consumers as well as in isolation.

## Offer Appearance And About Through The Lens

Every standard application lets the reader choose the theme (Dark, Light, System) and the language,
and opens one About box. Those are commands like any other: they are lens entries, and nothing
draws them permanently on the window. `Gui.AppearanceButton` remains the one owner of the choice,
its persistence and its signals; no application keeps a second theme picker, language combo,
property-grid row or options entry for them.

Register them with `appearanceButton.addToLens(lens)` once the lens exists: it adds a source that
answers with the themes under the theme label, the languages under the language label (the choice
in force checked) and About under the application label when `sigAboutRequested` has a callback,
each row applying its choice exactly as the button's own options do.

- Register the application string tables and every supported `Gui.Language` before the choices
  are first offered, so the language list is complete.
- Offer Dark, Light and System, and every registered language plus the system-language choice.
- Connect `sigAboutRequested` and open one `Gui.AboutDlg.createApplication` box. Supply the product
  name, compiler-derived application version, build date, repository source URL, and copyright
  holder; the shared dialog supplies the tile, wording, links, spacing, and fit (see
  [design-swag-dialogs](../design-swag-dialogs/SKILL.md#the-predefined-boxes)).
- Restore the persisted choices while the main window is still hidden with
  `setAppearanceTheme` and `setAppearanceLanguage`. Persist `appearanceTheme` and `language` from
  `sigThemeChanged` and `sigLanguageChanged`; an empty language means follow the account, while
  `Gui.ReferenceLanguage` means explicitly use English.
- The control applies the choice and sends the application notification before its signal. Use the
  signal only for persistence and for application-owned derived state such as cached artwork; do
  not apply the theme or language a second time.
- A language switch must retranslate text assigned at construction and re-run any layout whose
  measurements depend on that wording. Test the lens entries, both themes, the system choice,
  every language the application ships, and the About box through its normal Close action.

## Keep The Chrome Small And The Air Large

A Swag application is quiet, and quiet is mostly a question of size. An oversized glyph reads as a
toy: it fills its cell, it crowds its neighbour, and it forces every surface around it to grow to
hold it. The interface must read as an instrument at arm's length, never as a touch launcher.

- **Interface icons are outline glyphs** on a 16 grid, 1.4 stroke, round caps and joins, no fill
  except a deliberate dot or play triangle, drawn in soft. A filled or two-tone icon is louder than
  the word beside it.
- **A glyph takes at most half of its cell.** The rest is not spare room to reclaim; it is what
  separates one control from the next. Take it back and the surface immediately needs a border to
  say where a control ends.
- **One glyph carries one sign.** Combining a sun with a globe or a folder with a status badge
  makes two unreadable miniatures, not one informative icon. Choose the dominant concept, let the
  tooltip name the complete command, and keep shared nouns on shared geometry: every folder action
  starts from the same folder silhouette, every directional action from the same arrow weight.
  Inspect the actual 16- and 18-pixel raster, not only the vector cell.
- **Use one size table for the whole family.** These are logical pixels, from the charter.

  | Placement | Glyph | Cell |
  | --- | --- | --- |
  | Menu entry, list row, tree row | 16 | row 30 |
  | Lens row | 16 | row 38–40 |
  | Icon button | 16 | 32 |
  | Mini-bar button | 16 | 28 |
  | Dock cell | 18–20 | 36 |
  | Window glyph | 18 | — |
  | Swatch, chip | — | corner 4–5 |
  | State or changed-value dot | — | 6–8 |

- **A checked icon button is Arc**: the Arc selection ground, an Arc glyph, a faint Arc ring — the
  same in a horizontal row, the mini-bar and the dock. No underline, no leading rule, and the cell
  keeps its size in every state so nothing moves when it is checked.
- **Do not stack a label under a glyph.** It doubles the height of every control to carry a word
  the tooltip already carries, and turns a toolbar into a ribbon. A label belongs beside the glyph
  when it is needed at all, on the same line and starting right after it.
- **Nothing sits against an edge.** A glyph flush with the window edge and a label flush with the
  other side is not a dense surface, it is an unfinished one. The dock, the inspector and the sheet
  float inset from the window; content keeps its reading margins.
- **Chrome shrinks to nothing so content grows.** At the window's declared minimum size, the work
  holds the whole surface; the floating components cover it only while they are asked for, and the
  inspector folds to its edge tab.
- **A dense surface is not an efficient one.** A control present at all times to set a preference,
  a second title above a panel that already announces itself, a duplicated readout — each costs
  permanent room and buys one occasional click. Move it to the lens, the sheet or the inspector,
  and give the space to the work.

## Let An Option Carry Its Own Wording

A form is a column of named fields, and an option is not one of them. A check box or a switch
already says what turning it on does, so a name beside it repeats the sentence the control carries
and a blank label above it reserves the height of a name that is not there — which reads as the
option having drifted away from the field it qualifies.

- Add it with [[Gui.FormLayoutCtrl.addOptionField]], which leaves the label empty and spends
  no line on it. The control then lines up with the fields, which is where the reader is already
  looking.
- Put it under the field it qualifies, not at the bottom of the form. An option about what a drive
  *will be* belongs under the letter it takes, not beside the password that opened it.
- Give it the same help paragraph a field gets when what it does is not obvious from four words.
  The wording on the control says what it is; the paragraph says what it costs. Vault's options
  page is the pattern: a title, a help paragraph, an Arc switch.

## Ship A Feature In Every Language It Will Be Read In

A feature that puts words on a surface is not finished when it works in English. The wording is
part of the layout, and a translation is longer — French runs 15 to 25 percent longer than English
on ordinary interface prose, and one sentence in ten needs a whole extra line. **Check every
shipped language before calling the feature done**, and check it at the window's declared minimum
size, which is the width the text has least room in.

- **Look at the picture, in each language.** An assertion cannot see a label cut in half or a help
  paragraph missing its last line. Render the surface headlessly per language while reviewing by
  hand, and keep the one language-independent assertion the module already has — see
  `Testing.assertContentFits`, which fails when a window is arranged smaller than its content.
- **Assert the containment the check cannot infer.** `assertContentFits` compares a window against
  its own measure, so a part sized by that same measure always "fits" itself. What breaks is a part
  overflowing its parent, and no generic check sees it: a block whose height comes from a grid row
  does not grow for a longer form, it clips it. Write that comparison down for each block the
  feature touches — Swag Vault's `assertFormEndsInsideCard` is the worked example — and run it over
  every entry of `Gui.languages()`.
- **Prefer adapting the text to adapting the interface.** Shortening a sentence is one edit in two
  files and costs nothing; reflowing a layout changes it for every language including the ones that
  were fine. Say the same thing in fewer words first. Only when the wording is already as short as
  it can honestly get is it the layout's turn — and then fix the measurement rather than adding
  room: a height that has to be re-tuned per language is a height that was authored where it
  should have been measured.
- **Translate at the same time as you write.** A key added to the reference table and left out of
  `datas/lang/<tag>/*.tweak` silently falls back to English, so the feature ships half translated
  and nothing reports it. The `#run` validation catches a mistyped key, never a missing one. The
  English entry follows *Word The Commands*; the translation follows its own language.

## Tell A Reader What Went Wrong, Not How

A message a reader sees is a plain sentence in their language, never a technical one. "The
capture file is damaged." is a message; "capture SCC has no document model chunk", "CreateDIBSection
failed", or an NTSTATUS is not. This is a golden rule of the showcase applications.

- **No English prose in application sources outside the string tables.** Every sentence a surface
  can show comes from the application's reference table and its `datas/lang/<tag>/*.tweak`
  translations. Product names, the author, legal notices, format identifiers that a specification
  spells (`DT_NEEDED`, `Note On`), and protocol constants are not prose and stay as written.
- **Errors carry an identity, not a sentence.** An error the application raises is a type or an
  error kind plus data — a native code, `#callerlocation` — and no message text. The presenter maps
  that identity to a friendly sentence from the table (Swag Vault's `ErrorKind` and `kindMessage`,
  Swag Scope's `Viewer.failureText`). Raise with `fail volumeError(.Corrupted)`, not with a
  sentence.
- **The technical part is a second line, at most.** When it helps a report, show it under the
  sentence on a mono faint line: an error code (`Error code: 0x%{X}`, itself a table entry) or the
  detail the system or a decoder gave. It never replaces the sentence, and an error without a
  detail adds nothing. In a dialog the failure takes the critical dot before its title; in a form,
  a critical ring and a critical-dot line under the field.
- **Developer diagnostics stay out of the reader's way.** Debugger logs, integration-harness
  reports, and traces written only under a test tag are for whoever reads a report; they never
  reach a surface, so they need no translation.

## Look At The Surface, Not Only At Its Assertions

An application's tests read its window — what a button says, whether a form can act, whether the
layout survives a language. None of that can see it. A color that stopped reading, a control that
lost its ground, a row that drifted out of its column: an assertion never catches any of it,
because nothing about it is wrong enough to fail.

Photograph the window instead, and **judge the photograph against the charter picture of the same
surface, in both themes**. `Gui.Testing.HeadlessHost` renders a real window tree without a desktop,
so the picture costs a test rather than a screenshot session — and it keeps working when the
desktop is unavailable, which is exactly when a screenshot session is not.

Mark the enclosing test with `#[Swag.TestTag("golden")]`. This includes the application snapshot
in the repository-wide golden campaign independently of its filename or assertion helper.

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

Three things this gets wrong if they are not said:

- **One host per theme, never one host repainted.** A render target keeps what the last paint
  left, and a fill the theme makes translucent then composites over the theme before it. Two of
  four images came out that way once, and they were wrong in the direction that reads as a defect
  of the palette rather than of the harness.
- **A theme change is not only an event.** A style carrying a font or a sheet keeps a private copy
  of the theme it was computed against, and `Application.notifyThemeChanged` walks the surfaces the
  application created — not the one a headless host builds by hand. `HeadlessHost.notify` is what
  reaches it.
- **Commit one image per theme, at a bounded size.** The charter judges every surface in Encre and
  in Papier, so a surface has a golden in each. A full repaint of a large surface is minutes on the
  default configuration; shoot at the window's declared minimum size, or the region that changed,
  rather than dropping a theme. A floating component (the lens open, the sheet shown, the inspector
  unfolded) that is part of the change gets its own pair.

## Keep The Workspace Shippable

- Keep every standard application in the single `bin/apps` workspace. Put its executable module in
  `bin/apps/modules/<application>` with `module.swg`, `src/`, `src/tests/*.test.swg`, and a root-level
  `datas/` for icons and other immutable app resources. That root-level `datas/` is what the running
  program loads, and it never moves under `src/`; the fixtures a test reads are a separate folder,
  `src/tests/datas/`. An application module lays its tests out exactly like a `bin/std` one — see
  *Lay Out A Module's Tests The Same Way Every Time* in
  [modify-swag-codebase](../modify-swag-codebase/SKILL.md).
- Put a genuine shared application helper directly under `bin/apps/modules` as a normal workspace
  module. Compile one application's format viewers and optional backends into that application's
  module unless another shipped application imports the same contract; do not create loadable
  plugin modules or a special standalone build in `tools/apps.swgs`.
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
- Make `tools/apps.swgs` build, test, run, or smoke the shared applications workspace. Its positional
  name selects one application module. Package runtime dependencies after a
  normal workspace build when the executable is not functional without them.

## Prove The Application

Apply [validate-swag-changes](../validate-swag-changes/SKILL.md) to each changed behavior:

1. During iteration, run the owning test file with
   `swc tools/apps.swgs dm test <application> --test-file <name>.test.swg`.
2. Run the whole application's tests only when shared application state or several test families
   changed.
3. For a visible change, review the application's goldens in Encre and in Papier against the
   charter picture of the surface; a golden that changed for a part not touched is a finding.
4. Build with `swc tools/apps.swgs dm build <application>` when module setup, linking, resources,
   packaging, or shipped output changed.
5. Run `swc tools/apps.swgs dm smoke <application>` when startup, the main loop, or packaged
   runtime behavior changed.
6. Run any affected dedicated integration tool, such as `swc tools/vault.swgs dm` for Swag
   Vault and WinFsp. Keep tests that need UAC, drivers, hardware, or visible interaction behind
   these explicit tools; the ordinary aggregate suite must not prompt for privileges.
7. Inspect packaged output for the executable, runtime dependencies, icon, licenses, and absence
   of installer or test debris when packaging changed.

Finish by listing the application's commands and finding each one in the lens, searching for
obsolete names and absolute paths, inspecting ignored `.output` folders under test trees, and
reducing `git status` to intentional source and asset changes.
