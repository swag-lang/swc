# Silence migration

Every entry moves part of `bin/` to the charter in [README.md](README.md). The order is the
dependency order: themes and controls, window chrome and shared components, property grid and
dialogs, then each application, then the written rules.


## Entries

### design.silence.002 — Scroll bars are always visible

- Evidence: `ScrollWnd` bars are thin (`scrollBar_NormalSize` 10, a 6 px thumb) but are drawn
  whenever the content overflows, and they take their width from the view (`paddingZ`,
  `paddingW` in `ScrollWnd.computeLayout`). Fading them needs two things the control does not
  have: the bar must overlay the view instead of narrowing it, and `ScrollWnd` must learn that the
  pointer is over its content, which only its view's children receive (`Enter`/`Leave` reach the
  deepest window). Every list, tree, document and application golden that shows a thumb moves.
- Next: lay the bars over the view in `ScrollWnd.computeLayout`, track pointer presence through a
  hook on the view, and drive the thumb alpha with the animator — shown on a scroll or a hover,
  faded after a short idle.
- Done when: the charter wall and a scrolled list golden show no thumb at rest and one under the
  pointer, in both themes.

### design.silence.004 — The applications do not use the shared components

- Evidence: the toolkit has the lens (`Gui.Lens.View`), the information sheet (`Gui.InfoSheet`),
  the inspector (`Gui.Inspector`, which carries a generated grid through `setContent`), the
  mini-bar (`Gui.MiniBar`), the dock (`Gui.ToolDock`), the hint line (`Gui.HintLine`),
  `Gui.SectionLabel` and a floating surface for any other content (`Gui.FloatingPanel`), with
  `floating.test.swg`, `lens.test.swg` and their goldens, and `AppearanceButton.addToLens`; a
  hidden caption button keeps working and takes no room in the caption. Swag Capture and Swag
  Scope compose them (their remaining work is design.silence.008 and design.silence.007); Swag
  Prism and Swag Vault still inset their whole root by `Wnd.stripInset()` to keep their old bands
  clear of the floating strip.
- Next: per remaining application, register every command and `addToLens` on one lens bound to
  `Space` or `Ctrl K`, move readings to the sheet, tools to the dock and the mini-bar, properties
  to the inspector, and let the work reach into the strip where its picture shows it.
- Done when: the four applications use the components, every command is a lens entry, and no
  application re-implements one or insets its whole root under the strip.
- Related: design.silence.007, design.silence.008, design.silence.009, design.silence.010

### design.silence.005 — The property grid control still lacks search marks and the layout menu

- Evidence: the rows follow the charter (`properties.{grid,condensed,list,panel}.{ink,paper}`
  goldens: Arc dot after a changed name, faint revert glyph, padlock of a read-only value, section
  labels in faint spaced capitals with a faint chevron and, in Panel, a hairline; Condensed rows of
  26 with a hairline; validation as a dot and a line in the tone; notes as the Arc notice).
  `PropertiesCtrl` does not: search marks no matched characters and shows no result count, the
  section list shows no counts, and the `•••` menu offers no Presentation choice, because
  `Properties.kind` is fixed at creation. In Panel the self-labelled editors carry no changed-value
  dot, a Condensed warning shows its line instead of a caution mark in the left margin, and the
  Panel golden shows `Opacity` at 0 while the data holds 0.4 (it did before this restyle too).
- Next: let `Properties` switch kind by rebuilding its rows, put List, Grid, Condensed and Panel
  under a Presentation section of the joined `•••` menu with `✓` in Arc, mark matched characters
  with the highlight colour and count results in the search field and the section list; then fix
  the Panel slider refresh.
- Done when: `gui.properties.ctrl.paper` is reproduced by a `properties.ctrl.{ink,paper}` golden.
- Related: design.silence.002

### design.silence.006 — The file box lists dates in the body face and marks no match

- Evidence: `FileDlg` and the embedded `FileBrowserCtrl` follow the file box of the dialog
  pictures (`dialogs.file.{ink,paper}`): places as text tabs with the Arc underline, the path
  written before the filter in one field, quiet rows on the box ground, the type filter in the
  bottom-left slot. Three details remain: the dates and sizes use the body face instead of mono,
  the characters a filter matched are not highlighted, and the name column keeps its authored
  width instead of taking the room, so dates and sizes do not reach the right edge.
- Next: give `ListItem` a face of its own (or a mono column flag), let a list row carry the
  matched ranges the lens already computes with `Lens.match`, and let the first column of a
  `ListCtrl` stretch.
- Done when: `dialogs.file.{ink,paper}` match the file box of the dialog pictures in those three
  points too.

### design.silence.007 — Swag Scope viewers still keep their own controls off the lens

- Evidence: the window follows the charter: no command, information or viewer band; every window
  command (open, explore, close, reload, files beside, history, find and its options, full screen,
  play modes, the explored folder's history, order, view and online media, the appearance and
  About) is a lens entry on `Space`/`Ctrl K`; the file's readings are in the sheet (`I`); the
  viewer's commands float over the foot of the document while the pointer moves; its readings sit
  faint under it; the find bar floats on `Ctrl F`; the file and viewer panels are cards; the
  explorer is a page with its title, mono count, quiet order and view menus, Arc-ringed tiles and
  the chosen item in the sheet (`surface`, `viewer.{dark,light}`, `search.{dark,light}`,
  `explorer.{gallery,archive,movie}` goldens). What a viewer builds is still reached only on its
  floating bar or its line of readings: `Viewer.Host` has no way to give the lens entries, so the
  video transport, image tools, font samples, hex structure, PDF pages and every viewer's options
  sheet are not lens entries. The viewers keep their pre-charter shapes: no reading column for
  text and code, no table of contents in the margin or progress thread for Markdown, no structure
  tabs or large inspector value for hex, no specimen page for fonts, no edge-to-edge picture with
  veils for video, and documents do not scroll under the strip. The archive viewer's embedded
  host (`EmbeddedViewer`) still keeps its header band, viewer combo box and bottom command band.
- Next: add a lens source to `Viewer.Host` (bump `Viewer.ApiVersion`) that the window asks while
  the viewer is active, register each viewer's commands and its options sheet there, then rebuild
  each viewer on its picture, the embedded host last.
- Done when: every Scope golden matches its picture and every viewer control is a lens entry.
- Related: design.silence.004, design.silence.002

### design.silence.008 — Swag Capture's shape editing does not yet match its pictures

- Evidence: the editor is the capture on the ground with the tool dock, the mini-bar by the
  selection (colour, face, step reset, alignment, delete, `•••`), the inspector (title and count,
  Duplicate and Delete, quick styles, colour rows with swatch and hex, glyph rows for shape kind,
  dashes and line ends, then the generated grid) and the hint line with the size and zoom; the
  area overlay, the library page and the lens follow their pictures (`surface`, `surface.paper`,
  `area`, `library.surface`, `lens.paper` goldens). What the `capture.edit.*` pictures show and the
  editor does not: a callout's text is typed in a dialog, not inline with a caret; its face, size
  and alignment are not on the mini-bar and its style is not an "Aa" segment; a mask's kind is a
  combo of the grid, not a radio list with glyphs; a step's mini-bar has no number stepper; a
  multiple selection shows no arrange buttons or layer list in the inspector; the colour picker is
  the toolkit's picker, not the popover with recent colours, palette, exact value and opacity; a
  quick style has no name; the generated rows show a value box where the pictures show a mono
  value ("6 px") and a combo where they show segments (Line, Shadow), and position is two rows
  instead of the X · Y · W · H strip; the folded inspector's tab is horizontal; the hint line does
  not change with the tool. Elsewhere: the library's tab counts are in the proportional face and
  its thumbnails are letterboxed in a 4:3 cell; the recent captures are text rows of the lens, not
  thumbnails; the in-place editor still has its own icon bar; the area bar offers no delay or
  cursor choice (they are lens entries).
- Next: per `capture.edit.*` picture, move the missing editors into the inspector and the mini-bar
  — start with the colour popover and the segments of the generated grid (design.silence.005),
  which every kind shows — then inline callout text and the mask radio list.
- Done when: each `capture.edit.*` picture is reproduced by a golden of the editor in that state.
- Related: design.silence.004, design.silence.005

### design.silence.009 — Swag Prism still frames its panes

- Next: rebuild Prism as two columns with quiet text menus, the stage frieze and the comparison.
- Done when: the Prism goldens match the Prism pictures.
- Related: design.silence.004

### design.silence.010 — Swag Vault is still a banner over tabs

- Next: rebuild Vault as the list of vaults with in-place unlock, and create, progress and
  options as pages.
- Done when: the Vault goldens match the Vault pictures and privacy mode keeps the list empty.
- Related: design.silence.004, design.silence.006

### design.silence.011 — Examples and other consumers use removed APIs

- Evidence: `gui2` to `gui9` and `gui11` lay out their header from the top edge of a view that now
  reaches under the floating strip, so their first line meets the window glyph and title; `gui10`
  reads `Wnd.stripInset()` and shows the components on its Components page.
- Next: move every `bin/examples` program and other consumer to the two themes and the new
  components, and inset their headers by `Wnd.stripInset()`.
- Done when: the examples build and smoke clean in both themes.

### design.silence.012 — The skills still describe the old identity

- Next: rewrite `design-swag-identity`, `design-swag-themes`, `design-swag-dialogs` and
  `build-swag-standard-apps` so they state this charter and nothing that contradicts it.
- Done when: a new control, dialog or application written from the skills alone matches the
  charter.

### design.silence.014 — Command labels are in sentence case

- Next: move every English command label of `bin/` string tables (menus, lens entries, buttons,
  dialog actions, tabs, command tooltips) to the title-style capitalization of the charter,
  leaving sentences and French translations alone.
- Done when: a search of the English reference tables finds no command label in sentence case.

### design.silence.015 — A dismissed notice leaves in one frame

- Evidence: notices open their height and then fade their words in, and the inspector arrives
  from its edge when it unfolds, but `InfoBar.dismiss` destroys the bar at once, so the content
  under it jumps up by its height.
- Next: fade the words out over `motion_LeaveSeconds`, close the height over
  `motion_PanelSeconds`, then destroy; callers already learn of the dismissal through
  `sigDismissed`, before any of it.
- Done when: no shared component changes its place or presence in one frame on a user action.
- Related: design.silence.002
