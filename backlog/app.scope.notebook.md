# Swag Scope Notebook Viewer Backlog

The read-only reader for Jupyter notebooks and their stored outputs.

### app.scope.notebook.001 — Jupyter notebook reading is an initial inert subset

- Evidence: `.ipynb` opens in a dedicated reader that preserves cell order and displays Markdown,
  code source, plain text/stream output, `display_data`/`execute_result` `text/plain` MIME values,
  and traceback text. Scalar and line-array forms of plain MIME data are supported; active sibling
  MIME payloads are omitted from rendering. A document outline lists Markdown headings from cells
  and synthetic cell headings; selecting one navigates within the rendered notebook. Markdown
  formatting is rendered with raw HTML, links, and images neutralized. HTML, SVG, images, widgets,
  and other rich MIME output are explicitly reported as omitted and never executed or fetched. JSON
  is strict UTF-8 and
  capped at 16 MiB. Cell source accepts scalar text and arrays of lines; only selected kernel and
  language metadata are shown. Attachments, tables, arbitrary cell metadata inspection, and scoped
  source/output search remain absent.
- Progress: heading navigation is implemented for authored Markdown headings and synthetic cell
  headings. The viewer preserves inert code, execution counts, kernel/language metadata, plain-text
  output, and error text. Attachments, selected cell metadata, scoped search, and safe table/image
  rendering remain open.
- Next: add bounded source/output search with occurrence reveal, then expose selected cell metadata
  and add safe table/image rendering behind a deny-by-default MIME policy.
- Done when: cell order, type, execution count, metadata, attachments, errors, and every stored
  output remain inspectable; outline and search address inputs and outputs separately; unsupported or
  suppressed rich output is named and available as source; large output is collapsed and bounded.
- Related: app.scope.markdown.003, app.scope.json.001, app.scope.viewers.011
