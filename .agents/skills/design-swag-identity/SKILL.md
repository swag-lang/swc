---
name: design-swag-identity
description: Apply the Swag visual identity to the logo, favicons, generated documentation, the website, the VSCode theme, and any new surface. Use whenever adding or changing a brand asset, a stylesheet, a page layout, an editor theme, a color, or an icon anywhere in this repository.
---

# Design The Swag Identity

Swag is a compiler that runs your program while it compiles it. The identity says the
same thing: everything is **cut from a grid**, in **one accent over one ink**. Nothing is
rounded, nothing is decorative, and nothing is added that does not carry information.

A reader must recognize a Swag surface from three things alone, before reading a word:
the cut, the voltage, and the ink.

**Cut is not the same as rough.** Every edge sits where a rule puts it, and every cut is
measured. What the identity refuses is softness, not craft: a form that looks hacked out
of a slab has missed it as badly as one that looks upholstered.

## Hold The Three Constants

1. **The cut.** Every corner the identity opens is cut at 45 degrees, never rounded. The
   cut is a vocabulary, not a decoration: its width says what the corner is, and a corner
   left square says the form stops there on purpose.
2. **The voltage.** Exactly one accent, `#F7F900`, used for the mark, one rule per
   heading, active state, and nothing else. An accent that appears everywhere accents
   nothing.
3. **The ink.** Near-black `#0B0B0D`, not pure black, so a real black can still exist.

## Use The Palette

| Token | Value | Use |
| --- | --- | --- |
| Voltage | `#F7F900` | The mark, the heading rule, focus, the active rail |
| Ink | `#0B0B0D` | The header, the hero, the dark ground |
| Paper | `#FFFFFF` | The light ground |
| Ink text | `#1B1B1D` / `#E6E6EA` | Body on paper / on ink |
| Soft text | `#55555C` / `#A9A9B4` | Secondary prose, table descriptions |
| Faint text | `#83838D` / `#7D7D89` | Labels, counts, source links |
| Line | `#E2E2DF` / `#26262E` | Hairlines and table rules |

Kind colors carry meaning, so they are the one place several hues are allowed. Keep them
in this order and do not add to the set: namespace slate, struct blue, interface violet,
enum teal, const amber, alias cyan, attr pink, func green. Their exact values live in
`documentationStyles()` in `src/Doc/DocPage.cpp`.

Never place voltage on paper: yellow on white is unreadable. On a light ground the mark
is ink.

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

`tools/web.bat` runs it before generating the pages, so the assets the pages link are
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
4. Copy the icon into the VSCode extension with `tools/vsix.bat`.

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
- **No script.** A page is one static file. Interaction that needs more than CSS —
  `<details>`, `:target`, `:hover` — is not added. A unit test enforces this.

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

## Match The Editor

`vscode/themes/swag-dark.json` uses the same token colors as the documentation, so code
looks the same in the editor and on the page. The mapping is fixed:

| Token | Color | Documentation class |
| --- | --- | --- |
| comment | `#7AA86A` | `SCmt` |
| keyword, declaration, modifier, constant.language | `#74AAE0` | `SKwd` |
| keyword.control | `#C48FD0` | `SLgc` |
| entity.name.function | `#E8A06A` | `SFct` |
| entity.name.function.intrinsic | `#CBB45C` | `SItr` |
| entity.name.type, class | `#56C2B3` | `SCst` |
| storage.type | `#E0B464` | `STpe` |
| constant.numeric | `#9EC98F` | `SNum` |
| string | `#E0937C` | `SStr` |
| preprocessor, attribute | `#9A9AA6` | `SCmp`, `SAtr` |
| invalid | `#FF6666` | `SInv` |

Change one side and change the other in the same commit.

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
   `tools/web.bat dm`.
2. Look at a page in both palettes and at a narrow width before calling it done.
3. Look at the mark itself at 16, 32, and 128 pixels, not only at the size you drew it.
   If the counters close up, the crop is wrong before the mark is.
4. Confirm no page gained a script element, an external font, or a second accent.
5. When the geometry moved, confirm the four consumers agree: the generated assets, the
   inlined `--swag-mark`, the extension icon, and the mark inlined in `bench/`.
