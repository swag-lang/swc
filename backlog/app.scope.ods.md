# Swag Scope ODS Viewer Backlog

Reading and inspecting OpenDocument spreadsheets.

### app.scope.ods.001 — ODS reading lacks complete number styles and sheet fidelity

- Evidence: ODS uses saved formatted strings. Raw typed values lack full ODF number-style
  reconstruction, and charts, annotations, advanced geometry and exact font metrics are
  simplified. [File Viewer Plus 7](https://fileviewerplus.com/support/supported_file_formats)
  lists ODS, FODS and OTS as readable and convertible formats.
- Next: reconstruct common ODF number styles with a Calc workbook that omits saved display
  strings, then use a workbook with charts and drawings to establish what the viewer can
  reproduce and which worksheet components need an explicit omission.
- Done when: representative LibreOffice Calc sheets preserve common number formats,
  layout and components, unsupported charts or annotations are named, and navigation,
  cancellation and package budgets hold for large and damaged workbooks.
- Related: app.scope.viewers.009
