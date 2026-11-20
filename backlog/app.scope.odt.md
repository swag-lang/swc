# Swag Scope ODT Viewer Backlog

Reading and inspecting OpenDocument text documents.

### app.scope.odt.001 — ODT reading omits authored pages, annotations, and drawings

- Evidence: the reader uses the first declared page width and margins for its centered reading
  surface, with bounded defaults for invalid geometry. It still flows all content as one continuous
  page, so page height, section changes, repeated headers and footers, notes, comments and complex
  drawings are not represented. [File Viewer Plus 7](https://fileviewerplus.com/support/text_documents)
  reads ODT and OTT and offers page formatting, print and export.
- Next: use Writer documents with multiple page styles to map master-page and section changes, then
  add repeated headers and footers to a paginated reading model. Keep notes visible in reading
  order and record drawings and annotations that still need an explicit omission.
- Done when: representative LibreOffice Writer documents retain common page layout,
  headers and footers, notes, comments and drawings or identify unsupported components,
  and navigation, cancellation and package budgets hold for large and damaged documents.
- Related: app.scope.viewers.009
