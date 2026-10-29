---
name: design-swag-identity
description: Apply the Swag visual identity to the logo, favicons, application icon tiles, generated documentation, the website, the VSCode theme and syntax colors, and frame every GUI surface by the six laws of the Silence charter. Use whenever adding or changing a brand asset, a stylesheet, a page layout, an editor theme, a color, or an icon anywhere in this repository; GUI details then continue in design-swag-themes, design-swag-dialogs and build-swag-standard-apps.
---

# Design The Swag Identity

Swag is a compiler that runs your program while it compiles it. The identity says the same thing:
two tones over one ink, measured shapes, and nothing added that does not carry information.

It has two scopes:

- **The brand and the page**: the mark, the favicons, the application icon tile, the generated
  documentation, the website, the VSCode theme. This skill governs them in full.
- **The window**: every control, widget, dialog and application under `bin/`. It follows the
  **Silence** charter, [backlog/design/README.md](../../../backlog/design/README.md), and its
  pictures in [backlog/design/imgs/](../../../backlog/design/imgs/). What is still left to migrate
  is listed in [design.silence.md](../../../backlog/design/design.silence.md). The rules are split
  between [design-swag-themes](../design-swag-themes/SKILL.md) (palettes, roles, measures, type,
  controls, property grid), [design-swag-dialogs](../design-swag-dialogs/SKILL.md) (modal boxes)
  and [build-swag-standard-apps](../build-swag-standard-apps/SKILL.md) (window chrome, shared
  components, applications). If a rule here and the charter disagree about a window, the charter
  wins. The page and the web identity are outside the charter.

A reader should recognize a Swag surface before reading a word of it. A page shows the cut, the
Voltage and the ink. A window shows its silence: the work alone on a calm ground, with one accent
at a time.

## The GUI Follows Silence

The charter states the six laws. This is why each one exists. A surface that follows the letter
of a rule but breaks one of these laws is wrong.

1. **Nothing on screen but the work.** Every band a window keeps on screen takes height from the
   work for the whole session, only to save a click the reader makes twice a day.
2. **Information is asked for.** Taking information out of the product is a loss. Moving it
   behind a key, a hover or a selection only decides when it is shown.
3. **One door.** A reader who knows one key (`Space`, or `Ctrl K` where Space types text) can
   find everything. A command that is no longer on screen has not been hidden.
4. **One accent at a time.** Voltage acts and Arc chooses. Voltage means *this is the thing to
   do*, so two Voltage marks on one screen mean nothing.
5. **Air is a material.** A Swag surface is recognized as much by what it leaves empty as by
   what it draws: clean first, dense never.
6. **The default theme carries the hand.** The toolkit ships Encre (dark) and Papier (light),
   both recognizably Swag. An application that wants another look adds a theme sheet on top. The
   toolkit maintains two themes and no more.

**Move quietly.** Motion shows where a thing came from and that the interface heard the hand. If
a viewer remembers an animation, it was too much. The charter's Motion section gives the
durations, curves and travel. In code:

- Take every duration and travel from `ThemeMetrics.motion_*`. Use `motion_QuickSeconds` for state
  feedback, `motion_PageSeconds` for an arrival or a page, `motion_LeaveSeconds` for a departure,
  `motion_PanelSeconds` for a layout change, `motion_PageOffset`, `motion_EdgeTravel` and
  `motion_AnchorTravel` for travel, and `motion_ScrollRest` for scroll bars coming to rest. A
  literal duration in a control is a finding.
- Show and hide a floating surface with `Animator.arrive(wnd, travel)` and `Animator.leave(wnd)`.
  The window becomes reachable or goes away at once, and only its picture moves.
- Arrivals ease out and departures fade linearly. Never overshoot, bounce, pulse or scale a
  surface above one, and never loop at rest.
- Whatever the hand is waiting on appears at once: typing, the caret, the selection in a list,
  the focus ring, an error. Progress is `AnimationMotion.Essential`. Everything else is
  `Decorative`, so reduced motion ends it.
- Goldens are taken at rest, because the headless host runs with reduced motion. A test of the
  motion itself calls `host.setReducedMotion(false)`, checks the presentation state, then calls
  `host.app.animator.finishAll()`.

**Judge a surface against its picture.** Each GUI surface has a golden image in Encre and one in
Papier. Compare each golden with the charter picture as a whole screen, not only the part you
changed. A golden that changed in a part you did not touch is a finding.

## Hold The Constants

1. **Voltage, `#F7F900`.** It is the one signature (`Gui.Voltage`). On a page it marks the mark,
   one rule per heading, the primary action and the focus. In a window it marks the primary
   action, the focus ring, the caret and the current search occurrence. On Papier the primary
   action, the ring and the caret use ink instead (see
   [design-swag-themes](../design-swag-themes/SKILL.md#voltage-acts-arc-chooses)).
2. **Arc, `#38BDF8`.** It is the second tone (`Gui.Arc`) and means *chosen, elsewhere, on, in
   progress*. It is deepened on paper so it can be read as a word and as a hairline.
3. **The ink, `#0B0B0D`.** It is the ground of the icon tile and of the mark's assets
   (`Gui.Ink`, `INK` in `brand.swgs` and `package_app_icon.py`). It is near-black rather than pure
   black, so a real black can still exist. The window's Encre ground, `#17181C`, is one step
   lighter on purpose, so the tile still reads as a darker block on it.
4. **The cut.** Every corner the mark opens is cut at 45 degrees. The cut carries over to the
   page's repeated elements and to the glyph of every application icon, and its width says what
   the corner is. A window uses the charter's measured radii instead. In a window the cut only
   appears in the mark and in the icon glyphs.

The two tones are the whole identity vocabulary. Critical and caution are status colours, not
tones you may borrow for emphasis. A third identity hue would be a new brand, not a new option.
Kind colours (below) and file-kind hues (`fileKind_*`) are allowed several hues because each hue
carries a meaning.

## Use The Palette

The page palette lives in `DocPage::styles()` in `src/Doc/DocPage.cpp`, with a light and a dark
value for each part:

| Part | Paper / ink | Variable |
| --- | --- | --- |
| Ground | `#FFFFFF` / `#0E0E11` | `--swag-bg` |
| Header, hero, ink a Voltage block carries | `#050505` | `--swag-accent-ink` |
| Body text | `#1B1B1D` / `#E6E6EA` | `--swag-ink` |
| Soft text | `#55555C` / `#A9A9B4` | `--swag-ink-soft` |
| Faint text | `#83838D` / `#7D7D89` | `--swag-ink-faint` |
| Hairline | `#E2E2DF` / `#26262E` | `--swag-line` |
| Link (Arc) | `#047DB2` / `#38BDF8` | `--swag-link` |

The window palette is Silence's: two themes with their own grounds, surfaces, lines and inks. Its
tokens are in the charter, and their code names are in
[design-swag-themes](../design-swag-themes/SKILL.md). Do not copy page values into a theme or
theme values into a page.

Kind colours carry meaning, so they are one of the places where several hues are allowed. Keep
them in this order and do not add to the set: namespace slate, struct blue, interface violet,
enum teal, const amber, alias cyan, attr pink, func green. Their values are the `--swag-kind-*`
variables of `DocPage::styles()`.

## One Family, Two Modes In A Window

A tone is one colour in three roles: what it *points* with, the block it *fills*, and the ink
that block carries (`Gui.ThemeTone`). Most tones use the same value for the first two, and the
identity shows in the tones that cannot.

- **Voltage turns over on Papier. It is never deepened into another colour.** On Encre, Voltage
  fills, points and blinks. On Papier the same button is an ink fill with paper text, and the
  ring and the caret are ink. A deepened Voltage is an olive the family does not own, and Voltage
  text on paper cannot be read. On paper, Voltage only appears as a *wash* (the highlight of an
  occurrence or of a matched character) and in the tile, which has its own ink ground.
- **Arc carries the choosing.** A link, the selected row, a checked control, progress, an
  information notice. A row washed in Voltage cannot be read at all, and that is the job Arc
  exists to take.

## Measured Shapes

**A radius too small to be seen is worse than none**: it costs the same pixels and says nothing.
Every corner the identity draws should be a decision someone could name.

- **On a page**, structure stays square. Cards, tables and callouts are square. The cut appears
  on repeated elements (kind chips) and once on the hero.
- **In a window**, the charter names one radius per object: the window, floating surfaces, menus
  and popups, controls, chips. They are `ThemeMetrics.surfaceWnd_CornerRadius` and `corner_*`;
  see [design-swag-themes](../design-swag-themes/SKILL.md#measures). A radio, a switch knob or a
  dot stays fully round, because round is a semantic shape there.

**A mark drawn around a rounded thing takes that thing's corner, stepped out by its own
offset.** A ring offset from a control is concentric only if its radius is the control's radius
plus the offset plus half the ring's width.

**Flat is the default.** In a window only three kinds of shading are allowed, each shown in the
charter's pictures:

- the **floating shadow** under a floating surface, which says *this floats*;
- the **dim** behind the lens or a dialog, which says *the window behind waits*;
- the **hover veil** that keeps a title and a timeline legible over a picture, which says *the
  pointer is here*.

There is no title-bar glow, no gradient behind content, no glow around a mark, and no gradient
that changes from one application to another.

## Cut The Mark

The mark is a three-bar `S` cut out of a block and leaning right. It has twelve corners, each
opened by a cut whose width says which corner it is.

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

Three rules hold those numbers together:

1. `3 * stroke + 2 * gap == grid`. A counter weighs exactly what a bar weighs.
2. `terminal + notch == stroke`. At a free end the two cuts meet, so the bar comes to a point.
3. Every corner is cut. The shoulders open the form, and they are what keep the mark from
   reading as a seven-segment `5`. The notches keep a counter from reading as a slot punched
   through a slab.

The 45 degrees are measured on the grid, before the lean shears them. An edge in a generated
file is therefore not at 45 degrees on screen, and you must not "correct" it. Do not round
anything, and do not put the mark inside a container. The letter itself is settled: tune a
measure when a size needs it, but do not redraw the letter. A gradient ribbon, a folded ribbon, a
faceted gem, a fragmenting `S` and a drawn wordmark were all tried and rejected.

`bin/help/tools/brand.swgs` is the only definition of that geometry. It builds the mark once as
a `Pixel.LinePath` and hands it to `Pixel.Svg.Document` and `Pixel.ImageCanvas`. Run it separately
before `tools/help.bat` when the brand assets change. To regenerate the assets on their own:

```
swc bin/help/tools/brand.swgs
```

It writes `bin/help/imgs/swag_mark.svg`, `bin/help/imgs/swag_mark.png`, `bin/help/imgs/swag_icon.png`,
`bin/help/favicon.svg` and `bin/help/favicon.ico`. Never edit those files by hand. The favicon's
16, 32 and 48 pixel entries are each cut at their own size.

When the geometry changes, update four places in the same change:

1. Run the generator.
2. Paste the new path and its `viewBox` into `--swag-mark` in `DocPage::styles()`.
3. Paste the same path into `bench/page_template.html` and into the `bench/bench.html` it
   produced.
4. Copy the icon into the VSCode extension with `tools/vsix.bat`.

## Regenerate The Syntax Image

`bin/help/imgs/syntax.png` is a capture of a page the compiler coloured itself, so it can never
show syntax the compiler no longer accepts.

1. Edit the snippet in `bin/help/tools/syntax/src/syntax.md` when the language changes.
2. Generate the page: `swc doc --module bin/help/tools/syntax --doc-output-dir <out>`.
3. Capture the `.code-block` element at a device scale of 2, and write the result to
   `bin/help/imgs/syntax.png` and `vscode/images/syntax.png`.

## Place The Mark

- Keep clear space of at least one stroke (20 units, scaled) on every side.
- Below 24 pixels, use the icon tile rather than the bare mark.
- **The tile is for the desktop and the About box. A window shows the glyph.** The tile is one
  Voltage glyph on one ink ground, for the taskbar, the task switcher, an installer and the About
  box (52, corner 12). Inside a window the application glyph is drawn monochrome in
  `ThemeColors.wnd_CaptionMark` (soft ink at about 55 %), 18 px, at the top-left corner. The
  toolkit draws it. See [build-swag-standard-apps](../build-swag-standard-apps/SKILL.md#generate-a-specific-icon).
- **A tile has two crops.** In an application icon the mark fills 56 % (`ICON_FILL`). In a
  favicon it fills 74 % (`FAVICON_FILL`), because at 16 pixels the margin would cost the counters.
- The mark is the whole logo. `SWAG` is set in type beside it (weight 800, `.2em` tracking).
- Never stretch the mark, outline it, give it a shadow, or recolour it outside the two palette
  values.

## Draw The Interface Icons

Interface icons are the glyphs of icon buttons, menus, the dock and the lens. Draw them as
**outline glyphs on a 16 grid, 1.4 stroke, round caps and joins**, with no fill except a
deliberate dot or play triangle. Each glyph is drawn in one colour from the theme (soft at rest,
Arc when chosen) and never carries a second colour, a badge or a tile. Application icons are the
exception: they stay two-colour tiles because they are seen next to other products' icons. In a
file listing, a file's glyph takes the quiet hue of its kind (`Theme.fileGlyph`, `fileKind_*`).
The name and the row stay neutral.

Judge a glyph at 16 physical pixels at 100 % scale, in soft on Encre and in ink on Papier, with
its pixels enlarged rather than smoothed. A drawing at 64 hides what the stroke does at 16.

- **Keep an inner mark at least 3 units from its frame.** A cross or a curl inside a circle of
  radius 5.5 fills up with stroke and reads as a smudge. An upright mark (`!`, `i`) survives
  where a diagonal one does not.
- **Put a distinguishing detail outside the shared shape.** A `1` squeezed inside a repeat loop
  vanishes into the arrowheads. Open the loop and put the `1` beside it.
- **Draw the object's silhouette, not its rings.** A gear is a toothed outline with a hole.
  Concentric circles with spokes read as a target.
- **Two glyphs that mean different things must differ at a glance.** Duplicate is Copy with a
  plus filling its front sheet, not a plus squeezed between two frames.
- **One glyph carries one sign.** Do not combine a sun with a globe, or a folder with a badge.

## Set The Type

- **In a window**: Inter for every word and Roboto Mono for every measure; see
  [design-swag-themes](../design-swag-themes/SKILL.md#type).
- **On a page**: the system sans stack for interface and prose. Use the monospace stack for every
  identifier, signature, type, kind label and count: if the compiler knows the name, it is
  monospace.
- Section labels and kind chips are uppercase, small, with `.09em` to `.16em` tracking. They are
  labels, not headings.
- The documentation content column is at most `120ch`. Set that measure on the shared prose-font
  container, and never apply it again on descendants with another font.
- Use one `h1` per page. An `h2` has a leaning Voltage rule above it. Nothing else has one.

## Build The Page

The generated documentation is the reference implementation for pages:

- **The cut goes on repeated elements, not on big ones.** Kind chips have the cut, the hero has it
  once, and cards, tables and callouts stay square.
- **One accent bar per group.** An API entry gets a left rule in its kind colour, and a callout
  gets one in its severity colour. Never combine a rule, a fill and a border.
- **Hairlines, not boxes.** Tables have horizontal rules only.
- **State is a rule, not a fill.**
- **Both palettes, always.** Dark comes from `prefers-color-scheme` unless the page sets
  `data-theme`.
- **One script, and it is the search box.** A page is one static file that loads nothing else. A
  unit test enforces exactly one inline `<script>` with no `src`.

**These page rules do not apply to a window.** Applied to an application, they produce a grid of
boxes and rails. A window follows Silence instead: space first, a fill second, one hairline last,
and no rail; see [build-swag-standard-apps](../build-swag-standard-apps/SKILL.md).

## Join An Icon Menu To Its Button

A menu opened by the primary activation of an `IconButton` includes that button in its outline
as the opening tab. The button and the menu share one ground and one border. This applies
everywhere, including dialogs, the inspector, the mini-bar and the property grid's `•••` layout
menu.

Use `MenuCtrl.doModal(button, autoDestroy: true)` with the actual `IconButton`. Do not pass a
point computed from `surfaceRect()`: that takes the coordinate-based path, and the menu is no
longer joined to the button or placed by its rules. `RightUpward` opens the menu above the
button. The shared menu fits itself against the window edges, so the caller adds no offsets. A
context menu requested by the pointer stays at the pointer.

[`menu.test.swg`](../../../bin/std/modules/gui/src/tests/menu.test.swg) protects the joined
outline. [`properties.test.swg`](../../../bin/std/modules/gui/src/tests/properties.test.swg)
checks the property editor's real trigger in both themes. When you add a new trigger, test the
path that opens it.

## Match Every Syntax Surface

`vscode/themes/swag-dark.json`, the documentation colorizer and `RichEditLexerSwag`
([lexerswag.swg](../../../bin/std/modules/gui/src/controls/richedit/lexerswag.swg)) use the same
lexical colours:

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

When you change one lexical surface, change the other two in the same commit. Semantic tokens
only refine VSCode's colours when the language server resolves a symbol. The RichEdit lexer runs
these values through `Color.ensureContrast`, so the same hues stay legible on Encre and deepen on
Papier. When the intrinsic catalogue changes, compare both lexers against `Tokens.Def.inc`.

## Keep The Voice

The identity is recognizable in a terminal too, and by the same means:

- **The style comes from invariance, not variation.** One mark, `◆`. One sign-off: `clean`,
  `passed` or `stopped`. One closed table of step verbs. No random line and no rotating emoji.
- **Swag never talks over an error.** Character is allowed only where the reader has no problem
  to solve. From the first diagnostic on, the voice is dry, dense and useful.
- **One grammar for every failure.**

Console output, diagnostics and documentation prose follow
[write-swag-compiler-messages](../write-swag-compiler-messages/SKILL.md). GUI command labels follow
*Word The Commands* in [build-swag-standard-apps](../build-swag-standard-apps/SKILL.md#word-the-commands).

## Verify

1. Regenerate the assets and the site: `swc bin/help/tools/brand.swgs`, then
   `tools/help.bat dm`.
2. Look at a page in both palettes and at a narrow width.
3. Look at the mark at 16, 32 and 128 pixels. If the counters close up, the crop is wrong before
   the mark is.
4. Confirm that no page gained a second script element, an external font or a second accent.
5. When the geometry moved, confirm that the four consumers agree.
6. For a GUI surface, follow the validation in
   [design-swag-themes](../design-swag-themes/SKILL.md#validation).
