# Swag Scope RTF Viewer Backlog

Reading and inspecting Rich Text Format documents.

### app.scope.rtf.001 — RTF reading omits advanced layout and encoded text variants

- Evidence: the Swag RTF reader now displays paragraphs, common inline styles, alignment, simple
  tables, Unicode escapes and Windows-1252 text. Bounded embedded PNG and JPEG pictures retain
  their place in the prose; binary payloads and modern/compatibility picture pairs are handled
  without duplicate images. Bounded font/color tables now preserve character faces, half-point
  sizes, colors, highlights, paragraph spacing/indents and line spacing; group scopes and plain
  resets retain their meaning. Colored prose uses a paper background with reading margins.
  Unsupported style references, pictures and embedded objects remain explicit. Named RTF styles,
  page geometry, complex tables, fields and other code pages are still absent.
  [File Viewer Plus 7](https://fileviewerplus.com/support/text_documents) opens RTF in the same
  paginated editor it uses for Word documents. A generated 813-paragraph RTF conversion of
  the public-domain Christmas Carol now tests sustained reading and Unicode punctuation.
- Next: compare a non-Windows-1252 RTF and a paginated real-world RTF. Start with correctly
  decoded text, then extend named paragraph/character styles, page geometry and complex tables.
  Keep fields inert and retain the existing policy for linked resources.
- Done when: representative freely licensed RTF documents retain their reading order and common
  visual structure, unsupported content remains explicit, and all decoding remains native Swag.
