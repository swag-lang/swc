# Findings — HTML

`std/gui`'s HTML parser, cascade, layout, painter, and `HtmlView`. Intent for the same engine is
[todo.html.md](todo.html.md).

Conventions, the identifier counter, and the rest of the backlog are in [README.md](README.md).
Entries are sorted by identifier, ascending; position carries no priority.

### F-157 — A body-less fragment leaves every `body {}` author rule inert

- Area: std/gui (HTML)
- Found while: recording the `htmlview.floats` golden, whose page styling silently fell back to
  the theme's dark ground because the source was a fragment
- Observation: the parser never synthesizes the implied `<html>`, `<head>` and `<body>` elements,
  so a fragment fed to `HtmlView.createText` that opens directly with `<style>` or content has no
  body element at all. Every `body { ... }` author rule then matches nothing and is dropped
  whole — margins, background, color, font-size — while rules on classes and elements that do
  exist apply normally, which makes the failure look like a cascade defect rather than a missing
  element. Several existing inline-source tests carry a placebo `body { margin: 0 }` that has
  never applied; they pass because a missing body also has no default 8px margin to remove.
- Evidence: the `htmlview.floats` golden test in
  [htmlview.test.swg](../bin/std/modules/gui/src/tests/htmlview.test.swg) had to wrap its source
  in explicit `<html><body>` for its page background and text color to take; the same source
  without the wrapper renders on the theme ground with theme text.
- Next step: synthesize the implied elements the way browsers do — open `html` and `body` when
  content arrives outside them, route head content into a synthesized `head` — so a fragment and
  a full document build the same tree; the `closeImplied` `.Head -> .Body` case already expects
  those elements to exist.

### F-161 — The HTML box build allocates one heap String per word of the document

- Area: std/gui (HTML)
- Found while: the HTML engine performance pass (2026-08-18), profiling where a large page's
  load time goes after the measurement cache was made to survive streaming rebuilds.
- Observation: `HtmlLayout.appendText` routes every fragment through `HtmlLayout.transform`,
  which returns `String.from(text)` even for the `None` transform, so each word of the document
  costs one heap allocation and one copy at build time — and the streaming loader rebuilds the
  box tree at doubling intervals, repeating the allocations. `HtmlInlineItem.text` cannot be a
  borrowed slice today because `HtmlDocument.appendText` grows an existing text node's `String`
  when a chunk boundary splits a run, which can reallocate the buffer between two rebuilds.
- Evidence: code reading of `layout.swg` (`appendText`, `transform`) and `document.swg`
  (`appendText`); a 1 MB page holds on the order of 150k words, so a full load allocates
  roughly twice that many transient Strings.
- Next step: give the build a per-rebuild text arena (one growing buffer, items keep offsets),
  or intern untransformed fragments against the node's text with a copy taken only when the
  parser later extends that node; measure the load of `std.pixel.html` before and after.

### F-162 — A streaming rebuild re-parses every stylesheet from scratch

- Area: std/gui (HTML)
- Found while: the same HTML engine performance pass.
- Observation: `HtmlView.rebuild` calls `collectStyleSheets`, which clears the sheet and the
  value pool and re-walks the whole document re-parsing every `<style>` block and every linked
  stylesheet text. The streaming loader rebuilds at doubling intervals, so a document whose CSS
  arrives early still pays its full CSS parse about `log2(size / 192KB)` times, and a theme
  change pays it again although nothing in the source changed.
- Evidence: code reading of `view.swg` (`rebuild`, `collectStyleSheets`) and `stylesheet.swg`
  (`parse` clears nothing incrementally; rules, buckets and media are rebuilt whole).
- Next step: cache parsed sheets keyed by the style node's text identity (offset and length are
  stable once a `<style>` element closed), append only sheets not seen yet, and re-evaluate
  media queries instead of re-parsing on a theme change.
