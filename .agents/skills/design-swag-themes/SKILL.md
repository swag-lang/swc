---
name: design-swag-themes
description: Add, change, or review a GUI theme color, a palette token, or the way a widget picks its colors. Use whenever touching bin/std/modules/gui/src/paint/theme*.swg, adding a widget that needs a new themed part, writing a theme sheet, or judging whether an interface reads correctly in every shipped palette.
---

# Design Swag Themes

A theme is not a list of colors. It is a small set of decisions, and one rule per painted
part that turns those decisions into pixels. Everything in this skill follows from that.

## The Two Layers

[`ThemePalette`](../../../bin/std/modules/gui/src/paint/themepalette.swg) holds the decisions:
roughly thirty tokens — grounds, rules, ink, accent, status, veil, chrome.

[`ThemeColors`](../../../bin/std/modules/gui/src/paint/themecolors.swg) holds one value per
painted part, and **every one of them is derived** by `ThemeColors.apply(palette)`. No palette
writes a semantic color directly. `apply` is the specification: read it to know what a part of
the interface is allowed to be.

Four palettes ship: `darkPalette`, `lightPalette`, `swagDarkPalette`, `swagLightPalette`. Each
is a token list and nothing else.

### Why this shape, and what it rules out

The previous model wrote all three hundred colors by hand for the neutral palettes, and let the
Swag palettes override a subset of them. That is a delta, and a delta is a promise nobody can
keep: the dark Swag palette answered for `btnPushFlat_HotBk` and the light one did not, so a
black-and-white interface kept the pale blue hover of the neutral light theme it was derived
from. Twenty-two values were asymmetric that way. Deriving every color from tokens makes that
class of defect unrepresentable — a palette answers for everything or it does not compile.

## Rules

### Add a color only when a part cannot reuse one

Before adding a field to `ThemeColors`, find the part in `apply` that already means what you
want. A new field is justified when a widget paints something no existing rule covers, not when
a caller wants a different value in one place — that is what a theme sheet is for.

Every new field needs:

1. a one-line doc comment naming the part, not the color (`// Border of a hovered field.`);
2. a line in `apply` deriving it from tokens, never a literal;
3. a value in every palette, which it gets for free by being derived.

A field nothing reads is deleted, not kept "for later". Nine of them were.

### Add a token only when the derivation cannot answer

A token is a decision a designer must make. `hot` is a token because no formula knows how far a
hover should travel on an arbitrary ground. `btnPush_HotBk` is not, because it is `hot`.

The bar: could two reasonable themes disagree about it, in a way no other token predicts? If
not, derive it. The notice grounds are tokens because recognizing a warning is a hue, not a step
of lightness. The veil strengths are not: they are one ink at three alphas.

When a token is a decision rather than a color, make it one. `railed` is a `bool`, because a
rail drawn in anything but the accent marks the active item in a language the rest of the
interface does not speak — and because changing the accent then moves the rail with it.

### Keep the accent scarce, and never read on it

The accent points; it is not a ground for text. A palette whose accent is a brand color —
Voltage, Ink — cannot wash a hovered row with it, which is why `selectHot` and `selectPressed`
exist beside `hot` and `pressed`. A system-blue palette sets them to a tint of its accent; a
brand palette repeats the neutral pair. Both work, and the widgets never know.

`onAccent` is the only ink allowed on a fill of `accentGround`. When a widget draws a glyph over
something that may or may not be filled, it has to pick between the two — see `checkedInk` in
`apply`, where a checked tool takes the accent beside a rail and `onAccent` over a fill. Getting
this wrong makes a blue glyph disappear into a blue square.

### The accent has two roles, and one palette may split them

`accent` is what the theme **points** with — a rail, a ring, a rule, a mark — so it has to read
as a hairline on the grounds. `accentGround` is the block it **fills**, and carries `onAccent`.
Nearly every palette gives them the same value; a brand color is where they part. Voltage fills
beautifully under ink and vanishes as a hairline on paper, so `swagLightPalette` points in Ink
and still fills in Voltage — which is what keeps the two Swag modes one identity rather than a
brand theme beside a black-and-white one.

Two consequences hold whenever they differ:

- A filled action takes its border from `accent` and its fill from `accentGround`. Yellow parts
  from white by less than a tenth of a step of luminance, so a Voltage block with no rule around
  it reads as a smudge rather than as a control.
- The hot and pressed states shift the two separately: `accentHot`/`accentPressed` for the mark,
  `groundHot`/`groundPressed` for the block.

Because the two Swag palettes deliberately agree on the brand pair, the shared-color test in
`theme.colors.test.swg` finds the parts it answers for rather than listing them — it applies the
palette twice with a different pair and sets aside whatever moved. Keep that shape if you add a
part: a hand-written exception list is what lets a real mode leak slip in beside it.

### Every state must differ from the one before it

Rest, hover, press, disabled, checked. If two of them resolve to the same value the control
reports nothing at the moment the reader is deciding. `theme.colors.test.swg` asserts this for
the filled actions; hold the same bar by eye for anything new.

Disabled is the state most often got wrong: it must be **weaker** than rest, never stronger. A
disabled dial whose ring was the enabled ring, a disabled checked tool wearing the full accent
rail, a disabled icon painted white — all three shipped, and all three read as *more* available
than the enabled control beside them.

### A mark drawn over a control takes that control's shape

The keyboard-focus ring is the worked example, and every rule it follows applies to anything else
drawn *over* a control rather than *by* it.

- **Take the corner from what you are marking, not from the theme.** A palette decides the shape of
  a control — `setSwagGeometry` points a push button at the edit tiles, so the same button is a
  capsule under one palette and a square-cornered tile under another. A mark with a corner of its
  own therefore crosses its own control at four places in exactly one of them.
  [[Gui.ThemeImageRect.radius]] is where a tile says what corner it draws, so a widget publishes it
  from the tile it painted ([[Gui.Wnd.focusRingRadius]]) and the mark steps it in by its own inset
  to stay concentric.
- **Keep clear of the border, and check that you did.** A mark inset by less than the border it
  sits inside merges with it and reads as a thicker edge rather than as a second thing. The Swag
  palettes are where this shows first, because they point and border in the same Ink.
- **A mark that points in the accent has to be told what it lands on.** The accent is invisible on
  a control filled with that same accent — a dialog's default action, a switched-on toggle, a
  picked tool. Publish the fill ([[Gui.Wnd.focusRingGround]]) and let the theme pick between
  `focusRing` and `focusRingOnAccent` by contrast. Deciding by contrast rather than by a flag each
  widget sets is what makes it hold in a palette nobody wrote the widget for — and the flag it
  replaced was, in fact, set on push buttons and forgotten on toggles and tool buttons.
- **Hug the content when the cell is not the control.** A check box laid out in a column of a form
  takes the column's width, and a ring around that encloses as much empty ground as content. Widgets
  in that shape carry `WndFlags.NoFocusRing` and draw their own mark around the marker and its
  wording — see [[Gui.Button.markerFocusRect]].

### Never hardcode a color in a widget

A literal in a widget is a color no theme can answer for. The exceptions are named and few:

- the close button keeps its own red, because "close" must not move between themes;
- `imageRect_Fg` is white, which is the tint that leaves an image alone;
- a syntax palette keeps its hues, because a reader has learned that green is a comment — but
  each hue is pushed through `Color.ensureContrast` against the editor ground, so it stays
  readable when the interface turns white. See `richeditlexerswag.swg`.

Anything else goes through `ThemeColors`.

### A palette answers for geometry too

`Theme.setSwagDark`/`setSwagLight` narrow the surface corner and point the push button at the
edit tiles. `Theme.setDark`/`setLight` put both back. Applying a palette must always be total:
a theme that only sets colors leaves square buttons under a blue accent when a surface leaves
it. If you add a geometric decision to one palette, add its inverse to `setDefaultGeometry`.

## Theme Sheets

A sheet is tweak text with four folders: `/ThemePalette`, `/ThemeColors`, `/ThemeMetrics`,
`/ThemeImageRects`. `Theme.applySheet` reads it twice — tokens first, then the individual parts
— so folder order in the file does not matter and a sheet can do both.

A whole theme is the first folder and nothing else, which is what makes a user theme a page of
text rather than three hundred lines. The worked example lives at
[`bin/examples/modules/gui10/src/sepia.tweak`](../../../bin/examples/modules/gui10/src/sepia.tweak);
copy it to start a theme.

The built-in palettes stay in code on purpose. They are the specification, they are checked when
the module compiles, and duplicating them into sheets would create two places to change one
value. Sheets are how *other people's* themes are written, and shipping the mechanism plus one
real sheet proves the path without splitting the source of truth.

`Application.loadTheme(name)` resolves `themes/<name>.tweak` through the resource bundle, so an
application ships its themes as embedded resources and a disk folder can override or add to
them.

## Verify With gui10, Not With The Apps

[`bin/examples/modules/gui10`](../../../bin/examples/modules/gui10) is the theme inspector, and
it is the tool for this work. `tools/examples.bat run gui10`.

- **Colors** — every `ThemeColors` value of the active palette, by reflection, over the grounds
  it is drawn on, with a checkerboard behind anything translucent.
- **Palettes** — the same value across all five palettes side by side, with a **flagged rows
  only** switch that keeps just the rows the dark and light Swag palettes resolve identically.
  Five may: the four of the close button, and `imageRect_Fg`. A sixth is a part that did not
  follow the reader into the other mode. Run it after any change to `apply`.
- **Metrics** — every `ThemeMetrics` value.
- **Widgets** — every widget in every state a palette answers for. Hover and press are left to
  the pointer, which is why this page is scrolled through by hand. Its **focus rings** switch turns
  on [[Gui.ApplicationOptions.showFocusRings]].

### Show a singular state on everything at once

Only one control of a surface can hold the keyboard, so the focus mark is the one state the wall
cannot show by standing still — and judging it by tabbing is one screen per control, times one pass
per palette. `showFocusRings` draws the ring on every traversal stop instead, which turns that walk
into four images and is what made the toggle and the tool button confess that their ring had never
been visible at all.

Any state with the same shape — a singular one you would otherwise have to drive the surface into —
deserves the same treatment: a diagnostic in `ApplicationOptions`, a switch on the wall, and no
attempt to reproduce it by hand.

The sheets are built from reflection, so a field added to either struct appears without touching
the example. Do not hand-list names there.

`sCrypt` and `sCapture` are the confirmation, not the instrument: they show one composition of
the theme, and the parts they do not use are exactly the ones a change breaks silently.

## Validation

After changing `apply`, a palette, or a widget's color choice:

1. `tools/std.bat test -m gui` — the palette tests pin the shipped Swag values, assert the
   dark and light palettes do not agree on more than a handful of colors, and cover the sheet
   layers.
2. The command-stream goldens under `bin/std/modules/gui/src/tests/unittests/goldens/` change
   whenever a widget's colors do. A failing test leaves its `.actual` file beside the golden it
   diverged from; `tools/goldens.bat` accepts them in bulk. Review the diff — a golden that
   changed for a part you did not touch is a finding.
3. `tools/examples.bat smoke gui10` walks every page of every palette.
4. Look at the four palettes in gui10 before saying the change is done.
