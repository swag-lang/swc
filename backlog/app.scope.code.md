# Swag Scope Code Viewer Backlog

This backlog covers the read-only source code viewer: language detection, highlighting,
source structure, and navigation to local references. Shared source text behavior lives in
[app.scope.text.md](app.scope.text.md).

### app.scope.code.004 — Syntax detection cannot explain itself or remember an override

- Evidence: `Viewers.Code.detectLanguage` chooses from file name, extension and supported shebangs, and
  `GenericLexer` applies fixed lexical rules. The details show `languageName`, and a language
  typed into the lens offers to color the source as that language, or as Swag, for the file in
  view. The detection decision is not explained, an override is forgotten with the file, and there
  is no Plain Text choice.
- Next: state the evidence of the detection (extension, name or interpreter line) beside the
  language, and remember an override per file identity.
- Done when: every supported language is selectable, detection evidence is visible, overrides
  re-highlight the resident window immediately, and opening an unsupported language stays readable.

### app.scope.code.006 — Source structure has no sticky scope, indentation guides, or delimiter matching

- Evidence: lexical color is the only structural cue inside the code surface. Ctrl+], or the lens
  while the caret stands by a bracket, moves the caret to the parenthesis, bracket or brace that
  pairs with it within the resident text, counting only delimiters drawn in the same style, so one
  in a string or a comment pairs with no code. Pairs are not highlighted, an unmatched delimiter
  is not marked, and there is no sticky scope or indentation guide.
- Next: derive indentation, delimiter pairs, and sticky headings from the same bounded lexical and
  outline ranges planned by app.scope.code.001 and app.scope.code.005.
- Done when: the current scope path remains visible and navigable, indentation guides survive
  tabs and mixed widths honestly, matching and unmatched delimiters are distinguishable, each cue
  can be disabled independently, and streamed seeks reconstruct enough preceding state without
  rescanning the whole file synchronously.
- Related: app.scope.code.001, app.scope.code.002, app.scope.code.005

### app.scope.code.007 — Paths, URLs, includes, and source references are inert text

- Evidence: the code viewer cannot identify a local include/import, file-and-line diagnostic,
  relative path, URL, issue number, or symbol reference as an inspectable target. Copying and
  manually reopening a target loses provenance, while activating arbitrary text without a policy
  would weaken Swag Scope's offline and untrusted-input guarantees.
- Next: define non-executing link providers that first expose target spelling, resolution, source
  range, and trust state, then allow explicit navigation only through host-owned file opening.
- Done when: supported references are underlined only when resolution is known, hover or a
  panel shows the exact target before activation, relative paths cannot escape the approved local
  context silently, remote URLs are never fetched, missing and ambiguous targets are explained,
  and back navigation returns to the originating byte range.
- Related: app.scope.markdown.003, app.scope.viewers.011

### app.scope.code.001 — Source files have no outline or symbol navigation

- Evidence: `Viewers.Code.Panel` colors tokens but exposes no functions, types, headings, regions, or
  breadcrumbs. Professional code readers use an outline both to understand a file and to jump
  within it.
- Next: define a lightweight read-only symbol provider, starting with Swag and indentation/marker
  fallbacks, whose results retain whole-file byte ranges.
- Done when: symbols form a filterable hierarchy, track the visible scope, jump before the
  full file is resident, and malformed syntax yields partial symbols instead of losing the outline.

### app.scope.code.002 — Source code cannot fold regions

- Evidence: the streamed rich edit has no fold ranges, gutter affordance, or folded-height model;
  comments, regions, declarations, and indentation blocks always occupy their full height.
- Next: add fold ranges independent of styling, beginning with marker and indentation providers
  that can be reconciled as streamed content enters and leaves memory.
- Done when: fold/unfold current, recursive, all, and level commands preserve navigation and
  search reveal; hidden matches can be opened; and folds restore only against the same file version.

### app.scope.code.003 — Source code has no minimap, overview ruler, or durable location markers

- Evidence: search highlights exist only in the resident editor and the scrollbar carries no
  whole-file density, match, diagnostic, or symbol marks.
- Next: build a bounded whole-file overview index from line starts, styles, search batches, and
  symbols, then render it as an optional minimap or ruler.
- Done when: dragging navigates the whole file, markers remain proportional on huge inputs,
  visible-window position is clear, and disabling the overview removes its indexing cost.

### app.scope.code.005 — Highlighting has no conformance corpus or semantic limits

- Evidence: tests cover representative keywords and a few source fixtures, but nested comments,
  interpolation, raw strings, preprocessor branches, malformed tokens, and multi-chunk lexical
  state are not specified per language.
- Next: declare the lexer contract as lexical rather than semantic and add a compact adversarial
  corpus for each language family plus chunk-boundary variants.
- Done when: supported constructs and deliberate omissions are documented, state resumes
  correctly after a streamed seek, and each shipped language family has golden style spans.
