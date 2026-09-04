# HTML Backlog

This backlog covers the HTML engine in `bin/std/modules/gui/src/controls/html` — the
parser, the CSS cascade, the layout engine, the painter, and the `HtmlView` widget on top of
them. It is measured against the embedded engines it competes with — litehtml, Sciter and
Ultralight — with a browser as the reference for what a page means, while staying what none of
them are: an offline, script-free, network-free document viewer.

Evidence, investigations, and intended outcomes for the HTML engine stay together here. The engine
lives beside its widget inside `gui`, as [std.gui.pdf.md](std.gui.pdf.md#where-this-family-lives-and-why) records
for the document family; the view selects and copies, as the Markdown one now does too.
[README.md](README.md) has the whole layout.

Entries are ordered by decreasing value, not by decreasing effort. An entry disappears when it
ships; history lives in git, not here.

## Where the engine already stands

About 15 300 lines across fourteen files, and the shape is a real engine, not a tag-to-widget
translator. The parser is resumable and streams: a document fed in 48 KB chunks produces exactly
the tree the whole file would, partial renderings appear at growing intervals, a 48 MB cap ends
the load with a visible notice, and every node keeps its source byte offset — which is what lets
Swag Scope reveal a raw-file search hit on the exact line that draws it. It carries the elements a
document leaves implied — `html`, `head` and `body`, opened where the content says they belong —
and resolves the standard's complete list of 2 231 named character references, the legacy
spellings without a semicolon included. The tree builder carries the recoveries browsers
standardized: misnested formatting reopens across the misnesting, content a table cannot hold is
fostered in front of it, and an interrupted paragraph closes through its open inline children.
The cascade is the real
one: specificity, `!important`, source order, media queries including `prefers-color-scheme`
answered from the host theme, custom properties with proper scope and `var()` fallbacks,
`calc()`/`min()`/`max()`/`clamp()`, `color-mix()`, `::before`/`::after` generated boxes, and
rules bucketed by subject so a thousand-rule sheet costs a handful of comparisons per element.
Layout covers block flow with margin collapsing, a full inline formatting context with
justification, vertical alignment and word breaking (`overflow-wrap`, `word-break`, CJK
characters as break opportunities, `<wbr>`, soft hyphens drawn only at a taken break), left and
right floats with line boxes shortening around them and `clear`, row and column flex, a
declared-columns grid, tables sized from cell content, sticky positioning, and independently
scrolled `overflow` regions with themed scrollbars. Painting prunes by subtree bounds, orders positioned siblings by stacking level, and
answers hover on links without restyling — a documented stance: a state pseudo-class that would
need a per-frame restyle matches never, and the viewer lights the link while painting instead.

It is also measured against those engines rather than described. Parsing the 8.15 MB rustdoc page
of `src/tests/datas` into its 429 782 nodes, on the same machine and pinned to the performance
cores: this engine **130 ms (63 MB/s)**, html5ever with its reference DOM 278 ms (28 MB/s), the
same tokenizer with no tree at all 134 ms (58 MB/s), the `tl` crate — a zero-copy, deliberately
non-conforming DOM — 64 ms (120 MB/s), and lol-html's tokenizer, which builds nothing, 51 ms
(150 MB/s). It started the campaign at 412 ms and 214 MB.

What took it there is that the tree stopped owning anything it could address. A node is 64 bytes:
its children are a chain rather than an array, so an element costs no allocation at all, and every
string — a text run, an unknown tag's name, an attribute name and value, a class — is a range of
the source the document keeps, copied only when the source does not spell it that way (a folded
name, a run with a character reference). A start tag is read in one pass that answers where it
ends, whether its name was written in mixed case, and every attribute it carries; a run of text is
read in one pass that finds both the `<` that ends it and the `&` that would make it need
decoding.

Two boundaries are deliberate and permanent: nothing the document carries is ever executed, and
the engine never opens a network connection. A document is displayed from its own bytes and its
own folder, whatever it links to.

The suite behind the engine is structural and visual both: trees, cascade results, hit tests and
region scrolling on one side, and PNG goldens on the other — the comprehensive, tables and
flex-grid fixtures, a preserved-whitespace code block, and the generated Pixel API page rendered
whole. The gaps are of two kinds: pages that lay out or paint as something other than what they
mean, and CSS surface that is read and silently dropped.

---

## Tier B — Pages that lay out other than they mean

### std.gui.html.001 — Content wider than its container cannot be reached

- Intent: nothing in the engine scrolls horizontally. The widget's `ScrollWnd` is created with
  `DisableHorizontal` and the canvas is always laid out at viewport width; an `overflow` region
  keeps a `scrollTop` and no `scrollLeft`, so `overflow-x: auto` — the standard idiom on every
  code block and wide table — clips the right edge and offers no way to see it. A wide `<pre>`
  line (whose `white-space: pre` legitimately never wraps) is simply unreadable past the margin.
- Complete when: an `overflow-x: auto` region whose content is wider than itself scrolls
  horizontally with the same themed bar its vertical axis has, wheel and drag both drive it, and
  a document whose minimum content width exceeds the viewport either pans or is reported as a
  deliberate refusal rather than silently cut.

### std.gui.html.002 — `colspan` and `rowspan` are ignored

- Intent: `layoutTable` assigns each cell to the column of its index, so a header spanning three
  columns compresses into one and every row below it shifts. Spans are the first thing a real
  table uses. This was second in line in the old combined entry.
- Complete when: a cell's `colspan` and `rowspan` attributes place and size it across its
  columns and rows, column min/max measurement distributes a spanning cell's width over the
  columns it covers, and `html.tables.html` gains span cases checked against a browser.
- Related: std.gui.html.003

### std.gui.html.003 — A table has no column model

- Intent: columns are sized from cell content alone. A `width` on a cell or a `<col>`, a
  percentage column, `table-layout: fixed`, `border-spacing`, `border-collapse` and
  `caption-side` are all unread (`border-collapse` is not even a property the parser resolves).
  Every browser default separates cell borders by 2px; here cells touch, and a bordered table
  draws doubled walls where a collapsed one means single lines.
- Complete when: an author-declared column width wins over content sizing, `table-layout: fixed`
  sizes from the first row, border spacing separates and `border-collapse: collapse` merges
  adjacent cell borders, and the tables fixture compares those against browser geometry.
- Related: std.gui.html.002, std.gui.html.014

### std.gui.html.004 — A grid places items in source order only

- Intent: `layoutGrid` fills declared columns left to right, row by row. `grid-column` and
  `grid-row` are parsed as bare integers and then never read by layout; spans, negative lines,
  named lines and areas, `grid-template-rows`, `auto-fill`/`auto-fit` and implicit tracks are
  not modelled. A numeric `repeat()` now unrolls in `gridTemplate`; the two automatic counts
  still collapse to a single flexible track because they depend on the width layout discovers.
- Complete when: `grid-column`/`grid-row` with spans place items in an occupancy grid with
  implicit rows, `auto-fill` and `auto-fit` derive their count from the available width,
  `grid-template-rows` sizes declared rows, and `html.flex-grid.html` gains placed-and-spanned
  cases checked against a browser.

### std.gui.html.005 — Flex containers ignore half of their alignment surface

- Intent: four parsed properties never reach flex layout. `order` is stored and never sorted on.
  `align-content` never distributes the cross axis of a wrapped container. `align-items:
  baseline` falls through to start alignment because `layoutFlexLine` only handles center, end
  and stretch. And a column container ignores `justify-content` entirely — `layoutFlexColumn`
  stacks from the top whatever the document asks — and cannot wrap.
- Complete when: items lay out in `order` order, a wrapped container distributes its lines per
  `align-content`, row items align on their first baselines, a column container distributes free
  main-axis space per `justify-content`, and the flex fixture asserts each against browser
  geometry.

### std.gui.html.006 — A positioned box is positioned against the wrong ancestor

- Intent: three related divergences. `layoutAbsolute` positions an absolute box against its
  direct parent box, not against its nearest positioned ancestor, so the standard pattern —
  `position: relative` on a card, `position: absolute` on a badge two levels down — anchors to
  the wrong frame. `position: fixed` takes the same path and then scrolls away with the
  document, so a fixed header leaves the screen. And only `layoutBlockChildren` ever calls
  `layoutAbsolute`: an absolutely positioned child of a flex, grid or table container is built
  and painted but never laid out, so it draws at whatever zero-sized rectangle it was born with.
  `z-index` meanwhile orders positioned siblings within their parent without hoisting a
  positioned descendant through static ancestors into its stacking context.
- Complete when: an absolute box resolves its containing block by walking to the nearest
  non-static ancestor, a fixed box holds its viewport position while the document scrolls,
  every container layout routes its out-of-flow children through `layoutAbsolute`, and a
  positioned descendant paints at its stacking-context level rather than its tree level.

### std.gui.html.007 — Right-to-left text is drawn left-to-right

- Intent: there is no notion of direction anywhere: `dir` is an attribute like any other,
  `direction` and `unicode-bidi` are not property names, `text-align: start` is a synonym for
  left, and an Arabic or Hebrew text node is measured and drawn in logical order, which for RTL
  scripts is backwards. Part of the limit sits below this engine — the toolkit's text stack
  shapes no complex scripts — but the engine does not even reorder what the stack could draw.
- Complete when: the paragraph direction follows `dir`/`direction`, RTL runs within a line are
  reordered per the bidirectional algorithm's paragraph-and-run level, `start`/`end` alignment
  follows direction, and the residual shaping limit is recorded against the text stack rather
  than silently absorbed here.

### std.gui.html.008 — Percentage heights resolve against nothing in normal flow

- Intent: `layoutBlockChildren` builds each child's containing block with a width and
  `hasHeight: false`, so `height: 100%` resolves only for the root and for absolutely
  positioned boxes. The classic full-height chain — `html, body, .app { height: 100% }` — and
  every percentage-height panel inside a definite-height parent collapse to content height.
- Complete when: a child whose parent's used height is definite resolves percentage heights
  against it, the definiteness propagates down a chain of definite heights, and an indefinite
  parent still falls back to content height as it does today.

---

## Tier B — Pages that paint other than they mean

### std.gui.html.009 — SVG never draws, in a toolkit that rasterizes SVG for its own theme

- Intent: two halves. Inline `<svg>` is on the `isSkippedTag` list, so a page's diagrams and
  icons vanish silently. And `<img src="figure.svg">` fails because `Pixel.Image.load` has no
  SVG codec — while the same `pixel` module parses and rasterizes SVG for the theme atlas every
  application ships. The capability exists one layer down and is not wired to either path. A
  `data:image/svg+xml` reference degrades to the placeholder for the same missing-codec reason.
- Complete when: an `<img>` referencing a local `.svg` rasterizes at its laid-out size through
  the existing SVG engine, an inline `<svg>` subtree renders through the same code with its
  width and height honoured, and an SVG feature the rasterizer lacks degrades to the placeholder
  rather than to nothing.

### std.gui.html.010 — A gradient is read as no background at all

- Intent: `background` keeps only a color; `background-image`, `linear-gradient` and
  `radial-gradient` are deliberately dropped so the box keeps what is behind it. For a hero
  band or a striped code header that is the difference between the page's structure and a flat
  void — and `Painter` already draws gradient brushes for the toolkit's own widgets.
- Complete when: linear and radial gradients with color stops fill a box's background through
  the painter's brushes, a local `background-image` file is drawn with `background-size: cover`
  and `contain` at least, and an unsupported image value still degrades to the base color rather
  than to a wrong one.
- Note: `mask-image` today suppresses the fill entirely rather than painting it flat — the
  documented conservative choice. A real mask is the same image machinery this entry builds,
  applied as an alpha source, and should follow it.

### std.gui.html.011 — Shadows are not drawn

- Intent: `box-shadow` is not a property the parser resolves, and `text-shadow` is not either.
  Cards cast no elevation and outlined hero text loses its legibility layer. The engine's own
  generated documentation avoids both, which is why the gap has stayed invisible.
- Complete when: an outset `box-shadow` with offset, blur and color draws behind the border box
  (inset may be recorded as a limitation), `text-shadow` draws behind the run, and both respect
  border radius.

### std.gui.html.012 — Dashed, dotted and double borders paint solid

- Intent: `HtmlBorderStyle` distinguishes the styles and `paintDecorations` never reads them —
  every side is filled as a solid rectangle or trapezoid, so `border: 1px dashed` draws exactly
  like `solid`. Corner radii are also collapsed: the largest of the four corners is applied to
  all of them, drawn with the top side's width and color alone.
- Complete when: dashed and dotted sides draw their pattern, double draws its two lines, each
  corner uses its own radius, and mixed side colors on a rounded box either draw correctly or
  are recorded as the one documented approximation.

### std.gui.html.013 — `transform` does not exist

- Intent: no transform property is parsed and the painter applies none, so a rotated badge, a
  scaled thumbnail or a translated decoration renders untransformed in place. Unlike the entries
  above this rarely destroys a document's meaning — which is why it sits last in the tier — but
  pages that build shapes out of transformed pseudo-elements show their raw boxes.
- Complete when: `translate`, `scale` and `rotate` transforms apply to a box's painting and hit
  testing as one affine matrix, `transform-origin` is honoured, and layout remains untransformed
  as the specification says.

---

## Tier C — CSS and HTML surface that is silently dropped

### std.gui.html.014 — Presentational HTML is ignored

- Intent: the attributes legacy documents style themselves with — `width`, `height` (read only
  on replaced elements), `align`, `valign`, `bgcolor`, `border`, `cellpadding`, `cellspacing`,
  `hspace`, `vspace`, `nowrap`, and `<font color size face>` — are stored and never consulted,
  and the legacy elements `<center>`, `<font>`, `<big>`, `<strike>`, `<tt>` are unknown tags
  that default to unstyled inline. Saved mail, old manuals and tool-generated HTML from the
  attribute era lose their entire presentation.
- Complete when: the presentational attributes map to the computed style with the precedence of
  a zero-specificity author rule, the legacy elements carry their traditional default styles,
  and a fixture from the attribute era renders with its table borders, cell padding and centered
  blocks.
- Related: std.gui.html.003

### std.gui.html.015 — Selector matching diverges where documents notice

- Intent: two bounded divergences remain. A complex selector inside `:is()`/`:not()` is
  truncated to its first compound — `:is(nav a)` matches `nav` — which over- and under-styles
  silently. And `@layer` blocks are unwrapped into plain source order, so a sheet that uses
  layers to de-prioritize its reset cascades in the wrong order.
- Complete when: `:is()`/`:not()` either match their full complex argument or reject the rule
  rather than truncate it, and layered rules order below unlayered ones.

### std.gui.html.016 — The global keywords do nothing

- Intent: `inherit`, `initial`, `unset` and `revert` are explicitly rejected by
  `htmlParseLength` and fall through every keyword switch, so `background: inherit` and
  `all: unset`-style resets keep whatever was there. For inherited properties the accidental
  behavior is often right; for non-inherited ones it never is.
- Complete when: `inherit` copies the parent's computed value for any property, `initial`
  restores the property's default, `unset` picks between them by inheritance, and `revert` is
  at least `unset` with the divergence recorded.

---

## Tier C — What a reader cannot do

### std.gui.html.017 — What the document says about itself never reaches the reader

- Intent: `<title>` is parsed as raw text and exposed to nothing, so a host tab or window shows
  a file name where the document names itself. A `title` attribute — the tooltip half the web
  puts on abbreviations, truncated cells and icon links — never shows, although the hover
  tracking that could trigger it already exists for links. `<meta name="description">` is
  likewise unreachable.
- Complete when: the view exposes the document title and description to its host, hovering an
  element with a `title` shows it as a themed tooltip after the toolkit's delay, and Swag Scope
  captions its HTML tab with the title.

### std.gui.html.018 — A search cannot cross a text-node boundary

- Intent: `findText` runs `Utf8.indexOf` inside one text node at a time, so a phrase
  interrupted by any inline markup — `find <b>this</b> phrase` — can never be found, and the
  highlight cannot span nodes either. The document already assembles `textContent` per subtree,
  so the pieces exist.
- Complete when: a search runs over a concatenated text with a map back to node-and-offset
  ranges, a match spanning markup highlights each covered run, and case folding goes through
  Unicode rather than `Latin1NoCase`.
- Note: the Markdown view solved the same problem with a position model of its own — a text view
  plus a byte offset into its text — which is the shape this entry needs here.

---

## Tier D — Robustness

### std.gui.html.019 — A hostile document has no budget guard beyond depth and size

- Intent: the byte cap (48 MB) and the element depth cap (256, flattening with a visible
  notice) are the only limits. There is still no fixture for truncation at a hostile point, an
  attribute of pathological length, or a rule that expands `var()` toward its substitution cap
  on every element.
- Complete when: a malformed corpus covers truncated tags at chunk edges, pathological
  attribute lengths and pathological stylesheets with the expected outcome for each.

### std.gui.html.020 — What is left between this parser and a zero-copy one

- Intent: the page above parses in 130 ms where `tl` takes 64 ms. Where the remaining difference
  sits, measured by ablation on the 8.15 MB page: the tokenizer's own scan is about 40% of the
  time, storing text about 30%, storing attributes about 24%, and building the 430 k nodes
  themselves under 10 ms. Nothing here is a single missing idea any more — it is the write traffic
  of 430 k nodes and 289 k attributes against a scan that already runs at about 100 MB/s.
- Next: measure what a page costs when the node array is reserved from the source size (already
  done for a file, not for `createText`), then look at the two remaining per-attribute costs: the
  `class` test on every attribute name, and the pool append that follows it.
- Complete when: the page parses under 100 ms, or the remaining distance is recorded here as the
  cost of the data model rather than of the code.

---

## Out of scope

**Executing anything the document carries.** Scripts, event handlers, and every active content
form are parsed only far enough to be skipped. Permanent boundary, not a gap.

**The network.** No reference is ever fetched remotely — not stylesheets, not images, not
documents. A capability the host wants (a browsing pane) is a different product; this engine
displays files.

**State pseudo-classes by restyling.** `:hover` and its kind would cost a document-wide restyle
per pointer move; the viewer answers the pointer while painting instead. Recorded here because
it is a decision, not an omission.

**Interactive forms.** A checkbox draws its checked state and nothing accepts input; a field
model belongs to an application, not a viewer.

**Web fonts.** `@font-face` is skipped and families reduce to the theme's sans, serif and mono
faces on purpose: a themed application reads better in its own faces, and font fetching is
network. Revisit only if a consumer needs fidelity over consistency.

**Animations and transitions.** A static viewer draws the final state.
