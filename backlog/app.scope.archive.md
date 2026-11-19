# Swag Scope Archive Viewer Backlog

This backlog covers read-only archive browsing, member previews, and archive integrity.
Shared provenance and resource budgets for nested previews live in
[app.scope.viewers.md](app.scope.viewers.md).

### app.scope.archive.001 — Archive browsing stops at ZIP

- Evidence: the dedicated Archive viewer lists a complete ZIP tree, verifies CRC-32, extracts
  stored and Deflate entries under a bounded preview size, and hands the selected entry to the
  normal viewer registry. `tar`, `gzip`, `xz`, `zstd`, `7z`, RAR, CAB, and MSI remain signature-only,
  and archive-wide integrity testing has no separate operation.
- Next: after the current ZIP quality gate in app.scope.archive.002, separate the tree and entry
  model from ZIP, then add bounded `tar` and single-stream `gzip` through that shared model.
- Done when: ZIP, TAR, and GZIP share one browsing surface and provenance contract, nested
  compression is bounded, and adding another archive family does not fork the viewer UI.
- Related: app.scope.viewers.020, app.scope.archive.002

### app.scope.archive.002 — ZIP reading lacks a complete variant and integrity contract

- Evidence: ZIP and ZIP64 expose a tree and verify CRC-32 while opening bounded stored/Deflate
  members. Encrypted entries, split archives, unsupported methods and oversized entries currently
  stop with an explanation; there is no archive-wide test report. [7-Zip](https://www.7-zip.org/)
  also handles encrypted ZIP and a broad archive family, but extending families before the ZIP
  reader is dependable would dilute the existing reading contract.
- Next: test ZIP32/ZIP64, data descriptors, Unicode paths, duplicate names, damaged directories,
  encryption and size limits with real licensed archives; add a cancellable Test Archive report,
  then decide which encrypted and compression variants can be decoded natively in Swag.
- Done when: every advertised ZIP variant opens and verifies correctly, unsupported variants are
  identified precisely, a full-archive check reports individual failures without unbounded
  extraction, and member previews retain their provenance.
- Related: app.scope.viewers.020, app.scope.viewers.009
