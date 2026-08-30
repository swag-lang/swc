# Swag Scope Binary Viewer Backlog

This backlog covers the structured, read-only report under
`bin/apps/modules/swagscope/src/viewers/binary`. Format decoders turn bounded file bytes into a
hierarchical Field / Value / Offset / Meaning report with previews; the entries below turn that
report into a professional inspection workflow.

## Report exploration

### B-087 — Structured reports cannot be filtered by field semantics

- Evidence: shared search now indexes Field, Value, Offset, and Meaning cells, counts occurrences,
  highlights the exact cell, and opens its ancestor path. The viewer still has no persistent
  filter, explicit column scope, numeric predicate, warning/row-kind predicate, or result list.
- Next: index report columns and hierarchy into a bounded query model with text, exact, numeric,
  offset-range, warning, and row-kind predicates.
- Complete when: filters preserve the ancestor path, result counts and scopes are explicit,
  previous/next works independently from host document search, and clearing restores expansion and
  selection.

### B-088 — Report navigation has no address spaces or landmarks

- Evidence: the compact report menu now accepts absolute or selected-row-relative hexadecimal file
  offsets and walks visited rows backward or forward. It cannot name an RVA or virtual address,
  enumerate archive members, sections, or symbols as landmarks, resolve ambiguous mappings, or
  restore a separate expansion and scroll snapshot for each history entry.
- Next: define format-provided address spaces and named landmarks, then extend the file-offset jump
  and row history with those mappings and view-state snapshots.
- Complete when: address parsing names its space, ambiguous mappings list choices, standard groups
  are jump targets, and history restores row, expansion, and scroll state.
- Related: B-021

### B-089 — One report row cannot expose its exact raw bytes and decoded alternatives

- Evidence: a row has offset and length but selection only highlights text. There is no inline byte
  sample, endian/scalar reinterpretation, string decode, bit-field expansion, or safe handoff to a
  focused hexadecimal range.
- Next: add a row inspector backed by the same bounded file reader and shared byte-range contract.
- Complete when: exact bytes, length, endian-aware scalar forms, text candidates, flags/bits, and
  parent/child coverage are inspectable and copyable; large payloads stay lazy; and Open in Hex
  selects the same range.
- Related: B-020, B-021

### B-090 — Structured reports have no professional export formats

- Evidence: commands copy one line or the whole indented report as presentation text. There is no
  JSON/CSV tree export, selected-subtree export, schema/version marker, raw offset/length fields, or
  warning inventory suitable for automation.
- Next: define a stable report interchange schema separate from localized labels and stream it for
  the selected subtree or whole report.
- Complete when: JSON preserves hierarchy and typed fields, CSV/TSV preserves one row per record,
  text remains localized, exports include format/version/source identity and warnings, and huge
  reports do not require a second in-memory copy.

### B-091 — Two structured files cannot be compared semantically

- Evidence: hexadecimal comparison B-022 is byte-oriented. The binary viewer cannot align sections,
  headers, symbols, resources, chunks, or archive entries by identity and distinguish moved fields
  from changed values.
- Next: define normalized row keys and format-specific match policies, starting with PE/ELF/Mach-O
  headers and sections.
- Complete when: paired trees show added/removed/changed/moved rows, irrelevant offsets can be
  ignored explicitly, raw-byte differences remain reachable, and comparison stays bounded.
- Related: B-022, T-397

## Analysis depth

### B-092 — Parser damage and suspicious structures are not summarized as findings

- Evidence: readers can emit local meanings and truncated states, but there is no severity model,
  consolidated warning list, overlapping-range check, impossible-count/budget report, checksum
  status, or link from a finding to its row and bytes.
- Next: introduce format-neutral Info/Warning/Error findings and common range/integrity validators,
  then let each format contribute checks.
- Complete when: malformed but readable files keep their partial report, every recovery is listed,
  findings link to rows and byte ranges, resource limits are distinguished from corruption, and
  clean files state which checks ran.

### B-093 — Executable reports stop before dependency and symbol analysis

- Evidence: PE, ELF, Mach-O, COFF, and archives expose many imports, exports, sections, libraries,
  and symbols, but cannot demangle names, group dependencies, resolve forwarded/re-exported symbols,
  identify hardening posture, or map symbol to containing code/data.
- Next: add a shared symbol/dependency model with demangling and format-specific security-property
  findings, reusing exact report byte ranges.
- Complete when: imports/exports can be filtered and grouped, common C++/Rust/Swift names demangle
  without losing originals, dependencies and forwarding are navigable, and security properties
  cite the fields from which they were derived.

### B-094 — Container inspection is one level deep

- Evidence: ZIP, archive, RIFF, SCC, and other container reports list members or chunks, while T-403
  records that entries cannot be opened. Nested containers, compressed payload provenance, preview
  budgets, and a breadcrumb back to parents are absent.
- Next: define a virtual child-file contract carrying parent identity, offset, compression, sizes,
  and extraction budget before opening one supported ZIP or archive member recursively.
- Complete when: nested supported content opens in the appropriate viewer, breadcrumbs retain the
  complete container path, decompression bombs and traversal names are bounded, and raw extraction
  remains an explicit action.
- Related: T-403

### B-095 — Previews cannot be selected, enlarged, copied, or traced to their source

- Evidence: decoded ICO/SCC previews appear in a band, but they have no selection model, full-size
  view, metadata, source-range link, copy/save command, or indication that a preview was transformed.
- Next: make each preview a named report asset with source rows/ranges and a route into Image or the
  most appropriate viewer.
- Complete when: all previews can be focused and compared, Open as Viewer preserves provenance,
  copy/save distinguishes raw from decoded output, dimensions/format are visible, and malformed
  previews cannot fail the parent report.

This backlog covers the application-owned `Binary` viewer: structured reports, container browsing,
and new format readers that produce the common field/value/offset/meaning tree. Generic parsing,
compression, cryptography, or codec work stays with the standard module that implements it.

## Containers

### T-403 — An archive's entries cannot be opened

- Intent: a ZIP lists its central directory and stops; `tar`, `gzip`, `xz`, `zstd`, `7z`, `RAR`,
  `CAB` and `MSI` are only identified. Looking inside an archive is one of the two things a viewer
  is opened for.
- Complete when: a directory entry can be selected and its content handed to the matching viewer
  without extracting the whole archive, starting with the deflate and stored methods that
  `Core.Inflate` already covers, and with `tar`/`gzip` listing.

### T-412 — MP4 and Matroska containers are only identified

- Intent: playback and structural inspection answer different questions. The `Video` viewer reads
  the supported picture and sound tracks, while the `Binary` alternative should expose the
  container itself like it already does for RIFF and the other structured formats.
- Complete when: the ISO-BMFF box tree, the Matroska EBML tree, and the track, codec, duration and
  resolution summaries are reported like any other structure.

## Structured developer data

### T-410 — SQLite databases are only identified

- Intent: `.db` and `.sqlite` reach the entropy line. The schema and a bounded table read are what a
  reader wants, and the file format is documented and stable.
- Complete when: the schema, the tables and their row counts are listed, and a table is browsable
  through a bounded window over its pages.

### T-411 — Certificates and keys are not decoded

- Intent: `.pem`, `.der`, `.crt`, `.cer` and `.p12` show base64 or bytes. `Core.Crypto` and the
  binary viewer's structure model already give the two halves of what is needed.
- Complete when: an ASN.1 tree and a decoded X.509 summary — subject, issuer, validity, key, and
  extensions — are shown, with no validation claim of any kind.

### T-413 — A program database is only identified

- Intent: this repository writes PDBs. Reading one back with the same tool that inspects the image
  it belongs to is a capability the competition does not have, and it is a debugging asset here.
- Complete when: the MSF superblock, the stream directory, the named streams and the GUID/age that
  must match the image's CodeView record are reported by the `Binary` viewer.
