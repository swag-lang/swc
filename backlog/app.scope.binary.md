# Swag Scope Binary Viewer Backlog

This backlog covers the structured, read-only report under
`bin/apps/modules/swagscope/src/viewers/binary`. Format decoders turn bounded file bytes into a
hierarchical Field / Value / Offset / Meaning report with previews; the entries below turn that
report into a professional inspection workflow.

### app.scope.binary.001 — Structured reports cannot be filtered by field semantics

- Evidence: shared search indexes Field, Value, Offset and Meaning, and the host filter mode
  already retains matching report rows with their ancestors. `applyFilter` supports text and
  regular expressions; clearing it restores saved expansion and selection, with focused tests and
  a filter-bar golden. Explicit column scope, numeric/offset-range predicates, warning/row-kind
  predicates and an independent result list remain absent.
- Next: extend the existing hierarchical filter with typed column, numeric, offset-range,
  warning and row-kind predicates, retaining its bounded report representation.
- Done when: filters preserve the ancestor path, result counts and scopes are explicit,
  previous/next works independently from host document search, and clearing restores expansion and
  selection.

### app.scope.binary.005 — Two structured files cannot be compared semantically

- Evidence: the proposed hexadecimal comparison in app.scope.hexa.003 is byte-oriented. The binary viewer cannot align sections,
  headers, symbols, resources, chunks, or archive entries by identity and distinguish moved fields
  from changed values.
- Next: define normalized row keys and format-specific match policies, starting with PE/ELF/Mach-O
  headers and sections.
- Done when: paired trees show added/removed/changed/moved rows, irrelevant offsets can be
  ignored explicitly, raw-byte differences remain reachable, and comparison stays bounded.
- Related: app.scope.hexa.003, app.scope.001

### app.scope.binary.008 — Container previews have no shared provenance or resource budget

- Evidence: Archive extracts stored and Deflate ZIP members into temporary files and opens them
  through `EmbeddedViewer`. That host uses the complete registry, including Archive, so its model
  is not restricted to one container level. Each child shows a member title, but there is no
  composed container path, source byte-range/compression provenance, or shared extraction budget
  across descendants. RIFF, SCC, and Binary report assets do not use this child-file contract.
- Next: replace the temporary-path-only seam with a virtual child-file contract carrying parent
  identity, member path, source offset, compression, sizes, checksum, and a shared resource budget.
- Done when: nested supported content retains its complete container path and parent route,
  decompression work and resident bytes are bounded across levels, traversal names cannot choose
  output paths, and raw extraction remains an explicit action.
- Related: app.scope.binary.010

### app.scope.binary.010 — Archive browsing stops at ZIP

- Evidence: the dedicated Archive viewer lists a complete ZIP tree, verifies CRC-32, extracts
  stored and Deflate entries under a bounded preview size, and hands the selected entry to the
  normal viewer registry. `tar`, `gzip`, `xz`, `zstd`, `7z`, RAR, CAB, and MSI remain signature-only,
  and archive-wide integrity testing has no separate operation.
- Next: separate the tree/entry/integrity model from ZIP, add bounded `tar` plus single-stream
  `gzip` first, and expose Test Archive as a cancellable report that names each failed member.
- Done when: ZIP, TAR, and GZIP share one browsing surface and provenance contract, nested
  compression is bounded, integrity results distinguish header, data, checksum, encryption, and
  unsupported-method failures, and adding another archive family does not fork the viewer UI.
- Related: app.scope.binary.008

### app.scope.binary.014 — A program database is only identified

- Evidence: `.pdb` matches only the MSF 7.00 signature. The PE report already shows the CodeView
  GUID and age a PDB must match, and this repository writes PDBs (`src/Backend/Linker/PdbWriter.cpp`).
- Next: add an MSF reader that reports the superblock and stream directory, then decode the PDB
  info stream for its GUID and age.
- Done when: the MSF superblock, the stream directory, the named streams and the GUID/age that
  must match the image's CodeView record are reported by the `Binary` viewer.

### app.scope.binary.002 — Report navigation has no address spaces or landmarks

- Evidence: the compact report menu jumps to a file offset through the shared
  `parseFileOffset` grammar and walks visited rows backward or forward. It cannot name an RVA or
  virtual address, enumerate archive members, sections, or symbols as landmarks, resolve
  ambiguous mappings, or restore a separate expansion and scroll snapshot for each history entry.
- Next: define format-provided address spaces and named landmarks, then extend the file-offset jump
  and row history with those mappings and view-state snapshots.
- Done when: address parsing names its space, ambiguous mappings list choices, standard groups
  are jump targets, and history restores row, expansion, and scroll state.
- Related: app.scope.hexa.002

### app.scope.binary.003 — One report row cannot expose its exact raw bytes and decoded alternatives

- Evidence: a row has offset and length but selection only highlights text. There is no inline byte
  sample, endian/scalar reinterpretation, string decode, bit-field expansion, or safe handoff to a
  focused hexadecimal range.
- Next: add a row inspector backed by the same bounded file reader and shared byte-range contract.
- Done when: exact bytes, length, endian-aware scalar forms, text candidates, flags/bits, and
  parent/child coverage are inspectable and copyable; large payloads stay lazy; and Open in Hex
  selects the same range.
- Related: app.scope.hexa.001, app.scope.hexa.002

### app.scope.binary.004 — Structured reports have no professional export formats

- Evidence: commands copy one line or the whole indented report as presentation text. There is no
  JSON/CSV tree export, selected-subtree export, schema/version marker, raw offset/length fields, or
  warning inventory suitable for automation.
- Next: define a stable report interchange schema separate from localized labels and stream it for
  the selected subtree or whole report.
- Done when: JSON preserves hierarchy and typed fields, CSV/TSV preserves one row per record,
  text remains localized, exports include format/version/source identity and warnings, and huge
  reports do not require a second in-memory copy.

### app.scope.binary.006 — Parser damage and suspicious structures are not summarized as findings

- Evidence: readers can emit local meanings and truncated states, but there is no severity model,
  consolidated warning list, overlapping-range check, impossible-count/budget report, checksum
  status, or link from a finding to its row and bytes.
- Next: introduce format-neutral Info/Warning/Error findings and common range/integrity validators,
  then let each format contribute checks.
- Done when: malformed but readable files keep their partial report, every recovery is listed,
  findings link to rows and byte ranges, resource limits are distinguished from corruption, and
  clean files state which checks ran.

### app.scope.binary.007 — Executable reports stop before dependency and symbol analysis

- Evidence: PE, ELF, Mach-O, COFF, and archives expose many imports, exports, sections, libraries,
  and symbols, but cannot demangle names, group dependencies, resolve forwarded/re-exported symbols,
  identify hardening posture, or map symbol to containing code/data.
- Next: add a shared symbol/dependency model with demangling and format-specific security-property
  findings, reusing exact report byte ranges.
- Done when: imports/exports can be filtered and grouped, common C++/Rust/Swift names demangle
  without losing originals, dependencies and forwarding are navigable, and security properties
  cite the fields from which they were derived.

### app.scope.binary.009 — Previews cannot be selected, enlarged, copied, or traced to their source

- Evidence: decoded ICO/SCC previews appear in a band, but they have no selection model, full-size
  view, metadata, source-range link, copy/save command, or indication that a preview was transformed.
- Next: make each preview a named report asset with source rows/ranges and a route into Image or the
  most appropriate viewer.
- Done when: all previews can be focused and compared, Open as Viewer preserves provenance,
  copy/save distinguishes raw from decoded output, dimensions/format are visible, and malformed
  previews cannot fail the parent report.

### app.scope.binary.011 — MP4 and Matroska containers are only identified

- Evidence: the `Binary` viewer matches only the Matroska and `ftyp` signatures
  (`viewers/binary/document.swg`), while `std/video` already parses ISO-BMFF boxes and EBML
  elements for playback.
- Next: add bounded ISO-BMFF box and EBML element walkers as `Binary` format readers, reusing
  the `std/video` mp4 and matroska parsing where it exposes structure, then derive track summaries.
- Done when: the ISO-BMFF box tree, the Matroska EBML tree, and the track, codec, duration and
  resolution summaries are reported like any other structure.

### app.scope.binary.012 — SQLite databases are only identified

- Evidence: `.db` and `.sqlite` match only the `SQLite format 3` signature; the schema and table
  pages are not read, although the file format is documented and stable.
- Next: report the database header, then walk the page-1 `sqlite_schema` b-tree under page and
  cell budgets to list tables and indexes.
- Done when: the schema, the tables and their row counts are listed, and a table is browsable
  through a bounded window over its pages.

### app.scope.binary.013 — Certificates and keys are not decoded

- Evidence: `.pem`, `.der`, `.crt`, `.cer` and `.p12` show base64 or bytes; the `Binary`
  viewer has no ASN.1 reader.
- Next: add a bounded DER TLV walker (unwrapping PEM base64 first) that produces the report
  tree, then an X.509 summary over it.
- Done when: an ASN.1 tree and a decoded X.509 summary — subject, issuer, validity, key, and
  extensions — are shown, with no validation claim of any kind.
