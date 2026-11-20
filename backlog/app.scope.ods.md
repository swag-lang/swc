# Swag Scope ODS Viewer Backlog

Reading and inspecting OpenDocument spreadsheets.

### app.scope.ods.001 — ODS reading lacks complete number styles and sheet fidelity

- Evidence: ODS now reconstructs common currency, percentage, date, time, negative and zero
  number formats when a generated Calc workbook omits cached display strings; the reader marks
  formats it cannot safely render. Charts, annotations, advanced geometry and exact font metrics
  are simplified. [File Viewer Plus 7](https://fileviewerplus.com/support/supported_file_formats)
  lists ODS, FODS and OTS as readable and convertible formats.
- Next: use a Calc workbook with charts and drawings to establish what the viewer can reproduce
  and which worksheet components need an explicit omission.
- Done when: representative LibreOffice Calc sheets preserve common number formats,
  layout and components, unsupported charts or annotations are named, and navigation,
  cancellation and package budgets hold for large and damaged workbooks.
- Related: app.scope.viewers.009
