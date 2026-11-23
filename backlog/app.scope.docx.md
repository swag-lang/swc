# Swag Scope DOCX Viewer Backlog

Reading and inspecting Word documents in DOCX format.

### app.scope.docx.001 — DOCX lacks faithful page reading

- Evidence: the DOCX reader retains ordered paragraphs, simple tables, bounded raster images,
  page-break separators, numbered and bulleted list levels, and common inherited
  paragraph/character styles. Document defaults,
  parent styles, basic theme fonts/colors, sizes, emphasis, spacing and indents are resolved;
  styled headings populate the filterable outline. Broken optional styles retain readable prose
  and a visible simplification notice. Related default header/footer text is read with a bounded
  parser and shown once around the continuous body; page repetition and first/even variants are
  disclosed as simplified. Referenced footnotes are read from a bounded optional part and shown
  in first-reference order; separator records are skipped and missing or malformed notes get an
  inline omission marker. The final section’s authored page width, height and margins shape the
  reading body. Page and continuous section boundaries are detected, but this single-flow reader
  discloses that earlier section geometry is simplified; page-repeated headers/footers, footnote
  placement and styling, comments, floating objects and complex table geometry remain absent.
  [Word Read Mode](https://support.microsoft.com/en-gb/word/read-documents-in-word)
  preserves navigable pages and adapts them to the reading surface.
  [File Viewer Plus 7](https://fileviewerplus.com/support/text_documents) offers page formatting,
  tables and pictures in its document editor and also reads DOC, DOCM and Word templates.
  A generated 812-paragraph DOCX conversion of the public-domain Christmas Carol now exercises
  long-form reading, its opening and ending, and Unicode punctuation.
- Next: compare the same Word-authored DOCX fixtures against their authored layout and File Viewer
  Plus. Implement per-section geometry, then page-repeated headers/footers and authored footnote
  placement. Use those files for complex tables, numbering overrides, tabs and
  typography, and add document-wide search, selection and position restore without materializing
  every page at open.
- Done when: authored pages, text flow, images and table structure remain recognizable across a
  freely licensed DOCX corpus, unsupported constructs are named at their location, and the first
  page appears without decoding the full package.
- Related: app.scope.archive.001, app.scope.viewers.009
