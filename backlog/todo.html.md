# Html Roadmap

This file is the roadmap for the HTML engine in `bin/std/modules/gui/src/controls/html` — the
parser, the CSS cascade, the layout engine, the painter, and the `HtmlView` widget on top of
them. It is measured against the embedded engines it competes with — litehtml, Sciter and
Ultralight — with a browser as the reference for what a page means, while staying what none of
them are: an offline, script-free, network-free document viewer.

It is not the repository's discovery backlog. Defects and leads belong in the `findings.*`
files; where a document engine lives is decided — beside its widget, inside `gui`, as
[todo.pdf.md](todo.pdf.md#where-this-family-lives-and-why) records for the whole family;
selection and copy are shared with `MarkdownView` and stay in
[T-419](todo.gui.md#t-419--rendered-document-views-cannot-select-or-copy-text). This file holds
intent about the HTML engine itself. [README.md](README.md) has the whole layout.

Entries are ordered by decreasing value, not by decreasing effort. An entry disappears when it
ships; history lives in git, not here.

## Where the engine already stands

About 8 700 lines across thirteen files, and the shape is a real engine, not a tag-to-widget
translator. The parser is resumable and streams: a document fed in 48 KB chunks produces exactly
the tree the whole file would, partial renderings appear at growing intervals, a 48 MB cap ends
the load with a visible notice, and every node keeps its source byte offset — which is what lets
sFileScope reveal a raw-file search hit on the exact line that draws it. The cascade is the real
one: specificity, `!important`, source order, media queries including `prefers-color-scheme`
answered from the host theme, custom properties with proper scope and `var()` fallbacks,
`calc()`/`min()`/`max()`/`clamp()`, `color-mix()`, `::before`/`::after` generated boxes, and
rules bucketed by subject so a thousand-rule sheet costs a handful of comparisons per element.
Layout covers block flow with margin collapsing, a full inline formatting context with
justification and vertical alignment, row and column flex, a declared-columns grid, tables sized
from cell content, sticky positioning, and independently scrolled `overflow` regions with themed
scrollbars. Painting prunes by subtree bounds, orders positioned siblings by stacking level, and
answers hover on links without restyling — a documented stance: a state pseudo-class that would
need a per-frame restyle matches never, and the viewer lights the link while painting instead.

Two boundaries are deliberate and permanent: nothing the document carries is ever executed, and
the engine never opens a network connection. A document is displayed from its own bytes and its
own folder, whatever it links to.

The gaps are of four kinds: source that decodes into the wrong tree, pages that lay out or paint
as something other than what they mean, CSS surface that is read and silently dropped, and an
engine whose output no test ever compares to a rendered reference.

---

## Tier A — Source that reads wrong

### T-463 — A document that is not UTF-8 is drawn as mojibake

- Intent: `HtmlView` reads files through `readUtf8Chunk` and nothing ever asks what encoding the
  bytes are in. `<meta charset>` is parsed as an element and ignored, a byte-order mark is not
  looked for, and a windows-1252 or ISO-8859-1 file — which is what most HTML saved before 2010
  and a large share of generated reports still are — renders every accented character as garbage.
  Every competing engine sniffs at least the BOM and the meta declaration.
- Complete when: the BOM and a `<meta charset>` within the first kilobytes select the decoding,
  windows-1252 and ISO-8859-1 are transcoded to UTF-8 as they stream, an undeclared document
  falls back to windows-1252 when its bytes are not valid UTF-8, and a fixture in each encoding
  renders its accents.

### T-464 — A `>` inside a quoted attribute value ends the tag early

- Intent: `HtmlParser.readMarkup` finds the end of a tag with `Utf8.indexOf(source, '>')`,
  blind to quotes. `<a title="a > b">` closes the tag at the first `>`, the rest of the value
  becomes document text, and every element after it parses from the wrong position. Arrows in
  tooltips and comparison operators in data attributes are ordinary content on real pages.
- Complete when: the tag scanner honours single and double quotes while looking for `>`, an
  unterminated quote still terminates at some bounded point rather than eating the document, and
  the streaming carry logic still resumes correctly when the quoted tag is cut by a chunk edge.

### T-465 — The recoveries browsers standardized are missing

- Intent: the tree builder handles implied end tags well (`closeImplied`), but not the two
  recoveries the HTML standard made mandatory because the web depends on them. Misnested
  formatting — `<b>one <i>two</b> three</i>` — pops the inline stack flat, so `three` loses its
  italic where every browser reconstructs it (the adoption agency algorithm). And content written
  directly inside `<table>` but outside any cell stays there, where browsers foster-parent it in
  front of the table; here it lands inside the table structure and renders inside the grid.
  A `<p>` interrupted while an inline element is open is not closed at all — `closeImplied`
  stops at the first non-closable element — so an unbalanced page still builds a staircase.
- Complete when: misnested formatting elements keep their formatting across the misnesting,
  non-table content inside a table renders before it, an interrupted paragraph closes through
  its open inline children, and the parser tests assert those tree shapes against what a browser
  builds for the same source.

---

## Tier B — Pages that lay out other than they mean

### T-387 — `float` and `clear` lay out as ordinary blocks

- Intent: `float: left` and `float: right` are parsed into the computed style and then
  `HtmlLayout.buildChild` stacks the box like any other block, so a floated figure takes a whole
  line and nothing wraps around it. `clear` guards against floats that never float. This is the
  single most visible difference between this engine and a browser on a classic article page,
  and it was first in line when this list lived in `todo.gui.md`.
- Complete when: a left or right float is taken out of the stack, line boxes of the following
  content shorten around it, `clear` moves a block below the floats it names, and the
  comprehensive fixture's floated figure matches the browser's arrangement.

### T-466 — An unbreakable run never breaks

- Intent: `HtmlLayout.wordEnd` finds break opportunities only at ASCII whitespace. A long URL, a
  hash, or an identifier wider than the column overflows it; `overflow-wrap`, `word-break` and
  `line-break` are not even property names the sheet parser knows. Chinese and Japanese text —
  which carries no spaces — is one unbreakable run per text node and overflows every container
  it meets. `<wbr>` produces an empty inline box instead of a break opportunity, and `&shy;`
  stays a visible character in the run.
- Complete when: `overflow-wrap: break-word` and `word-break: break-all` break an overlong run
  at a character boundary, CJK characters are break opportunities by default, `<wbr>` and
  `&shy;` mark soft break points (the soft hyphen drawing only where a break was taken), and a
  fixture with a long URL and a CJK paragraph stays inside its column.
- Related: T-467

### T-467 — Content wider than its container cannot be reached

- Intent: nothing in the engine scrolls horizontally. The widget's `ScrollWnd` is created with
  `DisableHorizontal` and the canvas is always laid out at viewport width; an `overflow` region
  keeps a `scrollTop` and no `scrollLeft`, so `overflow-x: auto` — the standard idiom on every
  code block and wide table — clips the right edge and offers no way to see it. Combined with
  T-466 this makes a wide `<pre>` line simply unreadable past the margin.
- Complete when: an `overflow-x: auto` region whose content is wider than itself scrolls
  horizontally with the same themed bar its vertical axis has, wheel and drag both drive it, and
  a document whose minimum content width exceeds the viewport either pans or is reported as a
  deliberate refusal rather than silently cut.
- Related: T-466

### T-468 — `colspan` and `rowspan` are ignored

- Intent: `layoutTable` assigns each cell to the column of its index, so a header spanning three
  columns compresses into one and every row below it shifts. Spans are the first thing a real
  table uses. This was second in line in the old combined entry.
- Complete when: a cell's `colspan` and `rowspan` attributes place and size it across its
  columns and rows, column min/max measurement distributes a spanning cell's width over the
  columns it covers, and `html.tables.html` gains span cases checked against a browser.
- Related: T-469

### T-469 — A table has no column model

- Intent: columns are sized from cell content alone. A `width` on a cell or a `<col>`, a
  percentage column, `table-layout: fixed`, `border-spacing`, `border-collapse` and
  `caption-side` are all unread (`border-collapse` is not even a property the parser resolves).
  Every browser default separates cell borders by 2px; here cells touch, and a bordered table
  draws doubled walls where a collapsed one means single lines.
- Complete when: an author-declared column width wins over content sizing, `table-layout: fixed`
  sizes from the first row, border spacing separates and `border-collapse: collapse` merges
  adjacent cell borders, and the tables fixture compares those against browser geometry.
- Related: T-468, T-481

### T-470 — A grid places items in source order only

- Intent: `layoutGrid` fills declared columns left to right, row by row. `grid-column` and
  `grid-row` are parsed as bare integers and then never read by layout; spans, negative lines,
  named lines and areas, `grid-template-rows`, `auto-fill`/`auto-fit` and implicit tracks are
  not modelled. Worse, `repeat()` is not recognized by `gridTemplate` at all: `repeat(3, 1fr)`
  — the most common template on the web — parses as a single flexible track, so a three-column
  gallery renders as one column.
- Complete when: `repeat()` expands to its track list, `grid-column`/`grid-row` with spans place
  items in an occupancy grid with implicit rows, `grid-template-rows` sizes declared rows, and
  `html.flex-grid.html` gains placed-and-spanned cases checked against a browser.

### T-471 — Flex containers ignore half of their alignment surface

- Intent: four parsed properties never reach flex layout. `order` is stored and never sorted on.
  `align-content` never distributes the cross axis of a wrapped container. `align-items:
  baseline` falls through to start alignment because `layoutFlexLine` only handles center, end
  and stretch. And a column container ignores `justify-content` entirely — `layoutFlexColumn`
  stacks from the top whatever the document asks — and cannot wrap.
- Complete when: items lay out in `order` order, a wrapped container distributes its lines per
  `align-content`, row items align on their first baselines, a column container distributes free
  main-axis space per `justify-content`, and the flex fixture asserts each against browser
  geometry.

### T-472 — A positioned box is positioned against the wrong ancestor

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

### T-473 — Right-to-left text is drawn left-to-right

- Intent: there is no notion of direction anywhere: `dir` is an attribute like any other,
  `direction` and `unicode-bidi` are not property names, `text-align: start` is a synonym for
  left, and an Arabic or Hebrew text node is measured and drawn in logical order, which for RTL
  scripts is backwards. Part of the limit sits below this engine — the toolkit's text stack
  shapes no complex scripts — but the engine does not even reorder what the stack could draw.
- Complete when: the paragraph direction follows `dir`/`direction`, RTL runs within a line are
  reordered per the bidirectional algorithm's paragraph-and-run level, `start`/`end` alignment
  follows direction, and the residual shaping limit is recorded against the text stack rather
  than silently absorbed here.

### T-474 — Percentage heights resolve against nothing in normal flow

- Intent: `layoutBlockChildren` builds each child's containing block with a width and
  `hasHeight: false`, so `height: 100%` resolves only for the root and for absolutely
  positioned boxes. The classic full-height chain — `html, body, .app { height: 100% }` — and
  every percentage-height panel inside a definite-height parent collapse to content height.
- Complete when: a child whose parent's used height is definite resolves percentage heights
  against it, the definiteness propagates down a chain of definite heights, and an indefinite
  parent still falls back to content height as it does today.

---

## Tier B — Pages that paint other than they mean

### T-475 — An image embedded in the document never draws

- Intent: `HtmlImageCache.fetch` refuses `data:` URIs along with the network schemes. A `data:`
  image is not a network fetch — the bytes are already in the file — and the self-contained
  export every tool produces (notebooks, saved pages, generated reports) inlines every figure
  exactly this way. Such a document renders as a grid of placeholder rectangles.
- Complete when: a `data:` URI with a base64 or URL-encoded payload of any format `pixel`
  decodes is drawn like a file image, a malformed payload degrades to the placeholder, and the
  refusal of genuinely remote schemes is untouched.
- Related: T-476

### T-476 — SVG never draws, in a toolkit that rasterizes SVG for its own theme

- Intent: two halves. Inline `<svg>` is on the `isSkippedTag` list, so a page's diagrams and
  icons vanish silently. And `<img src="figure.svg">` fails because `Pixel.Image.load` has no
  SVG codec — while the same `pixel` module parses and rasterizes SVG for the theme atlas every
  application ships. The capability exists one layer down and is not wired to either path.
- Complete when: an `<img>` referencing a local `.svg` rasterizes at its laid-out size through
  the existing SVG engine, an inline `<svg>` subtree renders through the same code with its
  width and height honoured, and an SVG feature the rasterizer lacks degrades to the placeholder
  rather than to nothing.
- Related: T-475

### T-477 — A gradient is read as no background at all

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

### T-478 — Shadows are not drawn

- Intent: `box-shadow` is not a property the parser resolves, and `text-shadow` is not either.
  Cards cast no elevation and outlined hero text loses its legibility layer. The engine's own
  generated documentation avoids both, which is why the gap has stayed invisible.
- Complete when: an outset `box-shadow` with offset, blur and color draws behind the border box
  (inset may be recorded as a limitation), `text-shadow` draws behind the run, and both respect
  border radius.

### T-479 — Dashed, dotted and double borders paint solid

- Intent: `HtmlBorderStyle` distinguishes the styles and `paintDecorations` never reads them —
  every side is filled as a solid rectangle or trapezoid, so `border: 1px dashed` draws exactly
  like `solid`. Corner radii are also collapsed: the largest of the four corners is applied to
  all of them, drawn with the top side's width and color alone.
- Complete when: dashed and dotted sides draw their pattern, double draws its two lines, each
  corner uses its own radius, and mixed side colors on a rounded box either draw correctly or
  are recorded as the one documented approximation.

### T-480 — `transform` does not exist

- Intent: no transform property is parsed and the painter applies none, so a rotated badge, a
  scaled thumbnail or a translated decoration renders untransformed in place. Unlike the entries
  above this rarely destroys a document's meaning — which is why it sits last in the tier — but
  pages that build shapes out of transformed pseudo-elements show their raw boxes.
- Complete when: `translate`, `scale` and `rotate` transforms apply to a box's painting and hit
  testing as one affine matrix, `transform-origin` is honoured, and layout remains untransformed
  as the specification says.

---

## Tier C — CSS and HTML surface that is silently dropped

### T-481 — Presentational HTML is ignored

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
- Related: T-469

### T-482 — The `font` shorthand is unread and `word-spacing` is read and never applied

- Intent: two traps of the parsed-but-dead kind. `font: italic 14px/1.5 sans-serif` — the
  shorthand half the web's reset stylesheets use — is not a property name the sheet parser
  resolves, so the whole declaration vanishes. And `word-spacing` is parsed into every computed
  style and then no line in `layout.swg` reads it, so the property silently does nothing. The
  module's own standard elsewhere is that a construct is honoured or reported, never absorbed.
- Complete when: the `font` shorthand expands into its longhands including the `/line-height`
  form, `word-spacing` widens the spaces of a shaped line, and a test asserts both against
  measured geometry.

### T-483 — Modern color notations are refused

- Intent: `htmlParseColor` covers hex, `rgb()`, `hsl()`, named colors and `color-mix()`, and
  stops there. `oklch()` — which Tailwind 4 emits for every color — `oklab()`, `lab()`,
  `lch()`, `hwb()` and `color()` all fail to parse, and a failed color leaves the cascade
  alone, so a page authored with a current toolchain keeps its theme's defaults everywhere it
  meant to paint. Hue units other than degrees (`turn`, `rad`) are misread as raw numbers.
- Complete when: the OK-family, Lab-family and `hwb()` notations convert to sRGB, out-of-gamut
  components clamp, hue units convert, and a Tailwind-4-generated fixture shows its palette.

### T-484 — Selector matching diverges where documents notice

- Intent: four bounded divergences. `:nth-child(an+b)` supports only `odd`, `even` and a bare
  index — `nth-child(3n)` matches nothing. `:nth-of-type` and `first/last-of-type` share
  `nth-child`'s position counter in `matchesPseudo`, counting siblings of every type. A complex
  selector inside `:is()`/`:not()` is truncated to its first compound — `:is(nav a)` matches
  `nav` — which over- and under-styles silently. And `@layer` blocks are unwrapped into plain
  source order, so a sheet that uses layers to de-prioritize its reset cascades in the wrong
  order.
- Complete when: the full `an+b` grammar matches, `-of-type` selectors count within their type,
  `:is()`/`:not()` either match their full complex argument or reject the rule rather than
  truncate it, and layered rules order below unlayered ones.

### T-485 — The global keywords do nothing

- Intent: `inherit`, `initial`, `unset` and `revert` are explicitly rejected by
  `htmlParseLength` and fall through every keyword switch, so `background: inherit` and
  `all: unset`-style resets keep whatever was there. For inherited properties the accidental
  behavior is often right; for non-inherited ones it never is.
- Complete when: `inherit` copies the parent's computed value for any property, `initial`
  restores the property's default, `unset` picks between them by inheritance, and `revert` is
  at least `unset` with the divergence recorded.

### T-486 — The named-entity table is a fraction of the standard's

- Intent: `htmlNamedEntity` resolves some 250 of the 2 231 named references, chosen well, and
  the standard's legacy no-semicolon forms (`&amp`, `&copy`, `&nbsp` bare) are not recognized
  at all — text from the attribute-era web shows literal `&copy` where a mark belongs. The
  `HtmlEntity.second` field for two-code-point references exists and no entry sets it.
- Complete when: the full named table is generated from the specification's list into a compact
  lookup, the no-semicolon legacy subset resolves outside attributes as specified, and the
  two-code-point references use the field built for them.

---

## Tier C — What a reader cannot do

### T-487 — What the document says about itself never reaches the reader

- Intent: `<title>` is parsed as raw text and exposed to nothing, so a host tab or window shows
  a file name where the document names itself. A `title` attribute — the tooltip half the web
  puts on abbreviations, truncated cells and icon links — never shows, although the hover
  tracking that could trigger it already exists for links. `<meta name="description">` is
  likewise unreachable.
- Complete when: the view exposes the document title and description to its host, hovering an
  element with a `title` shows it as a themed tooltip after the toolkit's delay, and sFileScope
  captions its HTML tab with the title.

### T-488 — A search cannot cross a text-node boundary

- Intent: `findText` runs `Utf8.indexOf` inside one text node at a time, so a phrase
  interrupted by any inline markup — `find <b>this</b> phrase` — can never be found, and the
  highlight cannot span nodes either. The document already assembles `textContent` per subtree,
  so the pieces exist.
- Complete when: a search runs over a concatenated text with a map back to node-and-offset
  ranges, a match spanning markup highlights each covered run, and case folding goes through
  Unicode rather than `Latin1NoCase`.
- Related: [T-419](todo.gui.md#t-419--rendered-document-views-cannot-select-or-copy-text),
  which needs the same position model for selection.

---

## Tier D — Robustness

### T-489 — A hostile document has no depth or budget guard

- Intent: the byte cap (48 MB) is the only limit. Styling, box building, layout and painting
  all recurse per element depth (`resolveElement`, `buildChild`, `paintBox`), so a document of
  nothing but `<div>` nested a hundred thousand deep — a few hundred kilobytes — walks the
  native stack to overflow instead of failing cleanly. There is no fixture for truncation at a
  hostile point, an attribute of pathological length, or a rule that expands `var()` toward its
  substitution cap on every element.
- Complete when: element depth is bounded with the same visible-notice behavior as the size
  cap, the recursive passes survive the bound by construction, and a malformed corpus covers
  deep nesting, truncated tags at chunk edges and pathological stylesheets with the expected
  outcome for each.

---

## Tier E — Proof

### T-490 — No rendered document is compared against a golden

- Intent: `htmlview.test.swg` is a real structural suite — trees, cascade results, hit tests,
  fragment navigation, region scrolling — and not one test compares rendered output. Every
  layout and paint entry above would pass today's suite while drawing the wrong page, and the
  repository already has command-stream visual goldens in `pixel` and `gui` for exactly this
  job. The engine's largest consumer, the generated documentation, is not a fixture either.
- Complete when: the comprehensive, tables and flex-grid fixtures render under the existing
  visual-regression harness with goldens, one generated-documentation page joins them, and a
  layout entry shipping above must update a golden to land.

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
