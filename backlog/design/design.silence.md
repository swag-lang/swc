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

- Evidence: the window follows the charter — no band; every command is a lens entry; readings in
  the sheet (`I`) and faint at the foot; viewer controls on a floating mini-bar; panels are cards.
  Built on their pictures, each golden compared whole-screen with its picture:
  - Home (`home.{ink,paper}`, `home.hover.{ink,paper}`).
  - Explorer boards: a mixed folder (`explorer.mixed`, `.paper`) — one even grid filling the page,
    pictures and films cropped to the tile, faint line glyphs and extensions for the rest, name
    and one mono line of facts; films (`explorer.films`) — upright posters, title then year and
    length, the sheet headed by the poster beside its title with Open under it and the sources at
    its foot. The poster and synopsis come from the Apple catalogue first, credits and rating
    from Wikipedia and Wikidata. Music (`explorer.music`) as square covers; one album
    (`explorer.album`, `.paper`) with its cover, Play and Shuffle and its tracks; photographs
    (`explorer.photos`) as a justified mosaic by day.
  - The lens answers a typed query over code, text and Markdown with the lines of the file
    ("In This File"), and `:` with a number goes to that line (`showcase.lens.query`).
  - Archive (`explorer.archive`, `.paper`): rows with ratio bar, size and date, "Extract All…" and
    "Extract…" with a toast, the member's sizes, compression, date and CRC-32 in the sheet; the
    embedded host (`viewer.archive.document`) has no band: a quiet line with a quiet viewer menu,
    the commands on a mini-bar.
  - PDF (`viewer.pdf.page`, `.paper`): pages as paper with the floating shadow, the outline in
    the left margin under "Contents".
  - Code and text in their reading columns, Markdown with its margin outline and Arc thread.
  - Subtitles read as a list under the file's name and mono line: number, mono time range,
    words, the current cue on the selection ground, the rhythm of the minute around it, its rank
    and time at the foot (`viewer.subtitle.{ink,paper}`, in the shipped frame). A MIDI score reads
    as one lane per track under the bar numbers, each track in its series hue with its name and
    channel (`viewer.midi.{ink,paper}`); it has no transport nor play head, because Scope plays no
    MIDI. A recording is laid out around its cover (`viewer.sound.{ink,paper}`); the tags carry no
    picture yet, so the cover is a raised tile with the glyph of a sound, and the transport is
    still the floating command bar rather than the compact one of the picture.
  What still differs from the pictures, screen by screen:
  - Mixed board: a PDF, code, Markdown, sound and font cell show the preview the thumbnailer
    renders, not the drawn paper card, mono lines, heading, waveform or "Aa" of the picture; the
    facts line has no dimensions, pages, lines, sections or face (only length, count and size).
    The title is Bold, not 800.
  - Films: no playback progress thread at the poster's foot and no "Resume at 1 h 12" / "or from
    the start" — Scope keeps no resume position for a film yet; the count says "items", not
    "films".
  - Music and album: the hint line does not teach Enter / P; the count says "items", not
    "albums · tracks"; the album's cover casts no shadow; nothing plays from the album page
    itself, so no row is "playing" — the chosen one carries the ▶; the view menu cannot force
    covers, posters or mosaic.
  - Photos: the last row of a day is not justified; no mono tip of the camera facts under the
    pointer; the order is the folder's, not by date.
  - Archive: the sheet asks for the member's picture but the golden holds it still without one;
    dates are ISO, not the short day/month; the sheet's two buttons share the foot in halves.
  - PDF: the reading line still carries previous/next arrows beside "1 / 2"; no position thread
    at the right.
  - The goldens of the viewer harnesses (`viewer.*.document`) and of the window without the
    shipped frame start at the top edge: they need the frame (StandardWindow) to sit under the
    strip as the pictures do; the boards, archive and PDF goldens already have it.
  - Not yet rebuilt on their pictures: image (`scope.image`), table, HTML (column, address,
    outline), binary (report page), hex (structure tabs, large inspector), font (specimen page);
    the "Column ▾" quiet menu of text; the progress thread under the strip with documents
    scrolling under it; the video picture does not reach the strip and has no veils with chips.
- Next: the mixed board's drawn cards (a PDF's first page on paper, code lines, a Markdown
  heading, a waveform, "Aa" in a font's face) and its facts (dimensions, pages, lines); the
  shipped frame for every Scope golden; then image, table, HTML, binary, hex and font on their
  pictures; short dates in archive rows. The media pass takes the video
  viewer on `scope.video`: two veils shown on pointer movement — the title and a mono line on top,
  its own timeline (Arc progress, buffered part, white knob, chapter ticks, a mono time chip under
  the pointer), the play button, the mono time, the chapter and chips for subtitles, sound track
  and speed at the foot — and a framed golden at rest and under the pointer.
- Done when: every Scope golden matches its picture as a whole screen.
- Related: design.silence.004

### design.silence.008 — Swag Capture's editing does not yet match its pictures

- Evidence: the editor, the area capture, the in-place editor, the library and the lens have
  goldens (`surface`, `edit.{arrow,callout,multi,step,mask,color.paper,text,text.paper}`, `area`,
  `inplace{,.paper}`, `library.surface`, `lens.paper`). Words are typed in place for every text
  shape (aligned, level while a rotated shape is edited), the text mini-bar is compact and keeps
  clear of the dock and the inspector, quick styles are pictures of their shapes (`presets`
  goldens), the inspector head actions are
  faint words, the style is one "Aa" row, the area bar offers the delay and the cursor, its keys
  stand on the floating ground, the lens ends with the recent captures as pictures, and the
  in-place bar stands beside the zone when the screen has no room above or below it. What they
  still show differently: a quick style has no name (the picture writes « Repère orange » under
  the pills); the inspector rows of the head do not scroll with the generated settings; the
  library tab counts are in the proportional face (the tab bar sets one face per tab); a tool
  offers up to sixteen presets, which wrap to four rows where the pictures show one; a white
  text preset on Papier is white on the light cell; a mask preset is the glyph of its kind
  rather than its pattern.
- Next: give a quick style a name, shown under the strip and on its tooltip; let the inspector
  scroll its head rows with its content.
- Done when: each `capture.*` picture is reproduced by its golden.
- Related: design.silence.004, design.silence.005

### design.silence.011 — The window scripts were not reviewed against the charter

- Evidence: the example scripts that open windows (`chess.swgs`, `noise.swgs`) were not reviewed
  against the charter.
- Next: review the two scripts on their pictures, in both themes.
- Done when: the window scripts build and smoke clean in both themes.

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
