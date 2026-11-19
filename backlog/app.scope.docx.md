# Swag Scope DOCX Viewer Backlog

Reading and inspecting Word documents in DOCX format.

### app.scope.docx.001 — DOCX lacks faithful page reading

- Evidence: the DOCX reader retains ordered paragraphs, simple tables, bounded raster images,
  page-break separators and common inherited paragraph/character styles. Document defaults,
  parent styles, basic theme fonts/colors, sizes, emphasis, spacing and indents are resolved;
  styled headings populate the filterable outline. Broken optional styles retain readable prose
  and a visible simplification notice. Authored page size/margins, section columns, headers,
  footers, footnotes, comments, floating objects and complex table geometry remain absent.
  [Word Read Mode](https://support.microsoft.com/en-gb/word/read-documents-in-word)
  preserves navigable pages and adapts them to the reading surface.
- Next: lay out page and section geometry, then headers, footers and footnotes; extend numbering,
  tabs, table styles and complex-script font/theme fidelity with real producer fixtures. Add
  document-wide search, selection and position restore without materializing every page at open.
- Done when: authored pages, text flow, images and table structure remain recognizable across a
  freely licensed DOCX corpus, unsupported constructs are named at their location, and the first
  page appears without decoding the full package.
- Related: app.scope.archive.001
