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
  the Panel slider refresh. The Panel and Grid rows of the charter also show a slider's value as a
  mono reading with no box, and a two- or three-valued choice as segments: Swag Capture's inspector
  sets the value face itself (`PropWnd.fitFieldLabelColumn`), and no segment control exists yet.
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

### design.silence.007 — Swag Scope viewers keep their pre-charter shapes

- Evidence: the window follows the charter. No command, information or viewer band; every window
  command and every viewer command (through `Viewer.Host.setLensSource`) is a lens entry on
  `Space`/`Ctrl K`; the readings are in the sheet (`I`) and faint at the foot of the document; the
  viewer's controls float over that foot while the pointer moves; the find bar floats on
  `Ctrl F`; the panels are cards; the explorer is a page with its title, mono count, quiet menus,
  Arc-ringed tiles and the chosen item in the sheet (`surface`, `viewer.{dark,light}`,
  `search.{dark,light}`, `explorer.{gallery,archive,movie}` goldens). The viewers themselves still
  draw what they drew in their bands: text and code fill the window instead of a reading column
  (~900), Markdown has no table of contents in the left margin and no Arc progress thread, hex has
  no structure tabs and no floating inspector with the value in large type, the font viewer is
  not a specimen page (its sample field lives on the floating bar), the video picture does not
  reach the strip and has no top and bottom veils with chips, and no document scrolls under the
  strip. The archive viewer's embedded host (`EmbeddedViewer`) keeps its header band, viewer combo
  box and bottom command band. The explorer header crowds at the narrowest window with the file
  panel open, its tools covering the title.
- Next: rebuild each viewer on its picture (`scope.read`, `scope.markdown.paper`, `scope.hex`,
  `scope.font.paper`, `scope.video`), moving what still stands on the floating bar into the
  document where the picture puts it; then the embedded host on the window's model.
- Done when: every Scope golden matches its picture.
- Related: design.silence.004, design.silence.002

### design.silence.008 — Swag Capture's shape editing does not yet match its pictures

- Evidence: the editor states of the `capture.edit.*` pictures have goldens (`edit.arrow`,
  `edit.multi`, `edit.step`, `edit.mask`, `edit.color.paper`, beside `surface`, `area`,
  `library.surface`, `lens.paper`). What they still show differently: a callout's text is typed in
  a dialog, not inline with a caret, and the callout's mini-bar has no face, size or alignment;
  the generated settings show a combo where the pictures show segments (Line, Shadow, Joins) —
  the property grid draws no segment control (design.silence.005); multiple selection shows no
  "common settings" heading and its layers are only the kinds of the objects, not their words;
  a quick style has no name; the quick-style strip shows its horizontal bar at rest when the set
  outnumbers the column (design.silence.002); the inspector rows of the head do not scroll with
  the generated settings; the library tab counts are in the proportional face; the recent
  captures are text rows of the lens, not thumbnails; the in-place editor keeps its own icon bar;
  the area bar offers no delay or cursor choice (they are lens entries).
- Next: inline callout text with its mini-bar (face, size, alignment), then segments for two- or
  three-valued settings once the grid can draw them.
- Done when: each `capture.edit.*` picture is reproduced by its golden.
- Related: design.silence.002, design.silence.004, design.silence.005

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
