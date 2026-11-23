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
| Documents | `viewer.pdf`, `.epub`, `.docx`, `.odt`, `.rtf`, `.xlsx`, `.ods`, `.pptx`, `.odp`, `.cbz` | PDF object streams, rotation, JPEG and CCITT images, and a generated mixed text/raster scan; a complete Gutenberg story in EPUB, DOCX, ODT and RTF; nested EPUB/CBZ paths; a generated two-page comic and licensed 3-page and 15-page comics; split and formatted DOCX runs and an embedded illustration with a blocked external reference; RTF Unicode, tables, ignorable destinations and damage; XLSX cached values; ODS number formats without cached display text; relative and package-absolute slide/sheet relationships; slide order; damaged packages |
| Images | `viewer.svg`, `.bmp`, `.cur`, `.dds`, `.exr`, `.gif`, `.ico`, `.jpg`, `.jpeg`, `.ktx2`, `.png`, `.apng`, `.psd`, `.qoi`, `.tga`, `.tif`, `.tiff`, `.webp` | Original 128×64 SVG logo and generated watershed map; CMYK and progressive JPEG; GIF, APNG and WebP animation; 33-frame generated animated review illustration with EXIF metadata; compact WebP with a generated ICC identity profile |
| Sound | `viewer.wav`, `.flac`, `.mp3`, `.aac`, `.ac3`, `.eac3`, `.ec3`, `.dts`, `.ogg`, `.oga`, `.opus` | Generated six-second stereo field-station waveform with RIFF metadata (`viewer.field-station.wav` is a named copy); surround FLAC/E-AC-3 and hybrid Opus |
| Music | `viewer.mid`, `.midi`, `viewer.groove.mid`, `viewer.ensemble.mid` | Original single-track melody, five-track piano/bass/strings/drums groove, and generated four-track score with conductor, tempo, meter and key changes |
| Video | `viewer.mp4`, `.m4v`, `.mov`, `.mkv`, `.avi`, `.y4m` | Generated six-second moving-marker H.264 clip; HEVC in MP4, raw AVI and RV40 MKV |
| Structured text | `viewer.csv`, `.tsv`, `.tab`, `.srt`, `.vtt`, `.ass`, `.ssa`, `.lrc`, `.sub`, `.html`, `.htm`, `.xhtml`, `.md`, `.markdown`, `.ipynb` | Three-row fictional city-weather CSV, tab-delimited alias sample, timed captions in six subtitle formats, field-report XHTML/HTML, comprehensive Markdown, notebooks covering Markdown/code/plain/error/rich outputs and `display_data` table text |
| Code and plain text | `viewer.cpp`, `.json`, `.xml`, `.py`, `.swg`, `.txt`, `.rst` | Fictional North Basin survey records, UTF-8 field log, Python and Swag examples, XML/JSON data, reStructuredText report; spelling aliases share deterministic source payloads |
| Binary and hex | `viewer.console.exe`, `viewer.field-station.elf`, `viewer.hex.telemetry.bin` | Generated PE32+ app, dynamically linked ELF64 with symbols/debug info, structured 20-record telemetry dump opened in Hex |
| Font and archive | `viewer.arabic.ttf`, `viewer.arabic.ttc`, `viewer.arabic.partial.ttc`, `font-fixture-cjk.otf`, `font-fixture-damaged.otf`, `.zip`, `viewer.jar` | OFL Arabic regular font and Regular/Bold collection; partial TTC with a malformed middle face; OFL CFF OpenType specimen and damaged-table variant; generated field-survey bundle and ZIP64, descriptor, Unicode/duplicate, encrypted, damaged-directory and size-limit ZIP variants; executable JAR |

`viewer.mid` and `.midi` are byte-identical aliases for an original seven-note single-track melody.
`viewer.groove.mid` is an original five-track arrangement with conductor, piano, bass, strings and
drums. Their track layouts, timings and note events are retained as deterministic source data by
`generator/generate-literary-fixtures.py`. The separate `viewer.ensemble.mid` score is documented
above and is not rewritten by that generator.

The small text, code, XHTML/XML and caption fixtures in this family are repository-authored; the
survey and timed-caption examples use fictional North Basin field records. The generator also
preserves the long-form Markdown, HTML and MIDI payloads used by existing visual baselines. It
writes the `.md`/`.markdown`, `.html`/`.htm`, and
`.mid`/`.midi` aliases from a single source and keeps XML distinct from XHTML. No external prose,
captions, code or composition is used; hashes and generation details are in `THIRDPARTY.md`.

`viewer.field-guide.html` and `viewer.field-observations.csv` are repository-generated, fictional
fieldwork records. The handbook includes nested sections, internal links, a checklist table,
quotation and contact link; its paired CSV records twelve dated observations across three sites.
Both contain no external references; their SHA-256 hashes are in `THIRDPARTY.md`.

`viewer.field-notes.vtt` is a 12-cue WebVTT field transcript with note/style/region metadata and
speaker tags. `viewer.field-notes.txt` is a fictional UTF-8 field report with accented French
terms and searchable operational prose. `viewer.field-station.cpp` is an original C++20 example
with typed measurements, literals, comments, and a small aggregation routine. Their SHA-256 hashes
and generated provenance are recorded in `THIRDPARTY.md`.

`viewer.field-notes.ipynb` is a fictional repository-authored Jupyter field notebook. It includes
Markdown, code, plain output, an error traceback, and inert HTML/image MIME examples to verify that
rich content is named but never fetched or executed. It has no external assets or copied prose.
SHA-256: `1eef6b5925196899ed019384754d90caf352b70b8ffee5e4625a74338a86089a`.

`viewer.field-display.ipynb` is a generated CC0-1.0 notebook whose `display_data` has tabular
`text/plain` lines alongside inert HTML and SVG siblings. It verifies readable plain output without
activating the richer MIME values. SHA-256: `90958817efa3fde71da9f79e9bc2137163620016d5e19d6e1762d9d99abe54ce`.

`viewer.jar` is a valid generated Java package that exercises the Archive fallback; the viewer
lists its package files without running its class. The matrix also contains representative ZIP,
TAR/PAX and GZIP inputs, including damaged and bounded-preview cases. Other archive suffixes are
not claimed until a representative package is added. Extension aliases share payloads only when
the parser behavior is the same; each alias is still covered by reader selection.

Audio, video and selected PDF inputs are byte-identical copies of fixtures in the standard-module
test corpora. Their exact local/source mappings, hashes and licences are recorded in
`THIRDPARTY.md`. The current Swag Scope image fixtures are generated locally or have a documented
open licence; the obsolete Pixel-provenance note no longer applies to this matrix.
`viewer.arabic.ttf` and `viewer.arabic.ttc` are deterministic subsets of Noto Sans Arabic Regular
and Bold, with the TTC carrying both faces and basic Arabic block coverage. The generator script
and invocation are recorded in [`THIRDPARTY.md`](THIRDPARTY.md). See that guide for other
externally sourced inputs.
`viewer.arabic.partial.ttc` reuses those licensed faces and invalidates only the middle face's
scaler signature, so valid neighbors remain available around a malformed member. Its generator and hash are
also recorded in [`THIRDPARTY.md`](THIRDPARTY.md).
`viewer.image.docx` packages the generated `viewer.jpg` with one local and one external image
relationship; the external URL is intentionally never fetched.

The seven unmodified published fixtures — `viewer.christmas-carol.epub`,
`viewer.poi-sample.docx`, `viewer.poi-pictures.docx`, `viewer.monthly-budget.xlsx`,
`viewer.poi-sample.pptx`, `viewer.openmp-reference.pdf`, and `viewer.libreoffice.rtf` — have
recorded upstream URLs, licences, and SHA-256 hashes in `THIRDPARTY.md`. Content tests read
chapters, paragraphs, cells, slides, and distant PDF pages from them. The generated
Generated ODT, RTF and DOCX conversions carry the public-domain story into those readers. Small
generated fixtures keep their separate role in isolating individual format variants and failures.

`viewer.navigation.epub` and `viewer.navigation.ncx.epub` are repository-authored,
minimal EPUB 3 and EPUB 2 books. Each has two spine chapters, nested contents, inline
labels, and same-chapter and cross-chapter fragment targets. They contain no external assets.

`viewer.geometry.pptx` is a repository-authored two-slide widescreen presentation. It exercises
inherited title bounds, static master decoration, theme colors, text boxes and aligned cards.
Its embedded photograph is reused unchanged from `viewer.pictures.pptx` and retains that
fixture's recorded provenance and licence. No external resources are included.

`viewer.chart.pptx` is a repository-authored one-slide presentation with a cached two-series
bar chart and three shared categories. It exercises a relationship-resolved chart part without
an embedded workbook or external resources. Regenerate it with
`generator/generate-office-lite-fixtures.py`.

`viewer.project.zip` is a reproducible, repository-authored field-survey project bundle. It has
seven Deflate-compressed files across the root, `config/`, `data/`, `docs/` and `src/`, with
fictional site metadata, CSV observations, a source file and a bundled MIT licence.
Its data is generated for these tests and has no external dependencies; the SHA-256 is recorded
in `THIRDPARTY.md`.

`viewer.field-kit.tar` is a deterministic POSIX ustar archive generated by
`generator/generate-field-kit-tar.py`. Its three fictional files cover nested paths, source,
CSV and plain-text preview. It has no external assets. SHA-256: `c894b190c621cb1fee49319b034aec8d15991ac3aa448032e3de1e99df8e1765`.

`viewer.pax-field-kit.tar` is a generated POSIX PAX archive made by
`generator/generate-pax-tar.py`. A long nested UTF-8 path and payload size are stored in an
extended header; the fictional file has no external assets. SHA-256:
`51c304948a936659bf63ae4d13ae992f4ff3ddb4341b61f057f7ea60cfb3fcdb`.

`viewer.field-notes.txt.gz` and `viewer.field-kit.tar.gz` are deterministic GZIP examples generated
by `generator/generate-gzip-fixtures.py`. The first stores fictional notes and an original filename;
the second wraps the field-kit USTAR archive to exercise TAR.GZ browsing and member extraction.
Both include extra data, comments and a header CRC. Neither contains third-party material.
SHA-256: `8a31a72d6f196f114d2042722881d37b79eac4355a44385f13e86c99df702b95` and
`b56c18a2c18d11bc5f648aa7548d12799a2fb312bff45a031d47ac6e21e04ed4`.

`viewer.formats.xlsx` is a repository-authored workbook with two sheets and no external assets.
Its style part uses a relationship-resolved path and exercises currencies, percentages, negative
and zero sections, grouping, optional decimals, dates, elapsed time and cached formula values.

`viewer.pictures.rtf` embeds the generated `viewer.jpg` as a hexadecimal JPEG picture.
`viewer.alternate-picture.rtf` wraps generated `viewer.png` bytes as a modern shape picture and
its compatibility fallback. Both documents are repository-authored and contain no external resources.

Texture arrays, layered Photoshop images and multipart EXR images are generated by `generator/generate-texture-fixtures.py`. DDS and KTX2 use two layers with two mip levels; PSD contains three synthetic image layers; EXR contains two named scanline parts. PSD generation uses ImageMagick 7.1.1-43 Q16; EXR generation uses OpenEXR 3.5.4 and NumPy. These files contain only generated color samples and are covered by this repository's licence. See `THIRDPARTY.md` for hashes.

The simple raster fixtures are generated by `generator/generate-image-fixtures.py` using Pillow 12.3.0 and
fixed geometric drawing only; no source images, fonts, or profiles are read. It generates
`viewer.png` (512×512 RGB), `viewer.jpg`/`viewer.jpeg` (identical 1024×768 baseline JPEG), a
4×4 24-bit BMP, a 660×441 RLE TGA, a 48×32 four-component CMYK JPEG, and a 660×441 progressive
JPEG. The generator also refreshes the JPEG/PNG payloads embedded in `viewer.image.docx`,
`viewer.image.odt`, `viewer.odp`, `viewer.pictures.rtf`, and `viewer.alternate-picture.rtf`. The
files are fictional watershed illustrations, generated for these tests; fixture hashes and the
source/generation records are listed in `THIRDPARTY.md`.

`viewer.icc-profile.webp` and `viewer.icc-profile.jpg` are small generated color patches carrying
the same synthetic ICC header and ASCII `desc` identity. WebP preserves it as one ICC chunk; JPEG
stores it in APP2 `ICC_PROFILE` segments. The profile tests identity inspection only and does not
claim a usable color transform. Their deterministic generators and hashes are listed in
`THIRDPARTY.md`.

`viewer.icc-profile-mluc.webp` carries a generated ICC `mluc` description with French first and
English second, so the reader's locale choice is exercised through the WebP decoder. The profile
is synthetic and tests identity inspection only.

`viewer.xmp.webp` and `viewer.xmp.jpg` are 48×32 generated color patches carrying the same
synthetic XMP description, creator, subject, rights, and date in WebP and JPEG metadata. The
namespace aliases and RDF arrays exercise the bounded descriptive reader; all values and artwork
are generated. Regenerate both with `generator/generate-xmp-fixtures.py`.

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
Its two page layouts include an A4-width reading page with two-centimetre margins. The second
contains a title, introduction, embedded 320-by-240 illustration and following paragraph. Both packages
are generated from repository-authored HTML; `viewer.image.odt` reuses the generated `viewer.jpg`.
SHA-256: `viewer.odt` —
`efda1c3083909e66b34c778e8311972e8dfb04ebc162b240c796e07c6f122507`;
`viewer.image.odt` — `4f44eccacacf69ad8c668d37de94a43ed05db8d7621d8e55073615dae957e0e8`.
The synthetic watershed illustration was embedded as a data URL in the HTML input before conversion.
These ZIP packages contain genuine Writer styles, manifests and metadata, no local filesystem links. Functional tests supplement
those producer files with small controlled packages for inheritance, repeats, omissions and damage.

`viewer.christmas-carol.odt` imports the two narrative spine documents after the cover of the
licensed Gutenberg EPUB below as HTML, drops their images, then exports the content through the
LibreOfficeDev `odt:writer8` filter. Its generated RTF and DOCX conversions also enter the text
into those readers. The files contain about 800 paragraphs with the story's opening and closing
prose; source, conversion steps and SHA-256 values are in `THIRDPARTY.md`.

`viewer.christmas-carol.rtf` carries those two narrative chapters through LibreOffice's RTF
exporter. Its 813 paragraphs and Unicode punctuation add a long, generated reading document to
the RTF viewer's smaller focused formatting samples. Its source and conversion steps are in
`THIRDPARTY.md`.

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
18-point prose with bold emphasis, a green rectangle with white text, the generated watershed
illustration in a 4-by-3-inch frame, and an empty notes-page placeholder. This export does not retain
the flat input's standalone speaker paragraph.
`viewer.poi-sample.odp` is an Impress conversion of the licensed `viewer.poi-sample.pptx` corpus
file using the same producer/filter; it exercises presentation style parents, mixed character
sizes, lists, master placeholders and notes. Controlled packages supplement these producer files
for master visibility, style resets, hidden slides, omissions, malformed XML and expansion limits.

`viewer.watershed.odp` derives from the repository-authored `viewer.odp` without its photo. The
generated third slide adds five labelled vector shapes, two intentionally simplified drawings and
speaker notes for a fictional field briefing. It contains no external resources.

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

`imageset-animation.{apng,gif,webp}`, `imageset-icons.ico` and `imageset-pages-raw.tiff` are
generated by `generator/generate-image-sequences.py` with Pillow 12.3.0. They contain three
distinct finite-loop frames, three ICO sizes, and three differently sized TIFF pages respectively.
The `viewer.*` and `viewer.animation.*` variants are byte-identical aliases; the drawings are
procedural and have no external assets. Hashes and exact format properties are in `THIRDPARTY.md`.


`viewer.cur`, `viewer.qoi`, `viewer.archive.icons.png`, and `viewer.nested.cbz` are original
fixed-geometry fixtures generated by `generator/generate-image-archive-fixtures.py`. CUR contains
two hotspot images, QOI contains four explicit RGBA pixels, the archive sprite atlas contains three
small file icons, and the nested comic contains two fictional field-survey pages. `viewer.zip` and
`viewer.archive.zip` are byte-identical aliases of a ZIP with two fictional text/data entries.
Their generation steps, licences, and hashes are recorded in `THIRDPARTY.md`.
