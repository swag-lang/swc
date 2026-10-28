# Silence — the Swag GUI charter

This folder is the design contract of every surface under `bin/`: the GUI toolkit's controls,
widgets and dialogs, its two themes, and the four standard applications (Swag Scope, Swag
Capture, Swag Prism, Swag Vault). The pictures in [imgs/](imgs/) are the validated target; the
text below states the rules they follow. Where a picture and a rule disagree, the rule wins.

[design.silence.md](design.silence.md) lists what is still to migrate.

![The two themes](imgs/silence.themes.png)

## The six laws

1. **Nothing on screen but the work.** No permanent toolbar, menu bar, status bar, ribbon or side
   panel. The window is the document, the image, the list of vaults.
2. **Information is asked for.** Readings, outlines, metadata and settings appear on a key, a
   hover or a selection, then leave. They are never removed from the product: they move behind a
   gesture.
3. **One door.** `Space` (or `Ctrl K` where Space types text) opens the lens: search, go to, open,
   switch view, run any command. Every command of an application is reachable from its lens.
4. **One accent at a time.** Voltage acts, Arc chooses. Two yellow things on one screen is one too
   many.
5. **Air is a material.** Measured columns, reading margins, nothing flush with an edge, nothing
   boxed that space can separate.
6. **The default theme carries the hand.** The toolkit ships two themes, Encre (dark) and Papier
   (light), both recognisable as Swag. An application that wants another look adds its own theme
   on top; the toolkit keeps two to maintain.

## Themes

The toolkit has exactly two palettes. There is no neutral palette and no "Swag dark" variant:
Encre is the dark theme and Papier the light one. The appearance choice offers Dark, Light and
System (follow the operating system). Theme sheets remain the way an application or a user
writes a third theme.

| Token | Encre | Papier | Use |
| --- | --- | --- | --- |
| Ground | `#17181C` | `#F5F4F0` | Window, document background |
| Surface | `#1F2026` | `#FFFFFF` | Floating surfaces: lens, sheet, inspector, dialog, menu, popover |
| Raised | `#2A2C33` | `#EBEAE5` | Hover ground, pressed, track of a slider or progress |
| Line | `#33353D` | `#E0DED7` | Hairline edges of fields, cards, separators |
| Text | `#ECEDF0` | `#1A1B1E` | Body text |
| Soft | `#A3A6B0` | `#55585F` | Secondary text, labels |
| Faint | `#737783` | `#72757C` | Captions, units, hints, line numbers in prose |
| Voltage | `#F7F900` | `#F7F900` | The signature (see roles) |
| Arc | `#38BDF8` | `#0A7FB5` | The second tone (see roles) |
| Arc link | `#7DD3FC` | `#0A6FA0` | Link text |
| Arc selection ground | `rgba(56,189,248,.16)` | `#DCEFFA` | Selected row, thumbnail, segment, menu hover |
| Highlight | `rgba(247,249,0,.22)` | `#FBF68A` | Search occurrences, matched characters |
| Critical | `#FF6B6B` on `rgba(255,107,107,.12)` | `#C42B2B` on `#FBE9E9` | Errors |
| Caution | `#F2B544` on `rgba(242,181,68,.12)` | `#A36A00` on `#FBF1DC` | Warnings |

Information notices use Arc. Syntax colouring keeps the shared lexical palette of
`design-swag-identity`, deepened on Papier through `Color.ensureContrast`.

### Roles: Voltage acts, Arc chooses

**Voltage** marks what is being done or where the reader is acting:

- the primary action: on Encre a Voltage fill with ink text; on Papier an ink fill (`#1A1B1E`)
  with paper text — the same button, turned over;
- the keyboard focus ring: 2 px, Voltage on Encre, ink on Papier;
- the text caret: Voltage on Encre, ink on Papier;
- the current search occurrence: Voltage fill with ink text (on Papier, the highlight with an ink
  underline);
- the window's current tool when it is a mode (a dock cell) — see Dock.

**Arc** marks what is chosen, elsewhere, on or in progress: the selected row, thumbnail, segment
or tab underline; links; a checked checkbox, radio, switch; slider fill; progress bars;
selection handles on a canvas; the "value changed from default" dot; information notices.

Never put Voltage text on Papier, never wash a row with Voltage, never draw a Voltage rail or band.

## Measures

| Part | Value |
| --- | --- |
| Window corner | 10 |
| Floating surfaces (lens, sheet, inspector, dialog, popover) corner | 12 |
| Menu and popup corner | 10 |
| Controls corner (button, field, combo, segment frame) | 6 |
| Chip, swatch, keycap, inner segment corner | 4–5 |
| Button and field height | 32 (34 in dialogs, 28 in inspectors) |
| List row | 30–32; condensed property row 26 |
| Icon | 16 logical, outline, 1.4 stroke, round caps; 18–20 in a dock |
| Dock cell | 36 |
| Spacing | 4 · 8 · 12 · 16 · 20 · 24 · 32 · 48 |
| Reading column | ~900 for code, ~640 for prose |

Shadows exist only under floating surfaces (`0 30px 80px` at 45–60 % on Encre, 12–16 % on
Papier, with a 1 px line ring). Nothing else casts a shadow.

## Type

Inter for every word, Roboto Mono for every measure (offsets, sizes, counts, durations, paths,
hex values, line numbers). Page titles (a folder name, "Vaults", "Library"): 34–56, weight 800,
tracking −0.03 em. Sheet titles 20–22/800. Dialog titles 17/650. Body 13–15. Section labels:
10.5, uppercase, +0.14 em, weight 600, faint. Large facts (a percentage, a count, a rating):
Inter 200–300 at 26–120.

## Wording of commands

Command labels use title-style capitalization in the English reference strings: menu items,
lens entries, button and dialog action captions, tab titles, tooltips that name a command,
quick-style names. Every word takes a capital except articles, coordinating conjunctions and
prepositions of four letters or fewer, unless first or last: "Add Cursor to Line Ends",
"Save as Image…", "Show in Folder". Sentences — help, descriptions, messages, notices — keep
sentence case. Translations follow their language: French stays in sentence case ("Enregistrer
comme image…"). An ellipsis marks a command that asks for more before acting.

## Window chrome

![Reading in Encre](imgs/scope.read.png)

- No caption band, no menu bar, no accent rail, no caption glow, no status bar.
- The top 52 px is part of the content area and draggable wherever no control sits;
  double-click maximizes.
- The application glyph sits at (18, 16), 18 px, about 55 % opacity, monochrome soft colour.
- The document's name is centred at the top, 12 px, faint. Nothing else is written there.
- The window buttons are faint glyphs at the top right; they reach full contrast on hover.
- A document shows its position with a 1 px thread on the right edge and a short mark, not a
  scrollbar. A thin scrollbar (6 px) appears while scrolling or on hover.
- A faint hint line ("Space — everything else") may sit 24 px above the bottom edge while the
  reader is new to the window or the surface is empty.

## Motion

Motion says where a thing came from and that the interface heard the hand. It is never there to
be noticed: if a viewer remembers an animation, it was too much.

- **Short.** 120 ms for state feedback (hover, press, a switch), 180 ms for a surface arriving,
  220 ms for a change of layout. Leaving takes two thirds of arriving. Only progress lasts longer.
- **Decelerate in, plain out.** Arrivals ease out: they start at speed and settle. Departures fade.
  No overshoot, bounce, spring, wobble, blur trail, or scale above one.
- **Opacity carries the change; travel only says where from.** At most 8 px of travel for a
  floating surface, 16 px for a page. The lens and a dialog fade in with their dim and do not
  travel: a dim that moved would move the work. The sheet and the inspector arrive 8 px from the
  edge they stand against; the mini-bar and a menu leave their anchor by 4 px, the mini-bar
  rising when it stands above its selection. A notice opens its own height, then its words
  fade in.
- **The hand causes it.** Nothing moves unprompted except progress and activity. No pulse, no idle
  loop, no animated glyph, no attention-seeking entrance.
- **Input never waits.** Focus, hit testing and the keyboard reach the final state at once; an
  animation running when the next change arrives retargets from what is on screen. Typing, the
  caret, the selection in a list, the focus ring and an error appear instantly.
- **Scroll bars rest.** They show while the view scrolls or the pointer is over them, and fade
  out 600 ms after the last movement.
- **Reduced motion is honoured.** When the system asks for reduced motion, decorative motion
  completes immediately; progress keeps moving.

| Moment | Duration | Curve | Travel |
| --- | --- | --- | --- |
| Hover, press, check, switch knob | 120 ms | ease out | knob slides its track |
| Tab underline to the chosen tab | 180 ms | ease out | the underline slides |
| Lens, dialog arriving, with their dim | 180 ms | ease out | none |
| Sheet, inspector arriving | 180 ms | ease out | 8 px from their edge |
| Mini-bar, menu arriving | 180 ms | ease out | 4 px away from the anchor |
| Any floating surface leaving | 120 ms | linear fade | none |
| Page change | 180 ms | ease out | 16 px |
| Panel or notice changing the layout | 220 ms | ease in-out | its own size |
| Scroll bar resting | 180 ms fade after 600 ms still | linear | none |

## Shared components

### Lens

![The lens on Papier](imgs/scope.lens.paper.png)

Opened by `Space`. 600–640 wide, near the top third, surface colour, corner 12, floating
shadow. The document behind dims (about 16 % opacity, slight blur). An input of 64 px with 22 px
light text; results grouped under section labels (In this file, Symbol, Open, View as, commands
by family); rows of 38–40 px with a leading glyph or number, matched characters highlighted,
the chosen row on the Arc selection ground with `⏎` at its end. A footer lists the keys
(`↑↓` choose, `⏎` go, `Tab` view as, prefixes `:` line, `/` files, `>` actions). `Esc` closes.

### Sheet (`I`)

A floating panel 300–360 wide, inset 24 from the window edges, surface, corner 12. Title
21/800, a mono line of identity, large light figures for facts, a single primary action at
most, links in Arc, sources at the bottom.

![Explorer with a sheet](imgs/scope.explorer.png)

### Inspector

The sheet shape docked at the right (304 wide) carrying a property grid: section labels,
rows of label (88) and editor, no border around an individual setting. It folds to an edge tab
("Properties · I") so the work takes the full width.

### Mini-bar

A floating toolbar placed next to the selected object: 4 px padding, corner 8, surface,
floating shadow, 28 px buttons, separators of 1 × 16. It carries only what applies to the
selection, and `•••` opens the inspector.

### Dock

A vertical floating tool rail at the left edge, vertically centred: surface, corner 10, 6 px
padding, 36 px cells, glyphs 18. The active tool sits on the Arc selection ground with an Arc
glyph.

## Controls

![Controls in Encre](imgs/gui.controls.ink.png)

![Controls in Papier](imgs/gui.controls.paper.png)

- **Buttons**: primary (see roles), secondary (transparent, 1 px line ring, text colour), quiet
  (text only, soft), destructive (secondary with critical text). Disabled at 40–45 % opacity.
  Focus: 2 px ring offset by 2 px.
- **Icon buttons**: 32 cells, glyph soft; hover raised ground; checked: Arc selection ground,
  Arc glyph, faint Arc ring.
- **Segments** (toggle groups): a raised frame, the chosen segment on the Arc selection ground
  (Encre) or lifted white with a soft shadow (Papier).
- **Fields**: 32 high, surface ground with a 1 px line ring; hover a stronger ring; focus 2 px
  Voltage/ink ring; error 2 px critical ring and a message line below with a critical dot;
  disabled transparent with a faint ring. Placeholder faint. Password field with an eye glyph.
- **Combo box**: a field with `▾`; its list is a popup surface (corner 10) with the chosen row
  on the Arc ground and `✓` in Arc.
- **Checkbox / radio / switch**: off is a 1.5 px line ring; on is Arc (white check on Papier,
  ink check on Encre); mixed shows a dash. Switch 34 × 20, knob white when on.
- **Slider**: 2 px track on raised, Arc fill, 14 px white knob, value in mono beside it.
- **Progress**: 4 px track, Arc fill; indeterminate is a moving Arc segment; circular is an Arc
  arc on a raised ring.
- **Tabs**: text in faint, the active one in text colour with a 2 px Arc underline.
- **Lists, trees, headers**: rows 30, hover raised, selection Arc ground; header labels faint
  with a hairline under; tree chevrons faint.
- **Menus**: surface, corner 10, 6 px padding, rows 30, hover/selection Arc ground, shortcuts in
  mono faint at the right, `✓` in Arc, `›` for submenus, separators of one hairline inset 10.
- **Notices**: a tinted ground of the tone, an 7 px dot in the tone, bold first phrase, no
  border, no icon tile.
- **Tooltip**: surface (Papier: ink with paper text), corner 6, 12 px.
- **Scrollbars**: 6 px, raised track only while visible, thumb a stronger grey.

## Property grid

![The four layouts](imgs/gui.properties.kinds.png)

![Search, sections, states](imgs/gui.properties.ctrl.paper.png)

Each `PropertiesKind` keeps its purpose: **List** stacks label (13/600), help (12 faint) and
editor; **Grid** has a name column (150) and a value column; **Condensed** uses 26 px rows with
values as text and the editor opening on click, a hairline between rows; **Panel** uses
self-labelled controls and section labels followed by a hairline. In every kind:

- section labels are uppercase faint, collapsible with a small faint chevron, no band behind;
- a changed value carries a 6 px Arc dot after its name and a faint `↺` that restores it;
- read-only shows the value in faint with a lock glyph and no editable frame;
- an error is a critical ring on the editor and a critical-dot message below; a warning is a
  caution-dot message (in Condensed, a caution mark in the left margin);
- a note is an information notice (Arc tint, Arc `i`);
- mixed values across a multiple selection read "Mixed values" (translated) in faint italic;
- search highlights matched characters with the highlight colour and shows a result count;
  section navigation lists counts; the layout menu is a popup joined to its `•••` button.

## Dialogs

![Dialogs in Encre](imgs/dialogs.ink.png)

![Dialogs in Papier](imgs/dialogs.paper.png)

A dialog is a floating sheet: surface, corner 12, floating shadow over a dimmed window, padding
28, gap 16. It has **no caption band and no close cross**: its title (17/650) is the first line
of the body. The body text is 13.5/21 in soft. Actions sit at the bottom right inside the same
surface, the primary rightmost; the bottom left stays empty, without an `Esc` hint: the Cancel button
already says the box can be left. A failure puts an 8 px critical dot before the title and the technical detail
on a mono faint line. Forms put labels above fields (12.5 soft). The file dialog shows places as
text tabs, a path field that filters, rows with mono dates and sizes, and the type filter as a
quiet `▾` at the bottom left. About shows the application tile (52, corner 12), the name
21/800, version and date in mono, the capability line, then links.

Dialogs still size themselves from their content (no authored width/height beyond a minimum of
440) and every number comes from `ThemeMetrics`.

## Applications

Every application follows the window chrome above, uses the lens for its commands, and leaves
the screen to its work.

### Swag Scope

![Reading](imgs/scope.read.png) ![Video](imgs/scope.video.png)

- Reading: the document in a centred column, faint line numbers, the position thread, the name
  at the top. The action bar, the information band and the options band are gone: search, open,
  explore, view switch, go to, full screen and options are lens entries; readings (encoding,
  lines, size, outline) are in the sheet (`I`).
- Explorer: a page title (folder name, 44–56/800) over the path, a mono count, quiet sort and
  view menus, a contact sheet grid with names and mono metadata, the chosen item ringed in Arc,
  the sheet for the chosen item.
- Video: picture edge to edge; on hover a top veil with title, a bottom veil with the timeline
  (Arc progress, white knob, chapter ticks, hover time), time in mono, chips for subtitles,
  audio, speed.
- Markdown: a reading column, the table of contents in the left margin when the window is wide
  (active entry with an Arc left rule), reading progress as an Arc thread on the top edge.
- Hex: structure as text tabs, an airy grid, Arc selection, Voltage cursor byte, a floating
  inspector with the value under the cursor in large type.
- Font: a large specimen, the family name, style tabs, a glyph grid with the chosen glyph on the
  Arc ground, a sample field and sizes with mono labels.

![Markdown](imgs/scope.markdown.paper.png) ![Hex](imgs/scope.hex.png) ![Font](imgs/scope.font.paper.png)

### Swag Capture

![Annotating](imgs/capture.annotate.png)

- The editor shows the capture on the ground, a dock of tools at the left, a mini-bar next to the
  selection and the inspector at the right (foldable). Menus are gone: every command is in the
  lens, including capture modes, recent captures and the library.
- Area capture: the screen dimmed except the chosen zone, a 1 px Voltage edge, its size in a
  mono chip, a pixel loupe with a Voltage crosshair, modes as text tabs on a floating bar.
- Library: page title, folders as text tabs with mono counts, tags as chips (chosen in Arc),
  a grid of captures, rating and dates in mono.
- Shape editing, per kind: arrow (curve handles, start/end glyph pickers, sizes), callout (inline
  text, tail handle, font/size/style "Aa" segments), masks (image, blur, pixelation, magnifier,
  capture as a radio list), step numbers (mini-bar with number stepper and reset), multiple
  selection (common settings, align, arrange, group), colour popover (recent, palette, exact
  value, opacity) and quick styles.

![Arrow](imgs/capture.edit.arrow.png) ![Callout](imgs/capture.edit.callout.png)
![Mask](imgs/capture.edit.mask.png) ![Steps](imgs/capture.edit.steps.png)
![Multiple](imgs/capture.edit.multi.png) ![Colour](imgs/capture.edit.color.paper.png)
![Area](imgs/capture.area.png) ![Library](imgs/capture.library.png) ![Lens](imgs/capture.lens.paper.png)

### Swag Prism

- Two columns separated by one hairline: source and output; their settings are quiet text menus
  above each column (view, stage, optimisation level); compile with `Ctrl ⏎`; compile time in
  mono at the bottom right.
- Stages as a frieze of dots browsed with `← →`, the change since the previous stage shown as
  struck-out and Arc-marked lines with counts in a margin.
- Comparison: two outputs with their instruction counts in large light type and the gain in Arc;
  the loop marked by an Arc left rule in both.
- 2D render: source left, the image right, live statistics in mono, the live-edit switch.

![Columns](imgs/prism.columns.paper.png) ![Stages](imgs/prism.stages.paper.png)
![Compare](imgs/prism.compare.png) ![Render](imgs/prism.render.png)

### Swag Vault

- The window is a list of vaults under a page title: name 20/600, a mono identity line, a dot
  (mounted: green; locked: ring). Choosing a locked vault unfolds it in place (password, drive,
  key files link, read-only, primary "Mount"). With privacy mode on, the list stays empty and
  vaults open through the lens.
- Create, progress and options are pages with a back link, not tabs: a calm form with the
  capacity in large type; the randomisation progress as a huge percentage over an Arc line;
  options as rows with a title, a help paragraph and an Arc switch.

![List](imgs/vault.list.png) ![Unlock](imgs/vault.unlock.paper.png)
![Create](imgs/vault.create.paper.png) ![Progress](imgs/vault.progress.png) ![Options](imgs/vault.options.png)

## Icons

Interface icons are outline glyphs on a 16 grid, 1.4 stroke, round caps and joins, no fill except
for a deliberate dot or play triangle. Application icons keep their two-colour tile (Voltage glyph
on ink) for the taskbar and the About box; inside a window the glyph is drawn monochrome at low
opacity.

A glyph is judged at 16 physical pixels at 100 % scale, in both themes, with its pixels enlarged:
inner marks keep 3 units from their frame, a distinguishing detail sits outside the shared shape,
and an object is drawn by its silhouette. The rules and their reasons are in
[design-swag-identity](../../.agents/skills/design-swag-identity/SKILL.md#draw-the-interface-icons).

## Verifying a surface

Every surface is judged against its picture here, in both themes, through its golden image. A
golden that changed for a part not touched is a finding. See
[validate-swag-changes](../../.agents/skills/validate-swag-changes/SKILL.md) for the commands.
