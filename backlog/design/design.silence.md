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
  Swag Prism and Swag Vault compose them (the remaining work of the first two is
  design.silence.008 and design.silence.007). No component owns the quiet text
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
- Related: design.silence.007, design.silence.008

### design.silence.005 — The property grid control still lacks search marks and the layout menu

- Evidence: the rows follow the charter (`properties.{grid,condensed,list,panel}.{ink,paper}`
  goldens: Arc dot after a changed name, faint revert glyph, padlock of a read-only value, section
  labels in faint spaced capitals with a faint chevron and, in Panel, a hairline; Condensed rows of
  26 with a hairline; validation as a dot and a line in the tone; notes as the Arc notice).
  A search marks the matched characters of a name on the highlight ground and counts the found
  fields in the search field. `PropertiesCtrl` does not show counts in the section list, and the `•••` menu offers no Presentation choice, because
  `Properties.kind` is fixed at creation. In Panel the self-labelled editors carry no changed-value
  dot, a Condensed warning shows its line instead of a caution mark in the left margin, and the
  Panel golden shows `Opacity` at 0 while the data holds 0.4 (it did before this restyle too).
- Next: let `Properties` switch kind by rebuilding its rows, put List, Grid, Condensed and Panel
  under a Presentation section of the joined `•••` menu with `✓` in Arc, count results in the
  section list; then fix
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
  replace question is not destructive. The rows already set dates and sizes in mono
  (`ListItem.mono`), mark the typed words (`ListItem.matchStart`, `matchCount`), and give the name
  column the room the others leave (`ListFlags.StretchFirstColumn`).
- Next: build each mode against its picture.
- Done when: a golden per mode matches `dialogs.file.modes.{paper,ink}.png`.

### design.silence.007 — Swag Scope viewers keep their pre-charter shapes

- Evidence: the window follows the charter. No command, information or viewer band; every window
  command and every viewer command (through `Viewer.Host.setLensSource`) is a lens entry on
  `Space`/`Ctrl K`; the readings are in the sheet (`I`) and faint at the foot of the document; the
  viewer's controls float over that foot while the pointer moves; the find bar floats on
  `Ctrl F`; the panels are cards under a spaced-capitals label. The home is built on `scope.home`
  (`home.{ink,paper}`, `home.hover.{ink,paper}` goldens). The explorer is a page: a quiet
  breadcrumb with slashes, the title stepping from 44 down to 28 before anything is cut, the faint
  mono count and weight (dropped first on a narrow line), quiet menus with short words, the filter
  only on request on a line of its own, bare tiles, quiet folder glyphs, the chosen tile lifted in
  an Arc ring; an archive reads as quiet rows with a ratio bar, size and date, its packed and
  extracted weights under the title, the Enter/⌫/Space hints, and the chosen member's sizes,
  compression and CRC-32 in the sheet with Open (`explorer.{gallery,archive,movie}`). Code reads in
  a centered 900 column, Basic text in a 680 prose column at 16/29 (`viewer.{code,text}.document`);
  Markdown has its table of contents in the left margin and the Arc progress thread
  (`viewer.markdown.images.whitey`); the image viewer counts its rank in the folder.
  What still differs from the pictures: the progress thread runs along the window's top edge, not
  under the strip, and no document scrolls under the strip; text has no "Column ▾" quiet menu;
  the explorer has no "Extract All…" on the title line nor "Extract…" in the sheet, the sheet shows
  no preview card of the member, and folder rows of an archive have no date; the archive viewer's
  embedded host (`EmbeddedViewer`) keeps its header band, viewer combo box and bottom command band;
  PDF has no outline margin and no paper shadow; the video picture does not reach the strip and has
  no top and bottom veils with chips; sound is not laid out around its cover; hex has no structure
  tabs and no floating inspector with the value in large type; the font viewer is not a specimen
  page (its sample field lives on the floating bar); table, HTML (column, address, outline),
  subtitle (reading list), MIDI and binary (report page) keep their earlier shapes. Waits use
  `Gui.Spinner`; nothing in Scope needs a toast before `Gui.Toast` lands.
- Next: the progress thread under the strip; then the viewers in this order, each on its picture —
  `scope.pdf.paper`, `scope.video`, `scope.sound`, `scope.archive` (Extract, preview card, then the
  embedded host on the window's model), `scope.hex`, `scope.font.paper`, `scope.table.paper`,
  `scope.html.paper`, `scope.subtitle`, `scope.midi`, `scope.binary` — moving what still stands on
  the floating bar into the document where the picture puts it. Switch the explorer's private quiet
  menus to `IconButton.createQuiet` once it lands.
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

### design.silence.011 — Two toolkit seams the gui examples work around, and the window scripts

- Evidence: `paintSectionLabel` is internal, so gui10's colour sheet and gui11's group titles shape
  the small spaced capitals themselves in their own `onPaint`. `FileDlg`'s new-folder and replace
  questions are private, so gui9 reaches them only through a file box opened on a scratch folder,
  one click away from the question. The example scripts that open windows (`chess.swgs`,
  `noise.swgs`) were not reviewed against the charter.
- Next: publish the section-label painter and switch gui10 and gui11 to it; give `FileDlg` public
  entries for its two questions and let gui9 open them directly; review the two scripts.
- Done when: no example copies a toolkit painter, gui9 opens every file-box question directly, and
  the window scripts build and smoke clean in both themes.

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
