---
name: design-swag-identity
description: Apply the Swag visual identity to the logo, favicons, generated documentation, the website, the VSCode theme, and any new surface. Use whenever adding or changing a brand asset, a stylesheet, a page layout, an editor theme, a color, or an icon anywhere in this repository.
---

# Design The Swag Identity

Swag is a compiler that runs your program while it compiles it. The identity says the
same thing: everything is **cut from a grid**, in **one accent over one ink**. Nothing is
soft, nothing is decorative, and nothing is added that does not carry information.

A reader must recognize a Swag surface from three things alone, before reading a word:
the cut, the voltage, and the ink.

## Hold The Three Constants

1. **The cut.** Every corner the identity opens is cut at 45 degrees, never rounded.
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

The mark is a three-bar `S` cut out of a block, leaning right.

| Measure | Units | Meaning |
| --- | --- | --- |
| Grid | 100 | Height of the mark |
| Width | 84 | Width before the lean |
| Stroke | 22 | Every bar and stem |
| Gap | 17 | Every counter; `3 * 22 + 2 * 17` is the grid exactly |
| Shoulder | 22 | The wide cut on the top-left and bottom-right corners |
| Terminal | 12 | The narrow cut closing the two free ends |
| Lean | 0.16 | Horizontal shift per unit of height |

The two shoulder cuts are what separate the mark from a seven-segment `5`. Do not remove
them, do not round anything, and do not add a container the mark has to sit inside.

`web/tools/brand.swgs` is the single definition of that geometry. It rasterizes the
mark itself, so the compiler draws its own identity. Regenerate every asset with:

```
swc web/tools/brand.swgs
```

It writes `web/imgs/swag_mark.svg`, `web/imgs/swag_mark.png`, `web/imgs/swag_icon.png`,
`web/favicon.svg`, and `web/favicon.ico`. Never edit those files by hand.

When the geometry changes, three places must be updated in the same change:

1. Run the generator.
2. Paste the new path into `--swag-mark` in `documentationStyles()`, where the mark is
   inlined as an alpha mask so a generated page stays one self-contained file.
3. Copy the icon into the VSCode extension with `vscode/mkvsix.bat`.

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

- Keep clear space of at least one stroke (22 units, scaled) on every side.
- Below 24 pixels, use the icon tile rather than the bare mark.
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
- Body measure stops at 80 characters. Tables and code may use the full column.
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

The identity is not only visual. Console output, diagnostics, and documentation prose
follow [write-swag-compiler-messages](../write-swag-compiler-messages/SKILL.md); the
progress line, the `◆` mark, and the `clean` / `passed` / `stopped` sign-off are part of
the same identity as the cut and the voltage.

## Verify

1. Regenerate the assets and the site: `swc web/tools/brand.swgs`, then
   `web/tools/web.bat dm`.
2. Look at a page in both palettes and at a narrow width before calling it done.
3. Check the mark at 16, 32, and 128 pixels. If the counters close up, the placement is
   wrong, not the mark.
4. Confirm no page gained a script element, an external font, or a second accent.
