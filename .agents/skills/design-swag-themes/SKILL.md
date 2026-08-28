---
name: design-swag-themes
description: Add, change, or review a GUI theme color, a palette token, or the way a widget picks its colors. Use whenever touching bin/std/modules/gui/src/paint/theme*.swg, adding a widget that needs a new themed part, writing a theme sheet, or judging whether an interface reads correctly in every shipped palette.
---

# Design Swag Themes

A theme is not a list of colors. It is a small set of decisions, and one rule per painted
part that turns those decisions into pixels. Everything in this skill follows from that.

## The Two Layers

[`ThemePalette`](../../../bin/std/modules/gui/src/paint/themepalette.swg) holds the decisions:
roughly thirty tokens — grounds, rules, ink, five tones, veil, chrome.

[`ThemeColors`](../../../bin/std/modules/gui/src/paint/themecolors.swg) holds one value per
painted part, and **every one of them is derived** by `ThemeColors.apply(palette)`. No palette
writes a semantic color directly. `apply` is the specification: read it to know what a part of
the interface is allowed to be.

Three palettes ship: `darkPalette`, `lightPalette`, and `swagDarkPalette`. Each
is a token list and nothing else.

### A color is a tone, and a tone is three questions

`ThemeTone` is `{mark, ground, onGround}`: what the tone **points** with, the block it **fills**,
and the **ink** that block carries. A theme never has "a color" — it has those three, and asking
for them together is what makes a tone impossible to half-answer.

Five tones, and there is no sixth. `signature` and `alternate` are what the family is recognized
by; `critical`, `caution` and `info` are what happened. The split matters:

- **The identity tones keep their block and ink together.** The Swag palette fills Voltage at
  `#F7F900` and Arc at `#38BDF8`, and both carry Ink.
- **The status tones adapt freely.** A notice has to be read before it has to be recognized, so
  a dark band with light ink becomes a pale band with dark ink and nothing is lost.

### The mark is derived, never written twice

`apply` deepens each tone's mark until it clears `MarkContrast` against **the ground it is
nearest** — not the extreme ground of the theme. A mid-tone accent clears a near-black
application ground easily and vanishes on the raised grey of the panel drawn over it, which is
what the shipped neutral blue did for as long as it was written by hand.

That one derivation lets a palette write `ThemeTone.from(Voltage, Ink)` and get a legible hairline
on every ground: unchanged on ink, walked down to a dark Voltage on paper. The hue survives, which
is the point.

A palette may still write a mark that has nothing to do with its block, and `apply` will keep it:
that is how a status tone names an ink unrelated to its band. `apply` only ever moves a mark that
does not read.

### Why this shape, and what it rules out

The previous model wrote all three hundred colors by hand for the neutral palettes, and let the
Swag palette override a subset of them. That is a delta, and a delta is a promise nobody can
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
of lightness. `band` is a token because a plain information strip must remain distinct from
`ground`, `view`, and `panel` even when `raised` deliberately shares one of them. The veil
strengths are not: they are one ink at three alphas.

When a token is a decision rather than a color, make it one. `railed` is a `bool`, because a
rail drawn in anything but the signature marks the active item in a language the rest of the
interface does not speak — and because changing the signature then moves the rail with it.
`captionGlow` is an `f32` for the same reason: whether the chrome of a window is washed in the
brand is a decision no other token predicts, and the two ends of the band are derived from it —
`wnd_CaptionBkLead` toward `signature.ground`, because a wash is a fill and the mark that
*points* is a dark Voltage on paper. Set it to zero and the two ends collapse onto the band,
which is how a theme that follows the desktop keeps a flat bar.

`captionGlow` is a mix, so its visual weight depends on the band and the direction it travels.
The Swag dark palette spends 0.14 toward Voltage; the neutral palettes keep it at zero. Judge a
new value on its own ground rather than copying another palette's number.

### Keep the signature scarce, and spend the second tone instead

The signature says *do this*: the one filled action, the focus, the active rail, the checked
tool. It is not a ground for text and it is not a wash. A palette whose signature is a brand
color cannot tint a hovered row with it — a row washed in Voltage is unreadable — and that is
precisely the work `alternate` exists to take.

So `selectHot` and `selectPressed` carry the **alternate** tone in the Swag palette: a list, a
menu, a tab bar and a selected row are where a reader spends most of their time, and washing them
at the weight the neutral hover used to carry is how a theme gains a hue without gaining a
weight. They stay separate tokens rather than derivations because how far a wash may travel is a
decision, but a Swag palette that sets them to a grey has given the mode back its greyness.

The other parts that belong to the second tone, and not to the signature:

- **a link** (`url_Text`, `toolTip_Link`) — a link means *somewhere else*, which is the tone's
  whole meaning. Pointed with the signature, a light theme wrote every link in ink;
- **the alternate action** (`PushButtonForm.Alternate`, the `btnPush_Alternate*` family) — the
  button that leads to another page beside the one that does the work of the surface. A surface
  shows one strong action and at most one alternate; two filled buttons of the same tone are two
  primary actions.

`onGround` is the only ink allowed on a fill of `ground`. When a widget draws a glyph over
something that may or may not be filled, it has to pick between the two — see `checkedInk` in
`apply`, where a checked tool takes the mark beside a rail and `onGround` over a fill. Getting
this wrong makes a blue glyph disappear into a blue square.

### A tone's mark and block may differ, and then two consequences hold

- A filled action takes its border from `mark` and its fill from `ground`. Yellow parts from
  white by less than a tenth of a step of luminance, so a Voltage block with no rule around it
  reads as a smudge rather than as a control — and on paper that rule is a deepened Voltage,
  which is why the border is the mark rather than a color of its own.
- The hot and pressed states shift the two separately: `accentHot`/`accentPressed` for the mark,
  `groundHot`/`groundPressed` for the block.

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
  a control — `setSwagGeometry` points actions and rectangular tool cells at the four-pixel edit
  tile, while another palette may keep a capsule or a hard square. A mark with a corner of its
  own therefore crosses its own control at four places in exactly one of them.
  [[Gui.ThemeImageRect.radius]] is where a tile says what corner it draws, so a widget publishes it
  from the tile it painted ([[Gui.Wnd.focusRingRadius]]) and the mark steps it in by its own inset
  to stay concentric.
- **Keep clear of the border, and check that you did.** A mark inset by less than the border it
  sits inside merges with it and reads as a thicker edge rather than as a second thing. The Swag
  palette is where this shows first, because it points and borders in the same Ink.
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

`Theme.setSwagDark` narrows the surface corner and points push buttons, rectangular
tool cells, their full checked states, and standalone panels at the same four-pixel tile. Hover
and selection grounds reuse `selectionBox_Bk`, which carries that radius through lists, headers
and property rows. `Theme.setDark`/`setLight` put palette-specific geometry back. Applying a
palette must always be total: a theme that only sets colors leaves the previous palette's shapes
under its new accent. If you add a geometric decision to one palette, add its inverse to
`setDefaultGeometry`.

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

`$` references resolve through the same paths. Before this the tweak reader could only name flat
fields, which left `/ThemeImageRects` registered and impossible to write.

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
it is the tool for this work. `swc tools/examples.swgs run gui10`.

It opens on the palette and the page the command line names, so comparing a change against the
palettes it did not mean to touch is a script rather than sixteen windows driven by pointer:

```
swc tools/examples.swgs run gui10 --run-arg=--light --run-arg=--widgets
```

`--dark`, `--light`, `--swagdark`, `--sheet` choose the theme variant; `--colors`,
`--palettes`, `--metrics`, `--widgets` choose the page.

- **Colors** — every `ThemeColors` value of the active palette, by reflection, over the grounds
  it is drawn on, with a checkerboard behind anything translucent.
- **Palettes** — the same value across the three shipped palettes and the sheet-written example,
  side by side. Run it after any change to `apply`.
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

`sVaultDrive` and `sSnapForge` are the confirmation, not the instrument: they show one composition of
the theme, and the parts they do not use are exactly the ones a change breaks silently.

## Validation

After changing `apply`, a palette, or a widget's color choice:

1. `swc tools/std.swgs dm test gui --test-file theme.colors.test.swg --test-file theme.sheet.test.swg --test-file themestyle.test.swg`
   — the palette tests pin the shipped Swag values, assert every
   mark reads on every ground of its own palette and cover the sheet layers.
2. The command-stream goldens under `bin/std/modules/gui/src/tests/goldens/` change
   whenever a widget's colors do. A failing test leaves its `.actual` file beside the golden it
   diverged from; `swc tools/goldens.swgs` accepts them in bulk. Review the diff — a golden that
   changed for a part you did not touch is a finding.
3. The applications keep goldens of their own, and a palette change reaches them:
   `swc tools/apps.swgs dm test sSnapForge` is the one that shows a whole surface. Look at the
   `.actual` image before accepting it; that picture is the change.
4. `swc tools/examples.swgs dm smoke gui10` walks every page of every palette.
5. Look at the three shipped palettes and the sheet-written example in gui10 before saying the
   change is done.

Apply [validate-swag-changes](../validate-swag-changes/SKILL.md) to add only the widget golden files
and application consumers whose rendering path changed.
