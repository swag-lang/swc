---
name: design-swag-identity
description: Apply the Swag visual identity to the logo, favicons, generated documentation, the website, the VSCode theme, and any new surface. Use whenever adding or changing a brand asset, a stylesheet, a page layout, an editor theme, a color, or an icon anywhere in this repository.
---

# Design The Swag Identity

Swag is a compiler that runs your program while it compiles it. The identity says the
same thing: everything is **cut from a grid**, in a **closed set of tones over one ink**.
Corners are measured, decoration is absent, and nothing is added that does not carry
information.

A reader must recognize a Swag surface from three things alone, before reading a word:
the cut, the voltage, and the ink. That has to hold on paper exactly as it holds on ink,
and holding it there costs more than repeating the same numbers — see **One Family, Two
Modes**.

**Cut is not the same as rough.** Every edge sits where a rule puts it, and every cut or
curve is measured. What the identity refuses is softness without structure, not craft: a
form that looks hacked out of a slab has missed it as badly as one that looks upholstered.

**Square is the structure; a slight corner finishes the things held inside it.** Bars, rails,
separators, document grounds and joined chrome stay square because their edges describe the
surface. A bounded control, state or panel takes a small radius so its hard right angle does not
read as unfinished. Three measures cover the family:

- **The outline of a window.** It sits on a desktop beside applications that all soften that
  corner, and carried literally the cut turns it into a slab dropped on the screen.
  `ThemeMetrics.surfaceWnd_CornerRadius` is 12 in the Swag palette — it was 8, which read as a
  bevel on a square window rather than as a decision. **A radius too small to be seen is worse
  than none**: it costs the same pixels and reports nothing.
- **The four-pixel interface corner.** Buttons, fields, icon cells, hover and selection grounds,
  standalone raised panels, thumbnails, swatches and preview tiles all take the corner the theme
  gives `btnIcon_RoundSquareBk.radius`. Reusing that one radius is what makes a selected icon,
  the hover beneath it and the panel beside it belong to the same surface.
- **The full curve.** A radio mark, circular tool or intentionally round control remains circular.
  It is a semantic shape, not a larger value on the interface-corner scale.

The bounds still hold. Keep the interface radius at four logical pixels, never inflate it into a
capsule, and never apply it to the chrome between bounded things. The result is not "friendlier";
it is more finished while the grid, the cut and the information hierarchy stay intact.

**A mark drawn over a rounded thing takes that thing's corner, stepped in by its own inset.** A
frame inset by half its weight is concentric with the cell only if its radius is the cell's minus
that same half weight; drawn at the cell's radius it crosses the cell's edge at four places. See
the focus-ring rule in [design-swag-themes](../design-swag-themes/SKILL.md), which is the same
rule for the same reason.

**Flat is the default, not a law.** The same argument that won a corner wins a gradient: what the
identity refuses is decoration, not gradation. A wash is admissible when it is **subtle** — low
enough that neither of its ends can be named as a color — and **non-invasive** — it moves nothing
the reader acts on, adds no edge, and leaves no hole when it is taken away. Elegance that stays
out of the way is permitted. Elegance that announces itself is what this chart has always called
decoration, and it is still refused.

One form has argued for it and won, and it is the pattern rather than the exception:

- **The band of a title bar.** It is the one surface of a window with no content to carry, which
  is what lets it carry the focus instead: it lights from the mark on its leading edge, falls away
  toward the caption buttons, and goes flat when the window loses the focus — where the two
  caption grounds, ten levels apart, reported nothing across a desktop. Its axis is the 45 degrees
  the identity already cuts at. Its amplitude is a palette token, `ThemePalette.captionGlow`, and
  it is zero in the neutral palettes, which follow the desktop they sit on.

Four bounds hold it, and together they are the whole clause:

1. **A gradient that can be described by its color has already failed.** The test is subtraction,
   not addition: take it away and something must be missing; look at it and nothing must have
   been added. The bound is on what the band *weighs*, not on the number that produces it: a wash
   toward a color darker than the band is spent on luminance, which the eye reads at once, and a
   wash toward one as light as the band is spent on chroma, which costs roughly three times the
   mix for the same weight. `captionGlow` is therefore 0.14 on ink and 0.42 on paper — the same
   decision, priced differently. Copying the dark number into the light palette is what shipped a
   title bar nobody could see.
2. **It carries a state, or it does not exist.** A wash that is the same in every state is paint.
3. **One per surface, and never behind content.** Panels, cards, buttons, rows, rules, icons and
   the mark stay flat. A gradient under something that has to be read costs legibility and buys
   nothing.
4. **The same gradient in every application.** One hue per app is the end of the family, however
   good each one looks alone — see the voice section below, which is the same rule for text.

## Hold The Three Constants

1. **The cut.** Every corner the identity opens is cut at 45 degrees. The cut is a
   vocabulary, not a decoration: its width says what the corner is, and a corner left
   square says the form stops there on purpose. The refusal is of softness as a default,
   not of every curve — see below.
2. **The voltage.** One signature, `#F7F900`, for the mark, one rule per heading, the
   active state, and nothing else. A signature that appears everywhere signifies nothing.
   It is not the only color the identity owns — see the tone set below — but it is the only
   one that says *this is the thing to do*.
3. **The ink.** Near-black `#0B0B0D`, not pure black, so a real black can still exist.

## Use The Palette

| Token | Value | Use |
| --- | --- | --- |
| Voltage | `#F7F900` | The signature: the mark, the heading rule, focus, the active rail |
| Arc | `#38BDF8` | The second tone: a link, another page, a selected row, an alternate action |
| Ink | `#0B0B0D` | The header, the hero, the dark ground, and the ink every block carries |
| Paper | `#FFFFFF` | The light ground |
| Ink text | `#1B1B1D` / `#E6E6EA` | Body on paper / on ink |
| Soft text | `#55555C` / `#A9A9B4` | Secondary prose, table descriptions |
| Faint text | `#83838D` / `#7D7D89` | Labels, counts, source links |
| Line | `#E2E2DF` / `#26262E` | Hairlines and table rules |

Kind colors carry meaning, so they are the one place several hues are allowed. Keep them
in this order and do not add to the set: namespace slate, struct blue, interface violet,
enum teal, const amber, alias cyan, attr pink, func green. Their exact values live in
`documentationStyles()` in `src/Doc/DocPage.cpp`.

## One Family, Two Modes

The chart used to own exactly one accent, and that one accent was a dark-mode color. Voltage
points and fills on ink; on paper it can only fill. Carried literally, the light theme pointed
in ink instead — and a theme whose every rail, ring, rule and hovered border is black is a
black-and-white theme with a yellow button in it, which is not the same identity read the other
way up. Three rules replace that, and together they are what makes a Swag surface recognizable
at a glance in either mode.

1. **A tone is one color in three roles.** What it *points* with, the block it *fills*, and the
   ink that block carries. Most tones give the first two the same value; the identity lives in
   the ones that cannot.
2. **A block is the same color in every mode; only the mark adapts.** Voltage fills at `#F7F900`
   on ink and on paper alike, and Arc fills at `#38BDF8` in both — that invariance is what the
   reader recognizes. What a mode changes is only how far the mark has to be deepened before it
   separates from the page, and the deepening keeps the hue: a light Swag surface points in a
   dark Voltage, never in ink. The interface derives that rather than writing it down; see
   [design-swag-themes](../design-swag-themes/SKILL.md).
3. **The signature is scarce; the second tone is not the signature.** Voltage says *do this*, so
   it stays on the one filled action, the focus, the active rail, and the heading rule. Arc says
   *somewhere else, something of another kind*: a link, the page you can leave to, a selected
   row, the alternate action beside the primary one. A row washed in Voltage cannot be read at
   all, which is precisely the job the second tone exists to take. Two tones is the whole
   identity vocabulary — status colors are not tones you may borrow for emphasis, and a third
   identity hue is a new brand, not a new option.

## Cut The Mark

The mark is a three-bar `S` cut out of a block, leaning right. Twelve corners, each opened
by a cut whose width says which corner it is.

| Measure | Units | Meaning |
| --- | --- | --- |
| Grid | 100 | Height of the mark |
| Width | 84 | Width before the lean |
| Stroke | 20 | Every bar and stem |
| Gap | 20 | Every counter |
| Shoulder | 30 | The long cut on the top-left and bottom-right corners |
| Terminal | 12 | The cut that closes a free end |
| Notch | 8 | The short cut on each of the four corners of a counter |
| Lean | 0.14 | Horizontal shift per unit of height |

Three rules hold those numbers together. Break one and the mark stops being machined:

1. `3 * stroke + 2 * gap == grid`. A counter weighs exactly what a bar weighs, and five of
   them fill the height. Move one and move another.
2. `terminal + notch == stroke`. At a free end the two cuts meet, so the bar comes to a
   point instead of keeping a square corner.
3. Every corner is cut. The two shoulders open the form — they are what separate the mark
   from a seven-segment `5` — and the four notches keep a counter from reading as a slot
   punched through a slab: it flares where it meets the air, and is cut back where it stops.

The 45 degrees are measured on the grid, before the lean shears them. An edge in a
generated file is therefore not at 45 degrees on screen, and is not to be "corrected".

Do not round anything, and do not add a container the mark has to sit inside.

The letter itself is settled. It has been retuned once — the counter brought up to the
weight of a bar, the shoulders lengthened, the four notches added — and every attempt to
replace it was rejected: a gradient ribbon, a folded ribbon, a faceted gem, a fragmenting
`S`, and a drawn `SWAG` wordmark. Tune a measure when a size demands it; do not redraw the
letter.

`web/tools/brand.swgs` is the single definition of that geometry. It builds the mark once
as a `Pixel.LinePath` and hands it to the two writers that consume it — `Pixel.Svg.Document`
for the vector masters and `Pixel.ImageCanvas` for the rasters — so no asset can disagree
with another about where an edge is. The script owns the shape and nothing else; anything
generic it needs belongs in `bin/std`, not in the script.

`tools/web.swgs` runs it before generating the pages, so the assets the pages link are
always cut from the current definition. To regenerate them alone:

```
swc web/tools/brand.swgs
```

It writes `web/imgs/swag_mark.svg`, `web/imgs/swag_mark.png`, `web/imgs/swag_icon.png`,
`web/favicon.svg`, and `web/favicon.ico`. Never edit those files by hand. The favicon carries
16, 32, and 48 pixel entries, each cut at its own size rather than downsampled, so the
counters of the mark stay open in a browser tab.

When the geometry changes, four places must be updated in the same change. Only the first
is automatic; the other three hold a copy of the path, and a stale copy is invisible until
two surfaces sit side by side:

1. Run the generator.
2. Paste the new path and its `viewBox` into `--swag-mark` in `documentationStyles()`,
   where the mark is inlined as an alpha mask so a generated page stays one self-contained
   file.
3. Paste the same path into `bench/page_template.html`, and into the `bench/bench.html` it
   has already produced.
4. Copy the icon into the VSCode extension with `swc tools/vsix.swgs`.

## Regenerate The Syntax Image

`web/imgs/syntax.png` shows the language in its own colors. It is not a screenshot of an
editor: it is a capture of a page the compiler colored itself, which is why it can never
show syntax the compiler no longer accepts.

1. Edit the snippet in `web/tools/syntax/src/syntax.md` when the language moves.
2. Generate the page: `swc doc --module web/tools/syntax --doc-output-dir <out>`.
   That module pins `theme = .Dark`, so the capture matches the editor theme.
3. Capture the `.code-block` element at a device scale of 2, and write the result to
   `web/imgs/syntax.png` and `vscode/images/syntax.png`.

## Place The Mark

- Keep clear space of at least one stroke (20 units, scaled) on every side.
- Below 24 pixels, use the icon tile rather than the bare mark.
- **A mark has two cuts, and the ground decides which one.** The tile ships flattened — one glyph
  over one ink ground — because that is what a taskbar, a file list and an installer need. Drawn
  on a dark surface that already has a ground, the tile reads as a black square around the glyph,
  so the ground is keyed out and the glyph floats free. On a light surface it cannot be: the glyph
  is Voltage, and Voltage on paper is a mark nobody sees. There the tile stays, and the window
  carries the identity as the block of brand a light surface is supposed to carry it with. Decide
  by contrast against the actual band — `Gui.markReadsOn` — never by a flag the caller sets, or
  the mark disappears from every title bar in the light theme, which is exactly what happened.
- **A tile has two crops, and they are not interchangeable.** An application icon is looked
  at, so the mark holds 56% of it and keeps its clear space. A favicon is glanced at: at
  sixteen pixels that margin costs the counters, so the mark holds 74% and the margin is
  spent on the form. Both live in `brand.swgs` as `ICON_FILL` and `FAVICON_FILL`.
- The mark is the whole logo. There is no drawn wordmark: `SWAG` is set in type, 800
  weight, `.2em` tracking, beside the mark. A drawn wordmark was tried and rejected; it
  read as a novelty typeface and fought the mark.
- The mark is never stretched, outlined, given a shadow, or recolored outside the two
  palette values.

## Set The Type

- Interface and prose: the system sans stack.
- Every identifier, signature, type, kind label, and count: the monospace stack. If it is
  a name the compiler knows, it is monospace.
- Section labels and kind chips: uppercase, `.09em` to `.16em` tracking, small. They are
  labels, not headings.
- Set the documentation content column to a maximum of `120ch`. Resolve that measure on
  the shared prose-font container, then make paragraphs, lead text, code, tables, API
  blocks, and callouts fill it; never reapply the `ch` measure on descendants whose font
  family or size would produce a different right edge.
- One `h1` per page. An `h2` carries a leaning voltage rule above it; nothing else does.

## Build The Interface

The generated documentation is the reference implementation of this chart. When adding a
surface, take these rules from it:

- **The cut appears on repeated elements, not on big ones.** Kind chips carry the cut; the
  hero panel carries it once. Cards, tables, and callouts stay square.
- **One accent bar per group.** An API entry gets a left rule in its kind color; a callout
  gets a left rule in its severity color. Never both a rule and a fill and a border.
- **Hairlines, not boxes.** Tables have horizontal rules only. Vertical rules are noise.
- **State is a rule, not a fill.** Hover and active states move or reveal a rule; they do
  not repaint a block.
- **Both palettes, always.** Every rule must be written for light and dark. Dark is
  selected by `prefers-color-scheme` unless the page commits with `data-theme`.
- **One script, and it is the search box.** A page is one static file that reaches nothing:
  no server, no second file, no font, no network. Interaction that CSS can carry —
  `<details>`, `:target`, `:hover` — is written in CSS and stays there. Exactly one exception
  was argued and won: a page over a few hundred symbols is not navigable by scrolling, so the
  page prints its own index and one inline script that searches it. That index covers the page
  it sits in and nothing else, which is what keeps the file self-contained. A unit test enforces
  the count: one `<script`, inline, no `src`.

These rules are written for a generated page, where a reader scans a long document and a rule
tells them where one entry ends. **On an application surface a line costs more than it pays.**
The same instinct applied to a window produces a grid of boxes: a border around each panel, a
divider between each block, and a rail beside each of them. There, raise a group with its own
fill first, space it second, and rule it only when neither works — and expect to draw one rule,
not one per group. [build-swag-standard-apps](../build-swag-standard-apps/SKILL.md) governs an
application surface; this section governs a page.

**Air is part of the identity, on a page and in a window alike.** Nothing that does not carry
information includes the space a form does not need: a glyph blown up until it fills its cell, a
control sized for a fingertip, a panel wider than the data in it. A Swag surface is recognized as
much by what it leaves empty as by the cut, the voltage, and the ink — clean first, dense never.
The size ceilings that hold that line in an application live in
[build-swag-standard-apps](../build-swag-standard-apps/SKILL.md).

## Match Every Syntax Surface

`vscode/themes/swag-dark.json`, the generated documentation colorizer, and
`RichEditLexerSwag` use the same token colors, so code looks the same in VSCode, on a page,
and in a Swag GUI editor. The mapping is fixed:

| Token | Color | Documentation class |
| --- | --- | --- |
| comment | `#7AA86A` | `SCmt` |
| keyword, declaration, modifier, constant.language | `#74AAE0` | `SKwd` |
| keyword.control | `#C48FD0` | `SLgc` |
| entity.name.function | `#E8A06A` | `SFct` |
| entity.name.function.intrinsic | `#CBB45C` | `SItr` |
| built-in `Swag` namespace | `#94A3B8` | `SNsp` |
| entity.name.type, class | `#56C2B3` | `SCst` |
| storage.type | `#E0B464` | `STpe` |
| constant.numeric | `#9EC98F` | `SNum` |
| string | `#E0937C` | `SStr` |
| preprocessor, attribute | `#9A9AA6` | `SCmp`, `SAtr` |
| invalid | `#FF6666` | `SInv` |

Change one surface and change the other two in the same commit. The RichEdit lexer passes these
dark-palette values through `Color.ensureContrast` so the same hues remain legible on every GUI
theme. When the compiler intrinsic catalog changes, compare both syntax lexers against
`Tokens.Def.inc`; neither keeps a partial hand-written catalog.

## Keep The Voice

The identity is not only visual: a Swag surface is recognizable in a terminal too, and by
the same means. Nothing is added that does not carry information.

- **The style comes from invariance, not from variation.** One mark, `◆`. One sign-off,
  `clean` / `passed` / `stopped`. One closed table of step verbs, each a pair of gerund and
  participle — `checking` / `checked`. No random line, no message of the day, no rotating
  emoji: anything that varies for effect is stale in a week.
- **Swag never talks over an error.** Character is allowed exactly where the reader has no
  problem to solve — the opening line, the step names, the sign-off, the nothing-to-do
  case. From the first diagnostic on, the voice is dry, dense, and useful.
- **One grammar for every failure**, whether it comes from compile time, run time, the
  sanitizer, or the compiler breaking itself.

Console output, diagnostics, and documentation prose follow
[write-swag-compiler-messages](../write-swag-compiler-messages/SKILL.md).

## Verify

1. Regenerate the assets and the site: `swc web/tools/brand.swgs`, then
   `swc tools/web.swgs dm`.
2. Look at a page in both palettes and at a narrow width before calling it done.
3. Look at the mark itself at 16, 32, and 128 pixels, not only at the size you drew it.
   If the counters close up, the crop is wrong before the mark is.
4. Confirm no page gained a second script element, an external font, or a second accent.
5. When the geometry moved, confirm the four consumers agree: the generated assets, the
   inlined `--swag-mark`, the extension icon, and the mark inlined in `bench/`.
