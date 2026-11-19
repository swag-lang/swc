# Swag Scope ODS Viewer Backlog

Reading and inspecting OpenDocument spreadsheets.

### app.scope.ods.001 — ODS reading lacks complete number styles and sheet fidelity

- Evidence: ODS uses saved formatted strings. Raw typed values lack full ODF number-style
  reconstruction, and charts, annotations, advanced geometry and exact font metrics are
  simplified.
- Next: reconstruct ODF number styles when saved display strings are absent and identify
  unsupported worksheet components.
- Done when: representative LibreOffice Calc sheets preserve common number formats,
  layout and components, unsupported charts or annotations are named, and navigation,
  cancellation and package budgets hold for large and damaged workbooks.
