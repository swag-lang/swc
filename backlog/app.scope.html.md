# Swag Scope HTML Viewer Backlog

Application integration for rendered and source HTML. Parser, layout, and renderer work
lives in [std.gui.html.md](std.gui.html.md).

### app.scope.html.006 — HTML has no reader-mode or page-level diagnostics

- Evidence: a professional local-page viewer needs both faithful layout and a way to understand an
  unreadable page. The information sheet gives the title, language and description the head of
  the page writes (`HtmlView.documentFacts`), refreshed when a streamed head changes them. There is
  no extracted reading view, standards quirks indicator, or list of layout/parser warnings. A heading outline already ships
  through `DocumentOutline.bindHtml`; it does not expose those document facts or warnings. An
  unstyled HTML page opened during the outline test starts at the left edge, where an optional
  reading layout could supply a comfortable measure without changing faithful rendering.
- Next: surface document metadata and engine diagnostics first, then derive a clearly labelled
  reader view from semantic blocks without replacing faithful mode.
- Done when: title, language, metadata, headings, landmarks, and warnings are inspectable;
  reader mode preserves links and text order; and switching modes retains the logical location.
- Related: std.gui.html.017

### app.scope.html.001 — HTML encoding decisions have no override or conflict warnings

- Evidence: the information sheet names the encoding in force and what decided it (byte-order
  mark, declared label, or the bytes) from `HtmlView.encoding` and `encodingSource`. There is no
  manual override, no warning for a late or conflicting declaration, and no byte mapping for
  decoding failures.
- Next: add an override using the text viewer's supported encoding choices with explicit restart
  behavior, then report a declaration that arrives after the probe or contradicts a mark.
- Done when: late or conflicting declarations warn, invalid bytes remain traceable, and an
  override re-renders safely.
- Related: app.scope.text.004

### app.scope.html.003 — HTML source and rendered views have no shared position or split layout

- Evidence: choosing Code or Basic text discards the rendered position, active link, search match,
  and DOM node. There is no formatted source, line address, or live element mapping.
  [File Viewer Plus 7](https://fileviewerplus.com/open/html) documents page and source views,
  with a syntax tree and folding in the source view.
- Next: preserve the selected element and nearest source line across view changes using
  app.scope.html.002, then use the same mapping for a synchronized split.
- Done when: the selected element and scroll position map both ways, source retains exact bytes
  or declares normalization, search can target source or visible text, and scripts never execute.
- Related: app.scope.html.002

### app.scope.html.005 — HTML navigation has no history, address model, or fragment overview

- Evidence: `HtmlView` already follows same-document fragments and supported relative local HTML
  links, including a fragment in the destination. Other targets reach `sigLinkActivated`, which
  Swag Scope forwards to `Env.openUrl`. The application has no document address model,
  back/forward stack, visited state or broken-target overview around those engine operations.
- Next: expose local navigation transitions to the host and retain document, fragment, selection
  and scroll state in a navigation stack; distinguish external and blocked targets in its UI.
- Done when: back/forward restores scroll and selection, fragments and relative links resolve
  against the correct base, broken targets explain themselves, and external activation requires a
  deliberate command.

### app.scope.html.002 — HTML has no DOM outline or element-to-page inspection

- Evidence: `HtmlView` is hosted as one rendered surface. A reader cannot browse element hierarchy,
  inspect tag/id/class/attributes, or select an element and see its box and source range.
- Next: expose a read-only DOM adapter with stable node identity and bidirectional selection between
  a virtual tree, source, and rendered box.
- Done when: nodes can be filtered, collapsed, copied, and revealed; generated boxes identify
  their source node; malformed recovery is explicit; and huge repetitive DOMs remain virtualized.

### app.scope.html.004 — HTML resource loading and blocking are invisible

- Evidence: local pages may reference stylesheets, images, fonts, frames, media, data URLs, and
  remote URLs, but the viewer has no resource list, status, size, origin, cache, or reason a resource
  was not rendered.
- Next: route all resource resolution through an observable offline-first request ledger with
  explicit budgets and policy decisions.
- Done when: every requested resource shows resolved path/origin, type, bytes, result, and
  blocker; remote fetch is opt-in; traversal outside allowed roots is prevented; and entries link
  to the requesting node.
- Related: std.gui.html.019
