# Silence migration

Every entry moves part of `bin/` to the charter in [README.md](README.md). The order is the
dependency order: themes and controls, window chrome and shared components, property grid and
dialogs, then each application, then the written rules.


## Entries

### design.silence.004 — The applications do not use the shared components

- Evidence: the toolkit has the lens (`Gui.Lens.View`), the information sheet (`Gui.InfoSheet`),
  the inspector (`Gui.Inspector`, which carries a generated grid through `setContent`), the
  mini-bar (`Gui.MiniBar`), the dock (`Gui.ToolDock`), the hint line (`Gui.HintLine`),
  `Gui.SectionLabel` and a floating surface for any other content (`Gui.FloatingPanel`), with
  `floating.test.swg`, `lens.test.swg` and their goldens, and `AppearanceButton.addToLens`; a
  hidden caption button keeps working and takes no room in the caption. Swag Capture, Swag Scope,
  Swag Prism and Swag Vault compose them (their remaining work is design.silence.008,
  design.silence.007, design.silence.009 and design.silence.010). No component owns the quiet text
  menu of a header (a word and a faint chevron opening a menu, as the pictures put above a column
  or a page): Swag Scope's explorer, Swag Capture's library and Swag Prism's column headers each
  configure an `IconButton` for it and fit it to its words themselves (`createQuietMenu` in each),
  and the three differ.
- Next: give the toolkit the quiet menu and move the three applications onto it; per remaining
  application, register every command and `addToLens` on one lens bound to
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
  mono reading with no box: Swag Capture's inspector sets the value face itself
  (`PropWnd.fitFieldLabelColumn`).
- Done when: `gui.properties.ctrl.paper` is reproduced by a `properties.ctrl.{ink,paper}` golden.

### design.silence.006 — The file box modes and details of its rows are not built

- Evidence: `FileDlg` and the embedded `FileBrowserCtrl` follow the open file box of the dialog
  pictures (`dialogs.file.{ink,paper}`), but not the other modes of
  `dialogs.file.modes.{paper,ink}.png`: folder choice shows no chosen path and names nothing in
  its primary action, a save writes the extension into the name field, multiple choice has no
  checkboxes nor count, the new-folder form says nothing of where the folder goes, and the
  replace question is not destructive. The rows still use the body face for dates and sizes,
  mark no matched characters, and the name column does not take the room.
- Next: build each mode against its picture; give `ListItem` a mono face, let a row carry the
  matched ranges of `Lens.match`, and let the first column of a `ListCtrl` stretch.
- Done when: a golden per mode matches `dialogs.file.modes.{paper,ink}.png`.

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
  The window without a file shows a drop invitation where its picture (`scope.home`) shows the
  history, with its partial and full clears.
- Next: build the home on `scope.home` and `scope.home.paper` (the six last files as quiet rows,
  removal of one entry, partial clears, full clear with a question); rebuild each viewer on its
  picture — `scope.read`, `scope.text.paper`, `scope.markdown.paper`, `scope.hex`,
  `scope.font.paper`, `scope.video`, `scope.image`, `scope.pdf.paper`, `scope.sound`,
  `scope.midi`, `scope.table.paper`, `scope.html.paper`, `scope.subtitle`, `scope.binary`,
  `scope.archive` — moving what still stands on the floating bar into the document where the
  picture puts it; then the embedded host on the window's model.
- Done when: every Scope golden matches its picture.
- Related: design.silence.004

### design.silence.008 — Swag Capture's editing does not yet match its pictures

- Evidence: the editor, the area capture, the in-place editor, the library and the lens have
  goldens (`surface`, `edit.{arrow,callout,multi,step,mask,color.paper}`, `area`,
  `inplace{,.paper}`, `library.surface`, `lens.paper`). What they still show differently: the
  words of a callout are typed in place in a field set in their face but left-aligned, not at the
  callout's own alignment; the callout mini-bar's face opens the inspector rather than a list of
  faces; a quick style has no name; the inspector rows of the head do not scroll with the
  generated settings; the library tab counts are in the proportional face (the tab bar sets one
  face per tab); the recent captures are text rows of the lens, not thumbnails (the lens has no
  thumbnail row); the area bar offers no delay or cursor choice (lens entries only); the in-place
  bar does not move beside the zone when the screen has no room above or below it.
- Next: let the field typing a callout follow its alignment; give the lens a row of thumbnails
  for the recent captures; then the remaining items above.
- Done when: each `capture.*` picture is reproduced by its golden.
- Related: design.silence.004, design.silence.005

### design.silence.009 — Swag Prism's render view lacks the caret reading and the framed picture

- Evidence: Prism is two columns with quiet menus, the stage frieze with the change marked, the
  comparison with counts, gain and loop, and the render view with its live-edit switch; every
  command is a lens entry and the readings are in the sheet (`surface.{columns,stages,compare,
  render,lens}` goldens in Encre and Papier, `surface.gui`). What `prism.render` shows and the window
  does not: the caret's place (`Ln 9, Col 41`) at the foot of the source once the hint line has
  stopped teaching the lens — `RichEditCtrl` publishes no signal when the caret moves — and the
  picture drawn on the control corner. The source column shows a horizontal scroll bar for a line
  that only reaches the editor's caret allowance.
- Next: give `RichEditCtrl` a caret signal and read it on the hint line; clip the frame of
  `PreviewCanvas` to the control corner.
- Done when: `surface.render` reproduces `prism.render`.
- Related: design.silence.004

### design.silence.010 — Swag Vault still differs from its pictures in four details

- Evidence: the window is the list of vaults (name, mono identity line, live dot or ring, the
  mounted row on the surface ground with Open and Unmount), the chosen locked vault unfolds in
  place as a floating card (password, drive, key files, read only, Mount), create, progress and
  privacy are pages with a back link, every command is a lens entry and privacy mode keeps the
  list to what is mounted or being unlocked (`list`, `unlock`, `create`, `progress`, `options`
  goldens in Encre and Papier). What the pictures show and the window does not: the create page
  has no free-space reading ("212 GiB free on C:") because `Core` has no volume free-space query
  (no `GetDiskFreeSpaceExW` binding in `win32`); the inactivity delay is a quiet menu under its
  paragraph, not a word inside the sentence; unfolding a vault fades the card in and moves the
  rows below at once instead of opening the card's height over `motion_PanelSeconds`; a protected
  startup vault asks for its access in a box rather than unfolding in the list.
- Next: add a free-space query to `Core.File` with its `win32` binding and show it beside the
  capacity; animate the card's height with the rows following it.
- Done when: the Vault goldens match the Vault pictures in those four points.
- Related: design.silence.004, design.silence.016

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

### design.silence.016 — The toolkit has no light or semibold face

- Evidence: `Pixel.FontFamilyStyle` offers Regular, Bold, Italic and BoldItalic, so the charter's
  large light facts (Inter 200–300: Vault's percentage and capacity, the sheet's figures, Prism's
  instruction counts) are set in the regular weight, and its 600 weights (a vault's name, section
  labels) in bold.
- Next: ship Inter Light and SemiBold with the theme fonts, add the two styles to `FontFamily`,
  and let `Theme.createDefaultFont` take them; then set the facts light and the names semibold.
- Done when: `vault.progress` and the sheet golden show their figures in the light weight.
- Related: design.silence.010
