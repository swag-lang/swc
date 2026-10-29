# Silence migration

Every entry moves part of the GUI toolkit or a standard application to the charter in
[README.md](README.md). Examples under `bin/examples/` keep conventional windows and are outside
the Silence application migration. The order is the
dependency order: themes and controls, window chrome and shared components, property grid and
dialogs, then each application, then the written rules.


## Entries

### design.silence.004 — The lens's first screen needs a first-use review

- Evidence: the toolkit has the lens (`Gui.Lens.View`), the information sheet (`Gui.InfoSheet`),
  the inspector (`Gui.Inspector`, which carries a generated grid through `setContent`), the
  mini-bar (`Gui.MiniBar`), the dock (`Gui.ToolDock`), the hint line (`Gui.HintLine`),
  `Gui.SectionLabel` and a floating surface for any other content (`Gui.FloatingPanel`), with
  `floating.test.swg`, `lens.test.swg` and their goldens, and `AppearanceButton.addToLens`; a
  hidden caption button keeps working and takes no room in the caption. Swag Capture, Swag Scope,
  Swag Prism and Swag Vault compose them (the remaining work of the first two is
  design.silence.008 and design.silence.007). The quiet text menu of a header is
  `IconButton.createQuiet` with `setQuietText`, and every application builds its quiet menus with
  it; the section labels Swag Scope shaped itself (its panels, the days of a mosaic, the outline
  margin) are `Gui.SectionLabel`; the keys are named one way (`Gui.strings().key_Enter`,
  `key_CtrlEnter`, spaced shortcuts). Each application has an at-rest provider: Capture offers
  selection, capture or image actions; Prism offers the current view's actions and examples; Vault
  offers the chosen vault and New/Open; Scope offers viewer choices, then file/view basics, then
  viewer controls. In Scope, Close File, Explore Folder and the current side-panel action (for
  Markdown, Outline) are direct rows. Their order and visibility in the first screen have not
  been reviewed against first-use tasks in both themes.
- Next: review the empty-query lens in each application's first-use contexts and both themes;
  adjust the direct action order so the common tasks are visible before scrolling, then update
  and review the affected whole-screen goldens. In Scope, keep Explore Folder and Close File
  visible beside Outline, and verify that the full Markdown outline reaches its last heading by
  wheel and keyboard. Because the scrollbar rests hidden by charter, check how a first-time reader
  discovers scrolling.
- Done when: each application offers its common first-use tasks directly in the initial lens
  view, every other command remains reachable from the lens, and the whole-screen goldens match
  the approved design without any application re-implementing a shared component or insetting
  its whole root under the strip.
- Related: design.silence.007, design.silence.008

### design.silence.006 — The file box does not fit its rows as its pictures do

- Evidence: every mode has a golden in Encre and Papier (`dialogs.file.{folder,save,files,newfolder,replace}`
  beside `dialogs.file`), the file list ends a long name with an ellipsis and has no header, as
  `dialogs.file.modes.{paper,ink}.png` draws it; the new-folder form fits its text and the replace
  question ends on its destructive action. Against the pictures, the box keeps a tall empty list
  under a few rows instead of fitting them, the folder box's field says "Filter, or type a path"
  where the picture says "Filter folders", and the bar beside the field has no recent-places glyph.
- Next: let the box size its list to the rows it shows within a minimum and a maximum, give the
  folder mode its own placeholder, and decide on the recent-places glyph.
- Done when: each `dialogs.file.*` golden matches its picture whole-screen.

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
    still the floating command bar rather than the compact one of the picture. A film takes the
    whole window and nothing stands over it at rest; the pointer brings a top veil (title, facts
    in mono) and a bottom veil (timeline with Arc progress, indexed part, white knob and a mono
    time tip; play, time, chips for subtitles, sound track and speed)
    (`viewer.video.{ink,paper}`, `viewer.video.hover.{ink,paper}`); Scope reads no chapters, so
    the timeline shows no marks.
  What still differs from the pictures, screen by screen:
  - Mixed board: a sound cell shows the thumbnailer's preview or its glyph, not a drawn
    waveform; "Aa" is in the interface face, not the font's own; a film's facts have no size of
    its picture. The title is Bold, not 800.
  - Films: no playback progress thread at the poster's foot and no "Resume at 1 h 12" / "or from
    the start" — Scope keeps no resume position for a film yet; the count says "items", not
    "films".
  - Album: nothing plays from the album page itself, so no row is "playing" — the chosen one
    carries the ▶.
  - Photos: the last row of a day stays at its aim when stretching it would make it much taller
    than its aim; the tip names the file and its weight, not the camera's facts (Scope reads no
    EXIF yet); "taken" is the file's modification date.
  - Archive: the sheet asks for the member's picture but the golden holds it still without one;
    dates are ISO, not the short day/month; the sheet's two buttons share the foot in halves.
  - PDF: the reading line still carries previous/next arrows beside "1 / 2"; no position thread
    at the right.
  - The goldens of the window without the shipped frame start at the top edge: they need the
    frame (StandardWindow) to sit under the strip as the pictures do; the boards, archive and PDF
    goldens already have it. The viewer harnesses no longer photograph the old toolbar band
    (`ViewerActionBar` is gone with its `viewer.{text,pdf,html,image,font}.document` goldens):
    they stand their viewer on the real line of readings, and the window goldens show it.
  - Panels not yet rebuilt as the PDF margin outline is: the Markdown outline
    (`viewer.outline.markdown`, `.fr`) is a boxed card with a title, a close button and a
    filter field; the file panel (`panel`) is a card with an upper-case folder name and a
    filter; the information card of a viewer (`viewer.media.information`) is a two-column
    property list. The charter reads them in the margin, quiet, without a card.
  - The MusicBrainz choice box (`explorer.music.choice`) carries its menu label as title, with
    its ellipsis; the About box credits Wikipedia and Wikidata, not the Apple catalogue the
    posters and synopses now come from.
  - Not yet rebuilt on their pictures: image (`scope.image`), table, HTML (column, address,
    outline), font (specimen page);
    the "Column ▾" quiet menu of text; the progress thread under the strip with documents
    scrolling under it.
  - Viewers photographed in the shipped frame against their pictures (`pictured.*`): the image
    viewer stands on `scope.image`; the table (`pictured.table.paper`) is a page — title, mono
    facts, each column's kind under its name, figures in mono, hairlines, the sum of a column at
    the foot — but its rows are tighter than the picture's; HTML (`pictured.html.paper`) reads in
    its column with its address above and its sections in the right margin, its code on a card,
    but the code is not coloured, no section is marked as the one being read, and over a page
    that sets its own layout the address keeps the column's edge rather than the page's. The font
    viewer (`pictured.font.paper`) is not the specimen page yet: no large "Aa", family and style
    tabs, glyph row with the chosen glyph on Arc, the sample field and sizes with mono labels.
    The font viewer now stands on its specimen page (`pictured.font.paper`) but shows only its own
    style as a tab, the glyph line has no Unicode name, and the sample field stays on the floating
    bar. Hex (`pictured.hex`, a PNG forced into it) stands on its picture: the binary readers'
    structure as text tabs over an airy grid (the format, then Signature, IHDR, …, IDAT × 9,
    IEND, the one holding the caret underlined in Arc), Arc selection, the Voltage cursor byte,
    and the floating inspector — the value under the caret in large type, what it was read as,
    its readings, then the fields of its chunk. What still differs: the grid does not tint the
    chunk-type bytes; the reading line stands at the window's edge rather than the grid's and
    keeps the zoom at its right; the inspector lists every field of the chunk (compression,
    filter, CRC) where the picture keeps five, under the specification's names. An executable
    opens on the binary viewer's report page (`pictured.binary.page`, a small console program):
    its name over the mono identity line, the figures in large light type, the sections as one
    proportional bar with its legend, the imports by library; the structure tree is a lens entry
    away, and a search or a jump goes back to it. What still differs: only the four largest
    sections take a hue (the theme has four series hues) and the hues are the theme's, brighter
    than the picture's; the machine reads "x64"; the reading line gives the format summary, not
    the parts of the report as lens entries; only PE images fill the page — ELF, Mach-O and the
    other formats keep the tree (`pictured.binary`).
- Next: the binary report's parts in the reading line and the lens, and its page for ELF and
  Mach-O; the hex grid's tint of a structure's tag bytes; the font's other styles, glyph names and sample field;
  coloured code cards in HTML and the section being read marked; the table's row pitch; the mixed board's waveform cells,
  "Aa" in the font's own face, a film's picture size in its facts, and an ExtraBold page title.
- Done when: every Scope golden matches its picture as a whole screen.
- Related: design.silence.004

### design.silence.008 — Swag Capture's preset cells are smaller than in their pictures

- Evidence: the `capture.*` pictures and their goldens agree, but for one choice: a preset cell
  is 38 by 31 where the pictures draw 44 by 36, so that five presets and their chip fit across
  the 264 the inspector leaves; at 44 by 36 a row holds four presets.
- Evidence, left when the campaign closed:
  - The tool letters (`V R P A L T C D H N M X F`) were registered on the main window and
    answered in the library, changing the editor's tool unseen; the tool commands are now
    disabled while the library is on screen (`global.test.swg`).
  - The full gui suite runs 5 to 7 minutes, past a `--run-timeout 300`; it needs about 420.
- Next: decide with the charter owner between five smaller presets and four of the pictures'
  size.
- Done when: the preset row of the inspector matches its picture.
- Related: design.silence.004

### design.silence.011 — Standalone example scripts stay outside Silence

- Decision: standalone scripts are examples, not Silence applications. A window-using script keeps
  its title and border and uses the GUI toolkit's Encre and Papier themes where applicable.
- Out of scope: a Silence application strip, lens-only commands, or application-specific layout
  rules in a standalone script.

### design.silence.017 — All examples use Swag-drawn windows

- Decision: examples are teaching programs, not Silence applications. Every top-level example
  window uses Swag-rendered title and border chrome, with Encre and Papier where applicable.
  GUI examples with multiple pages or palettes keep navigation and theme selection visible.
- Evidence: the GUI examples use `Gui.Surface` and draw their chrome through `SurfaceWnd`; Pixel
  and OpenGL examples still call `Core.Env.createWindow`, which delegates the title and border to
  the operating system.
- Next: move the low-level rendering examples into a host that keeps their renderer-specific
  content while drawing and handling window chrome through the GUI toolkit.
- Done when: every example window has a Swag-drawn title and border, remains resizable and
  closable, and its full-screen layout is reviewed in the applicable themes.
- Out of scope: a Silence application strip, lens-only navigation, or Silence component showcase
  in an example.


### design.silence.018 — The charter and the code disagree on measures and leftovers

- Evidence, found while the skills were rewritten on the charter:
  - Floating shadow: the charter says `0 30px 80px` at 45–60 % (Encre) and 12–16 % (Papier); the
    code blurs 64 at offset 24, about 27 % and 10 % (`FloatingShadowDarkShare`, `LightShare`).
  - Dock: the Measures table says a 36 cell and an 18–20 glyph, the Capture section 30; the code
    has `toolDock_CellSize` 30 and `toolDock_Glyph` 16.
  - Scroll bar: 6 px under Window chrome, 8 px under Controls; `scrollBar_Size` is 8.
  - Lens: no blur behind it, only the dim; its foot does not list `Tab`.
  - Section label: the charter says 10.5, `sectionLabel_FontSize` is 10.
  - Swag Scope's current search match pulses a glow (`ViewerSearchOverlay`, `searchMatch_Glow`);
    the Motion section forbids pulses and glows at rest.
  - `dialog.swg` still documents a faint `Esc` hint at the bottom left it no longer paints.
  - Band leftovers: `informationBar_Bk`, `commandBar_Bk`, `toolBar_Bk` (all the ground), the
    window styles `.InformationBar`, `.InformationPanel`, `.CommandBar`, `.ToolBar`, the metrics
    `menuBar_*`, `iconBar_*`, `panel_GutterSize`; `action_IconSize` 20 gives a 36 cell where the
    charter says 32 with a 16 glyph.
  - The documentation page deepens Voltage on paper (`--swag-active: #7e8000`), against the rule
    that Voltage is never deepened.
- Next: decide each line with the charter owner — fix the charter or the code — and delete the
  band leftovers once nothing paints them.
- Done when: every measure the charter states is the one the code uses, and no band style,
  color or metric remains.

### design.silence.009 — Scope's Markdown outline needs a first-use review

- Evidence: the lens exposes Outline directly, and its side panel lists every heading in a
  scrollable `ListCtrl`; a focused test with forty headings confirms the wheel moves the list.
  The scrollbar follows the charter and fades at rest, which leaves no persistent visual cue.
  The quiet outline in the reading margin is separate: it previews the first two heading levels
  and does not scroll. A first-use report says the Markdown viewer still feels like it has bars,
  and its information panel looks unattractive, too high and poorly rounded. The persistent
  reading line and Arc progress thread are now removed from Markdown; details stay in the `I`
  sheet, and the lens remains the visible route to zoom and options. Its explicit outline card
  still needs the charter's quieter margin treatment.
- Next: replace the Markdown outline card with an on-demand, quiet margin that lists every heading;
  make its scroll state discoverable on hover and by keyboard, and compare the whole page in Encre
  and Papier. Keep the always-on reading surface free of footer, progress strip and command bar.
- Done when: the Markdown page reads without persistent bands, its full outline is available from
  the lens in a quiet margin, every heading is reachable by wheel and keyboard, and the outline's
  shape and placement match the charter in both themes.
- Related: design.silence.004, design.silence.007
