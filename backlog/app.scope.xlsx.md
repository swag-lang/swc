# Swag Scope XLSX Viewer Backlog

Reading and inspecting Excel workbooks in XLSX format.

### app.scope.xlsx.001 — XLSX lacks a true workbook reading surface

- Evidence: the XLSX reader orders sheets and shows values or uncached formula expressions in a
  512-column grid. One sheet is shown at a time, starting with the saved active sheet; the
  filterable outline, arrows and Ctrl+Page Up/Down switch sheets. Hidden and very-hidden sheets
  stay hidden until explicitly revealed. The native grid preserves declared column widths, row
  heights, sparse addresses, disjoint merged cells and hidden rows/columns; a separate command
  reveals hidden ranges. Cell selection, keyboard moves, copy and a theme-aware text view support
  reading, and `:` with a cell address in the lens selects that cell. Only visible rows are
  painted, including million-row address spans. Direct and base
  XFs now retain font size/emphasis, colors, solid fills, common borders, alignment, wrapping and
  Normal-font indents. Spreadsheet theme/indexed colors and luminance tints are resolved; numeric
  overflow stays explicit. Common built-in and custom currency, grouped decimal, percentage,
  date and elapsed-time formats retain both Excel date systems and the fictitious 1900 leap day.
  Unsupported formats keep the stored value and a notice; unsupported visual effects are labelled
  simplified. Saved cells now inherit custom row XFs and then column XFs when their own style
  is absent; explicit cell XF zero remains an override. Producer output and a LibreOffice re-save
  confirm this precedence. Unsaved blank regions still have no inherited paint. Exact named
  font matching, frozen panes, filters, comments
  and charts remain absent. [Excel's frozen panes](https://support.microsoft.com/en-gb/excel/get-started/freeze-panes-to-lock-rows-and-columns)
  illustrate why authored grid navigation matters to reading.
- Next: paint inherited styles in unsaved blank regions and resolve named font families, then preserve frozen panes and add
  rectangular selection, sheet-qualified cell addresses and sheet-wide search before read-only chart
  previews. Extend numeric formatting to conditions, fractions, scientific notation and localized
  date profiles with producer fixtures; keep unsupported codes explicit.
- Done when: real workbooks show their authored grid and formatted values, frozen and hidden regions
  behave as declared, formulas never execute, large sheets stay bounded, and every omitted construct
  is explicitly reported.
- Related: app.scope.table.001, app.scope.table.003
