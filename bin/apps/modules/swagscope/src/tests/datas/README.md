# Swag Scope viewer fixtures

`viewer.<extension>` is the canonical small file for a format or extension claimed by a
content reader. `viewer.<variant>.<extension>` changes one meaningful property, such as codec,
colour model, page encoding, package path, or damage. The extension is always the one the
application selects; a variant name is never a substitute for a real suffix. Tests outside this
directory may retain older names when those files serve a particular screenshot or journey.

The executable fixture matrix includes every `viewer.*` file in this directory and is
[`fixtures.swg`](../cases/functional/viewers/fixtures/fixtures.swg). It checks that every listed
file exists and selects the expected reader. The image cases also decode their payloads;
format-owned tests exercise EPUB, CBZ, PDF, DOCX, RTF and XLSX content and negative cases. The
registry smoke opens one file for each viewer. A selector check alone does not prove that every
legal variation of a format can be read.

`viewer.hex` is a readable-text payload opened directly by the Hex viewer's smoke; automatic
selection correctly offers Text first for those bytes.

| Family | Canonical fixtures | Variants exercised here |
| --- | --- | --- |
| Documents | `viewer.pdf`, `.epub`, `.docx`, `.rtf`, `.xlsx`, `.pptx`, `.cbz` | PDF object streams, rotation, JPEG and CCITT images; nested EPUB/CBZ paths; split and formatted DOCX runs; RTF Unicode, tables, ignorable destinations and damage; inline XLSX strings; relative and package-absolute slide/sheet relationships; slide order; damaged packages |
| Images | `viewer.svg`, `.bmp`, `.cur`, `.dds`, `.exr`, `.gif`, `.ico`, `.jpg`, `.jpeg`, `.ktx2`, `.png`, `.apng`, `.psd`, `.qoi`, `.tga`, `.tif`, `.tiff`, `.webp` | CMYK and progressive JPEG; GIF, APNG and WebP animation |
| Sound | `viewer.wav`, `.flac`, `.mp3`, `.aac`, `.ac3`, `.eac3`, `.ec3`, `.dts`, `.ogg`, `.oga`, `.opus` | Surround FLAC/E-AC-3 and hybrid Opus |
| Video | `viewer.mp4`, `.m4v`, `.mov`, `.mkv`, `.avi`, `.y4m` | H.264 and HEVC in MP4, raw AVI and RV40 MKV |
| Structured text | `viewer.csv`, `.tsv`, `.tab`, `.srt`, `.vtt`, `.ass`, `.ssa`, `.lrc`, `.sub`, `.html`, `.htm`, `.xhtml`, `.md`, `.markdown` | Existing `viewer.reading.srt`, HTML pages and comprehensive Markdown cover richer reading states |
| Code and plain text | `viewer.cpp`, `.json`, `.xml`, `.py`, `.swg`, `.txt`, `.rst` | Syntax families and common prose; many spelling aliases share these parsers |
| Font and archive | `viewer.ttf`, `.ttc`, `.zip` | Collection wrapper; existing archive navigation fixture |

`viewer.odt`, `.ods`, `.odp` and `.jar` exercise the Archive fallback and do **not**
mean that Swag Scope reads their document content. They remain in the backlog for dedicated
readers. Other ZIP package suffixes currently share the same Archive implementation; they
need genuine representative packages before entering this matrix. The many Code and Basic Text
extension aliases need selector coverage, but do not each need a duplicate payload unless
their parser or display behavior differs.

The copies from `bin/std/modules/{pixel,audio,video,gui}/src/tests/datas` retain the source
corpus' licences and provenance. Other copied inputs are already present in this directory;
`viewer.qoi`, the subtitle/table examples and package variants were created for these tests.
`viewer.ttc` wraps the existing `segoeui.ttf` face and adjusts its table offsets. See
[`THIRDPARTY.md`](THIRDPARTY.md) for externally sourced inputs.

The six `viewer.christmas-carol.epub`, `viewer.poi-sample.docx`,
`viewer.monthly-budget.xlsx`, `viewer.poi-sample.pptx`, and
`viewer.openmp-reference.pdf`, and `viewer.libreoffice.rtf` fixtures are unmodified, published documents with recorded
upstream URLs, licences, and SHA-256 hashes in `THIRDPARTY.md`. Content tests read chapters,
paragraphs, cells, slides, and distant PDF pages from them; the small generated fixtures keep
their separate role in isolating individual format variants and failures.
