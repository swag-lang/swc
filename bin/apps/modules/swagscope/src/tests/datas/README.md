# Swag Scope viewer fixtures

`viewer.<extension>` is the canonical small file for a format or extension claimed by a
content reader. `viewer.<variant>.<extension>` changes one meaningful property, such as codec,
colour model, page encoding, package path, or damage. The extension is always the one the
application selects; a variant name is never a substitute for a real suffix. Tests outside this
directory may retain older names when those files serve a particular screenshot or journey.

The executable fixture matrix includes every `viewer.*` file in this directory and is
[`fixtures.swg`](../cases/functional/viewers/fixtures/fixtures.swg). It checks that every listed
file exists and selects the expected reader. The image cases also decode their payloads;
format-owned tests exercise EPUB, CBZ, PDF, DOCX, ODT, RTF, XLSX, ODS, PPTX and ODP content and negative cases. The
registry smoke opens one file for each viewer. A selector check alone does not prove that every
legal variation of a format can be read.

`viewer.hex` is a readable-text payload opened directly by the Hex viewer's smoke; automatic
selection correctly offers Text first for those bytes.

| Family | Canonical fixtures | Variants exercised here |
| --- | --- | --- |
| Documents | `viewer.pdf`, `.epub`, `.docx`, `.odt`, `.rtf`, `.xlsx`, `.ods`, `.pptx`, `.odp`, `.cbz` | PDF object streams, rotation, JPEG and CCITT images; nested EPUB/CBZ paths; licensed 3-page and 15-page comics; split and formatted DOCX runs and an embedded photo with a blocked external reference; RTF Unicode, tables, ignorable destinations and damage; inline XLSX strings; relative and package-absolute slide/sheet relationships; slide order; damaged packages |
| Images | `viewer.svg`, `.bmp`, `.cur`, `.dds`, `.exr`, `.gif`, `.ico`, `.jpg`, `.jpeg`, `.ktx2`, `.png`, `.apng`, `.psd`, `.qoi`, `.tga`, `.tif`, `.tiff`, `.webp` | CMYK and progressive JPEG; GIF, APNG and WebP animation |
| Sound | `viewer.wav`, `.flac`, `.mp3`, `.aac`, `.ac3`, `.eac3`, `.ec3`, `.dts`, `.ogg`, `.oga`, `.opus` | Surround FLAC/E-AC-3 and hybrid Opus |
| Video | `viewer.mp4`, `.m4v`, `.mov`, `.mkv`, `.avi`, `.y4m` | H.264 and HEVC in MP4, raw AVI and RV40 MKV |
| Structured text | `viewer.csv`, `.tsv`, `.tab`, `.srt`, `.vtt`, `.ass`, `.ssa`, `.lrc`, `.sub`, `.html`, `.htm`, `.xhtml`, `.md`, `.markdown` | Existing `viewer.reading.srt`, HTML pages and comprehensive Markdown cover richer reading states |
| Code and plain text | `viewer.cpp`, `.json`, `.xml`, `.py`, `.swg`, `.txt`, `.rst` | Syntax families and common prose; many spelling aliases share these parsers |
| Font and archive | `viewer.ttf`, `.ttc`, `.zip` | Collection wrapper; existing archive navigation fixture |
| 3D scene | `viewer.obj`, `viewer.ascii.stl`, `viewer.binary.stl` | Repository-authored tetrahedron OBJ plus ASCII and binary STL triangle fixtures |

`viewer.jar` exercises the Archive fallback and does **not** mean that Swag Scope reads
its executable content. Other ZIP package suffixes currently share the same Archive implementation; they
need genuine representative packages before entering this matrix. The many Code and Basic Text
extension aliases need selector coverage, but do not each need a duplicate payload unless
their parser or display behavior differs.

The copies from `bin/std/modules/{pixel,audio,video,gui}/src/tests/datas` retain the source
corpus' licences and provenance. Other copied inputs are already present in this directory;
`viewer.qoi`, the subtitle/table examples and package variants were created for these tests.
`viewer.ttc` wraps the existing `segoeui.ttf` face and adjusts its table offsets. See
[`THIRDPARTY.md`](THIRDPARTY.md) for externally sourced inputs.
`viewer.image.docx` packages the existing `viewer.jpg` with one local and one external image
relationship; the external URL is intentionally never fetched.

The seven `viewer.christmas-carol.epub`, `viewer.poi-sample.docx`,
`viewer.poi-pictures.docx`, `viewer.monthly-budget.xlsx`, `viewer.poi-sample.pptx`, and
`viewer.openmp-reference.pdf`, and `viewer.libreoffice.rtf` fixtures are unmodified, published documents with recorded
upstream URLs, licences, and SHA-256 hashes in `THIRDPARTY.md`. Content tests read chapters,
paragraphs, cells, slides, and distant PDF pages from them; the small generated fixtures keep
their separate role in isolating individual format variants and failures.

`viewer.navigation.epub` and `viewer.navigation.ncx.epub` are repository-authored,
minimal EPUB 3 and EPUB 2 books. Each has two spine chapters, nested contents, inline
labels, and same-chapter and cross-chapter fragment targets. They contain no external assets.

`viewer.geometry.pptx` is a repository-authored two-slide widescreen presentation. It exercises
inherited title bounds, static master decoration, theme colors, text boxes and aligned cards.
Its embedded photograph is reused unchanged from `viewer.pictures.pptx` and retains that
fixture's recorded provenance and licence. No external resources are included.

`viewer.formats.xlsx` is a repository-authored workbook with two sheets and no external assets.
Its style part uses a relationship-resolved path and exercises currencies, percentages, negative
and zero sections, grouping, optional decimals, dates, elapsed time and cached formula values.

`viewer.pictures.rtf` embeds the existing `viewer.jpg` as a hexadecimal JPEG picture.
`viewer.alternate-picture.rtf` wraps the existing `viewer.png` as a modern shape picture and
its compatibility fallback. Both documents are repository-authored; the reused image bytes
retain their original provenance and licences. They contain no external resources.

`viewer.styles.docx` is a repository-authored document with relationship-resolved style and theme
parts. It exercises custom heading IDs, parent styles, character styles, theme fonts/colors,
paragraph spacing/indents, direct bold resets and a simple table. It contains no external assets.

`viewer.navigation.xlsx` is a repository-authored three-sheet workbook with a saved active
sheet, a hidden intermediate sheet and literal sheet labels. It contains no external assets.

`viewer.styles.rtf` is a repository-authored reading note with two fonts, a color table,
highlights, paragraph indents and spacing, and grouped character formatting. It has no external assets.

`viewer.geometry.xlsx` derives from the repository-authored numeric-format workbook. Its first
sheet adds declared dimensions, horizontal/vertical merges, hidden ranges and distant totals;
it contains no external assets.

`viewer.styles.xlsx` adds repository-authored theme colors, font sizes/emphasis, filled headers,
a wrapped reading note and bordered totals to the geometry workbook. Its theme lives at a
relationship-resolved path; it contains no external assets.

`viewer.odt` and `viewer.image.odt` are repository-authored reading examples produced by
LibreOfficeDev 26.8.0.0.alpha0 (build 2c87e51eeaa2b413ff4ae097b2705eea1995d8e5), using the
HTML (StarWriter) import filter and the `odt:writer8` export filter. The first contains a green
24-point title, three 16-point section headings, 12-point body text, bold/italic passages,
an indented blue note, a three-row table with a green header, and a link to the final section.
The second contains a title, introduction, embedded 320-by-240 photo and following paragraph.
The photograph reuses the existing `viewer.jpg` corpus image and its existing provenance; it was
embedded as a data URL in the HTML input before conversion. These ZIP packages contain genuine
Writer styles, manifests and metadata, no local filesystem links. Functional tests supplement
those producer files with small controlled packages for inheritance, repeats, omissions and damage.

`viewer.ods` and `viewer.navigation.ods` are LibreOffice Calc exports of the repository-authored
`viewer.styles.xlsx` and `viewer.navigation.xlsx`. `viewer.monthly-budget.ods` derives from the
licensed `viewer.monthly-budget.xlsx` corpus file. They were generated with LibreOfficeDev
26.8.0.0.alpha0 (build 2c87e51eeaa2b413ff4ae097b2705eea1995d8e5), using headless
`--convert-to ods:calc8`. They exercise genuine Calc style inheritance, saved formatted values,
formula caches, row/column geometry, repeated unused cells, merges and sheet visibility. The
source XLSX files remain the reproducible inputs; controlled ODS packages supplement them for
saved active-sheet settings, sparse million-row addresses, repeated column defaults and damage.

`viewer.odp` is a repository-authored 10-by-5.625-inch presentation exported from a flat ODF
input by LibreOfficeDev 26.8.0.0.alpha0 (build 2c87e51eeaa2b413ff4ae097b2705eea1995d8e5),
using headless `--convert-to odp:impress8`. Its two slides contain green 28-point titles,
18-point prose with bold emphasis, a green rectangle with white text, the existing `viewer.jpg`
photo in a 4-by-3-inch frame, and an empty notes-page placeholder. This export does not retain
the flat input's standalone speaker paragraph. Photo provenance is unchanged.
`viewer.poi-sample.odp` is an Impress conversion of the licensed `viewer.poi-sample.pptx` corpus
file using the same producer/filter; it exercises presentation style parents, mixed character
sizes, lists, master placeholders and notes. Controlled packages supplement these producer files
for master visibility, style resets, hidden slides, omissions, malformed XML and expansion limits.

`viewer.default-styles.xlsx` is a repository-authored five-row workshop budget written with
openpyxl 3.1.5, without external assets. Column A uses a 14-point font; B has a pale green fill,
green 14-point type and `"€"#,##0.00`; C has grey italic type. Row 3 has bold purple 15-point
type, a pale purple fill and `#,##0.00`; row 5 uses bold green type and `0.0%`. A1 and B4 have
direct cell styles, while the other saved cells, including empty B1/C1, omit a cell XF.
The source writer assigns these through `column_dimensions`, `row_dimensions` and cell styles.
An independent LibreOfficeDev 26.8 re-save materializes B2's column XF, B3/B5's row XF and
B4's unchanged direct XF, confirming the expected precedence. The workbook itself is the
unmodified openpyxl package, not that materialized re-save. Its licence is this repository's.
SHA-256: `0a251d0cab7928d459a051dc43da26a39e49ab7fea1ef85912860e3e7323a8f3`.

`viewer.extreme.obj` contains finite coordinates outside the scene viewer's safe camera range and
confirms that framing fails with a user-facing format error.
