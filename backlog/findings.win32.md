# Findings — Win32

The Windows native modules and their checked API boundary under `bin/std/modules`.

Conventions, the identifier counter, and the rest of the backlog are in [README.md](README.md).
Entries are sorted by identifier, ascending; position carries no priority.

### F-074 — A Windows call that fails without setting a last error is reported as success

- Area: std/win32
- Found while: asking GDI for the `ttcf` table of a font that is not part of a collection
- Observation: every checked wrapper in `win32`, `gdi32`, `kernel32` and their siblings ends the
  same way — test the documented failure value, then `failWinError(GetLastError())`. But
  [win32.swg:6](../bin/std/modules/win32/src/win32.swg#L6) opens with
  `if errorMessageID == 0 do return`. When Windows answers a failure value without setting a last
  error, the wrapper raises nothing and hands the failure value back as a result. There are 126
  call sites, in `core`, `gui`, `ogl` and `pixel` as well as in the bindings themselves.
- Evidence: measured with `GetFontData(hdc, 'ttcf', 0, null, 0)` on Segoe UI and on Arial — neither is
  in a collection — returns `GDI_ERROR`, sets no last error, and the wrapper reports no failure. The
  caller receives `4294967295` as a byte count. `Array.resize` on it then failed four gigabytes
  down, and the failure surfaced as an access violation in an unrelated destructor rather than as
  the refusal it was. `TypeFace.readHfontData` now tests `GDI_ERROR` itself, which is correct at
  that call site in any case, but the other 125 sites carry the same hole untested.
- Why it is not simply a missing `else`: a zero last error after a failure value is normal on
  Windows, not exceptional. `GetFontData`, `GetGlyphOutline` and the `Get*` family document a
  sentinel and say nothing about `SetLastError`.
- Next step: make `failWinError` raise for a zero code instead of returning — a generic
  `Swag.SystemError` carrying zero still fails, which is what every one of its call sites already
  means. Then sweep for the wrappers that call it *without* first testing a failure value, because
  those depend on the current early return and would start failing on success. Validate with the
  whole Windows-facing set: `core`, `gui`, `ogl`, `pixel` and the applications.
