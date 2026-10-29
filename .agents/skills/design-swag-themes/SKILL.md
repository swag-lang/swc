---
name: design-swag-themes
description: Add, change, or review a GUI theme — the two Silence palettes Encre and Papier, a palette token, a Voltage or Arc role, a ThemeMetrics measure, the GUI type, the look of a control in any state, or the marks of the property grid. Use whenever touching bin/std/modules/gui/src/paint/theme*.swg, a widget or composite's colors, shapes or sizes, the theme atlases, a theme sheet, or judging whether an interface reads correctly in both shipped themes.
---

# Design Swag Themes

The GUI follows one charter, **Silence**: [backlog/design/README.md](../../../backlog/design/README.md)
and its pictures in [backlog/design/imgs/](../../../backlog/design/imgs/). The charter gives the
values: Themes, Roles, Measures, Type, Controls, Property grid and Motion. This skill says where
each value lives in the code and which rules keep the code faithful to it. Read the six laws in
[design-swag-identity](../design-swag-identity/SKILL.md#the-gui-follows-silence) first. If a
picture and a rule of the charter disagree, the rule wins.

A theme is not a list of colours. It is a small set of decisions, plus one rule per painted part
that turns those decisions into pixels.

## Exactly Two Palettes

The toolkit ships and maintains two themes: **Encre**, the dark one (`Theme.setDark()`,
`ThemeColors.encrePalette()`), and **Papier**, the light one (`Theme.setLight()`,
`ThemeColors.papierPalette()`). There is no neutral palette and no "Swag dark" variant. The
appearance choice (`AppearanceTheme`) offers Dark, Light and System, and System follows the
operating system. A third look is a theme sheet (see below). Every rule, control and golden is
written for both themes. A widget that reads well in only one of them is unfinished.

The charter's token table maps onto the code like this:

| Charter token | `ThemePalette` | Main `ThemeColors` parts |
| --- | --- | --- |
| Ground | `ground` | `ground`, `wnd_Bk`, `view_Bk` |
| Surface | `surface` | `surface`, `dlg_Bk`, the floating components |
| Raised | `raised` | `raised`, `pressed` (derived) |
| Line | `line` | `line`, `strongLine` (derived with the faint ink) |
| Text, Soft, Faint | `text`, `softText`, `faintText` | same names; `disabled` is derived |
| Voltage | `signature` (a tone) | `signature`, `onSignature`, `focusRing`, `caret` |
| Arc | `alternate` (a tone) | `arc`, `onArc` |
| Arc link | `link` | `link` |
| Arc selection ground | `selection` | `selection` |
| Highlight | `highlight` | `highlight` |
| Current occurrence | `currentMatch` (a tone) | `searchMatch_Bk`, `searchMatch_Border` |
| Critical, Caution, information | `critical`, `caution`, `info` (tones) | `critical`/`criticalBk`, `caution`/`cautionBk`, `info`/`infoBk` |
| Live | `live` | `live` |
| Kinds of file | `kindImage` … `kindArchive` | `fileKind_*`, read through `Theme.fileGlyph` |
| Chosen segment, tool tip | `segment`, `tip` | segment and tool-tip parts |
| Floating shadow, dim, veils | `shadow`, `veil` | `floating_Shadow`, `lens_Dim`, `veilSoft`/`Medium`/`Strong` |

[`theme.colors.test.swg`](../../../bin/std/modules/gui/src/tests/theme.colors.test.swg) pins the
charter values. If a derivation lands one step away from the table, the derivation has a defect;
it is not a new value. Information notices use Arc: there is no separate information hue.

## Voltage Acts, Arc Chooses

The charter's Roles section is the rule. Implementation notes:

- **Voltage** (`signature`) marks what acts: the primary action, the focus ring, the caret, the
  current search occurrence, and a dock tool that is a mode. On Encre it fills Voltage with ink
  text. On Papier the same button is turned over, `ThemeTone.from(ink, paper)`, and the ring and
  the caret become ink. The highlight is the only place Voltage touches text on Papier, as a
  light wash.
- **Arc** (`alternate`) marks what is chosen, elsewhere, on or in progress: the selection ground,
  the active tab's underline, links, checked boxes, radios and switches, slider and progress
  fills, canvas handles, the changed-value dot, information notices.
- **Three refusals.** Never put Voltage text on Papier. Never wash a row with Voltage. Never draw
  a Voltage rail or band.
- **Status colours are not for emphasis.** A notice is a tinted ground of its tone, a 7 px dot,
  and a bold first phrase. It has no border, no icon tile and no three-colour icon.

A control that needs a state the charter does not name takes the nearest role: chosen is Arc,
acting is Voltage, unavailable is weaker. Only after that does it ask for a new colour.

## The Two Layers

[`ThemePalette`](../../../bin/std/modules/gui/src/paint/themepalette.swg) holds the decisions,
which are the charter's tokens. [`ThemeColors`](../../../bin/std/modules/gui/src/paint/themecolors.swg)
holds one value per painted part, and **`ThemeColors.apply(palette)` derives every one of
them**. No palette writes a semantic colour directly. Read `apply` to know what a part is allowed
to be, and read the charter to know what `apply` must produce.

`ThemeTone` is `{mark, ground, onGround}`: what the tone points with, the block it fills, and the
ink that block carries. `apply` makes each tone readable before deriving anything from it. It
deepens a mark until it clears `MarkContrast` against the theme ground the mark is *nearest*
(ground, surface or raised), and it brings a link up to `LinkContrast`. That derivation exists
for parts the charter does not list. Where the charter names a value, the derivation must land
on it.

Deriving every colour from tokens makes a whole class of defects impossible. With hand-written
values, a light palette once kept the hover of the dark palette it was copied from, and 22 values
ended up asymmetric that way.

## Rules

- **Add a colour only when a part cannot reuse one.** A new `ThemeColors` field needs a doc
  comment that names the part, not the colour (`// Border of a hovered field.`). It also needs a
  line in `apply` that derives it from tokens and roles, never from a literal. A field that
  nothing reads is deleted.
- **Add a token only when no derivation can answer.** Ask: could two reasonable themes disagree
  about it in a way no other token predicts? The charter's table is the token set, so a new token
  needs a line in the charter too. The charter removed bands, rails and caption glows, and no
  token paints them. `informationBar_Bk`, `commandBar_Bk` and `toolBar_Bk` remain in
  `ThemeColors` only as the ground under the `WndStyle` bands that still exist. Never give them a
  value of their own, and never build a new surface on a band.
- **Every state differs from the one before it.** Rest, hover, press, focus, checked and disabled
  must each resolve to a different value. Disabled is always *weaker* than rest: 40–45 % opacity
  for a button, a faint ring on a transparent ground for a field.
- **A mark drawn around a control takes that control's shape.** The focus ring is
  `focusRing_Size` (2) at `focusRing_Offset` (2), outside the control, in `focusRing`. A tile
  publishes its corner in `ThemeImageRect.radius`, and a widget passes it on through
  `Wnd.focusRingRadius`, so the ring stays concentric. When the cell is not the control (a check
  box in a form column), set `WndFlags.NoFocusRing` and draw the mark around the marker and its
  wording, as `Button.markerFocusRect` does.
- **Never hardcode a colour in a widget.** There are three named exceptions. `imageRect_Fg` is
  white, the tint that leaves an image alone. The knob of a slider, and of a switch that is on,
  is white. Syntax hues go through `Color.ensureContrast` against the editor ground
  ([lexerswag.swg](../../../bin/std/modules/gui/src/controls/richedit/lexerswag.swg)).
- **Never hardcode a measure.** A literal size in a widget is a measure no theme can answer for.
- **A palette also answers for geometry.** Encre and Papier share one geometry, so switching
  between them moves no edge. A theme sheet that changes a shape writes it in `/ThemeMetrics` or
  `/ThemeImageRects`.

## Measures

Every number a widget, a dialog or an application lays out with comes from
[`ThemeMetrics`](../../../bin/std/modules/gui/src/paint/thememetrics.swg) or from the tile radius
of [`ThemeImageRects`](../../../bin/std/modules/gui/src/paint/themerects.swg). The values are in
the charter's Measures table. Each group of `ThemeMetrics` belongs to one part:

| Part | Group |
| --- | --- |
| Window corner and shadow | `surfaceWnd_*` |
| Window strip (52, floating over the view), glyph, title, window buttons | `wnd_*` |
| Corners by object: floating 12, menu 10, control 6, chip 4 | `corner_*` |
| Control height in a dialog (34) and in an inspector (28) | `control_DialogHeight`, `control_InspectorHeight` |
| Motion | `motion_*` |
| Floating shadow and inset | `floating_*` |
| Lens, sheet, inspector, mini-bar, dock, hint line, toast | `lens_*`, `infoSheet_*`, `inspector_*`, `miniBar_*`, `toolDock_*`, `hintLine_*`, `toast_*` |
| Keycap, section label | `keycap_*`, `sectionLabel_*` |
| Dialog | `dialog_*` |
| Property grid | `property_*` |
| Focus ring, tab underline, scroll bar, quiet control | `focusRing_*`, `tabItem_*`, `scrollBar_*`, `quiet_*` |

- **A radius says what the thing is.** Never inflate a control into a capsule, never square a
  control the scale rounds, and never round a hairline.
- **A shadow means "floating".** Only floating surfaces cast one. `Theme.drawFloatingShadow`
  draws it from `floating_ShadowBlur` and `floating_ShadowOffsetY`, and
  `Theme.floatingShadowReach` says how far it reaches. A floating component paints its shadow
  outside its body, before its children, and grows its invalidation padding by that reach. A
  dialog surface (`SurfaceFlags.Sheet`) keeps the reach as its margin. On Encre the floating
  shadow uses half of the palette's `shadow` alpha, and on Papier 60 %: on near-black, darkness
  reads as a hole, so there the surface parts from the work mostly by its lighter fill and its
  hairline. Never draw a shadow from an atlas tile.
- **Spacing comes from the scale** (4 · 8 · 12 · 16 · 20 · 24 · 32 · 48).
- **A reading column has a measure**: about 900 for code and 640 for prose, centred.

## Type

Inter for every word, Roboto Mono for every measure: offsets, sizes, counts, durations, paths,
hex values, line numbers, dates in a list. If a reader would compare it digit by digit, it is
mono. Sizes and weights per role (page title, sheet title, dialog title, body, section label,
large fact) are in the charter's Type section. The toolkit ships four upright Inter weights, and
each role takes one: `Light` for a large fact, `Regular` for body text, `SemiBold` for a section
label and for a name that leads a row, `Bold` for titles. Roboto Mono has only regular and bold.

A section label is always `Gui.SectionLabel`. Nobody shapes their own small capitals.

## Controls

The charter's Controls section and the pictures
[gui.controls.ink](../../../backlog/design/imgs/gui.controls.ink.png) and
[gui.controls.paper](../../../backlog/design/imgs/gui.controls.paper.png) give every control in
every state. [`controls.charter.test.swg`](../../../bin/std/modules/gui/src/tests/controls.charter.test.swg)
and its goldens hold the measurable part. Implementation notes:

- **Push buttons** have four forms: primary (`btnPush_Strong*`), secondary (`btnPush_*`), quiet
  (`btnPushFlat_*`) and destructive (`btnPush_Destructive*`). Use one primary per surface: two
  filled buttons are two answers to what Enter does. A button that is on uses
  `btnPush_Alternate*` (the Arc selection ground, Arc text, a faint Arc ring).
- **Icon buttons** have a soft glyph and the raised ground on hover. When checked they take the
  Arc selection ground, an Arc glyph and a faint Arc ring, with no underline and no Voltage. The
  cell keeps its size in every state.
- **Quiet controls**, such as the words of a header that open a menu ("Name ▾") or act, are
  `IconButton.createQuiet` with `setQuietText`. Do not build them from a flat button and a label.
- **Steppers** (`Gui.Stepper`) are a field with a quiet `−` and `+` at its ends and the value in
  mono.
- **Tabs** are words as wide as themselves, `tabItem_WordGap` apart, with a 2 px Arc underline
  exactly under the active word. There is no box and no ground behind the bar.
- **Lists, trees, headers and menus** use rows of 30, the raised ground on hover, and the Arc
  selection ground for the chosen row. Measures in a row are faint mono. A menu shortcut is faint
  mono at the right, a `✓` is Arc, and a separator is one hairline inset 10. A menu opened from
  an icon button joins it (see
  [design-swag-identity](../design-swag-identity/SKILL.md#join-an-icon-menu-to-its-button)).
- **Scroll bars** are `scrollBar_Size` thick. They rest invisible and show while the view scrolls
  or the pointer is over them, then fade after `motion_ScrollRest`.
- **Tooltips** use the `tip` tone: the surface on Encre, ink with paper text on Papier.
- **Colour pickers** use swatches on the chip corner with a ring around the chosen one, and show
  the exact value in mono.

## The Property Grid

The four `PropertiesKind` layouts and `PropertiesCtrl` follow the charter's Property grid section
and its pictures, [gui.properties.kinds](../../../backlog/design/imgs/gui.properties.kinds.png)
and [gui.properties.ctrl.paper](../../../backlog/design/imgs/gui.properties.ctrl.paper.png). In
every kind:

- section labels have no band behind them;
- a changed value gets a `property_ModifiedMarkSize` Arc dot and a faint `↺`;
- read-only is faint with a lock glyph;
- errors are a critical ring and a critical-dot line;
- notes are an information notice;
- mixed values read "Mixed values" in faint italic;
- the layout menu is joined to its `•••` button;
- no border goes around an individual setting, and no box goes around a section.

## Theme Sheets

A sheet is tweak text with four folders: `/ThemePalette`, `/ThemeColors`, `/ThemeMetrics` and
`/ThemeImageRects`. `Theme.applySheet` reads it twice, tokens first and individual parts second,
so the order of the folders does not matter. A value name reaches into a nested struct with `.`,
which is how a tone is written, and `$` references resolve through the same paths:

```
signature.mark      0xFF9A6B18
signature.ground    0xFF9A6B18
signature.onGround  0xFFFBF7EF
btnPush_Normal.radius   3
```

A whole theme is the first folder and nothing else. Copy
[`bin/examples/modules/gui10/src/sepia.tweak`](../../../bin/examples/modules/gui10/src/sepia.tweak)
to start one. Sheets are the only way an application or a user adds a third look.
`Application.loadTheme(name)` resolves `themes/<name>.tweak` through the resource bundle. An
application theme starts from Encre or Papier and changes tokens. It does not reopen the roles:
Voltage still acts and Arc still chooses. The two built-in palettes stay in code, because they
are the specification and they are checked when the module compiles.

## Verify With gui10 And The Charter Pictures

[`bin/examples/modules/gui10`](../../../bin/examples/modules/gui10) is the theme inspector:

```
swc tools/examples.swgs run gui10 --run-arg=--light --run-arg=--widgets
```

`--dark` (Encre), `--light` (Papier) and `--sheet` choose the theme. `--colors`, `--palettes`,
`--metrics`, `--widgets` and `--components` choose the page:

- **Colors** shows every `ThemeColors` value over its grounds.
- **Palettes** shows the same values across the three themes. Run it after any change to `apply`.
- **Metrics** shows every `ThemeMetrics` value.
- **Widgets** shows every widget in every state. Its **focus rings** switch turns on
  `ApplicationOptions.showFocusRings`, which draws the ring on every traversal stop at once.
- **Components** shows the lens, the sheet, the inspector, the mini-bar, the dock and the hint
  line.

Put each page beside the charter picture of the same theme and compare control by control:
corner, ring, fill, glyph, accent. A control that differs from its picture is a finding even
when every test passes. The pages are built by reflection, so do not hand-list names there. Any
other singular state you would otherwise have to drive the surface into deserves the same
treatment: a diagnostic in `ApplicationOptions` and a switch on the wall.

## Validation

After changing `apply`, a palette, a measure, or a widget's look:

1. `swc tools/std.swgs dm test gui --test-file theme.colors.test.swg --test-file theme.sheet.test.swg --test-file themestyle.test.swg --test-file controls.charter.test.swg`
2. A theme change crosses widgets and applications, so run the complete golden campaign:
   `swc tools/goldens.swgs dm test`. Each mismatch leaves a `.actual.png` beside its golden.
   (`SWAG_GOLDEN_CONTINUE=1` collects every mismatch of a test in one run; see
   [validate-swag-changes](../validate-swag-changes/SKILL.md).)
3. **Review every `.actual` as a whole screen against its charter picture, in Encre and Papier.**
   Do not look only at the diff, and do not look only at the part you meant to change. A golden
   that changed in a part you did not touch is a finding. Promote each reviewed snapshot on its
   own by moving its `.actual.png` over its golden. Never run `swc tools/goldens.swgs accept` (or
   bare `goldens.swgs`): it promotes every snapshot on disk, reviewed or not.
4. `swc tools/examples.swgs dm smoke gui10`, then look at Encre, Papier and the sheet theme in
   gui10.

Apply [validate-swag-changes](../validate-swag-changes/SKILL.md) for any further consumers.
