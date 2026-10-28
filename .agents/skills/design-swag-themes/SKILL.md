---
name: design-swag-themes
description: Add, change, or review a GUI theme — the two Silence palettes Encre and Papier, a palette token, a Voltage or Arc role, a ThemeMetrics measure, the GUI type, the look of a control in any state, or the marks of the property grid. Use whenever touching bin/std/modules/gui/src/paint/theme*.swg, a widget or composite's colors, shapes or sizes, the theme atlases, a theme sheet, or judging whether an interface reads correctly in both shipped themes.
---

# Design Swag Themes

The GUI follows one charter, **Silence**: [backlog/design/README.md](../../../backlog/design/README.md)
and its pictures in [backlog/design/imgs/](../../../backlog/design/imgs/). The pictures are the
visual target; the text states the rules they follow, and where a picture and a rule disagree, the
rule wins. This skill turns the parts of the charter a theme answers for — palettes, roles,
measures, type, controls, property grid — into rules you can apply without the picture open. Read
the six laws in [design-swag-identity](../design-swag-identity/SKILL.md#the-gui-follows-silence)
first; everything here serves them.

A theme is not a list of colors. It is a small set of decisions, and one rule per painted
part that turns those decisions into pixels. Everything in this skill follows from that.

## Exactly Two Palettes

The toolkit ships two themes and maintains two: **Encre** (dark, `Theme.setDark()`) and
**Papier** (light, `Theme.setLight()`). Both are recognizable as Swag; neither is a neutral
fallback. There is no neutral palette and no "Swag dark" variant — those were three palettes to
keep in step, and the one that carried the identity was always the one the others drifted from.

- The appearance choice offers **Dark, Light, System**; System follows the operating system and
  resolves to one of the two.
- An application that wants another look **adds its own theme on top**, through a theme sheet
  (see below). The toolkit keeps two to maintain; it does not grow a third.
- Every rule, every control and every golden is written for both. A widget that reads in one theme
  only is unfinished, not half finished.

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

Information notices use Arc: there is no separate information hue. Syntax colouring keeps the
shared lexical palette of [design-swag-identity](../design-swag-identity/SKILL.md#match-every-syntax-surface),
deepened on Papier through `Color.ensureContrast`.

These values are the specification. `theme.colors.test.swg` pins them; a derivation that lands a
part one step away from the table is a defect of the derivation, not a new value.

## Voltage Acts, Arc Chooses

One accent at a time. Two yellow things on one screen is one too many, and the rule that keeps it
that way is a division of labour, not a quota.

**Voltage** marks what is being done, or where the reader is acting:

- **the primary action**: on Encre a Voltage fill with ink text; on Papier an ink fill
  (`#1A1B1E`) with paper text — the same button, turned over;
- **the keyboard focus ring**: 2 px, Voltage on Encre, ink on Papier;
- **the text caret**: Voltage on Encre, ink on Papier;
- **the current search occurrence**: Voltage fill with ink text on Encre; on Papier the highlight
  with an ink underline;
- **the window's current tool when it is a mode** — a dock cell; see the dock in
  [build-swag-standard-apps](../build-swag-standard-apps/SKILL.md#compose-the-shared-components).

**Arc** marks what is chosen, elsewhere, on, or in progress: the selected row, thumbnail or
segment; the active tab's underline; links; a checked checkbox, radio or switch; slider fill;
progress; selection handles on a canvas; the "value changed from default" dot; information
notices.

**Highlight** marks occurrences — every search match, every matched character in the lens or a
filter. It is a wash of Voltage, light enough to read text through, and it is the only place
Voltage touches text on Papier.

Three refusals hold the roles together:

- **Never put Voltage text on Papier.** Yellow parts from white by less than a tenth of a step of
  luminance; on paper a Voltage word is a word nobody reads. That is why Papier turns its primary
  over to ink rather than deepening Voltage into an olive no reader would recognize.
- **Never wash a row with Voltage.** A row washed in a colour that means *do this* says the wrong
  thing, and cannot be read at all. Rows, entries, tabs and thumbnails select with the Arc
  selection ground.
- **Never draw a Voltage rail or band.** A permanent bar of the signature is decoration that
  borrows the colour of action; it was the window's accent rail and caption glow, and both are
  gone.

Status colours are not tones to borrow for emphasis. Critical and Caution say *something went
wrong* or *mind this*; Arc says *for your information*. A notice is a tinted ground of its tone, a
7 px dot in the tone, a bold first phrase, no border and no icon tile. There are no three-colour
status icons.

## The Two Layers

[`ThemePalette`](../../../bin/std/modules/gui/src/paint/themepalette.swg) holds the decisions: the
tokens of the table above and the few geometric decisions a theme makes.

[`ThemeColors`](../../../bin/std/modules/gui/src/paint/themecolors.swg) holds one value per
painted part, and **every one of them is derived** by `ThemeColors.apply(palette)`. No palette
writes a semantic color directly. `apply` is the specification: read it to know what a part of
the interface is allowed to be — and read the charter to know what `apply` must produce.

### A color is a tone, and a tone is three questions

`ThemeTone` is `{mark, ground, onGround}`: what the tone **points** with, the block it **fills**,
and the **ink** that block carries. A theme never has "a color" — it has those three, and asking
for them together is what makes a tone impossible to half-answer.

The charter's roles are exactly that split. Encre's signature fills Voltage, carries ink and
points in Voltage (ring, caret). Papier's signature fills ink, carries paper and points in ink —
the hue is turned over rather than deepened, because a deepened Voltage is a colour the family
does not own. Arc fills and points in `#38BDF8` on Encre and in `#0A7FB5` on Papier, where the
lighter Arc would vanish as a hairline; a checked mark carries white on Papier and ink on Encre.
Critical and Caution write an ink and a tinted ground that have nothing in common but their hue,
which is why a palette names both.

### The mark is derived when the charter does not name it

`apply` may still deepen a tone's mark until it clears `MarkContrast` against **the ground it is
nearest** — the surface a popup is drawn on, not the extreme ground of the theme. That derivation
exists for parts the charter does not list. Where the charter names a value, the derivation must
land on it; a palette that needs a hand-written override to reach the table has the wrong
derivation.

### Why this shape, and what it rules out

Writing three hundred colors by hand, or letting one palette override a subset of another, is a
delta — and a delta is a promise nobody can keep: a dark palette answered for a hovered flat
button and the light one did not, so a light interface kept the hover of the palette it was
derived from. Twenty-two values were asymmetric that way. Deriving every color from tokens makes
that class of defect unrepresentable — a palette answers for everything or it does not compile.

## Rules

### Add a color only when a part cannot reuse one

Before adding a field to `ThemeColors`, find the part in `apply` that already means what you
want. A new field is justified when a widget paints something no existing rule covers, not when
a caller wants a different value in one place — that is what a theme sheet is for.

Every new field needs:

1. a one-line doc comment naming the part, not the color (`// Border of a hovered field.`);
2. a line in `apply` deriving it from tokens and the roles above, never a literal;
3. a value in both palettes, which it gets for free by being derived.

A field nothing reads is deleted, not kept "for later". Nine of them were.

### Add a token only when the derivation cannot answer

A token is a decision a designer must make. The bar: could two reasonable themes disagree about
it, in a way no other token predicts? If not, derive it. The charter's table is the token set;
a new token needs that argument written next to it and a line in the charter.

What the charter removed has no token any more: there is no band ground (no window draws an
information, command or tool band), no rail switch (nothing draws a rail), no caption glow (no
window has a caption band to wash). A palette field that only existed to paint one of them is
deleted with it, not set to zero.

### Every state must differ from the one before it

Rest, hover, press, focus, checked, disabled. If two of them resolve to the same value the control
reports nothing at the moment the reader is deciding. `theme.colors.test.swg` asserts this for
the filled actions; hold the same bar by eye for anything new.

Disabled is the state most often got wrong: it must be **weaker** than rest, never stronger. The
charter fixes it at 40–45 % opacity for buttons and a faint ring on a transparent ground for
fields. A disabled dial whose ring was the enabled ring, a disabled checked tool wearing the full
accent, a disabled icon painted white — all three shipped, and all three read as *more* available
than the enabled control beside them.

### A mark drawn around a control takes that control's shape

The keyboard-focus ring is the worked example, and every rule it follows applies to anything else
drawn *around* a control rather than *by* it.

- **2 px, offset by 2 px, outside the control.** The ring is drawn on the ground around the
  control, never on its fill. That is what lets one ring colour per theme hold around every
  control, including a Voltage primary on Encre: the 2 px of ground between them separates them.
- **Take the corner from what you are marking, stepped out by the offset.** A ring around a 6 px
  control is concentric at 6 + offset + half its width; drawn at the control's own radius it
  crosses its corners at four places. [[Gui.ThemeImageRect.radius]] is where a tile says what
  corner it draws, so a widget publishes it from the tile it painted ([[Gui.Wnd.focusRingRadius]])
  and the ring derives its own.
- **Hug the content when the cell is not the control.** A check box laid out in a column of a form
  takes the column's width, and a ring around that encloses as much empty ground as content. Widgets
  in that shape carry `WndFlags.NoFocusRing` and draw their own mark around the marker and its
  wording — see [[Gui.Button.markerFocusRect]].

### Never hardcode a color in a widget

A literal in a widget is a color no theme can answer for. The exceptions are named and few:

- `imageRect_Fg` is white, which is the tint that leaves an image alone;
- a white knob on a slider or a switch that is on, as the charter draws it;
- a syntax palette keeps its hues, because a reader has learned that green is a comment — but
  each hue is pushed through `Color.ensureContrast` against the editor ground, so it stays
  readable on Papier. See `bin/std/modules/gui/src/controls/richedit/lexerswag.swg`.

Window buttons take no colour of their own: they are faint glyphs that reach full contrast on
hover. Anything else goes through `ThemeColors`.

### A palette answers for geometry too

Applying a palette must always be total: a theme that only sets colours leaves the previous
palette's shapes under its new accent. Encre and Papier share one geometry — the measures below —
so switching between them moves no edge. If a theme sheet adds a geometric decision, it writes it
in `/ThemeMetrics` or `/ThemeImageRects`; a palette never reaches for a radius by side effect.

## Measures

Every number a widget, a dialog or an application lays out with comes from
[`ThemeMetrics`](../../../bin/std/modules/gui/src/paint/thememetrics.swg) or the tile radius of
[`ThemeImageRects`](../../../bin/std/modules/gui/src/paint/themerects.swg). A literal is a
measure no theme can answer for, exactly as a literal colour is a colour no palette can answer
for. The charter's values:

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

- **A radius is a statement of what the thing is.** The window, the floating surfaces, a control
  and a chip are four objects, and their four radii say so. Never inflate a control into a capsule,
  never square a control the scale rounds, and never round the hairline between two things.
- **A shadow means "floating".** Shadows exist only under floating surfaces (`0 30px 80px` at
  45–60 % on Encre, 12–16 % on Papier, with a 1 px line ring). Nothing else casts one: a shadow
  under a button or a card says it floats when it does not.
- **Spacing comes from the scale.** A gap that is not on the scale is a gap nobody chose.
- **A reading column has a measure.** Code runs about 900 wide and prose about 640, centred in the
  window; text set wider is read by moving the head.
- **The window strip and the floating components have their own groups.** The strip is
  `wnd_StripHeight` (52) and floats over the view (`Wnd.stripInset`). The lens, the information
  sheet, the inspector, the mini-bar, the dock and the hint line read the `floating_`, `lens_`,
  `infoSheet_`, `inspector_`, `miniBar_`, `toolDock_`, `hintLine_`, `keycap_` and `sectionLabel_`
  groups, and paint their shadow and the dim behind the lens with `ThemeColors.floating_Shadow`
  and `ThemeColors.lens_Dim`. A floating component draws its ground with the surface token, a
  hairline ring in the line token, and that shadow; nothing else of it is a new colour.
- **The floating shadow is one primitive.** `Theme.drawFloatingShadow` draws it — wide and soft
  (`floating_ShadowBlur`), lower than the body (`floating_ShadowOffsetY`), lighter and closer under
  a thin thing such as the mini-bar — and `Theme.floatingShadowReach` says how far it reaches. A
  floating component is its body alone and paints the shadow outside itself, before its children,
  with its invalidation padding grown by that reach, so the pointer beside it reaches the work; a
  dialog surface (`SurfaceFlags.Sheet`) keeps that reach as its margin. On Encre the shadow
  is half as dark as on Papier: darkness on near-black reads as a hole, so the surface parts from
  the work by its lighter fill and its hairline. Never draw a shadow from an atlas tile; a tile
  that small reads as a grey double edge.

## Type

- **Inter for every word, Roboto Mono for every measure** — offsets, sizes, counts, durations,
  paths, hex values, line numbers, dates in a list. If a reader would compare it digit by digit, it
  is mono.
- Page titles (a folder name, "Vaults", "Library"): 34–56, weight 800, tracking −0.03 em.
- Sheet titles 20–22/800. Dialog titles 17/650. Body 13–15.
- Section labels: 10.5, uppercase, +0.14 em, weight 600, faint. They are labels, not headings, and
  they take no band behind them.
- Large facts — a percentage, a count, a rating, an instruction count: Inter 200–300 at 26–120.
  A fact the reader came for is set large and light; a label beside it stays small and faint.

## Controls

Every control in [bin/std/modules/gui/src/controls](../../../bin/std/modules/gui/src/controls) and
the theme atlases (`theme/widgets.svg`, `theme/icons.svg`) answers for these states in both themes.
The pictures [gui.controls.ink](../../../backlog/design/imgs/gui.controls.ink.png) and
[gui.controls.paper](../../../backlog/design/imgs/gui.controls.paper.png) show each one.

- **Push buttons** — four forms. *Primary*: the Voltage role (Voltage fill and ink text on Encre;
  ink fill and paper text on Papier). *Secondary*: transparent, 1 px line ring, text colour.
  *Quiet*: text only, soft. *Destructive*: secondary with critical text. Disabled at 40–45 %
  opacity. Focus: the 2 px ring offset by 2 px. One primary per surface: two filled buttons are two
  answers to what Enter does.
- **Icon buttons** — 32 cells, glyph soft; hover the raised ground; checked: Arc selection ground,
  Arc glyph, faint Arc ring. No underline, no leading rule, no Voltage on a checked tool.
- **Segments** (toggle groups) — a raised frame; the chosen segment on the Arc selection ground on
  Encre, lifted white with a soft shadow on Papier.
- **Fields** — 32 high, surface ground, 1 px line ring; hover a stronger ring; focus the 2 px
  Voltage/ink ring; error a 2 px critical ring and a message line below with a critical dot;
  disabled transparent with a faint ring. Placeholder faint. A password field carries an eye glyph.
- **Combo box** — a field with `▾`; its list is a popup surface (corner 10) with the chosen row on
  the Arc selection ground and `✓` in Arc. A stepper (`Gui.Stepper`) is a field with quiet `−` and
  `+` at its ends and the value in mono between them.
- **Checkbox, radio, switch** — off is a 1.5 px line ring; on is Arc (white check on Papier, ink
  check on Encre); mixed shows a dash. A switch is 34 × 20 with a white knob when on.
- **Slider** — 2 px track on raised, Arc fill, 14 px white knob, value in mono beside it.
- **Progress** — 4 px track, Arc fill; indeterminate is a moving Arc segment; circular is an Arc
  arc on a raised ring.
- **Tabs** — text in faint, the active one in text colour with a 2 px Arc underline. No box around
  a tab, no ground behind the bar. A breadcrumb is faint text with `/`, its last part in text.
- **Lists, trees, headers** — rows 30, hover raised, selection the Arc selection ground; header
  labels faint with one hairline under; tree chevrons faint; measures in a row in mono faint.
- **Menus** — surface, corner 10, 6 px padding, rows 30, hover and selection the Arc selection
  ground, shortcuts in mono faint at the right, `✓` in Arc at the trailing edge, `›` for
  submenus, separators of one hairline inset 10. A menu opened from an icon button joins it — see
  [design-swag-identity](../design-swag-identity/SKILL.md#join-an-icon-menu-to-its-button).
- **Notices** — a tinted ground of the tone, a 7 px dot in the tone, bold first phrase, no border,
  no icon tile. Info uses Arc, caution Caution, error Critical.
- **Tooltip** — surface (on Papier: ink with paper text), corner 6, 12 px text.
- **Scrollbars** — 6 px, raised track only while visible, thumb a stronger grey. A document shows
  its position with the 1 px thread of the window chrome instead; the bar appears while scrolling
  or on hover.
- **Colour pickers** — swatches on the chip corner, the chosen one ringed; the exact value in mono.

A control that needs a state this list does not name takes the nearest role above — chosen is Arc,
acting is Voltage, unavailable is weaker — before it asks for a new colour.

## The Property Grid

The four `PropertiesKind` layouts and `PropertiesCtrl` follow
[gui.properties.kinds](../../../backlog/design/imgs/gui.properties.kinds.png) and
[gui.properties.ctrl.paper](../../../backlog/design/imgs/gui.properties.ctrl.paper.png). Each kind
keeps its purpose:

- **List** stacks label (13/600), help (12 faint) and editor.
- **Grid** has a name column (150) and a value column.
- **Condensed** uses 26 px rows with values as text and the editor opening on click, one hairline
  between rows.
- **Panel** uses self-labelled controls and section labels followed by a hairline.

In every kind:

- section labels are uppercase faint, collapsible with a small faint chevron, **no band behind**;
- a changed value carries a **6 px Arc dot** after its name and a faint `↺` that restores it;
- read-only shows the value in faint with a lock glyph and no editable frame;
- an error is a critical ring on the editor and a critical-dot message below; a warning is a
  caution-dot message — in Condensed, a caution mark in the left margin whose text appears on
  hover;
- a note is an information notice (Arc tint, Arc `i`);
- mixed values across a multiple selection read "Mixed values" (translated) in faint italic;
- search highlights matched characters with the highlight colour and shows a result count; section
  navigation lists counts; the layout menu is a popup joined to its `•••` button.

No border around an individual setting, and no box around a section: the hairline and the label
already say where one ends.

## Theme Sheets

A sheet is tweak text with four folders: `/ThemePalette`, `/ThemeColors`, `/ThemeMetrics`,
`/ThemeImageRects`. `Theme.applySheet` reads it twice — tokens first, then the individual parts
— so folder order in the file does not matter and a sheet can do both.

A value name reaches into a nested struct with `.`, which is how a tone is written:

```
signature.mark      0xFF9A6B18
signature.ground    0xFF9A6B18
signature.onGround  0xFFFBF7EF
btnPush_Normal.radius   3
```

`$` references resolve through the same paths.

A whole theme is the first folder and nothing else, which is what makes a user theme a page of
text rather than three hundred lines. The worked example lives at
[`bin/examples/modules/gui10/src/sepia.tweak`](../../../bin/examples/modules/gui10/src/sepia.tweak);
copy it to start a theme.

Sheets are how an application adds a third look and how a user writes their own: the charter's
"apps may add their own theme" is this mechanism and nothing else. The two built-in palettes stay
in code on purpose. They are the specification, they are checked when the module compiles, and
duplicating them into sheets would create two places to change one value.

`Application.loadTheme(name)` resolves `themes/<name>.tweak` through the resource bundle, so an
application ships its themes as embedded resources and a disk folder can override or add to
them. An application theme starts from Encre or Papier and changes tokens; it does not re-open the
roles — Voltage still acts and Arc still chooses, whatever colours they take.

## Verify With gui10 And The Charter Pictures

[`bin/examples/modules/gui10`](../../../bin/examples/modules/gui10) is the theme inspector, and
it is the tool for this work. `swc tools/examples.swgs run gui10`.

It opens on the theme and the page the command line names, so comparing a change across the
themes it did not mean to touch is a script rather than a dozen windows driven by pointer:

```
swc tools/examples.swgs run gui10 --run-arg=--light --run-arg=--widgets
```

`--dark` (Encre), `--light` (Papier) and `--sheet` choose the theme; `--colors`, `--palettes`,
`--metrics`, `--widgets` choose the page.

- **Colors** — every `ThemeColors` value of the active theme, by reflection, over the grounds it
  is drawn on, with a checkerboard behind anything translucent.
- **Palettes** — the same value across Encre, Papier and the sheet-written example, side by side.
  Run it after any change to `apply`.
- **Metrics** — every `ThemeMetrics` value.
- **Widgets** — every widget in every state a theme answers for. Hover and press are left to the
  pointer, which is why this page is scrolled through by hand. Its **focus rings** switch turns on
  [[Gui.ApplicationOptions.showFocusRings]].

**Put the Widgets page beside the charter picture of the same theme** and compare control by
control: corner, ring, fill, glyph, which accent. The picture is the target; a control that differs
from it is a finding even when every test passes.

### Show a singular state on everything at once

Only one control of a surface can hold the keyboard, so the focus mark is the one state the wall
cannot show by standing still — and judging it by tabbing is one screen per control, times one pass
per theme. `showFocusRings` draws the ring on every traversal stop instead, which turns that walk
into two images and is what made the toggle and the tool button confess that their ring had never
been visible at all.

Any state with the same shape — a singular one you would otherwise have to drive the surface into —
deserves the same treatment: a diagnostic in `ApplicationOptions`, a switch on the wall, and no
attempt to reproduce it by hand.

The sheets are built from reflection, so a field added to either struct appears without touching
the example. Do not hand-list names there.

The applications are the confirmation, not the instrument: they show one composition of the
theme, and the parts they do not use are exactly the ones a change breaks silently.

## Validation

After changing `apply`, a palette, a measure, or a widget's look:

Always run `swc tools/goldens.swgs dm test`. Theme changes cross widget and application boundaries,
so the complete `golden`-tagged campaign is required in addition to the focused checks below.

1. `swc tools/std.swgs dm test gui --test-file theme.colors.test.swg --test-file theme.sheet.test.swg --test-file themestyle.test.swg`
   — the palette tests pin the charter values of Encre and Papier, assert every mark reads on every
   ground of its own theme, and cover the sheet layers.
2. The command-stream goldens under `bin/std/modules/gui/src/tests/goldens/` change whenever a
   widget's look does. **A control or composite has a golden in each theme.** A failing test leaves
   its `.actual` file beside the golden it diverged from; `swc tools/goldens.swgs` accepts them in
   bulk. Review the diff against the charter picture — a golden that changed for a part you did not
   touch is a finding.
3. The applications keep goldens of their own, and a palette change reaches them:
   `swc tools/apps.swgs dm test <application>` shows a whole surface. Look at the `.actual` image
   before accepting it; that picture is the change.
4. `swc tools/examples.swgs dm smoke gui10` walks every page of both themes.
5. Look at Encre, Papier and the sheet-written example in gui10 before saying the change is done.

Apply [validate-swag-changes](../validate-swag-changes/SKILL.md) for the remaining focused tests and
consumer checks implied by the changed rendering path. Review every `.actual` reported by the
complete golden campaign before accepting it.
