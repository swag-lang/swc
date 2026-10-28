---
name: design-swag-identity
description: Apply the Swag visual identity to the logo, favicons, application icon tiles, generated documentation, the website, the VSCode theme and syntax colors, and frame every GUI surface by the six laws of the Silence charter. Use whenever adding or changing a brand asset, a stylesheet, a page layout, an editor theme, a color, or an icon anywhere in this repository; GUI details then continue in design-swag-themes, design-swag-dialogs and build-swag-standard-apps.
---

# Design The Swag Identity

Swag is a compiler that runs your program while it compiles it. The identity says the
same thing: a **closed set of tones over one ink**, measured shapes, and nothing added that
does not carry information.

The identity has two scopes, and they share one vocabulary:

- **The brand and the page** — the mark, the favicons, the application icon tile, the generated
  documentation, the website, the VSCode theme. This skill governs them in full.
- **The window** — every control, widget, dialog and application under `bin/` — follows the
  **Silence** charter, [backlog/design/README.md](../../../backlog/design/README.md), with its
  pictures in [backlog/design/imgs/](../../../backlog/design/imgs/). This skill states its six laws
  and what the window shares with the brand; the rules live in
  [design-swag-themes](../design-swag-themes/SKILL.md) (palettes, roles, measures, type, controls,
  property grid), [design-swag-dialogs](../design-swag-dialogs/SKILL.md) (modal boxes) and
  [build-swag-standard-apps](../build-swag-standard-apps/SKILL.md) (window chrome, shared
  components, applications). Where a page rule below and the charter disagree about a window, the
  charter wins; the documentation site and the web identity are outside its scope.

A reader must recognize a Swag surface before reading a word: on a page by the cut, the voltage
and the ink; in a window by its silence — the work alone on a calm ground, one accent at a time.

## The GUI Follows Silence

The six laws, with the reason each one exists. Every GUI rule in the other skills serves one of
them, and a surface that keeps the letter of a rule while breaking a law is wrong.

1. **Nothing on screen but the work.** No permanent toolbar, menu bar, status bar, ribbon or side
   panel. The window is the document, the image, the list of vaults. Every band a window keeps
   costs the work its height for the whole session, to save a click the reader makes twice.
2. **Information is asked for.** Readings, outlines, metadata and settings appear on a key, a
   hover or a selection, then leave. They are never removed from the product: they move behind a
   gesture. Removing information is a loss; moving it is a choice about when it is shown.
3. **One door.** `Space` (or `Ctrl K` where Space types text) opens the lens: search, go to, open,
   switch view, run any command. Every command of an application is reachable from its lens. A
   reader who knows one key can find everything, and a screen that no longer shows a command has
   not hidden it.
4. **One accent at a time.** Voltage acts, Arc chooses. Two yellow things on one screen is one too
   many: the signature means *this is the thing to do*, and two of them mean nothing.
5. **Air is a material.** Measured columns, reading margins, nothing flush with an edge, nothing
   boxed that space can separate. A Swag surface is recognized as much by what it leaves empty as
   by what it draws — clean first, dense never.
6. **The default theme carries the hand.** The toolkit ships two themes, Encre (dark) and Papier
   (light), both recognisable as Swag. An application that wants another look adds its own theme
   on top; the toolkit keeps two to maintain.

**Judge a surface against its picture.** The charter's pictures are the visual target. Every GUI
surface is judged against its picture, in both themes, through its golden image; a golden that
changed for a part not touched is a finding.

## Hold The Constants

1. **The voltage.** One signature, `#F7F900`. On a page: the mark, one rule per heading, the
   primary action and the focus. In a window: the primary action, the focus ring, the caret and
   the current search occurrence — on Papier the primary, the ring and the caret turn over to ink
   (see [design-swag-themes](../design-swag-themes/SKILL.md#voltage-acts-arc-chooses)). A
   signature that appears everywhere signifies nothing. It is not the only colour the identity
   owns — see Arc below — but it is the only one that says *this is the thing to do*.
2. **The ink.** Near-black `#0B0B0D`, not pure black, so a real black can still exist. It is the
   ground of the icon tile, of the page's header and hero, and the ink a Voltage block carries.
   The window's Encre ground, `#17181C`, sits one step lighter on purpose: a slightly cool graphite
   on which the tile still reads as the darker block it is.
3. **The cut.** Every corner the *mark* opens is cut at 45 degrees, and the cut carries onto the
   page's repeated elements and the glyph of every application icon. The cut is a vocabulary, not
   a decoration: its width says what the corner is. In a window, shapes take the charter's
   measured radii instead (below) — the cut stays in the mark and the icon glyphs a window shows.

## Use The Palette

The page palette:

| Token | Value | Use |
| --- | --- | --- |
| Voltage | `#F7F900` | The signature: the mark, the heading rule, the primary action, focus |
| Arc | `#38BDF8` | The second tone: a link, another page, a selected row, what is chosen |
| Ink | `#0B0B0D` | The header, the hero, the dark ground, and the ink every block carries |
| Paper | `#FFFFFF` | The light ground |
| Ink text | `#1B1B1D` / `#E6E6EA` | Body on paper / on ink |
| Soft text | `#55555C` / `#A9A9B4` | Secondary prose, table descriptions |
| Faint text | `#83838D` / `#7D7D89` | Labels, counts, source links |
| Line | `#E2E2DF` / `#26262E` | Hairlines and table rules |

The window palette is Silence's: exactly two themes, Encre and Papier, with their own grounds,
surfaces, lines and inks, and Arc deepened to `#0A7FB5` on Papier. Its token table and roles live
in [design-swag-themes](../design-swag-themes/SKILL.md); do not copy page values into a theme or
theme values into a page.

Kind colors carry meaning, so they are the one place several hues are allowed. Keep them
in this order and do not add to the set: namespace slate, struct blue, interface violet,
enum teal, const amber, alias cyan, attr pink, func green. Their exact values live in
`documentationStyles()` in `src/Doc/DocPage.cpp`.

## One Family, Two Modes

The chart once owned exactly one accent, and that accent was a dark-mode colour: Voltage points
and fills on ink; on paper it can only fill, and a light theme whose every ring, rule and hovered
border was black read as a black-and-white theme with a yellow button in it. Three rules replace
that, and together they make a Swag surface recognizable at a glance in either mode.

1. **A tone is one color in three roles.** What it *points* with, the block it *fills*, and the
   ink that block carries. Most tones give the first two the same value; the identity lives in
   the ones that cannot.
2. **Voltage turns over on paper; it is never deepened into another colour.** On ink, Voltage
   fills, points and blinks. On paper, the same button is an ink fill with paper text, and the
   ring and the caret are ink: a deepened Voltage is an olive the family does not own, and Voltage
   text on paper is a word nobody reads. Voltage survives on paper as a *wash* — the highlight of
   a search occurrence, a matched character — and in the tile, where it carries its own ink ground.
3. **The signature is scarce; the second tone is not the signature.** Voltage says *do this*.
   Arc says *chosen, elsewhere, on, in progress*: a link, the selected row, a checked control,
   progress, an information notice. Arc deepens on paper (`#0A7FB5`) so it can be read as text and
   as a hairline. A row washed in Voltage cannot be read at all, which is precisely the job the
   second tone exists to take. Two tones is the whole identity vocabulary — status colours
   (critical, caution) are not tones to borrow for emphasis, and a third identity hue is a new
   brand, not a new option.

## Measured Shapes

**A radius too small to be seen is worse than none**: it costs the same pixels and reports
nothing. Every corner the identity draws is a decision someone could name.

- **On a page**, structure stays square: cards, tables and callouts are square, and the cut
  appears on repeated elements (kind chips) and once on the hero. A page is scanned as a long
  document, and square blocks tile it without a seam.
- **In a window**, the charter measures four objects: the window (10), floating surfaces — lens,
  sheet, inspector, dialog, popover (12) — menus and popups (10), controls — button, field, combo,
  segment frame (6) — and chips, swatches, keycaps (4–5). A radio, a switch knob or a dot stays
  fully round: that is a semantic shape, not a larger value on the scale. The numbers live in
  `ThemeMetrics`; see [design-swag-themes](../design-swag-themes/SKILL.md#measures).

**A mark drawn around a rounded thing takes that thing's corner, stepped by its own offset.** A
ring offset from a control is concentric only if its radius is the control's plus that offset
and half its own width; drawn at the control's radius it crosses the control's corners at four
places. See the focus-ring rule in [design-swag-themes](../design-swag-themes/SKILL.md), which is
the same rule for the same reason.

**Flat is the default.** What the identity refuses is decoration, not depth. A wash is admissible
only when it is **subtle** — neither of its ends can be named as a colour — **non-invasive** — it
moves nothing the reader acts on, adds no edge, and leaves no hole when taken away — and **carries a
state**: a wash that is the same in every state is paint. Take it away and something must be
missing; look at it and nothing must have been added.

In a window that leaves three things and no others, each shown in the charter's pictures: the
**floating shadow** under a floating surface (it says *this floats*), the **dim** behind the lens
or a dialog (it says *the window behind waits*), and the **hover veil** that keeps a title and a
timeline legible over a picture (it says *the pointer is here*). The window carries no title-bar
glow, no gradient behind content, and no gradient that varies by application: one hue per app is
the end of the family, however good each looks alone.

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

`bin/help/tools/brand.swgs` is the single definition of that geometry. It builds the mark once
as a `Pixel.LinePath` and hands it to the two writers that consume it — `Pixel.Svg.Document`
for the vector masters and `Pixel.ImageCanvas` for the rasters — so no asset can disagree
with another about where an edge is. The script owns the shape and nothing else; anything
generic it needs belongs in `bin/std`, not in the script.

`tools/help.swgs` runs it before generating the pages, so the assets the pages link are
always cut from the current definition. To regenerate them alone:

```
swc bin/help/tools/brand.swgs
```

It writes `bin/help/imgs/swag_mark.svg`, `bin/help/imgs/swag_mark.png`, `bin/help/imgs/swag_icon.png`,
`bin/help/favicon.svg`, and `bin/help/favicon.ico`. Never edit those files by hand. The favicon carries
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

`bin/help/imgs/syntax.png` shows the language in its own colors. It is not a screenshot of an
editor: it is a capture of a page the compiler colored itself, which is why it can never
show syntax the compiler no longer accepts.

1. Edit the snippet in `bin/help/tools/syntax/src/syntax.md` when the language moves.
2. Generate the page: `swc doc --module bin/help/tools/syntax --doc-output-dir <out>`.
   That module pins `theme = .Dark`, so the capture matches the editor theme.
3. Capture the `.code-block` element at a device scale of 2, and write the result to
   `bin/help/imgs/syntax.png` and `vscode/images/syntax.png`.

## Place The Mark

- Keep clear space of at least one stroke (20 units, scaled) on every side.
- Below 24 pixels, use the icon tile rather than the bare mark.
- **The tile is for the desktop and the About box; a window shows the glyph.** The tile ships
  flattened — one Voltage glyph over one ink ground — because that is what a taskbar, a task
  switcher, a file list, an installer and the About box (52, corner 12) need. Inside a window the
  application glyph is drawn **monochrome**, in the soft colour at about 55 % opacity, 18 px at the
  top left: it signs the window without becoming a block of brand above the work, and it reads the
  same on Encre and on Papier, where a Voltage glyph would vanish. See
  [build-swag-standard-apps](../build-swag-standard-apps/SKILL.md#generate-a-specific-icon).
- **A tile has two crops, and they are not interchangeable.** An application icon is looked
  at, so the mark holds 56% of it and keeps its clear space. A favicon is glanced at: at
  sixteen pixels that margin costs the counters, so the mark holds 74% and the margin is
  spent on the form. Both live in `brand.swgs` as `ICON_FILL` and `FAVICON_FILL`.
- The mark is the whole logo. There is no drawn wordmark: `SWAG` is set in type, 800
  weight, `.2em` tracking, beside the mark. A drawn wordmark was tried and rejected; it
  read as a novelty typeface and fought the mark.
- The mark is never stretched, outlined, given a shadow, or recolored outside the two
  palette values.

## Draw The Interface Icons

Interface icons — the glyphs of icon buttons, menus, the dock, the lens — are **outline glyphs on
a 16 grid, 1.4 stroke, round caps and joins**, no fill except a deliberate dot or play triangle;
18–20 in a dock. They are drawn in one colour taken from the theme (soft at rest, Arc when chosen)
and never carry a second colour, a badge or a tile. Application icons are the exception and stay
two-colour tiles, because they are seen on a desktop beside other products' icons rather than in a
row of commands. Size ceilings and cells live in
[build-swag-standard-apps](../build-swag-standard-apps/SKILL.md#keep-the-chrome-small-and-the-air-large).

## Set The Type

- **In a window**: Inter for every word, Roboto Mono for every measure. Sizes and weights are in
  [design-swag-themes](../design-swag-themes/SKILL.md#type).
- **On a page**, interface and prose: the system sans stack.
- Every identifier, signature, type, kind label, and count: the monospace stack. If it is
  a name the compiler knows, it is monospace.
- Section labels and kind chips: uppercase, `.09em` to `.16em` tracking, small. They are
  labels, not headings.
- Set the documentation content column to a maximum of `120ch`. Resolve that measure on
  the shared prose-font container, then make paragraphs, lead text, code, tables, API
  blocks, and callouts fill it; never reapply the `ch` measure on descendants whose font
  family or size would produce a different right edge.
- One `h1` per page. An `h2` carries a leaning voltage rule above it; nothing else does.

## Build The Page

The generated documentation is the reference implementation of this chart for pages. When adding
a page surface, take these rules from it:

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
tells them where one entry ends. **They do not transfer to a window.** Applied to an application
they produce a grid of boxes: a border around each panel, a divider between each block, a rail
beside each of them. A window follows Silence instead — space first, a fill second, one hairline
last, and no rail at all; see [build-swag-standard-apps](../build-swag-standard-apps/SKILL.md).

## Join An Icon Menu To Its Button

A menu opened by primary activation of an `IconButton` incorporates that button into its outline as the opening tab.
The button and the menu share one continuous ground and border; the trigger must not remain
outside a detached popup. This applies inside dialogs, property editors, the inspector and the
mini-bar — including the property grid's `•••` layout menu.

Use `MenuCtrl.doModal(button, autoDestroy: true)` with the actual `IconButton`. Do not replace the
button with a point computed from `surfaceRect()`: that selects the coordinate-based path and loses
both the attachment and its placement rules. `RightUpward` opens above the button; other arrow
positions open below it. The shared menu owns fitting against the presentation-layer edges,
including a trigger aligned to the right edge. Do not compensate with caller-owned offsets.
Pointer-requested context menus keep their pointer position, including a right-click on an icon.

[`menu.test.swg`](../../../bin/std/modules/gui/src/tests/menu.test.swg) protects the joined outline
and edge placement; [`properties.test.swg`](../../../bin/std/modules/gui/src/tests/properties.test.swg)
checks the property editor's actual trigger in Encre and Papier. When adding a new trigger,
test its opening path, not only a menu constructed directly by the test.

## Match Every Syntax Surface

`vscode/themes/swag-dark.json`, the generated documentation colorizer, and
`RichEditLexerSwag` use the same lexical token colors, so code looks the same in VSCode, on a
page, and in a Swag GUI editor. VSCode can refine resolved symbols with semantic tokens; keep
those refinements restrained and based on the symbol's role, not another accent color:
parameters use body text in italics, fields and enum members use a quiet grey-blue, and global
variables use the existing slate. Methods stay in the function family with a softer orange;
intrinsic functions keep their gold. The mapping is:

| Token | Color | Documentation class |
| --- | --- | --- |
| comment | `#7AA86A` | `SCmt` |
| keyword, declaration, modifier, constant.language | `#74AAE0` | `SKwd` |
| keyword.control | `#C48FD0` | `SLgc` |
| entity.name.function | `#E8A06A` | `SFct` |
| entity.name.function.intrinsic | `#CBB45C` | `SItr` |
| resolved namespace (VSCode semantic token) | `#94A3B8` | semantic token only |
| resolved type, struct, interface, enum (VSCode semantic token) | `#56C2B3` | semantic token only |
| resolved parameter (VSCode semantic token) | `#D5D5DD`, italic | semantic token only |
| resolved method (VSCode semantic token) | `#D7A17F` | semantic token only |
| resolved field, enum member (VSCode semantic token) | `#B8C4CC` | semantic token only |
| resolved global variable (VSCode semantic token) | `#94A3B8` | semantic token only |
| resolved intrinsic function or method (VSCode semantic token) | `#CBB45C` | semantic token only |
| built-in `Swag` namespace | `#94A3B8` | `SNsp` |
| entity.name.type, class | `#56C2B3` | `SCst` |
| storage.type | `#E0B464` | `STpe` |
| constant.numeric | `#9EC98F` | `SNum` |
| string | `#E0937C` | `SStr` |
| preprocessor, attribute | `#9A9AA6` | `SCmp`, `SAtr` |
| invalid | `#FF6666` | `SInv` |

Change one lexical surface and change the other two in the same commit. Semantic tokens refine
VSCode's lexical colors only when the language server resolves a symbol; unresolved code keeps
the shared lexical palette. The RichEdit lexer passes these dark-palette values through
`Color.ensureContrast` so the same hues remain legible on Encre and deepen on Papier. When the
compiler intrinsic catalog changes, compare both syntax lexers against `Tokens.Def.inc`; neither
keeps a partial hand-written catalog.

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
[write-swag-compiler-messages](../write-swag-compiler-messages/SKILL.md). GUI command labels
follow *Word The Commands* in [build-swag-standard-apps](../build-swag-standard-apps/SKILL.md#word-the-commands).

## Verify

1. Regenerate the assets and the site: `swc bin/help/tools/brand.swgs`, then
   `swc tools/help.swgs dm`.
2. Look at a page in both palettes and at a narrow width before calling it done.
3. Look at the mark itself at 16, 32, and 128 pixels, not only at the size you drew it.
   If the counters close up, the crop is wrong before the mark is.
4. Confirm no page gained a second script element, an external font, or a second accent.
5. When the geometry moved, confirm the four consumers agree: the generated assets, the
   inlined `--swag-mark`, the extension icon, and the mark inlined in `bench/`.
6. For a GUI surface, compare its goldens in Encre and Papier with the charter picture; the
   validation steps are in [design-swag-themes](../design-swag-themes/SKILL.md#validation).
