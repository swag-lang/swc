# Swag Scope Notebook Viewer Backlog

The planned read-only reader for Jupyter notebooks and their stored outputs.

### app.scope.notebook.001 — Jupyter notebooks have no document reader

- Evidence: `.ipynb` has no notebook renderer. The content probe offers the Text viewer for its
  raw JSON, alongside Binary and Hexadecimal. Markdown cells, code cells, execution order,
  attachments, stored images, tables, errors, and metadata lose their document structure. The
  intended reader presents stored content with cell/output search and an outline; kernel
  execution remains outside its contract.
- Next: parse notebook cells and render Markdown, syntax-colored source, plain text, bounded images,
  tables, and JSON output through existing viewers while defining a deny-by-default MIME and trust
  policy for HTML, SVG, JavaScript, widgets, and external resources.
- Done when: cell order, type, execution count, metadata, attachments, errors, and every stored
  output remain inspectable; outline and search address inputs and outputs separately; unsupported or
  suppressed rich output is named and available as source; large output is collapsed and bounded;
  and opening a notebook never starts a kernel, executes code, or fetches a resource.
- Related: app.scope.markdown.003, app.scope.json.001, app.scope.viewers.011
