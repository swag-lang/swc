# Swag Scope Archive Viewer Backlog

This backlog covers read-only archive browsing, member previews, and archive integrity.
Shared provenance and resource budgets for nested previews live in
[app.scope.viewers.md](app.scope.viewers.md).

### app.scope.archive.001 — Archive browsing stops at ZIP

- Evidence: the dedicated Archive viewer lists ZIP, ustar and PAX TAR trees, verifies ZIP CRC-32,
  and extracts bounded ZIP or TAR entries through the normal viewer registry. It now opens one
  GZIP member or lists a TAR.GZ payload through the same archive model. Input and expanded GZIP
  data are each capped at 256 MiB; CRC-32 and ISIZE are checked before a member is offered.
  xz, zstd, 7z, RAR, CAB, and MSI remain unsupported,
  and archive-wide integrity testing has no separate operation.
  [File Viewer Plus 7](https://fileviewerplus.com/support/archives) documents member preview and
  extraction across more than 30 archive formats, including 7z and RAR.
- Next: add xz and zstd with bounded stream decoders, then reuse the same entry model for 7z and RAR.
- Done when: ZIP, TAR, GZIP, 7z and RAR share one browsing surface and provenance contract,
  and nested previews and extraction stay within a shared resource budget.
- Related: app.scope.viewers.020, app.scope.archive.002

### app.scope.archive.002 — ZIP reading lacks a complete variant and integrity contract

- Evidence: ZIP and ZIP64 expose a tree and verify CRC-32 while opening bounded stored/Deflate
  members. Generated functional fixtures now exercise a ZIP64 end record and saturated size/offset
  fields, a non-seekable writer's data descriptor, UTF-8 names and duplicate entries, a damaged
  central directory, an advertised entry size above the preview limit, and a generated ZipCrypto
  member that is classified as encrypted and rejected before output. Split archives, unsupported
  methods and oversized entries stop with an explanation. There is still no archive-wide test
  report. A safe cancellable report needs incremental decompression: current entry verification
  inflates each whole member into memory and cannot observe cancellation during the inflater call.
  [7-Zip](https://www.7-zip.org/) also handles encrypted ZIP and a broad archive family;
  [File Viewer Plus 7](https://fileviewerplus.com/support/archives) documents a password prompt
  for supported protected archives.
- Next: add an incremental, cancellable verification path with aggregate resource limits; then
  expose its per-entry results as a Test Archive report. Decide whether to implement ZipCrypto and
  AES encryption natively in Swag; the generated ZipCrypto comparison fixture currently verifies
  only that protected content is not mistakenly opened as plaintext.
- Done when: a full-archive check reports individual failures with cancellation and aggregate
  resource bounds, unsupported and encrypted variants are identified precisely, and member previews
  retain their provenance.
- Related: app.scope.viewers.020, app.scope.viewers.009
