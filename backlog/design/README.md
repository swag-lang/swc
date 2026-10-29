# Silence — the Swag GUI charter

This folder is the design contract of the GUI toolkit's controls, widgets, dialogs and two
themes, and of the four standard applications (Swag Scope, Swag Capture, Swag Prism, Swag
Vault). The examples under `bin/examples/` are teaching programs, not Silence applications.
Examples built on the GUI toolkit use its Swag-rendered caption, title and border. The direct
Pixel and OpenGL examples still use low-level native windows; moving those renderers under the
same Swag-drawn chrome is unresolved in [`design.silence.md`](design.silence.md).
Examples with multiple pages or palettes keep their navigation and theme selector visible. GUI
examples use Encre and Papier through the toolkit and may show menus, toolbars and other controls
that the toolkit provides. The
pictures in [imgs/](imgs/)
are the validated target for the toolkit and standard applications; the text below states the
rules they follow. Where a picture and a rule disagree, the rule wins.

[design.silence.md](design.silence.md) lists what is still to migrate.

![The two themes](imgs/silence.themes.png)

## The six laws

1. **The work comes first.** Keep the document, image or list dominant. Repeated task controls
   belong beside it: navigation in a folder, transport in a player, tools and output in an
   editor. Remove decorative bands and duplicate readouts, not the means of doing the work.
2. **Details are asked for.** Metadata, advanced settings and secondary readings appear on
   request. Current mode, selection, progress, failures and the next essential action remain
   understandable without knowing a shortcut or discovering a hover target.
3. **One complete door, several direct gestures.** A visible Commands control and `Ctrl Space`
   open the same lens: search, go to, open, switch view, run any command. Every command remains
   reachable from it. Frequent actions also have direct controls; the lens never makes learning
   command names a prerequisite for using an application.
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
| Live | `#4ADE80` | `#15803D` | The dot of something running now: a mounted drive |

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

### Pointing, focus and selection

These are separate states and each keeps its own signal:

- **Hover** is temporary. Raise the whole hit target under the pointer; do not highlight only its
  text or glyph. It leaves when the pointer leaves.
- **Keyboard focus** is where keys act. Show its 2 px focus ring in Voltage on Encre and ink on
  Papier. Moving focus never silently changes which item is selected.
- **Selection** is the file or folder the reader chose. Keep it visibly marked after the pointer
  leaves and while the control is not focused. A row uses the Arc selection ground across its full
  bounds. A thumbnail keeps its picture intact, with an Arc outline painted above the picture and
  the Arc selection ground under its name and facts. The selected glyph may take the selection's
  ink; unrelated text and facts stay neutral.

Selection is never conveyed by hover alone, by a thin mark that the content covers, or by a glyph
colour alone. Encre and Papier use the same distinction, and every selectable row and tile is
checked in both.

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

The toolkit ships Inter in four upright weights, and each role takes one: `Light` (300) for a
large fact — Vault's percentage and capacity, the sheet's figures, Prism's instruction counts;
`Regular` for body text; `SemiBold` (600) for a section label and for a name that leads a row, such
as a vault's; `Bold` for titles, which stand in for the 650–800 weights. Roboto Mono keeps its
regular and bold faces: a light or semibold measure is set regular or bold.

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
- The document's name is centred at the top, 12 px, faint. A quiet Commands control gives the
  lens a visible pointer entrance in the existing strip, with its shortcut in the tooltip. It
  stays available without hovering an invisible target; at narrow widths it keeps a named
  accessible target and a recognizable glyph. It does not require a second caption band.
- The window buttons are faint glyphs at the top right; they reach full contrast on hover.
- The window shadow is restrained: 35 % on Encre and 24 % on Papier. It separates the surface
  from its surroundings without competing with the work. Floating panels and sheets use the
  stronger shadow described in [Measures](#measures).
- A document shows its position with a 1 px thread on the right edge and a short mark, not a
  scrollbar. A thin scrollbar (6 px) appears while scrolling or on hover.
- A faint hint line ("Ctrl Space — everything else") may sit 24 px above the bottom edge while the
  reader is new to the window or the surface is empty.
- `Ctrl+Space` opens the lens from any focused control. The window handles it before the focused
  viewer or field, even when that control also uses `Space`.
- Keys are named the same way everywhere — a keycap of the hint line, the foot of the lens, the
  end of a menu or lens row: `Space`, `Esc`, `Tab`, `↵` for Enter, and a chord as its keys
  separated by spaces (`Ctrl K`, `Ctrl ↵`, `Ctrl Shift S`), written by `Input.formatKeyShortcut`
  and the key names of `Gui.strings()`. What a key does is a few lowercase words after it
  ("compile", "views, stages, examples").

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
  fade in; dismissed, its words fade out first, then its height closes, so the content under it
  rises instead of jumping.
- **A state eases, a mark grows.** A check box fills and its mark grows into it; a radio dot grows
  from the centre of its ring as it fades from the option left; a disclosure chevron turns its
  quarter turn. Each takes the 120 ms of state feedback.
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
| Check mark, radio dot, disclosure chevron | 120 ms | ease out | mark grows, chevron turns |
| Tab underline to the chosen tab | 180 ms | ease out | the underline slides |
| Lens, dialog arriving, with their dim | 180 ms | ease out | none |
| Sheet, inspector arriving | 180 ms | ease out | 8 px from their edge |
| Mini-bar, menu arriving | 180 ms | ease out | 4 px away from the anchor |
| Any floating surface leaving | 120 ms | linear fade | none |
| Page change | 180 ms | ease out | 16 px |
| Panel or notice changing the layout | 220 ms | ease in-out | its own size |
| Notice dismissed | 120 ms fade, then 220 ms close | linear, then ease in-out | its own size |
| Scroll bar resting | 180 ms fade after 600 ms still | linear | none |

## Shared components

### Lens

![The lens on Papier](imgs/scope.lens.paper.png)

Opened by `Ctrl Space`. 600–640 wide, near the top third, surface colour, corner 12, floating
shadow. The document behind dims (about 16 % opacity, slight blur). An input of 64 px with 22 px
light text; results grouped under section labels (In this file, Symbol, Open, View as, commands
by family); rows of 38–40 px with a leading glyph or number, matched characters highlighted,
the chosen row on the Arc selection ground. Selecting a row never shifts its shortcut or detail.
Enter is taught once in the footer, not repeated beside the selection. The footer lists the keys
(`↑↓` choose, `↵` go) and clickable source links (`:` line, `/` files, `>` actions) for sources
the application actually supports. Clicking a source preserves the query and narrows its scope;
clicking Actions with an empty input browses all commands. `Esc` clears a query, then closes.

The lens is the application's command palette as much as its search, and it starts from where
the reader is:

- Before anything is typed it is a direct action list. Keep a compact, stable set of basic
  actions first, followed by selection or viewer actions and then recent commands. Capture
  keeps capture, open, library, export and copy available while an annotation is selected.
  Scope changes its basic group when the task changes between reading and exploring, not when
  a different file or row is selected. Basic actions must fit the first viewport at the minimum
  supported window size. A disabled action keeps its position and explains its prerequisite.
- Typing expresses intent. A strong title match must not sit below weak content matches merely
  because one provider registered first. The ranking contract below governs this order; explicit
  source selection remains available when the reader knows which kind of result they want.
- An action that cannot run now stays listed, in the disabled ink and with its matches faded,
  so the reader learns it exists; it cannot be chosen.
- Every action shows its shortcut in faint mono at the end of its row, so the lens also teaches
  the keys it stands in for.
- Inside the lens, keep the common actions as a short group of named rows. Do not duplicate them
  in an icon toolbar above the results: that spends the first viewport twice and creates a second
  navigation order. An inline row is for one exclusive choice, not unrelated action shortcuts.
- A section label is always `Gui.SectionLabel` — small spaced semibold capitals in the faint ink —
  whether a component, an application header or a painted list draws it; nobody shapes its own.

#### Direct controls and task walkthroughs

These walkthroughs are design checks against the source and whole-window goldens, not results
from observed user sessions. They set the acceptance tasks for the implementation tracked in
[design.silence.004](design.silence.md#designsilence004--the-lens-needs-a-discoverable-pointer-entrance-and-direct-task-controls).

| Task | Cost when everything goes through the lens | Required direct route |
| --- | --- | --- |
| First Capture launch, mouse only | A shortcut hint explains a key, but offers no visible command entrance | A named Commands control; Capture Area is immediately visible in the empty state |
| Capture a region, add an arrow, copy into a message | Opening a modal palette to finish interrupts work on the canvas; Copy can mean an object or the finished picture | Keep the tool dock; offer explicit Copy Image and Save as Image together beside the work |
| Annotate three successive captures | Selecting an annotation must not replace the route to the next capture | Capture Area and Last Area keep their positions; expose delay/cursor/output choices in one capture settings group |
| Correct an annotation and undo | Reopening the lens for each correction hides the effect behind a dimmed canvas | Direct selection tools and Undo/Redo; keep settings open while adjusting, with visible feedback |
| Find yesterday's capture in an empty or populated library | A Library link attached only to recent thumbnails is not a reliable route | Library is an independent command; visible filter, sort and return to editor on its page |
| Open a film, pause, seek, change volume | Modal search interrupts watching and hides the timeline | A transport with play/pause, seek, volume and full screen; subtitles, audio and speed in its adjacent controls |
| Browse films, open one, return to the folder | Repeated lens calls for Back or Up make ordinary exploration expensive | Stable Back/Forward/Up and current location in the page header; sorting and view choices remain nearby |
| Resume a film later | A beautifully empty player cannot replace a missing resume feature | Store playback position and offer Resume / Start from Beginning; this is product behavior, not a cosmetic lens fix |
| Find an unfamiliar action | A blank search field requires the product's exact vocabulary | Browse command families without typing; search recognizes localized synonyms and restrained spelling errors |

There is no universal top toolbar copied across every mode. A folder gets navigation, a player
gets transport, and an editor gets tools and output. Put three to five frequent actions in a
stable task group using the shared controls, with words beside unfamiliar icons. Keep secondary
choices in a small adjacent menu or the lens. Never make a row of unlabeled icons stand in for
discoverability. Direct controls route through the same command identifiers and state as the lens.

Repeated editing controls remain visible while editing. Playback controls can recede during
uninterrupted playback, but appear immediately on pointer movement, remain while hovered or
keyboard-focused, and are visible when paused. Pointer use, keyboard traversal and tooltips must
agree. A novice must be able to open, browse, perform and leave the main task using only the
pointer; an experienced reader must be able to complete it without the pointer.

#### Search intent and predictable ranking

Search must be deterministic and local. It does not need a remote language model. The following
is the target contract; the matcher currently supports case folding, substrings, initials and
ordered characters. The remaining work is tracked with the lens migration.

1. Normalize surrounding and repeated whitespace, case and accents for comparison while
   preserving the original label and correct UTF-8 highlight spans. Treat terminal command
   ellipses as presentation, not a required part of a query.
2. Rank an exact title first, then whole words and word prefixes (allow multiple words in any
   order), then declared localized aliases, initials, and finally approximate matches. A query
   such as `image copy` must find Copy Image; `plein ecran` must find Plein écran.
3. Within an equally strong match class, prefer usable actions relevant to the current task.
   Use context and recent use only as bounded tie-breakers. Keep deterministic ties in the
   declared order; never rearrange the empty-query basic actions according to usage history.
4. Only offer typo recovery as a fallback for meaningful words: initially one insertion,
   deletion, substitution or adjacent transposition for words of at least four characters.
   Never fuzz numbers, paths, shortcuts or line addresses. Show the real command label, never
   silently rewrite the input or run a guessed action. Keep exact disabled matches visible with
   their reason, without treating an unavailable match as grounds to hide usable alternatives.
5. Keep result kinds recognizable: actions, files and occurrences. An exact command beats a
   loose occurrence, an exact filename remains findable, and occurrences retain document order
   within their section. Cap previews per source and offer Show All before one source fills the
   lens. Prefixes are accelerators; clickable, named scope controls carry the same capability.
6. Use aliases from the user's vocabulary: screenshot/capture, export/save image, mute/sound,
   subtitle/caption, and their translations. Match command families as well as labels so a
   reader can browse Capture or Playback without guessing one leaf command. Do not turn a long
   hidden description into a source of weak matches.

When nothing matches, keep the query, identify the active scope, and offer All Commands or a
scope reset. Do not leave the user with an unexplained empty list. A list that overflows must
advertise that it scrolls; a clipped last row or a discoverable scroll indicator is needed even
before the first wheel movement. Keep navigation and source controls reachable at minimum width
and with French labels, without colliding with the keyboard help.

#### Acceptance of a lens change

Use Encre and Papier, English and French, the minimum window size and a non-default display
scale. Compare complete task sequences, not just the number of visible controls. For the tasks
above, check first successful action, unnecessary lens reopenings, mistaken object/image copy,
backtracking, and recovery from a typo. Test with a fresh profile as well as recent history.
History must improve convenience without becoming a prerequisite.

Keep an executable query corpus with exact commands, filenames, collisions with document text,
multiword queries, aliases, accents, typos, disabled actions and no-result queries. Assert the
first usable result and the reachable alternatives, not only that something matches. Golden
images cover fixed shortcut columns and overflowing result lists; interaction tests cover source
switching, focus return, keyboard traversal and settings changed without reopening the lens.

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

### Toast

![Toasts](imgs/gui.toast.png) ![Toasts on Papier](imgs/gui.toast.paper.png)

A short confirmation of something the hand just did — copied, saved, removed, mounted — or a
failure that does not need a question. One pill, centred above the hint line: surface, corner
10, floating shadow, 42 high, 18 of side padding. An optional 7 px dot in its tone (Arc for done,
critical for a failure), the sentence in body ink, a name or a path in faint mono, and at most
one action in Arc link ink at its end ("Undo", "Show", "Details").

It arrives with the floating arrival, 8 px upward; it stays 3 s, 4.5 s when it carries an
action, and as long as the pointer is over it; then it leaves with the floating departure. It
never takes the keyboard. A new toast replaces the one on screen rather than stacking under it.
Anything that needs an answer is a dialog, not a toast.

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
- **Combo box**: a field with a faint `▾`, in the text colour under the pointer or while its list
  is open; its list is a popup surface (corner 10) with the chosen row on the Arc ground and `✓`
  in Arc.
- **Checkbox / radio / switch**: off is a 1.5 px line ring; on is Arc (white check on Papier,
  ink check on Encre); mixed shows a dash. Switch 34 × 20, knob white when on.
- **Slider**: 2 px track on raised, Arc fill, 14 px white knob, value in mono beside it.
- **Progress**: 4 px track, Arc fill; indeterminate is a moving Arc segment; circular is an Arc
  arc on a raised ring.
- **Tabs**: words as wide as themselves with 22 px between two, the first word on the bar's edge
  in line with the title above; text in faint, the active one in text colour with a 2 px Arc
  underline exactly under its words.
- **Lists, trees, headers**: rows 30, hover raised (it comes in and goes out over 120 ms),
  selection Arc ground; header labels faint with a hairline under, each title aligned as its
  cells are and the sort marker right after its words; tree chevrons faint, turning a quarter
  turn when a branch opens. Dates, sizes and counts in faint mono; the name column takes the room
  the others leave. A list with no row says so in one faint sentence where its rows would be.
- **Menus**: surface, corner 10, 6 px padding, rows 30, hover/selection Arc ground, shortcuts in
  mono faint at the right, `✓` in Arc, `›` for submenus, separators of one hairline inset 10.
- **Notices**: a tinted ground of the tone, an 7 px dot in the tone, bold first phrase, no
  border, no icon tile.
- **Tooltip**: surface (Papier: ink with paper text), corner 6, 12 px.
- **Scrollbars**: one thickness, 8 px with a 4 px thumb; they rest invisible and show while the
  view scrolls or the pointer is over them.

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

### The file box, in every mode

![The file box in every mode, Papier](imgs/dialogs.file.modes.paper.png)

![The file box in every mode, Encre](imgs/dialogs.file.modes.ink.png)

- **Choose a folder.** Only folders are listed, without sizes; there is no type filter. The
  bottom-left slot shows, in faint mono, the path that will be chosen — the selected folder, or
  the folder shown when nothing is selected — and the primary action names it ("Choose
  "design"").
- **Save.** The rows stand in faint ink: they are context, not choices. The name field is
  labelled above, focused, its stem selected and the extension written after it in faint, so
  typing replaces the name and keeps the type. The type filter holds the bottom-left slot and
  changes that extension.
- **Choose several files.** Each row carries a checkbox; the chosen rows stand on the Arc
  selection ground. After the type filter, the bottom-left slot counts the choice in faint mono
  ("3 chosen · 23 KB") and the primary action says how many it opens ("Open the 3").
- **New folder.** A form of one field, "Name", its proposed name selected, with a faint line
  saying where it goes ("In Documents / swag") and "Create" as the primary action.
- **Replace.** The title names the file ("rapport.pdf" already exists.), the body says what is
  lost, a mono faint line gives its size and date, and the primary action is destructive.

## Applications

Every application follows the window chrome above, uses the lens for its commands, and leaves
the screen to its work.

### Swag Scope

![Reading](imgs/scope.read.png) ![Video](imgs/scope.video.png)

- Reading: the document alone in a centred column. Markdown has no persistent footer, progress
  thread or action strip; its current section is marked in the quiet heading margin when the
  window is wide. `Ctrl Space` opens the lens for file, view and reading actions; `I` opens file
  and reading details. The full outline is opened on demand from the lens and remains a quiet,
  scrollable list beside the page, without an information card.
- Explorer: a page title (folder name, 44–56/800) under the faint path, a mono count, quiet sort
  and view menus on the title line, right-aligned with the grid; the chosen item ringed in Arc
  at a 2 px gap; the sheet for the chosen item. No side panel and no filter field until asked
  for (`/`). Every edge of the page — path, title, grid, menus — is one edge.
- The cell takes the shape of what the folder holds, as a media player would show it:
  - **A mixed folder**: one even grid of 4:3 cells on the raised ground. Each cell shows what its
    file is: a picture its picture, a PDF its first page on a paper card, code a few lines in
    mono, Markdown its heading and lines, a sound its waveform, a film a frame with its duration
    in a mono chip, a font "Aa" in its face, a folder its glyph and item count, anything else
    the page glyph of its kind with its extension in faint mono. Under it: the name, then one
    mono line of facts (dimensions or pages or duration, and the size at the right).
  - **Films**: portrait posters in their own shape (never squashed), the playback progress as an
    Arc thread along the poster's foot, title and year · duration under it; the sheet carries the
    poster, the rating, "Resume at 1 h 12" as the one primary action, the people and the file,
    and at its foot who said what ("Sources Apple · Wikipedia · Wikidata").
  - **Music, a library**: square covers, album name then artist · year in mono.
  - **Music, one album**: the cover large at the left with Play and Shuffle under it; at the
    right "ALBUM · 2001", the title, the artist, the facts in mono, then the tracks as rows
    (number, title, duration in mono), the playing one on the Arc ground with ▶.
  - **Photos**: a justified mosaic that keeps every picture's shape, grouped by day under a
    spaced-capitals label with its count; the camera facts of the hovered one in a mono tip.
  The kind is read from what most of the folder holds; the view menu can always force grid,
  covers, posters, mosaic or details.

![A mixed folder](imgs/scope.explorer.mixed.png)

![A mixed folder in Papier](imgs/scope.explorer.mixed.paper.png)

![Films](imgs/scope.explorer.films.png)

![A music library](imgs/scope.explorer.music.png)

![One album](imgs/scope.explorer.album.png)

![One album in Papier](imgs/scope.explorer.album.paper.png)

![Photos](imgs/scope.explorer.photos.png)
- Video: picture edge to edge; on hover a top veil with title, a bottom veil with the timeline
  (Arc progress, white knob, chapter ticks, hover time), time in mono, chips for subtitles,
  audio, speed.
- Markdown: a reading column, the current section marked in the left margin when the window is
  wide (active entry with an Arc left rule), and a full outline opened on demand in the opposite
  margin. No footer or progress thread stays on the page.
- Hex: structure as text tabs, an airy grid, Arc selection, Voltage cursor byte, a floating
  inspector with the value under the cursor in large type.
- Font: a large specimen, the family name, style tabs, a glyph grid with the chosen glyph on the
  Arc ground, a sample field and sizes with mono labels.

![Markdown](imgs/scope.markdown.paper.png) ![Hex](imgs/scope.hex.png) ![Font](imgs/scope.font.paper.png)

![Home](imgs/scope.home.png) ![Home, clearing the history](imgs/scope.home.paper.png)

- Home: the empty window stays quiet. The Scope mark, large and faint, gives the page its
  centre; one line under it invites a drop or `Ctrl+O`, and recalls opening a folder with
  `Ctrl+E`; under a hairline, the last six files as
  plain rows — a small line glyph in its file-kind colour and never a thumbnail — the name in
  soft, the time in faint mono, and nothing else: no title, no paths, no
  groups. The row under the pointer comes up on the raised
  ground with its folder in faint mono and a faint `×` that removes it from the history (Delete
  does the same on the chosen row). "Clear…", faint under the list, appears with the pointer and
  offers the partial clears — the entries whose file is gone, with their count, the entries
  older than a month — and, apart and in critical ink, clearing everything, which asks first.
  Older entries are in the lens under `/`.

![Archive](imgs/scope.archive.png) ![Archive on Papier](imgs/scope.archive.paper.png)

- Archive: the explorer's page grammar inside the archive — the path in the archive as a mono
  breadcrumb, the folder as title, a mono line of counts and sizes (compressed, extracted,
  method), quiet "Extract All…" and sort; rows with a glyph, the name, a thin Arc bar for the
  compression ratio, mono size and date. The chosen entry is described on a floating card: a
  preview, the name, its identity line, sizes before and after, ratio, date, checksum, and
  "Open" (primary) and "Extract…". Backspace climbs a folder.

![Image](imgs/scope.image.png) ![PDF](imgs/scope.pdf.paper.png) ![Sound](imgs/scope.sound.png)

- Image: the picture alone, centred on the ground; a mini-bar on movement (previous, next,
  zoom, fit, rotate, adjustments); the reading line gives name, size, format, weight and the
  rank in the folder; the zoom stands at the right of it.
- PDF: pages on the ground with the paper shadow, the outline in the left margin with the
  current part on an Arc rule, the position thread at the right, page and zoom in the reading
  line.
- Sound: the cover, the title large, artist, album and year, then the waveform with what is
  played in Arc and the times in mono; transport on a mini-bar; the format in the reading line.

![MIDI](imgs/scope.midi.png) ![Table](imgs/scope.table.paper.png) ![HTML](imgs/scope.html.paper.png)

- MIDI: tracks at the left with their colour dot and channel (a muted track faint), a piano roll
  on bar rules, the play head in Voltage; transport and tempo on a mini-bar.
- Table: the file name as title, a mono line of rows, columns, separator and encoding; the
  header with the column name and its inferred type in faint mono; numbers right-aligned in
  mono; hairlines between rows; the chosen row on the Arc ground; a sum of the chosen numeric
  column in the reading line.
- HTML: the page rendered in a reading column, its address in faint mono above, its outline in
  the right margin; source and rendering are two views of the lens.

![Subtitles](imgs/scope.subtitle.png) ![Binary](imgs/scope.binary.png) ![Text](imgs/scope.text.paper.png)

- Subtitles: the cues as a reading list — number and times in faint mono, the text in reading
  type, the current cue on the Arc ground — over a thin timeline of the cues with the position
  in Voltage.
- Binary: a report page — the file name, a mono identity line (format, machine, kind, signature,
  size), large light figures (sections, imports, entropy, strings), the sections as one
  proportional bar with its legend, then the imports by library; the parts of the report are
  named in the reading line and are lens entries.
- Text: prose in a reading column of 680, 16/29, no line numbers; code keeps the numbered column
  of the reading picture.

### Swag Capture

![Annotating](imgs/capture.annotate.png)

- The editor shows the capture on the ground, a dock of tools at the left, a mini-bar next to the
  selection and the inspector at the right (foldable). Its compact task controls offer capture
  and image output directly. Every command remains in the lens, including capture modes, recent
  captures and the library; secondary choices may use adjacent menus.
- Area capture: the screen dimmed except the chosen zone, a 1 px Voltage edge, its size in a
  mono chip, a pixel loupe with a Voltage crosshair, modes as text tabs on a floating bar, then
  after a hairline how the screen is read: `Delay: none ▾` (a list of delays; one waits, then
  reads the screen again) and `Cursor` (a switch, on in the text ink over an Arc underline). The
  keys at the foot stand on the floating ground, since the frozen screen can be any picture.
- Editing in place, right after a capture: the desktop stays dimmed and the captured zone
  stands in full light with a white hairline edge, its size in a mono chip and Arc handles that
  still move its edges. The annotations are drawn on it directly. One floating bar hangs under
  the zone (above it, or beside it, when the screen has no room): the tools as glyphs with the
  chosen one on the Arc ground, the colour, then the destinations in words — Pin, Editor,
  Save… — and Copy as the primary action, and a faint `×`. The keys stand at the foot: Enter
  copies and closes, `Ctrl+S` saves, `Esc` cancels.

  ![Editing in place](imgs/capture.inplace.png) ![Editing in place, Papier](imgs/capture.inplace.paper.png)
- Library: page title, folders as text tabs with mono counts, tags as chips (chosen in Arc),
  a grid of captures, rating and dates in mono. The lens at rest offers what can be done with
  the chosen captures — open, export, tags, favourite, move to a folder, delete — and their
  rating as one row of segments, then what the page shows as another; every other command of
  the page (view, sort, folders, dates, applications, tags) is one word away. The hint line
  teaches the keys of the page, `Ctrl Space` last: `↵` open, `Del` delete, `F2` rename, `0–5` rate,
  `/` filter.
- Shape editing, per kind: arrow (curve handles, start/end glyph pickers, sizes), callout (inline
  text, tail handle, font/size/style "Aa" segments), masks (image, blur, pixelation, magnifier,
  capture as a radio list), step numbers (mini-bar with number stepper and reset), multiple
  selection (common settings, align, arrange, group), colour popover (recent, palette, exact
  value, opacity) and quick styles (each a small picture of the shape it draws, in its own
  colours, the chosen one ringed in Arc, then `+`).
- Words are typed in place, for every shape that carries some — a text, a callout, the label of a
  step: a double click, Enter or `F2` lays a field per line over the shape, in its face, size,
  ink and alignment. Enter breaks the line (a step keeps its label on Enter), `Ctrl+Enter` or a
  click elsewhere keeps the words as one step of the history, `Esc` lets them go. A rotated shape
  straightens over `motion_QuickSeconds` while its words are typed, and turns back after.
- The text mini-bar is compact — colour, face list, size in mono, **B** *I*, the alignments
  across and down, delete, `•••` — and stands above or below the selection, never over the dock,
  the inspector or an edge of the capture; while words are typed it stands below them. The
  inspector keeps the face, the size and the style "Aa" segments.
- The lens closes with the recent captures as a strip of pictures ended by `Library →`; `↓`
  reaches the strip, `←` `→` go along it, Enter opens the one ringed in Arc. Library also has its
  own basic action, so an empty recent strip never removes that route.
- The inspector shows the presets of the selection's kind (of the tool in hand without a
  selection; none for a selection of several kinds): one row of five and `+`, or five and `•••`
  opening every preset with `+`, ordered by use. The row is one stop of Tab, entered on the
  preset in force: `←` `→` go along it, Enter applies the preset ringed in the focus ink, and
  Enter or `↓` on `•••` opens the popover, where the arrows, Enter and `Esc` go on; `Esc` gives
  the keys back to the row. The preset in force is named under the row; a right click
  renames it, replaces it with the current style or removes it. The head rows of the inspector
  scroll with its settings, which stand 30 apart under TEXT, SHAPE, STROKE, ENDS, EFFECTS and
  POSITION. Several objects are titled by their kinds ("2 rectangles · 1 text"), what they
  share first. Library folder tabs give their count in mono.
- The dock holds eight tools in 30-pixel cells: select, shape (and polygon), arrow (and line),
  text, callout, draw (and highlighter), step, image (and pixel selection, favourites). A cell
  with a corner mark lists its group on a click on the mark or a right click; every tool keeps
  its command, its lens entry and its key, and comes into its cell when used.
- Every action is reachable from the lens, frequent actions have direct controls, and the lens
  names the key at the end of the row. A letter is typed when a field holds the focus, so a field keeps it; Tab walks the
  inspector down its rows and the mini-bar along its controls. The hint line teaches the keys of
  the mode in force: the tool in hand and `Ctrl Space`; the selection (`← ↑ → ↓` nudge, `Ctrl D`, then
  `↵` for the words of a shape that has some, `Delete` otherwise: four keys are what the room
  beside the inspector holds); or the words being typed.

  | Keys | Action |
  | --- | --- |
  | `Ctrl Space` | the lens |
  | `I` | fold or unfold the inspector |
  | `V` `R` `P` `A` `L` `T` `C` `D` `H` `N` `M` `X` `F` | select, shape, polygon, arrow, line, text, callout, draw, highlighter, step, image, pixel selection, favourites |
  | `← ↑ → ↓`, `Shift` + arrow | nudge the selection 1 px, 10 px |
  | `Delete` | delete the selection |
  | `Ctrl D` | duplicate the selection |
  | `Ctrl G`, `Ctrl Shift G` | group, ungroup |
  | `]` `[`, `Ctrl ]` `Ctrl [` | forward, backward a step; to the front, to the back (also `PgUp` `PgDn`, `Home` `End`) |
  | `Ctrl A`, `Esc`, `Ctrl Shift I` | select all, none, invert |
  | `↵`, `F2` | type the words of the selection; then `Ctrl ↵` keeps them, `Esc` lets them go |
  | `Ctrl C` `Ctrl X` `Ctrl V` | copy, cut, paste; `Ctrl Shift A` copies the whole picture |
  | `Ctrl Z`, `Ctrl Y` | undo, redo |
  | `Ctrl N`, `Ctrl Shift N`, `Ctrl O` | new capture, new from the clipboard, open an image |
  | `Ctrl S`, `Ctrl Shift S` | save the linked image, save as |
  | `Ctrl Shift D`, `Ctrl Shift T` | duplicate the capture, flatten it |
  | `Ctrl +`, `Ctrl -`, `Ctrl 0` | zoom in, out, to 100 % |
  | `Print`, `Ctrl Print`, `Alt Print`, `Ctrl Shift Print` | capture an area, the screen, the active window, the last area again |
  | `Ctrl Alt O` | options |

![Arrow](imgs/capture.edit.arrow.png) ![Callout](imgs/capture.edit.callout.png)
![Mask](imgs/capture.edit.mask.png) ![Steps](imgs/capture.edit.steps.png)
![Multiple](imgs/capture.edit.multi.png) ![Colour](imgs/capture.edit.color.paper.png)
![Area](imgs/capture.area.png) ![Library](imgs/capture.library.png) ![Lens](imgs/capture.lens.paper.png)

- Quick styles: each preset is a small picture of the shape it draws, in its own colours — a
  rectangle or an ellipse with its outline, fill and weight, an arrow with its curve and head,
  "Aa" with its fill and outline, a callout bubble with its tail, a numbered step, a marker stroke,
  a mask's pattern — in a 44 × 36 cell on the raised ground, corner 7. The preset in force has the
  Arc ring at a 2 px gap; "+" (a hairline cell) saves the selected shape as a new preset. The
  inspector shows only the row of the tool in use, under its title; never letters, glows or bare
  outlined squares standing for a shape.

![Quick styles](imgs/capture.presets.png) ![Quick styles, Papier](imgs/capture.presets.paper.png)

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

**Kinds of file.** In a listing — the file box, Scope's home and explorer, the lens — a file's
glyph carries one quiet hue of its kind: pictures green, films violet, sounds amber, code slate,
paged documents old rose, archives sand. Folders and plain files keep the neutral ink. The hue is
the glyph's alone: the name, the facts and the cell's ground stay neutral, a selected row may
draw the glyph in its own ink, and a cell showing a real preview (a poster, a cover, a page)
has no glyph and so no hue. Each theme has its own set, deepened on Papier
(`fileKind_*`, `Theme.fileGlyph`).

![Neutral and tinted kinds in Encre](imgs/scope.tints.png)

![Neutral and tinted kinds in Papier](imgs/scope.tints.paper.png)

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
