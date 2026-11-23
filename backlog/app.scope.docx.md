# Swag Scope DOCX Viewer Backlog

Reading and inspecting Word documents in DOCX format.

Feature completion means closing the four DOCX outcomes below and meeting DOCX-specific corpus and
resource checks in `app.scope.viewers.009`. Whole-file search, streamed selection and per-file state
remain in the shared viewer entries `app.scope.viewers.016`, `.001` and `.003`.

### app.scope.docx.001 — DOCX section layout is flattened into one flow

- Evidence: the reader uses the last section's page box, turns page breaks into separators, and
  shows related default header/footer text once. It detects page and continuous section boundaries
  but does not repeat first/even headers or preserve each section's geometry.
- Next: add a Word-authored fixture with changing page sizes and margins, all four section-break
  kinds, and default/first/even header/footer variants. Use it to build section-aware page layout.
- Done when: next-page, continuous, even-page and odd-page breaks and each supported page box affect
  the rendered surface; the right header/footer variant appears on the corresponding page; and
  unsupported section properties are disclosed at the affected section.
- Related: app.scope.viewers.009

### app.scope.docx.002 — DOCX footnotes lose their authored placement

- Evidence: referenced footnotes are read from a bounded optional part, retain basic run emphasis,
  and appear in first-reference order in an appendix. Every marker, including repeated references,
  opens the note and the note links back to each marker. Authored page/section placement is flattened;
  endnotes are not read.
- Next: add Word-authored footnote/endnote fixtures with different page/section placements and a
  missing ID; implement endnotes and place supported notes in the document flow.
- Done when: supported footnotes and endnotes appear at their authored page or section location,
  each marker opens its note and each note returns to the selected marker, and unsupported or
  unresolved notes have a visible marker.
- Related: app.scope.viewers.009

### app.scope.docx.003 — DOCX comments are detached from their text ranges

- Evidence: classic comment authors and escaped text appear once in first-reference order. Inline
  references open their comment, and a return link targets the start of a comment range. Range
  spans, overlapping/cross-paragraph ranges and threaded replies are not fully represented.
- Next: add fixtures for overlapping and cross-paragraph ranges, comments in table cells, and
  threaded replies; preserve each supported range and explicitly disclose unsupported reply forms.
- Done when: each supported classic comment is anchored to its authored text range, its marker opens
  the comment and the comment returns to that range; missing references and unsupported ranges or
  replies have focused tests and visible notices.
- Related: app.scope.viewers.018, app.scope.viewers.009

### app.scope.docx.004 — Complex DOCX tables and drawings lose structure

- Evidence: simple tables, bounded inline raster images, horizontal spans, authored widths and
  vertical cell alignment are supported. Nested tables, vertical merges, borders, floating objects,
  and drawing anchors are not faithfully represented.
- Next: add Word-authored cases for nested tables, vertical merges, borders and anchored drawings;
  implement the common structures and identify unsupported features at their location.
- Done when: supported tables retain row/cell order, spans, widths and alignment, anchored drawings
  remain at their authored text location, and unsupported structures have a visible local notice.
- Related: app.scope.viewers.009
