# Swag Scope Markdown Viewer Backlog

Application integration for rendered and source Markdown. Engine work lives in
[std.gui.markdown.md](std.gui.markdown.md).

### app.scope.markdown.001 — The full Markdown outline reads the whole source and has no breadcrumb

- Evidence: `DocumentOutline` lists Markdown headings with depth and source offsets, marks the
  heading being read from the reader's first move on while it is open, and keeps the mark through
  its filter. Choosing a heading records the place left in `Viewer.History`; Alt+arrows and the
  lens return through `Markdown.View.revealBlock`. The headings are read only when the outline
  first opens, but that worker still reads the complete source, a rendered link is not a recorded
  jump, and no breadcrumb names the enclosing sections.
- Next: build a bounded heading index instead of reading the whole file, then show the path of
  enclosing headings for the marked one.
- Done when: the outline of a very large document appears without retaining its whole source,
  and the visible section's enclosing headings are readable beside it.
- Related: std.gui.markdown.005, app.scope.viewers.003

### app.scope.markdown.003 — Markdown links and resources have no trust or diagnostics surface

- Evidence: links activate and Markdown renders local raster and SVG images and embedded raster
  images, but the viewer does not list local and remote targets, broken anchors, missing images,
  blocked schemes, or resources outside the document directory. Embedded HTML shares the offline
  resource policy; the viewer does not expose each resource's resolution or the reason it was blocked.
- Next: inventory every parsed target and classify resolution, availability, scheme, and trust
  without fetching remote content implicitly.
- Done when: a resource panel links each target to source and rendered content, broken local
  references are explained, remote access requires explicit policy, and blocked content remains
  visible as a diagnostic.

### app.scope.markdown.002 — Markdown has no synchronized source and rendered split view

- Evidence: `.md` and `.markdown` now offer Markdown, Basic text, Binary, and Hexadecimal, so the
  source is reachable as its own view. There is still no synchronized split view and no mapping
  from a rendered block to its source range.
- Next: retain parser source ranges in the adapter and host rendered/source panes with a shared
  logical position.
- Done when: Rendered, Source, and Split modes preserve the nearest block, scroll can
  synchronize in either direction, search results map across modes, and large files stay streamed.
- Related: std.gui.markdown.005

### app.scope.markdown.004 — Markdown reading position and presentation cannot be shared or exported

- Evidence: a reader cannot copy a stable link to a heading, export the rendered document, or save
  the active theme/measure as a self-contained reading artifact. Reopening also loses position.
- Next: define stable heading/block locators and a read-only export contract for HTML and paginated
  output after the shared print path exists.
- Done when: a logical reading position restores through app.scope.viewers.003, heading links can be copied,
  self-contained HTML preserves safe local assets, and paginated output uses app.scope.viewers.002.
- Related: app.scope.viewers.003, app.scope.viewers.002
