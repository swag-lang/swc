# Markdown Backlog

This backlog covers the Markdown engine in `bin/std/modules/gui/src/controls/markdown` —
the block parser, the inline renderer, and the `Markdown.View` widget on top of them. It is
measured against the readers it competes with — Typora, the VS Code preview, and GitHub's web
rendering — with CommonMark plus GFM as the reference for what a document means, while staying
what the whole document family is: an offline, script-free, network-free viewer.

Evidence, investigations, and intended outcomes for the Markdown engine stay together here. The
engine lives beside its widget inside `gui`, as [gui.pdf.md](gui.pdf.md#where-this-family-lives-and-why)
records for the document family; application-level zoom stays in
[scope.text.md](scope.text.md), shared printing in
[scope.viewers.md](scope.viewers.md), and shell thumbnail integration in
[app.scope.md](app.scope.md).
[README.md](README.md) has the whole layout.

Entries are ordered by decreasing value, not by decreasing effort. An entry disappears when it
ships; history lives in git, not here.

## Where the engine already stands

About 4 150 lines across seven files, split cleanly into a parser and a renderer. The block
parser is line-based and single-pass: ATX and setext headings, fenced code with a language label,
GFM pipe tables with per-column alignment, ordered, unordered and task lists with soft-wrap
continuation, block quotes carrying the five GitHub alerts, thematic breaks, YAML front matter,
`[TOC]`, footnotes, reference definitions, and display mathematics in both `$$` and `\[` forms.
The inline renderer emits a private markup protocol — emphasis through bold-italic, strikethrough,
highlight, code spans, sub- and superscript, inline/reference/collapsed links, autolinks and bare
URLs, escapes, entities, and inline mathematics parsed by `Pixel.MathExpression` rather than
approximated with text. Inline phrasing HTML is translated into the same rich-text protocol;
layout-bearing HTML is hosted by the adjacent HTML engine, including its offline image policy.
The view streams multi-megabyte files behind a byte-to-height estimate,
reveals an arbitrary byte offset without parsing what precedes it, navigates by line, page and
document boundary from the keyboard, restyles live from a theme sheet and a typography style —
the Swag Scope viewer ships five complete reading themes on top of it — finds and highlights text,
and signals link activation to its host. Tests cover the block grammar, emphasis nesting, inline
mathematics, wrap, forward and reverse streaming, and both failure paths.

## Tier A — Parity a reader notices in the first minute

### B-516 — An image renders as a link, not as an image

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

### B-517 — Block structure is flat: containers do not nest

The parser recognizes every leaf block but no container can hold one. A list inside a quote, a
fence inside a quote, or a `> >` nested quote all degrade — the second `>` renders as literal
text. A fence inside a list item is deliberately hoisted to a sibling block, which keeps it
readable but loses its indentation and its ownership; a second paragraph of a list item loses the
item's hanging indent entirely. Real documents — changelogs, RFCs, this repository's own backlog —
are made of exactly these shapes. The outcome is a container-block tree (quote and list item own
child blocks, rendered with inherited indent and the quote border spanning its children) while
keeping the streamed, per-block visual pipeline as it is.

- Intent: quotes and list items own child blocks instead of flattening or hoisting them
- Complete when: a fixture with a list in a quote, a fence in a list item, a multi-paragraph item
  and a two-level quote lays out with correct indentation and borders, and the existing
  list-hoisting test is rewritten to the new stance

### B-518 — A code block has no syntax coloring

The fence's language is shown as an uppercase label but never used: no syntax coloring, while the
repository already colors Swag both in `DocMarkdown` and through the RichEdit lexer interface
(`controls/richedit/lexerswag.swg`). Long lines also soft-wrap with nothing marking the wrap.
Coloring is the visible half of parity with every competitor.

- Intent: fenced code colors through the shared lexer interface
- Complete when: a `swag` fence colors, an unknown language stays plain, and wrapped lines are
  visually distinguishable from new lines

## Tier B — The text and the links must be right

### B-519 — Reference and footnote definitions do not cross a streaming boundary

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

### B-520 — The document cannot navigate itself

`[TOC]` renders an inert text block: no entry is a link. Heading anchors do not exist, so a
`#fragment` link leaves through `sigLinkActivated` and dies in `Env.openUrl`. A footnote
reference paints as a superscript but does not jump to its footnote. A reader of a long streamed
document has keyboard paging and nothing else. Anchored navigation needs the parser to keep each
heading's byte offset, which is the same currency `revealFileOffset` already trades in.

- Intent: TOC entries, `#fragment` links and footnote references scroll to their target
- Complete when: clicking a TOC entry or an in-document anchor reaches its heading in both
  `createText` and a streamed file

## Tier C — Conformance and finish

### B-521 — Inline HTML has no documented stance

The implementation now does more than this roadmap used to record. Inline phrasing elements are
parsed through `HtmlParser` and translated into Markdown rich text, while layout-bearing elements
become embedded `HtmlView` blocks; local and `data:` images in those blocks paint under the HTML
engine's offline policy. What remains implicit is the public contract: which elements are
preserved semantically, which merely contribute their children, how unsupported markup falls
back, and where inline HTML ends and an HTML block begins. Markdown image syntax in B-516 is a
separate path and must not be presented as a prerequisite for HTML images.

- Intent: the implemented inline/block HTML split is a deliberate, documented contract
- Complete when: public module documentation records the supported semantics, fallback and
  offline-resource policy, with fixtures for representative phrasing, block and image elements

### B-522 — No measured conformance stance

Nobody can say which part of CommonMark the parser speaks. Run the CommonMark and GFM example
corpora through `parseBlocks`/`renderInline`, record each case as passing or deviating by choice,
and fix the cheap, high-frequency failures the sweep will surface — known already: indented code
blocks do not exist, and the emphasis flanking rules are approximate. The recorded stance is the
durable artifact; the fixes are the first harvest.

- Intent: conformance is a measured number with a recorded stance, not a guess
- Complete when: the corpus runs as a test and a stance file lists every deviation as deliberate

### B-523 — Find cannot walk its matches

`findText` clears the current highlight and advances to the next block, selecting occurrence zero
there. It therefore cannot reach a second match in the same block, move backwards, or report a
match count. The renderer already has private occurrence-counting and exact-occurrence selection
for streamed `revealFileOffset`; the remaining work is to expose that machinery as document-wide
search state and connect it to the host. Swag Scope's search panel deserves the same behavior over
Markdown as over code.

- Intent: find walks matches one by one and says how many there are
- Complete when: repeated find advances match-by-match across and within blocks, and the match
  count is exposed to the host

### B-524 — A rendered document ignores a live language switch

The engine's strings live in `Gui.Strings` with French translations, but an alert title is baked
into its block's text at parse time, so a document already on screen keeps the previous language
until it is reloaded — the same class of failure the menu bar once had, one widget over.

- Intent: a language switch restyles a rendered document's alert titles
- Complete when: switching the language re-renders parsed alert blocks in place, in `createText`
  and streamed documents alike

### B-525 — No typographic finish

Straight quotes stay straight, `--` never becomes an en dash, `...` never becomes an ellipsis,
and `:smile:` renders as its source. Typora treats smart punctuation as an opt-in and readers
expect emoji shortcodes anywhere GitHub-flavored text appears. Both are inline-renderer
transforms behind a `Style` flag, default off.

- Intent: opt-in smart punctuation and emoji shortcodes
- Complete when: the flag converts quotes, dashes and ellipses without touching code spans or
  math, and known shortcodes render their emoji
