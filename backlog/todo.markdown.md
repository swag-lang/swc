# Markdown Roadmap

This file is the roadmap for the Markdown engine in `bin/std/modules/gui/src/controls/markdown` —
the block parser, the inline renderer, and the `Markdown.View` widget on top of them. It is
measured against the readers it competes with — Typora, the VS Code preview, and GitHub's web
rendering — with CommonMark plus GFM as the reference for what a document means, while staying
what the whole document family is: an offline, script-free, network-free viewer.

It is not the repository's discovery backlog. Defects and leads belong in the `findings.*` files;
where a document engine lives is decided — beside its widget, inside `gui`, as
[todo.pdf.md](todo.pdf.md#where-this-family-lives-and-why) records for the whole family; selection
and copy are shared with `HtmlView` and stay in
[T-419](todo.gui.md#t-419--rendered-document-views-cannot-select-or-copy-text), and the
application-level affordances a viewer plugin adds — zoom, printing, thumbnails — stay in
[todo.filescope.md](todo.filescope.md). This file holds intent about the Markdown engine itself.
[README.md](README.md) has the whole layout.

Entries are ordered by decreasing value, not by decreasing effort. An entry disappears when it
ships; history lives in git, not here.

## Where the engine already stands

About 2 900 lines across seven files, split cleanly into a parser and a renderer. The block
parser is line-based and single-pass: ATX and setext headings, fenced code with a language label,
GFM pipe tables with per-column alignment, ordered, unordered and task lists with soft-wrap
continuation, block quotes carrying the five GitHub alerts, thematic breaks, YAML front matter,
`[TOC]`, footnotes, reference definitions, and display mathematics in both `$$` and `\[` forms.
The inline renderer emits a private markup protocol — emphasis through bold-italic, strikethrough,
highlight, code spans, sub- and superscript, inline/reference/collapsed links, autolinks and bare
URLs, escapes, entities, and inline mathematics parsed by `Pixel.MathExpression` rather than
approximated with text. The view streams multi-megabyte files behind a byte-to-height estimate,
reveals an arbitrary byte offset without parsing what precedes it, navigates by line, page and
document boundary from the keyboard, restyles live from a theme sheet and a typography style —
the sFileScope plugin ships five complete reading themes on top of it — finds and highlights text,
and signals link activation to its host. Tests cover the block grammar, emphasis nesting, inline
mathematics, wrap, forward and reverse streaming, and both failure paths.

## Tier A — Parity a reader notices in the first minute

### T-491 — An image renders as a link, not as an image

`![alt](url)` renders the clickable text `[Image: alt]`. Every README leads with a logo or a
screenshot, so this is the first difference a reader sees against any competitor. Local images —
a path resolved against the document's directory — and `data:` URIs decode through Pixel and
paint at their intrinsic size capped to the document column; the HTML engine beside this one
already decodes `data:` images, and the network stance is shared: a remote URL stays a link.
Streaming must survive it: decode off the parse step, occupy a placeholder, and relayout when the
bitmap arrives, without disturbing the byte-to-height estimate.

- Intent: Markdown documents show their images instead of naming them
- Complete when: a fixture with a local image and a `data:` image paints both through `createText`
  and `createFile`, and a remote URL still renders as today's link
- Related: T-419

### T-492 — Block structure is flat: containers do not nest

The parser recognizes every leaf block but no container can hold one. A list inside a quote, a
fence inside a quote, or a `> >` nested quote all degrade — the second `>` even paints as a stray
`›` glyph. A fence inside a list item is deliberately hoisted to a sibling block, which keeps it
readable but loses its indentation and its ownership; a second paragraph of a list item loses the
item's hanging indent entirely. Real documents — changelogs, RFCs, this repository's own backlog —
are made of exactly these shapes. The outcome is a container-block tree (quote and list item own
child blocks, rendered with inherited indent and the quote border spanning its children) while
keeping the streamed, per-block visual pipeline as it is.

- Intent: quotes and list items own child blocks instead of flattening or hoisting them
- Complete when: a fixture with a list in a quote, a fence in a list item, a multi-paragraph item
  and a two-level quote lays out with correct indentation and borders, and the existing
  list-hoisting test is rewritten to the new stance

### T-493 — A code block is not a code surface

Three gaps compound. Leading indentation collapses — the layout skips spaces at the start of a
line for every kind but `.List` (`inlineview.swg`), so a fenced Swag snippet paints flush-left and
its structure is gone. The fence's language is shown as an uppercase label but never used: no
syntax coloring, while the repository already colors Swag both in `DocMarkdown` and through the
RichEdit lexer interface (`controls/richedit/lexerswag.swg`). And long lines soft-wrap with
nothing marking the wrap. Indentation is a correctness break, not a preference; coloring is the
visible half of parity with every competitor.

- Intent: fenced code paints with exact whitespace and language coloring
- Complete when: indentation is preserved byte-for-byte, a `swag` fence colors through the shared
  lexer interface, an unknown language stays plain, and wrapped lines are visually distinguishable
  from new lines

### T-494 — Table columns all get the same width

`TableView` divides the available width by the column count, so a two-word status column takes the
same room as a sentence-long description column and forces it to wrap. Columns must size from
measured cell content — natural width per column, minimum readable width, surplus distributed to
the columns that want it — inside the document column cap. While in the file: body rows carrying
more cells than the header silently drop the extras; clip them visibly or widen the table, but
decide.

- Intent: table columns size from their content
- Complete when: the comprehensive fixture's tables show narrow columns narrow and wide columns
  wide, at every document width the sFileScope plugin offers

## Tier B — The text and the links must be right

### T-495 — The markup protocol cannot say a literal angle bracket

`richText` substitutes `<` and `>` (and the `&lt;`/`&gt;` entities) with the look-alike guillemets
`‹`/`›` so `InlineView.parse` never re-reads document text as protocol tags. The reader gets the
wrong glyph, search over the rebuilt atom text cannot match the source characters, and the moment
selection ships (T-419) a copy would paste guillemets into a compiler. The protocol needs a real
escape, and the substitution disappears everywhere.

- Intent: the inline protocol carries literal `<` and `>` losslessly
- Complete when: a paragraph, a code span and a table cell containing `a < b > c` paint, search
  and (once T-419 lands) copy the exact characters
- Related: T-419

### T-496 — A link destination ends at the first closing parenthesis

`[text](url "title")` puts the quoted title inside the activated URL; a destination containing
`)` truncates early; the `<destination with spaces>` form is unread. Titles are common in
generated documentation, so today those links are silently wrong. Parse the destination per
CommonMark — balanced or escaped parentheses, optional angle form, optional title — activate the
clean URL, and keep the title (a tooltip is the natural home once one exists).

- Intent: link destinations parse to the URL the author wrote
- Complete when: titled links, parenthesized URLs and angle destinations all activate their exact
  target in the parser tests

### T-497 — Reference and footnote definitions do not cross a streaming boundary

`parseBlocks` collects definitions only from the chunk it is parsing, and the convention every
real document follows — all `[name]: target` lines gathered at the end of the file — is exactly
the layout streaming defeats: body reference links render as raw `[text][ref]` literals because
their definitions have not been read yet. Resolution has to become document-wide in streamed
mode: either a definition pre-scan when the file opens, or atoms that carry the reference name
and resolve when the definition arrives. `revealFileOffset` windows have the same hole in both
directions.

- Intent: a streamed document resolves references wherever their definitions sit
- Complete when: a multi-chunk streamed fixture with end-of-file definitions renders every
  reference link and footnote live, including after a reveal

### T-498 — The document cannot navigate itself

`[TOC]` renders a flat, inert text block — its two-space indents are the same leading whitespace
the layout collapses (T-493's cause), and no entry is a link. Heading anchors do not exist, so a
`#fragment` link leaves through `sigLinkActivated` and dies in `Env.openUrl`. A footnote
reference paints as a superscript but does not jump to its footnote. A reader of a long streamed
document has keyboard paging and nothing else. Anchored navigation needs the parser to keep each
heading's byte offset, which is the same currency `revealFileOffset` already trades in.

- Intent: TOC entries, `#fragment` links and footnote references scroll to their target
- Complete when: clicking a TOC entry or an in-document anchor reaches its heading in both
  `createText` and a streamed file, and the TOC shows its hierarchy

## Tier C — Conformance and finish

### T-499 — Inline HTML has no stance

READMEs written for GitHub lean on a small HTML set — `<br>` in table cells, `<img>` for sized
logos, `<kbd>`, `<details>` — and today all of it renders as escaped text with substituted
glyphs. The engine will never execute anything, but it owes a decision: support a minimal
allowlist (at least `<br>` and `<img>`, which have exact equivalents already), and render the
rest as clean literal text once T-495 makes that possible. Document the list the way the HTML
engine documents its stances.

- Intent: a decided, documented behavior for inline HTML instead of an accident
- Complete when: `<br>` breaks a line, `<img>` paints through T-491's path, and an unsupported tag
  renders as its literal source text
- Related: T-491, T-495

### T-500 — No measured conformance stance

Nobody can say which part of CommonMark the parser speaks. Run the CommonMark and GFM example
corpora through `parseBlocks`/`renderInline`, record each case as passing or deviating by choice,
and fix the cheap, high-frequency failures the sweep will surface — known already: no
double-backtick code spans, no backslash hard break, a fence closes on any three matching
characters so a ```` ```` ```` fence cannot display a ```` ``` ```` fence, ordered lists render
their literal markers instead of renumbering, indented code blocks do not exist, and `_foo_bar`
closes emphasis inside a word. The recorded stance is the durable artifact; the fixes are the
first harvest.

- Intent: conformance is a measured number with a recorded stance, not a guess
- Complete when: the corpus runs as a test, a stance file lists every deviation as deliberate,
  and the failures named above are fixed or claimed

### T-501 — Find highlights one match, first per block

`highlightText` marks only the first case-insensitive occurrence in a block, and `findText` moves
block to block with a single wrap: no all-match highlight, no next/previous within a block, no
match count. sFileScope's search panel deserves the same behavior over Markdown as over code.

- Intent: find shows every match and walks them one by one
- Complete when: all visible occurrences highlight, repeated find advances match-by-match across
  and within blocks, and the match count is exposed to the host

### T-502 — The view's English is hardcoded

The alert titles ("Note", "Tip", "Important", "Warning", "Caution" in `block.swg`), "This
Markdown document is empty.", "Unable to read this Markdown document." and the zero-byte failure
message are literal English inside the module, against the repository's localization rule. Route
them through `Gui.Strings` with French translations like every other gui string.

- Intent: no user-visible literal English in the Markdown engine
- Complete when: every string has a `Gui.Strings` key and a French translation, and a language
  switch restyles a rendered document's alert titles

### T-503 — No typographic finish

Straight quotes stay straight, `--` never becomes an en dash, `...` never becomes an ellipsis,
and `:smile:` renders as its source. Typora treats smart punctuation as an opt-in and readers
expect emoji shortcodes anywhere GitHub-flavored text appears. Both are inline-renderer
transforms behind a `Style` flag, default off.

- Intent: opt-in smart punctuation and emoji shortcodes
- Complete when: the flag converts quotes, dashes and ellipses without touching code spans or
  math, and known shortcodes render their emoji
