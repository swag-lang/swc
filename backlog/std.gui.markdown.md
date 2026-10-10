# Markdown Backlog

This backlog covers the Markdown engine in `bin/std/modules/gui/src/controls/markdown` —
the block parser, the inline renderer, and the `Markdown.View` widget on top of them. It is
measured against the readers it competes with — Typora, the VS Code preview, and GitHub's web
rendering — with CommonMark plus GFM as the reference for what a document means, while staying
what the whole document family is: an offline, script-free, network-free viewer.

The engine lives beside its widget inside `gui`; application-level zoom stays in
[app.scope.text.md](app.scope.text.md), shared printing in
[app.scope.viewers.md](app.scope.viewers.md), and shell thumbnail integration in
[platform.portability.md](platform.portability.md).
[README.md](README.md) has the whole layout.


## Entries

### std.gui.markdown.005 — Inline TOC, fragment and footnote links do not navigate the document

- Evidence: `Markdown.parseHeadings` returns headings with distinct source byte offsets, and
  `Markdown.View.revealHeading` navigates to one in a streamed document. Swag Scope uses these
  APIs for its outline; `documentoutline.test.swg` covers heading parsing and navigation beyond
  the initial resident window.
- Remaining: `[TOC]` is still emitted as unlinked text, a `#fragment` link leaves through
  `sigLinkActivated`, and a footnote reference has no local jump target. Programmatic heading
  navigation does not give these inline references an identity or resolution rule.
- Next: assign stable heading and footnote anchors, resolve inline targets against the document,
  and route TOC and local-link activation through the existing heading/reveal operations.
- Done when: TOC entries, in-document fragments and footnote references reach their targets
  in both `createText` and streamed files, with duplicate headings and unloaded targets covered.
- Related: app.scope.document.001

### std.gui.markdown.010 — No opt-in smart punctuation

- Evidence: the inline renderer preserves straight quotes, `--` and `...` as authored text.
- Next: add a default-off style option for contextual quotes, dashes and ellipses, with an
  explicit rule for existing punctuation and escaped input.
- Done when: enabling the option transforms prose while preserving code spans, math,
  escaped punctuation and source-offset mapping used by search and selection.
- Related: std.gui.markdown.011

### std.gui.markdown.011 — Emoji shortcodes remain source text

- Evidence: the inline renderer has no shortcode lookup; `:smile:` is rendered literally.
- Next: define a versioned shortcode table and a default-off style option, preserving unknown
  names and keeping code, math and escaped input outside the transform.
- Done when: known shortcodes render their emoji with correct search/selection offsets,
  unknown names remain readable, and disabled mode preserves the authored text.
- Related: std.gui.markdown.010

### std.gui.markdown.002 — Block structure is flat: containers do not nest


The parser recognizes every leaf block but no container can hold one. A list inside a quote, a
fence inside a quote, or a `> >` nested quote all degrade — the second `>` renders as literal
text. A fence inside a list item is deliberately hoisted to a sibling block, which keeps it
readable but loses its indentation and its ownership; a second paragraph of a list item loses the
item's hanging indent entirely. Real documents — changelogs, RFCs, this repository's own backlog —
are made of exactly these shapes. The outcome is a container-block tree (quote and list item own
child blocks, rendered with inherited indent and the quote border spanning its children) while
keeping the streamed, per-block visual pipeline as it is.

- Intent: quotes and list items own child blocks instead of flattening or hoisting them
- Done when: a fixture with a list in a quote, a fence in a list item, a multi-paragraph item
  and a two-level quote lays out with correct indentation and borders, and the existing
  list-hoisting test is rewritten to the new stance

### std.gui.markdown.003 — A code block has no syntax coloring


The fence's language is shown as an uppercase label but never used: no syntax coloring, while the
repository already colors Swag both in `DocMarkdown` and through the RichEdit lexer interface
(`controls/richedit/lexerswag.swg`). Long lines also soft-wrap with nothing marking the wrap.
Coloring is the visible half of parity with every competitor.

- Intent: fenced code colors through the shared lexer interface
- Done when: a `swag` fence colors, an unknown language stays plain, and wrapped lines are
  visually distinguishable from new lines

### std.gui.markdown.004 — Reference and footnote definitions do not cross a streaming boundary


`parseBlocks` collects definitions only from the chunk it is parsing, and the convention every
real document follows — all `[name]: target` lines gathered at the end of the file — is exactly
the layout streaming defeats: body reference links render as raw `[text][ref]` literals because
their definitions have not been read yet. Resolution has to become document-wide in streamed
mode: either a definition pre-scan when the file opens, or atoms that carry the reference name
and resolve when the definition arrives. `revealFileOffset` windows have the same hole in both
directions.

- Intent: a streamed document resolves references wherever their definitions sit
- Done when: a multi-chunk streamed fixture with end-of-file definitions renders every
  reference link and footnote live, including after a reveal

### std.gui.markdown.007 — No measured conformance stance


Nobody can say which part of CommonMark the parser speaks. Run the CommonMark and GFM example
corpora through `parseBlocks`/`renderInline`, record each case as passing or deviating by choice,
and fix the cheap, high-frequency failures the sweep will surface — known already: indented code
blocks do not exist, and the emphasis flanking rules are approximate. The recorded stance is the
durable artifact; the fixes are the first harvest.

- Intent: conformance is a measured number with a recorded stance, not a guess
- Done when: the corpus runs as a test and a stance file lists every deviation as deliberate

### std.gui.markdown.008 — Find cannot walk its matches


`findText` clears the current highlight and advances to the next block, selecting occurrence zero
there. It therefore cannot reach a second match in the same block, move backwards, or report a
match count. The renderer already has private occurrence-counting and exact-occurrence selection
for streamed `revealFileOffset`; the remaining work is to expose that machinery as document-wide
search state and connect it to the host. Swag Scope's search panel deserves the same behavior over
Markdown as over code.

- Intent: find walks matches one by one and says how many there are
- Done when: repeated find advances match-by-match across and within blocks, and the match
  count is exposed to the host
