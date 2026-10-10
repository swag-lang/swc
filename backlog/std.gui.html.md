# HTML Backlog

This backlog covers the HTML engine in `bin/std/modules/gui/src/controls/html` — the
parser, the CSS cascade, the layout engine, the painter, and the `HtmlView` widget on top of
them. It is measured against the embedded engines it competes with — litehtml, Sciter and
Ultralight — with a browser as the reference for what a page means. This engine is an offline,
script-free, network-free document viewer.

The engine lives beside its widget inside `gui`; the view owns document selection and copying.
[README.md](README.md) has the entry format.


## Entries

### std.gui.html.003 — A table has no column model

- Intent: columns are sized from cell content. A definite pixel `width` on a cell replaces that
  cell's content measure in `intrinsicWidths` (`controls/html/layout.swg`), and `layoutTable`
  folds it into its column's minimum and maximum, so it is one input rather than a declared
  column width. A percentage width, a `<col>` width, the HTML `width` attribute on a cell,
  `table-layout: fixed`, `border-spacing`, `border-collapse` and `caption-side` are all unread
  (`border-collapse` is not even a property the parser resolves). Every browser default separates
  cell borders by 2px; here cells touch, and a bordered table draws doubled walls where a
  collapsed one means single lines.
- Done when: an author-declared column width wins over content sizing, `table-layout: fixed`
  sizes from the first row, border spacing separates and `border-collapse: collapse` merges
  adjacent cell borders, and the tables fixture compares those against browser geometry,
  including the pixel-width cell case already supported.
- Related: std.gui.html.002, std.gui.html.014

### std.gui.html.012 — Dashed, dotted and double borders paint solid

- Evidence: `HtmlBorderStyle` distinguishes `Dashed`, `Dotted` and `Double`, but `paintDecorations`
  only tests for `None`, so every side is filled as a solid rectangle or trapezoid and
  `border: 1px dashed` draws exactly like `border: 1px solid`.
- Next: give a side its dash pattern at paint time, deciding where the phase restarts at a corner
  and how a pattern follows a rounded one, then draw `double` as two strokes sharing the declared
  width.
- Done when: dashed and dotted sides draw their pattern and `double` draws its two lines, on
  square and rounded boxes alike, with a golden holding each.

### std.gui.html.006 — A fixed box is placed against the viewport and then scrolls away from it

- Evidence: `position: fixed` resolves against the viewport, which places it correctly while the
  document sits at scroll zero, but `paintBox` still reaches it through its parent and adds the
  scroll translation, so a fixed header leaves the screen. It is also pruned with an ancestor whose
  `paintBounds` left the viewport, and hit tested at the scrolled position rather than the drawn one.
- Next: collect the fixed boxes the layout placed, then give the four tree walks of `paint.swg` —
  painting, hit testing, scroll-region lookup and selection — a root-level pass over that list,
  excluded from the ordinary walk and from `computePaintBounds`, so a fixed box neither scrolls
  nor is pruned with an ancestor that left the viewport.
- Done when: a fixed box holds its viewport position while the document scrolls, is hit tested
  where it is drawn, and stays visible when the box that holds it in the tree has scrolled away.
- Related: std.gui.html.023

### std.gui.html.023 — `z-index` does not hoist a positioned descendant into its stacking context

- Historical provenance: split from std.gui.html.006, which owned it beside the containing-block
  resolution that has since shipped.
- Evidence: `paintChildren` orders positioned *siblings* by `stackingLevel` within their parent, and
  `hasStacked` is set on a box only when one of its own children carries a non-zero level. A
  positioned box nested under static ancestors therefore paints at its tree level: a `z-index: 10`
  badge inside a plain wrapper still draws under a later sibling of that wrapper, which is the
  ordinary overlay and dropdown idiom. Hit testing, scroll-region lookup and selection repeat the
  same walk shape, so the order has to be shared rather than fixed in the painter alone.
- Next: decide where the stacking context is built. Collecting each context's positioned
  descendants once, at the end of layout, keeps the four walks reading one ordered list instead of
  each rediscovering the order; establish which boxes create a context — a positioned box with a
  level, `opacity` below one, an `overflow` region — before choosing the representation.
- Done when: a positioned descendant paints, hit tests and selects at its stacking-context
  level rather than its tree level, the boxes that create a context are documented, and a golden
  holds the overlay idiom.
- Related: std.gui.html.006

### std.gui.html.009 — Inline and embedded SVG images are not rendered

- Evidence: `HtmlImageCache.fetch` in `controls/html/image.swg` parses local `.svg` files through
  `Svg.Drawing`, preserves their natural layout size, and rasterizes visible vectors at their
  displayed size with a 4,096-pixel dimension bound and an 8-megapixel area bound.
  `htmlview.test.swg` verifies intrinsic dimensions and CSS overrides. Inline `<svg>` remains in
  `HtmlDocument.isSkippedTag`, and data URIs still go through the raster-only `Image.fromDataUri`.
- Next: route bounded embedded SVG bytes through the existing SVG engine and define how an inline
  subtree preserves its namespace, dimensions, styles, and offline resource policy.
- Done when: inline `<svg>` and `data:image/svg+xml` render through the same bounded path as
  local SVG, their dimensions are honored, unsupported content has a visible placeholder, and
  regression fixtures preserve the working local-image path.

### std.gui.html.011 — Shadows are not drawn

- Intent: `box-shadow` is not a property the parser resolves, and `text-shadow` is not either.
  Cards cast no elevation and outlined hero text loses its legibility layer. The generated
  documentation stylesheet in `src/Doc/DocPage.cpp` now uses `box-shadow`, which this viewer drops.
- Done when: an outset `box-shadow` with offset, blur and color draws behind the border box
  (inset may be recorded as a limitation), `text-shadow` draws behind the run, and both respect
  border radius.

### std.gui.html.013 — `transform` does not exist

- Intent: no transform property is parsed and the painter applies none, so a rotated badge, a
  scaled thumbnail or a translated decoration renders untransformed in place. Unlike the entries
  above this rarely destroys a document's meaning, but
  pages that build shapes out of transformed pseudo-elements show their raw boxes.
- Done when: `translate`, `scale` and `rotate` transforms apply to a box's painting and hit
  testing as one affine matrix, `transform-origin` is honoured, and layout remains untransformed
  as the specification says.

### std.gui.html.015 — Cascade layers collapse into source order

- Evidence: `addSubSelectors` rejects an argument when compound parsing leaves unconsumed input;
  `htmlview.test.swg` covers `:is(nav a)` and `:not(nav a)` without applying a truncated selector.
- Intent: `@layer` blocks are still unwrapped into plain source order, so a sheet that uses
  layers to de-prioritize its reset cascades in the wrong order.
- Done when: layers retain their declared order, ordinary layered rules order below unlayered
  rules, and important declarations reverse layer precedence, with focused cascade tests.

### std.gui.html.019 — Adversarial document coverage is incomplete

- Intent: the byte cap (48 MB) and the element depth cap (256, flattening with a visible
  notice) bound document storage and nesting. There is still no fixture for truncation at a hostile point, an
  attribute of pathological length, or a rule that expands `var()` toward its substitution cap
  on every element.
- Done when: a malformed corpus covers truncated tags at chunk edges, pathological
  attribute lengths and pathological stylesheets with the expected outcome for each.

### std.gui.html.020 — What is left between this parser and a zero-copy one

- Intent: the page above parses in 130 ms where `tl` takes 64 ms. Where the remaining difference
  sits, measured by ablation on the 8.15 MB page: the tokenizer's own scan is about 40% of the
  time, storing text about 30%, storing attributes about 24%, and building the 430 k nodes
  themselves under 10 ms. Nothing here is a single missing idea any more — it is the write traffic
  of 430 k nodes and 289 k attributes against a scan that already runs at about 100 MB/s.
- Evidence: file loading, `createText`, and text replacement now call `reserveForSource`.
- Next: refresh the profile after those reservations, then examine the two per-attribute costs: the
  `class` test on every attribute name, and the pool append that follows it.
- Done when: the page parses under 100 ms, or the remaining distance is recorded here as the
  cost of the data model rather than of the code.

### std.gui.html.014 — Legacy presentational HTML support is incomplete

- Implemented: `HtmlStyleResolver` applies `align` and image `width`/`height` before author CSS.
- Intent: the remaining attributes legacy documents style themselves with — cell dimensions,
  `valign`, `bgcolor`, `border`, `cellpadding`, `cellspacing`,
  `hspace`, `vspace`, `nowrap`, and `<font color size face>` — are stored and never consulted,
  and the legacy elements `<center>`, `<font>`, `<big>`, `<strike>`, `<tt>` are unknown tags
  that default to unstyled inline. Saved mail, old manuals and tool-generated HTML from the
  attribute era lose the presentation carried by those unsupported features.
- Done when: the presentational attributes map to the computed style with the precedence of
  a zero-specificity author rule, the legacy elements carry their traditional default styles,
  and a fixture from the attribute era renders with its table borders, cell padding and centered
  blocks.
- Related: std.gui.html.003

### std.gui.html.001 — Content wider than its container cannot be reached

- Intent: nothing in the engine scrolls horizontally. The widget's `ScrollWnd` is created with
  `DisableHorizontal` and the canvas is always laid out at viewport width; an `overflow` region
  keeps a `scrollTop` and no `scrollLeft`, so `overflow-x: auto` — the standard idiom on every
  code block and wide table — clips the right edge and offers no way to see it. A wide `<pre>`
  line (whose `white-space: pre` legitimately never wraps) is simply unreadable past the margin.
- Done when: an `overflow-x: auto` region whose content is wider than itself scrolls
  horizontally with the same themed bar its vertical axis has, wheel and drag both drive it, and
  a document whose minimum content width exceeds the viewport either pans or is reported as a
  deliberate refusal rather than silently cut.

### std.gui.html.002 — `colspan` and `rowspan` are ignored

- Intent: `layoutTable` assigns each cell to the column of its index, so a header spanning three
  columns compresses into one and every row below it shifts. Spans are the first thing a real
  table uses. This was second in line in the old combined entry.
- Done when: a cell's `colspan` and `rowspan` attributes place and size it across its
  columns and rows, column min/max measurement distributes a spanning cell's width over the
  columns it covers, and `html.tables.html` gains span cases checked against a browser.
- Related: std.gui.html.003

### std.gui.html.004 — A grid places items in source order only

- Intent: `layoutGrid` fills declared columns left to right, row by row. `grid-column` and
  `grid-row` are parsed as bare integers and then never read by layout; spans, negative lines,
  named lines and areas, `grid-template-rows`, `auto-fill`/`auto-fit` and implicit tracks are
  not modelled. A numeric `repeat()` now unrolls in `gridTemplate`; the two automatic counts
  still collapse to a single flexible track because they depend on the width layout discovers.
- Done when: `grid-column`/`grid-row` with spans place items in an occupancy grid with
  implicit rows, `auto-fill` and `auto-fit` derive their count from the available width,
  `grid-template-rows` sizes declared rows, and `html.flex-grid.html` gains placed-and-spanned
  cases checked against a browser.

### std.gui.html.005 — Flex containers ignore half of their alignment surface

- Intent: four parsed properties never reach flex layout. `order` is stored and never sorted on.
  `align-content` never distributes the cross axis of a wrapped container. `align-items:
  baseline` falls through to start alignment because `layoutFlexLine` only handles center, end
  and stretch. And a column container ignores `justify-content` entirely — `layoutFlexColumn`
  stacks from the top whatever the document asks — and cannot wrap.
- Done when: items lay out in `order` order, a wrapped container distributes its lines per
  `align-content`, row items align on their first baselines, a column container distributes free
  main-axis space per `justify-content`, and the flex fixture asserts each against browser
  geometry.

### std.gui.html.007 — Right-to-left text is drawn left-to-right

- Intent: there is no notion of direction anywhere: `dir` is an attribute like any other,
  `direction` and `unicode-bidi` are not property names, `text-align: start` is a synonym for
  left, and an Arabic or Hebrew text node is measured and drawn in logical order, which for RTL
  scripts is backwards. Part of the limit sits below this engine — the toolkit's text stack
  shapes no complex scripts — but the engine does not even reorder what the stack could draw.
- Done when: the paragraph direction follows `dir`/`direction`, RTL runs within a line are
  reordered per the bidirectional algorithm's paragraph-and-run level, `start`/`end` alignment
  follows direction, and the residual shaping limit is recorded against the text stack rather
  than silently absorbed here.

### std.gui.html.010 — A gradient is read as no background at all

- Intent: `background` keeps only a color; `background-image`, `linear-gradient` and
  `radial-gradient` are deliberately dropped so the box keeps what is behind it. For a hero
  band or a striped code header that is the difference between the page's structure and a flat
  void — and `Painter` already draws gradient brushes for the toolkit's own widgets.
- Done when: linear and radial gradients with color stops fill a box's background through
  the painter's brushes, a local `background-image` file is drawn with `background-size: cover`
  and `contain` at least, and an unsupported image value still degrades to the base color rather
  than to a wrong one.
- Note: `mask-image` today suppresses the fill entirely rather than painting it flat — the
  documented conservative choice. A real mask is the same image machinery this entry builds,
  applied as an alpha source, and should follow it.

### std.gui.html.016 — The global keywords do nothing

- Intent: `inherit`, `initial`, `unset` and `revert` are explicitly rejected by
  `htmlParseLength` and fall through every keyword switch, so `background: inherit` and
  `all: unset`-style resets keep whatever was there. For inherited properties the accidental
  behavior is often right; for non-inherited ones it never is.
- Done when: `inherit` copies the parent's computed value for any property, `initial`
  restores the property's default, `unset` picks between them by inheritance, and `revert` is
  at least `unset` with the divergence recorded.

### std.gui.html.017 — What the document says about itself never reaches the reader

- Intent: `<title>` is parsed as raw text and exposed to nothing, so a host tab or window shows
  a file name where the document names itself. A `title` attribute — the tooltip half the web
  puts on abbreviations, truncated cells and icon links — never shows, although the hover
  tracking that could trigger it already exists for links. `<meta name="description">` is
  likewise unreachable.
- Done when: the view exposes the document title and description to its host, hovering an
  element with a `title` shows it as a themed tooltip after the toolkit's delay, and Swag Scope
  captions its HTML tab with the title.

### std.gui.html.018 — A search cannot cross a text-node boundary

- Intent: `findText` runs `Utf8.indexOf` inside one text node at a time, so a phrase
  interrupted by any inline markup — `find <b>this</b> phrase` — can never be found, and the
  highlight cannot span nodes either. The document already assembles `textContent` per subtree,
  so the pieces exist.
- Done when: a search runs over a concatenated text with a map back to node-and-offset
  ranges, a match spanning markup highlights each covered run, and case folding goes through
  Unicode rather than `Latin1NoCase`.
- Note: the Markdown view solved the same problem with a position model of its own — a text view
  plus a byte offset into its text — which is the shape this entry needs here.

---
