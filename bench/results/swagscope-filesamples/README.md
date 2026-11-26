# Swag Scope format comparison on FileSamples

Measured 2026-11-26.

## Scope

FileSamples contains 808 downloaded fixtures across 181 extensions in `audio`, `code`, `document`,
`ebook`, `font`, `image`, and `video`. This report compares the Release decoder paths shared by
Swag Scope with established in-process reference libraries. It measures one representative fixture
per directly decoded image, audio, and video extension, every PDF fixture, and two fonts each for
TTF and OTF. It does not time all 808 files or every size/profile variant.

**Result:** Swag Scope is not uniformly slow. The largest measured regressions are its FLAC and
DTS audio paths, its PDF page render, and its WebP/EXR image decode. BMP, ICO, JPEG, PNG, TIFF,
WAV and most tested video containers are competitive or faster under these API workloads. The
four SVG fixtures remain slower than resvg. The original results and the Linux follow-up are
summarized below.

## Measured formats

Times are medians of seven measured repetitions, in milliseconds. The ratio is
**Swag Scope / reference**; a value above 1 means Swag Scope took longer. Exact samples, fixture
sizes, dimensions and raw timings are in [`measurements.json`](measurements.json).

### Raster images

Swag Scope used `Pixel.Image.load` (mapped file plus decode). ImageMagick used MagickWand in the
same process and materialized the full image: `MagickReadImage` followed by an RGBA8 export for
integer raster formats. The EXR fixture decodes to RGBF16 in Swag Scope; MagickWand exported RGBF32
to preserve HDR range rather than compare it after an 8-bit conversion. One FileSamples fixture per
supported extension was used.

| Fixture | Size | Pixels | Swag Scope | ImageMagick 7.1.2 | Ratio |
| --- | ---: | ---: | ---: | ---: | ---: |
| `bmp/sample_640×426.bmp` | 818 KB | 640 × 426 | 0.398 | 7.135 | 0.06× |
| `exr/sample_640×426.exr` | 1.64 MB | 640 × 426 | 18.962 | 6.700 | 2.83× |
| `gif/sample_640×426.gif` | 195 KB | 640 × 426 | 14.751 | 10.679 | 1.38× |
| `ico/sample_640×426.ico` | 180 KB | 256 × 170 | 0.268 | 2.948 | 0.09× |
| `jfif/sample1.jfif` | 81 KB | 1024 × 512 | 3.437 | 12.511 | 0.27× |
| `jpe/sample_640×426.jpe` | 89 KB | 640 × 426 | 4.039 | 8.061 | 0.50× |
| `jpeg/sample_640×426.jpeg` | 89 KB | 640 × 426 | 4.485 | 8.216 | 0.55× |
| `jpg/sample_640×426.jpg` | 89 KB | 640 × 426 | 4.466 | 8.674 | 0.51× |
| `png/sample_640×426.png` | 534 KB | 640 × 426 | 5.231 | 13.097 | 0.40× |
| `tiff/sample_640×426.tiff` | 818 KB | 640 × 426 | 1.055 | 7.951 | 0.13× |
| `webp/sample1.webp` | 659 KB | 4275 × 2451 | 361.627 | 261.711 | 1.38× |

WebP is the largest raster hot spot by elapsed time. EXR is about 2.8× the ImageMagick path, and
GIF is about 1.4×. Swag Scope is faster on the other measured raster fixtures. The `.jps` alias was
registered after these measurements, so the original corpus comparison excludes it.

### Audio

Swag Scope used `SoundFile.load(preloadData: false)` and decoded the first ten seconds through
`decodePcm16`. PyAV opened the same file, decoded the first ten seconds through FFmpeg, resampled to
signed 16-bit PCM, and materialized the output array. Times include container/file open and output
materialization, but not audio-device startup or playback.

| Fixture | Size | Swag Scope | PyAV 19.0.2 / FFmpeg 9 | Ratio |
| --- | ---: | ---: | ---: | ---: |
| `aac/sample3.aac` | 1.76 MB | 41.668 | 21.415 | 1.95× |
| `ac3/sample3.ac3` | 2.54 MB | 40.340 | 16.771 | 2.41× |
| `dts/sample3.dts` | 18.66 MB | 381.202 | 37.500 | 10.17× |
| `flac/sample1.flac` | 12.36 MB | 478.449 | 11.848 | 40.38× |
| `mp3/sample3.mp3` | 1.69 MB | 82.086 | 20.732 | 3.96× |
| `oga/sample1.oga` | 12.41 MB | 97.961 | 11.921 | 8.22× |
| `ogg/sample3.ogg` | 1.49 MB | 33.059 | 28.487 | 1.16× |
| `opus/sample3.opus` | 1.24 MB | 76.507 | 36.521 | 2.09× |
| `wav/sample3.wav` | 18.66 MB | 0.865 | 25.926 | 0.03× |

FLAC and DTS need profiling first, followed by MP3 and OGA. PyAV's Python resampler/array path
adds work beyond FFmpeg's native decoder; it biases the reference time upward, so these large
slowdowns warrant confirmation with a native FFmpeg harness before setting a numeric target.
WAV's reference includes resampling and a Python array copy, unlike Swag Scope's direct PCM16
conversion; its apparent 30× advantage is not an equivalent-operation speedup.

The [native Linux follow-up](audio-decode-linux.md) measures open and decode separately after
optimization, with PCM verification for all nine audio fixtures.

### Video

Swag Scope opened each container in picture-only mode and decoded its first key picture to RGB8.
PyAV/FFmpeg opened the same 640 × 360 sample, decoded the first video frame, and converted it to
RGB24. These numbers include each library's container-open and frame-materialization path; the
PyAV binding and NumPy conversion add wrapper work.

| Fixture | Size | Swag Scope | PyAV / FFmpeg | Ratio |
| --- | ---: | ---: | ---: | ---: |
| `avi/sample_640x360.avi` | 584 KB | 4.016 | 2.497 | 1.61× |
| `m4v/sample_640x360.m4v` | 575 KB | 4.087 | 11.769 | 0.35× |
| `mkv/sample_640x360.mkv` | 573 KB | 4.748 | 12.235 | 0.39× |
| `mov/sample_640x360.mov` | 575 KB | 4.348 | 12.123 | 0.36× |
| `mp4/sample_640x360.mp4` | 575 KB | 4.453 | 11.049 | 0.40× |

Only AVI loses in this first-frame probe, by roughly 1.6× at a few milliseconds. The other four
container samples are faster in the Swag API path. This says nothing about long playback, seek,
audio sync, large resolutions, or other codecs in those containers.

### PDF

Swag Scope used `Gui.Pdf.Reader.open`, loaded page 1 and rasterized it with a 1200 px long-side
limit. PDFium did the same through pypdfium2, including conversion to a PIL image. All three PDF
fixtures were included.

| Fixture | Size | Output | Swag Scope | PDFium 159 | Ratio |
| --- | ---: | ---: | ---: | ---: | ---: |
| `sample1.pdf` | 581 KB | 928 × 1200 | 83.813 | 27.837 | 3.01× |
| `sample2.pdf` | 66 KB | 848 × 1200 | 19.829 | 9.040 | 2.19× |
| `sample3.pdf` | 1.25 MB | 849 × 1200 | 59.088 | 16.461 | 3.59× |

The Swag PDF parse-plus-first-page render path is consistently slower on this corpus. The comparison
does not time GUI layout, thumbnails, navigation, or later pages.

### Fonts

Swag Scope read the file, parsed a `TrueType.Face`, set 20 px size and loaded glyph `A`. Pillow used
FreeType to load the same font and rasterize the same glyph. These small fonts expose setup cost;
they do not represent a full character-map browse.

| Fixture | Swag Scope | Pillow 12.3 / FreeType 2.14 | Ratio |
| --- | ---: | ---: | ---: |
| `ttf/slick.ttf` | 0.099 | 0.135 | 0.73× |
| `ttf/NotoSansShavian-Regular.ttf` | 0.159 | 0.134 | 1.19× |
| `otf/slick.otf` | 0.110 | 0.071 | 1.56× |
| `otf/NotoSansShavian-Regular.otf` | 0.118 | 0.069 | 1.71× |

All four timings are below 0.2 ms. The following benchmark isolates the cost of loading a face and
also measures glyphs present in the fonts.

#### Font loader follow-up on Linux

The Release benchmark compares `335b91f31e` with borrowed PostScript names in `post` and CFF and
on-demand lookup for predefined CFF encodings. It uses fresh faces at 20 px on Linux x86-64
(Intel Xeon Platinum 8573C), with a warm file cache and one pinned CPU. Each table cell is the
median of 11 interleaved batches of 1,001 loads. The total includes file reading, face parsing,
pixel-size setup and glyph rendering. It excludes face destruction and checksum calculation.
Pillow 12.3.0 with FreeType 2.14.3 used `ImageFont.truetype` and `getmask` on the same files.

The two TTFs match the sizes from the Windows comparison. The OTFs in this follow-up were generated
from those TTFs with FontTools 4.61.1, scaling the em to 1000 units and converting quadratic outlines
to CFF charstrings. The upstream Shavian OTF is a separate 5,468-byte build. Slick and Noto Sans
Shavian both lack `A`, so the table also includes the mapped `a` and `U+10450` respectively.
The glyph indices and bitmap checksums matched between the two Swag builds on all 15 workloads.

| Fixture | Character | Swag before (µs) | Swag after (µs) | Pillow (µs) |
| --- | --- | ---: | ---: | ---: |
| `slick.ttf` | `A` | 15.50 | 13.84 | 169.48 |
| `slick.ttf` | `a` | 33.62 | 34.18 | 168.15 |
| `NotoSansShavian-Regular.ttf` | `A` | 51.28 | 37.95 | 204.69 |
| `NotoSansShavian-Regular.ttf` | `U+10450` | 52.52 | 43.90 | 227.05 |
| Slick converted to CFF OTF | `A` | 29.13 | 16.82 | 47.95 |
| Slick converted to CFF OTF | `a` | 46.70 | 31.24 | 105.11 |
| Noto Sans Shavian converted to CFF OTF | `A` | 54.22 | 39.20 | 67.53 |
| Noto Sans Shavian converted to CFF OTF | `U+10450` | 57.11 | 41.03 | 72.04 |
| Noto Sans Shavian upstream OTF | `A` | 59.73 | 40.77 | 74.85 |
| Noto Sans Shavian upstream OTF | `U+10450` | 58.99 | 43.50 | 73.85 |

The `A` workload dropped by 26% on the Noto Sans Shavian TTF, 42% on the converted Slick OTF,
and 28–32% on the two Shavian OTFs. Face parsing accounts for most of the improvement. Four
additional TTFs (Lato, Open Sans, Source Code Pro, and Font Awesome) also improved by 30–43%.
Open Sans, Source Code Pro, and Font Awesome still take longer than Pillow in this workload.

#### Original FileSamples OTFs on Linux

The six supplied OTF files were measured with the same Linux Release protocol, Pillow version,
and `335b91f31e` baseline. The Slick and Noto Sans Shavian files are 2,888 and 16,848 bytes,
matching the Windows measurement record. The final loader also copies the font bytes directly
and reads packed CFF offsets and horizontal metrics after checking their complete table ranges.

| Fixture | Character | Swag before (µs) | Swag after (µs) | Pillow (µs) | Time saved |
| --- | --- | ---: | ---: | ---: | ---: |
| `slick.otf` | `A` | 35.28 | 17.30 | 57.87 | 51% |
| `NotoSansShavian-Regular.otf` | `A` | 77.59 | 41.11 | 77.22 | 47% |
| `slick.otf` | `a` | 68.12 | 39.64 | 133.63 | 42% |
| `NotoSansShavian-Regular.otf` | `U+10450` | 75.00 | 43.15 | 81.41 | 42% |
| `Lato-Regular.otf` | `A` | 221.31 | 76.35 | 104.89 | 66% |
| `OpenSans-Regular.otf` | `A` | 516.90 | 157.94 | 125.35 | 69% |
| `SourceCodePro-Regular.otf` | `A` | 356.82 | 105.29 | 104.42 | 70% |
| `fontawesome-webfont.otf` | `A` | 710.10 | 209.40 | 117.98 | 71% |
| `fontawesome-webfont.otf` | `U+F000` | 718.45 | 210.63 | 139.90 | 71% |

Glyph indices, bitmap dimensions and bitmap checksums matched between the Swag builds in every
scenario. The Slick and Shavian `A` workloads both finish ahead of Pillow on this host. Open Sans
and Font Awesome retain the largest gaps. The Windows timings are from the earlier comparison.

#### Packed CFF indexes and public font samples

The next Release run compares directly with `9f43abffa8`, the published font optimization, and
adds five upstream font files. Swag retains the validated CFF offsets in their packed form, skips
the CID hash table for identity charsets, and reads grouped Unicode maps and vertical metrics
from validated spans.

The timings use the same Linux host, pinned CPU, 20 px size and Pillow 12.3.0 with FreeType 2.14.3.
Each result is the median of 11 interleaved batches. A batch opens and renders 501 fresh faces,
or 11 for the 16.5 MB CJK font. The file cache stays warm. The total includes reading, parsing,
setting the size and rendering a glyph. The repeated-glyph check renders 4,001 times with a face
already open in each batch.

| Fixture | Character | Published Swag (µs) | New Swag (µs) | Pillow (µs) | Swag time saved |
| --- | --- | ---: | ---: | ---: | ---: |
| `slick.otf` | `a` | 40.55 | 36.94 | 111.70 | +8.9% |
| `NotoSansShavian-Regular.otf` | `U+10450` | 37.49 | 32.73 | 73.70 | +12.7% |
| `Lato-Regular.otf` | `A` | 68.87 | 66.09 | 98.80 | +4.0% |
| `OpenSans-Regular.otf` | `A` | 141.11 | 118.84 | 109.87 | +15.8% |
| `SourceCodePro-Regular.otf` | `A` | 96.94 | 84.67 | 102.69 | +12.7% |
| `fontawesome-webfont.otf` | `U+F000` | 184.15 | 154.04 | 128.24 | +16.4% |
| `SourceSans3-Regular.otf` | `A` | 504.32 | 262.63 | 241.58 | +47.9% |
| `SourceSerif4-Regular.otf` | `g` | 317.62 | 176.73 | 225.67 | +44.4% |
| `NimbusSans-Regular.otf` | `A` | 104.27 | 82.36 | 116.92 | +21.0% |
| `NotoSans-Regular.ttf` | `A` | 638.13 | 667.29 | 1513.33 | -4.6% |
| `NotoSansCJKjp-Regular.otf` | `U+65E5` | 18758.16 | 9176.11 | 1325.83 | +51.1% |

Glyph indices, bitmap dimensions and bitmap checksums matched in all 11 cases. Median repeated
render times ranged from 7% faster to 3% slower. The Noto Sans TTF control took 4.6% longer at
its load median, with faster and slower batches on both sides. Noto Sans CJK retains the largest
absolute gap against Pillow.

The public fixtures were fetched directly from these upstream revisions.

- Adobe Source Sans 3 OTF, 334,924 bytes. [Upstream file](https://github.com/adobe-fonts/source-sans/blob/87b37a2daaed80fcb8e8ccb0085c4d72ddade12e/OTF/SourceSans3-Regular.otf)
- Adobe Source Serif 4 OTF, 241,392 bytes. [Upstream file](https://github.com/adobe-fonts/source-serif/blob/80d3f8894c09c937bebfa9011247d2e1c79fd6f4/OTF/SourceSerif4-Regular.otf)
- URW Nimbus Sans OTF, 82,264 bytes. [Upstream file](https://github.com/ArtifexSoftware/urw-base35-fonts/blob/3c0ba3b5687632dfc66526544a4e811fe0ec0cd9/fonts/NimbusSans-Regular.otf)
- Noto Sans TTF, 348,408 bytes. [Upstream file](https://github.com/notofonts/noto-fonts/blob/v20201206-phase3/hinted/ttf/NotoSans/NotoSans-Regular.ttf)
- Noto Sans CJK JP OTF, 16,467,736 bytes. [Upstream file](https://github.com/notofonts/noto-cjk/blob/Sans2.004/Sans/OTF/Japanese/NotoSansCJKjp-Regular.otf)

#### Direct file loading and deferred glyph-name indexes

This Release comparison adds the six supplied TTF files to the six supplied OTFs and five
public fixtures. The published baseline is `2edf874a67`. Both Swag copy-path columns read the
file with `File.readAllBytes` and pass the result to `Face.load`. The direct path uses
`Face.loadFile`, which reads into the face's owned storage. Swag builds the reverse glyph-name
index on demand for `post` and CFF, keeps horizontal advances in their validated SFNT table,
and skips redundant validation and expansion of shared maps and identity CID ranges.

Each column uses the median of 11 interleaved batches on one CPU, with a warm file cache.
A batch opens 501 fresh faces per fixture, or 25 for Noto Sans CJK JP, sets 20 px and renders
one glyph from each face. The reference uses Pillow 12.3.0 with FreeType 2.14.3 and the same
files and characters. Cleanup is outside the timed span.

| Fixture | Character | Published Swag copy (µs) | New Swag copy (µs) | New Swag file (µs) | Pillow (µs) |
| --- | --- | ---: | ---: | ---: | ---: |
| `slick.ttf` | `a` | 33.99 | 35.30 | 34.26 | 184.21 |
| `slick.otf` | `a` | 38.88 | 40.84 | 37.49 | 145.07 |
| `NotoSansShavian-Regular.ttf` | `U+10450` | 38.20 | 35.91 | 35.53 | 256.18 |
| `NotoSansShavian-Regular.otf` | `U+10450` | 37.47 | 30.39 | 32.34 | 83.35 |
| `Lato-Regular.ttf` | `A` | 69.99 | 48.16 | 49.15 | 215.34 |
| `Lato-Regular.otf` | `A` | 63.37 | 48.57 | 45.13 | 110.28 |
| `OpenSans-Regular.ttf` | `A` | 172.60 | 95.85 | 95.62 | 121.42 |
| `OpenSans-Regular.otf` | `A` | 125.45 | 68.58 | 64.09 | 138.58 |
| `SourceCodePro-Regular.ttf` | `A` | 119.34 | 70.84 | 67.87 | 86.52 |
| `SourceCodePro-Regular.otf` | `A` | 92.70 | 53.42 | 56.43 | 107.15 |
| `fontawesome-webfont.ttf` | `U+F000` | 157.97 | 122.37 | 95.17 | 268.96 |
| `fontawesome-webfont.otf` | `U+F000` | 209.37 | 144.13 | 99.04 | 139.17 |
| `SourceSans3-Regular.otf` | `A` | 291.16 | 161.27 | 156.42 | 275.87 |
| `SourceSerif4-Regular.otf` | `g` | 205.76 | 132.37 | 123.60 | 273.52 |
| `NimbusSans-Regular.otf` | `A` | 87.57 | 55.10 | 53.79 | 134.32 |
| `NotoSans-Regular.ttf` | `A` | 673.42 | 353.56 | 314.42 | 1580.09 |
| `NotoSansCJKjp-Regular.otf` | `U+65E5` | 9735.88 | 9102.00 | 2890.71 | 1301.63 |

Glyph indices, bitmap dimensions and bitmap checksums matched across all three Swag paths for
all 17 fixtures. The direct file path comes in ahead of Pillow on 16 fixtures. Noto Sans CJK JP
improves from 9.74 ms to 2.89 ms, with Pillow at 1.30 ms. The separate file-read phase on the new
copy path takes 2.21 ms for this 16.5 MB font.

Rendering 4,001 times with the same face and size already set, the median per-glyph time
ranged from 4.2% faster to 2.5% slower than the published build across the 17 fixtures.

#### Expanded reproducible font corpus

The Linux follow-up covers 44 scenarios across 41 files. It adds multiple CJK collection faces,
variable TrueType, legacy kerning, new scripts, and three WOFF1 files rejected by the published
loader. The updated decoder leads Pillow in 36 scenarios, and all eight remaining cases have
lower medians than published Swag. [Expanded font results](font-decode-linux.md)

The packed-table follow-up uses the same corpus and records separate timings for file reads and
SFNT parsing. Swag leads in 38 of the 44 scenarios. [Packed glyph table results](font-decode-linux.md#packed-glyph-tables)

### SVG results already reported

The prior four-file comparison measured Scope's SVG parse plus CPU rasterization against resvg
0.50.0. Its total ratios were **18.4×, 75.0×, 7.9× and 11.4×** for outputs from 640 × 426 up
to the 2048 × 1365 cap. Rasterization dominated. Details, timings by phase, hashes and limitations
remain in [`std.pixel.image.057`](../../../backlog/std.pixel.image.md#stdpixelimage057--svg-cpu-rasterization-is-far-slower-than-resvg).

The Linux A/B rerun verified all four original files and preserved Swag's raster checksums.
With one worker, the revised renderer took **14.36×, 6.39×, 3.95× and 5.93×** as long as resvg.
On this host, the 1280 × 853 sample fell from 1427 ms to 136 ms against the Swag baseline.
See the [SVG benchmark](../../workloads/svgraster/README.md#original-filesamples-svgs) for the
one-worker and four-worker measurements.

## FileSamples coverage and remaining comparisons

The comparisons above cover the directly registered Pixel image decoders present in the corpus
(except the `.jps` alias), all nine FileSamples audio extensions registered by `SoundFile`, all five
video extensions registered by `Video.Reader`, all PDF fixtures, and representative TTF/OTF files.
Other fixtures use specialized document or text readers, or fall through to a generic view; they do
not share a single decode operation with a general-purpose library.

| Filesamples family (fixture count) | Fixture formats handled by a dedicated Swag Scope reader | Comparison status |
| --- | --- | --- |
| Raster images (151) | BMP, EXR, GIF, ICO, JFIF, JPE, JPEG, JPG, PNG, TIFF, WebP, SVG | All 11 raster extensions measured; four SVG fixtures are in the earlier comparison |
| Sound (266) | AAC, AC3, DTS, FLAC, MP3, OGA, OGG, Opus, WAV | All nine overlapping direct-decoder extensions measured |
| Video (194) | AVI, M4V, MKV, MOV, MP4 | All five overlapping reader extensions measured on one 640 × 360 sample each |
| Documents (42) | PDF, DOCX, RTF, ODT, ODS, ODP, XLSX, CSV | All PDFs measured; the other readers need matched open/render workloads |
| E-books (35) | EPUB | Not timed; chapter extraction and HTML reading need a matched reader workload |
| Web and source (66) | HTML, JSON, YAML, SQL and the listed code samples | Not timed; syntax highlighting, parsing and layout are different operations |
| Fonts (54) | TTF, OTF | Representative glyph load measured; not all font fixtures |
| Archives | No standalone archive fixture; office and EPUB packages are handled by their specialized viewers | No separate archive timing |
| Legacy Office | DOC, XLS, PPT | Not treated as supported content: Scope identifies or rejects these legacy formats |

The existing [app.scope.viewers.009](../../../backlog/app.scope.viewers.md#appscopeviewers009--the-viewer-family-has-no-release-quality-compatibility-matrix)
tracks matched comparisons for specialized viewers, including DOCX, XLSX, PPTX and PDF against a
full viewer. LibreOffice 26.8.3.1 is now installed for future Office-format reference work; this
report does not claim an Office comparison because there is no matching Swag Scope decode-only
measurement for those viewer transformations.

## Method and limits

- Host: Windows 11 build 26300, Intel Core Ultra 9 185H. Swag code ran as Release programs through
  the checkout's `bin/swc.exe`. Each measured fixture has seven timing samples; libraries were
  called in-process. The reference harness discarded one warm-up sample. SVG data is from the
  existing seven-run resvg comparison.
- Reference versions: ImageMagick 7.1.2-36 Q16-HDRI; PyAV 19.0.2 with FFmpeg libavcodec 63.1.102;
  PDFium 159.0.8149.0 through pypdfium2 5.15.2; Pillow 12.3.0 with FreeType 2.14.3; resvg 0.50.0.
- Each API boundary includes parsing/opening and the relevant decoded output. File reads and
  rendering are included where the listed operation includes them. GUI construction, window
  startup, presentation and storage of benchmark PNGs are excluded.
- These are single-machine corpus measurements, not confidence intervals or universal codec
  rankings. The image reference exports RGBA8; audio/video and PDF/font references include Python
  binding work. Ratios for those families are comparative API-path evidence, not pure native-kernel
  ratios. The audio WAV conversion is specifically not equivalent, as described above.
- Several formats have multiple fixtures or codec variants. The report uses one representative
  per supported image/audio/video extension, one 640 × 360 sample per video container, all PDFs,
  and four fonts. Larger images, full audio files, all video codec profiles, long playback,
  document interaction and UI first-content latency remain unmeasured.

The seven raw timing samples for the Windows comparisons are preserved in
[`measurements.json`](measurements.json). SVG phase medians remain in the linked `.057` entry. The
Filesamples catalogue records each source URL and SHA-256; benchmark inputs are not copied into
this repository.

## Raster decode follow-up on Linux

The Release `Pixel.Image.load` comparison used the same compiler for baseline `335b91f31e` and
the modified decoder sources. Each implementation warmed up before timing. The table gives
medians of 21 samples per implementation, taken in rotating order on one pinned CPU of an Intel
Xeon Platinum 8573C. ImageMagick 7.1.1-43 Q16-HDRI read and exported RGBA8 for integer files and
RGBF32 for EXR, with its thread limit set to one. The decoded CRC64, dimensions, and Pixel format
matched for every baseline and candidate decode.

| Fixture | Swag before (ms) | Swag after (ms) | ImageMagick (ms) | Swag speedup |
| --- | ---: | ---: | ---: | ---: |
| EXR, 640 × 426 | 48.14 | 2.06 | 9.26 | 23.4× |
| GIF, 640 × 426 | 21.67 | 5.58 | 11.43 | 3.9× |
| WebP, 4275 × 2451 | 599.49 | 319.61 | 381.36 | 1.9× |

All three images match the reported byte sizes and dimensions. The follow-up used `sample.exr`
(`617ff98fb0a1f3b9da819fb9ac8d4af1f75bb4cf9b46dfb881af011bbe176752`), `sample.gif`
(`eb04e3ff38fc7ecba1f7715ca7dae26b24e03766dc7c43ddeec75d5f1af74acd`), and `sample.webp`
(`c90994e27f7e26c6b3a94e8a4ebf2ccd46b974852ef3eaf3686d2270cf340abf`). The files came from the
[Image Extension Dataset mirror](https://github.com/Shin-Aska/image-extension-dataset/tree/501d37367cceafbeaa0aff739ec29cc1d8c1dd2f/files).

## Second raster decode pass on Linux

The second Release `Image.load` comparison used `ede61bc32f` as its baseline. The elapsed
times below are medians of 21 warmed, interleaved repetitions on a pinned CPU of the same Xeon
8573C host. Pixel format, dimensions, and CRC64 matched on every repetition. The two QOI
controls were encoded from a flat color and the FileSamples PNG.

| Fixture | Swag before (ms) | Swag after (ms) |
| --- | ---: | ---: |
| `sample.bmp` | 0.133 | 0.133 |
| `sample.tga` | 0.134 | 0.145 |
| `sample.ico` | 0.150 | 0.035 |
| `sample.psd` | 0.847 | 0.469 |
| Flat QOI | 2.097 | 0.199 |
| Photo QOI | 5.250 | 4.693 |
| `sample.exr` | 1.251 | 0.370 |
| `sample.gif` | 3.580 | 2.234 |
| `sample.tiff` | 0.695 | 0.096 |
| `sample.jpg` | 4.398 | 2.102 |
| `sample.jfif` | 3.972 | 2.454 |
| `sample.png` | 5.227 | 5.317 |
| `sample.webp` | 230.482 | 203.265 |

On `sample.webp`, 16 alternating thread CPU measurements gave 316.147 to 296.169 ms, with the
same decoded CRC64. Five lossy VP8 controls used 11–17% less CPU time. The small VP8L control
stayed near 0.27 ms. PNG's interlaced RGB8 control went from 10.515 to 10.036 ms, and RGB16
went from 17.751 to 17.308 ms in a separate 41-pair trial. Inflate accounted for about 85% of
the sampled FileSamples PNG decode. The BMP and TGA bulk-copy trials had no repeatable gain.

The baseline executable repeated the first block row of `sample.dds`. The revised BC1 decode
matches ImageMagick's RGBA output byte for byte. For a comparison at equal output, changing
only source block addressing in the baseline gave 3.577 ms, versus 1.518 ms for the revised
kernel. A KTX2 control containing the same BC1 blocks went from 3.387 to 1.510 ms. The timed
DDS and KTX2 outputs matched that corrected baseline, as did five small BC1–BC5 controls.

## Raster decode with varied fixtures on Linux

The next Release comparison used `c0fa4362c2` as the baseline and `b86060795a` as the
candidate. The [raster decode workload](../../workloads/rasterdecode/README.md) includes a corpus
generator and records fixture SHA-256, pixel checksums, and raw samples. The table uses seven
warmed, interleaved elapsed samples per implementation on a pinned Xeon Platinum 8573C CPU.
The Swag builds produced the same dimensions, format, and pixel CRC64 on these cases. The
MagickWand reference is ImageMagick 7.1.1-43 Q16-HDRI. The optional still WebP reference is
libwebp 1.5.0 with `WebPDecodeRGBAInto` and its default color conversion.

| Fixture | Swag before (ms) | Swag after (ms) | ImageMagick (ms) | libwebp (ms) |
| --- | ---: | ---: | ---: | ---: |
| FileSamples PSD RGB8 | 0.477 | 0.206 | 6.089 | |
| Raw PSD gray16, 1023 × 677 | 1.299 | 0.276 | 33.010 | |
| Raw PSD RGBA8, 1601 × 1073 | 1.987 | 1.422 | 34.910 | |
| PNG palette with transparency, 1152 × 768 | 3.796 | 3.275 | 25.329 | |
| PNG RGB16 Adam7, 639 × 425 | 12.090 | 11.969 | 19.045 | |
| Two-frame GIF, first image | 9.153 | 1.765 | 6.504 | |
| Transparent GIF, 1537 × 1025 | 58.293 | 10.209 | 37.784 | |
| TIFF gray LZW with predictor, 2051 × 1549 | 19.464 | 9.922 | 24.359 | |
| TIFF RGB LZW, 2051 × 1549 | 102.659 | 74.227 | 125.710 | |
| FileSamples JPEG | 2.349 | 2.326 | 4.798 | |
| JPEG 4:2:0, 4275 × 2451 | 48.507 | 43.589 | 203.635 | |
| Progressive JPEG, 4275 × 2451 | 165.764 | 155.176 | 249.498 | |
| JPEG CMYK, 1024 × 587 | 14.775 | 10.628 | 19.492 | |
| Lossless WebP interface, 1280 × 800 | 30.680 | 23.749 | 17.869 | 7.466 |
| Lossless WebP photo, 1254 × 1254 | 77.348 | 60.640 | 47.704 | 29.439 |
| Lossless WebP photo, 4275 × 2451 | 419.373 | 309.495 | 343.684 | 165.146 |
| Lossy WebP with compressed alpha, 1921 × 1081 | 73.119 | 63.941 | 50.662 | 22.912 |

The PNG palette gain repeated in a 19-pair run, from 5.235 to 3.775 ms. The FileSamples PNG
and APNG were close in that run. The grain PNG showed a small elapsed slowdown, from 20.648
to 21.215 ms, while a separate CPU-time profile showed a gain. A 21-pair retest with and without
the shared Inflate change returned matching CRC64 values and mixed timings on five PNGs.

A separate seven-pair run measured libjpeg-turbo 2.1.5 directly. The reference opened each
file with `jpeg_stdio_src` and materialized the full image in BGR8. This avoids the ImageMagick
wrapper and export overhead. The native library and Swag use their own chroma reconstruction.

| Fixture | Swag (ms) | libjpeg-turbo (ms) |
| --- | ---: | ---: |
| FileSamples JPEG | 2.131 | 1.927 |
| JPEG 4:2:0, 4275 × 2451 | 43.555 | 45.666 |
| JPEG 4:4:4, 4275 × 2451 | 67.442 | 61.997 |
| Progressive JPEG, 4275 × 2451 | 162.407 | 117.843 |

The previous EXR ZIP decoder reversed the byte predictor after deinterleaving and rejected raw
blocks stored under ZIPS compression. OpenEXR reverses the predictor before restoring byte order.
OpenEXR 3.1.13 verified both cases. The ZIP timings
below use a scalar baseline with the order and stored-block handling corrected, so the two Swag
outputs are identical. These EXR elapsed times come from a separate nine-pair run with the same
MagickWand version.

| EXR fixture | Swag before (ms) | Swag after (ms) | ImageMagick (ms) |
| --- | ---: | ---: | ---: |
| RGB FLOAT, uncompressed, 319 × 207 | 0.694 | 0.251 | 1.883 |
| RGBA FLOAT, uncompressed, 319 × 207 | 0.960 | 0.213 | 2.567 |
| RGBA HALF ZIP, 1024 × 513 | 74.256 | 9.802 | 80.999 |
| RGBA FLOAT ZIP | 22.642 | 7.318 | 10.827 |

ImageMagick rejected the 1 × 3 ZIPS fixture with stored rows. The native OpenEXR reference
decoded it correctly at 30.5 µs of CPU time, compared with 18 µs for Swag.

## Fourth raster decode pass on Linux

The Release `Image.load` measurements compare `b31d712f65` with the raster changes through
`cc5407d2f9`. Each elapsed median uses nine warmed samples per implementation in rotating
order on a pinned Xeon Platinum 8573C CPU. The
[raster decode workload](../../workloads/rasterdecode/README.md) records input SHA-256 and
verified identical dimensions, pixel formats, and CRC64 values on all 49 inputs. The native
comparisons use libjpeg-turbo 2.1.5, libpng 1.6.48, and libwebp 1.5.0. The full image export comparison
uses ImageMagick 7.1.1-43 Q16-HDRI. The reference libraries use their own color conversion.

| Fixture | Swag before (ms) | Swag after (ms) | Native library (ms) | ImageMagick (ms) |
| --- | ---: | ---: | ---: | ---: |
| FileSamples JPEG | 2.271 | 2.205 | 2.009 | 5.319 |
| Progressive JPEG 4:2:0, 4275 × 2451 | 206.922 | 145.539 | 160.163 | 352.070 |
| Progressive JPEG 4:4:4, 1601 × 907, quality 94 | 60.520 | 47.003 | 44.576 | 60.944 |
| Progressive grayscale JPEG | 30.841 | 23.425 | 23.256 | 46.487 |
| Sequential JPEG 4:4:4, 4275 × 2451 | 69.305 | 70.222 | 64.999 | 238.213 |
| FileSamples PNG | 6.108 | 5.266 | 6.871 | 11.037 |
| Grain PNG, 1152 × 768 | 24.422 | 20.167 | 27.760 | 44.873 |
| Grain PNG, 1801 × 1199 | 54.056 | 47.021 | 55.200 | 89.676 |
| PNG palette with transparency, 1152 × 768 | 4.853 | 4.571 | 9.705 | 40.387 |
| APNG, default image | 8.228 | 7.315 | 9.691 | 16.999 |
| FileSamples lossy WebP | 210.641 | 208.632 | 96.499 | 309.274 |
| VP8L photo, 4275 × 2451 | 338.837 | 259.232 | 176.939 | 391.583 |
| VP8L photo, 1254 × 1254 | 66.845 | 56.922 | 31.249 | 52.856 |
| VP8L interface, 1280 × 800 | 27.019 | 16.701 | 8.603 | 18.405 |
| VP8 with compressed alpha, 1921 × 1081 | 101.575 | 71.080 | 33.914 | 77.120 |

A seven-sample repeat for the largest progressive JPEG gave 193.373 ms before and 135.380 ms
after, with libjpeg-turbo at 120.899 ms. Swag's gain held in both runs, and the relative order
with libjpeg-turbo varied. PNG's smaller 48-color palette fixture was retested in 60 rotating
blocks on each of two cores. Its median was within 3% of the baseline on both cores.
The RGB16 Adam7 control was 16.596 to 17.404 ms elapsed in the broad run. A 36-block
follow-up measured 12.185 to 11.490 ms. The isolated Inflate change reduced its thread CPU
time from 17.076 to 16.066 ms.

| Fixture | Swag before (ms) | Swag after (ms) | ImageMagick (ms) |
| --- | ---: | ---: | ---: |
| TIFF gray LZW with predictor, 2051 × 1549 | 11.991 | 1.950 | 33.029 |
| TIFF RGB LZW with predictor, 2051 × 1549 | 104.579 | 82.309 | 109.221 |
| TIFF RGBA LZW with predictor, noisy image | 18.658 | 13.308 | 23.650 |
| TIFF RGB PackBits | 2.911 | 3.003 | 38.280 |
| Raw PSD gray+alpha, 16-bit, 2561 × 1441 | 12.510 | 3.385 | 212.435 |
| Raw PSD RGB16, 2561 × 1441 | 19.181 | 5.001 | 84.377 |
| Raw PSD RGBA16, 2561 × 1441 | 25.782 | 7.089 | 150.061 |
| EXR RGB, mixed HALF/FLOAT, 641 × 253 | 1.519 | 0.478 | 2.975 |
| EXR RGBA, mixed HALF/FLOAT, 1279 × 401 | 5.876 | 1.572 | 14.915 |
| EXR RGBA HALF ZIP, 1024 × 513 | 4.549 | 3.826 | 24.732 |

The raw PSD inputs use seeded sample planes and odd row widths. OpenEXR 3.5.5 independently
verified the complete FLOAT pixel buffers of six mixed EXRs, including ZIP, NaNs and
subnormals. The independent Python OpenEXR read plus NumPy interleave took 7.030 ms for the
1279 × 401 fixture.

The animation comparison decodes and composes every frame. Swag uses `ImageReader.read` and
Pillow 12.3 uses `seek`, `convert("RGBA")`, and `tobytes()`. Each elapsed median uses seven
rotating samples. The two Swag builds and Pillow produced the same full RGBA8 byte stream
for both fixtures.

| All frames | Swag before (ms) | Swag after (ms) | Pillow 12.3 (ms) |
| --- | ---: | ---: | ---: |
| GIF, 1021 × 767, 12 frames | 118.260 | 16.743 | 62.077 |
| APNG, 97 × 63, 7 frames with binary alpha | 2.269 | 0.889 | 2.332 |

The GIF input SHA-256 is `16a926170a7608c0a4c7c20d0bb5d4f88d8ac40bd5fb733b0c4905d05574deea`.
The APNG input SHA-256 is `fb8ad92d6a4d2674d9cf41673cb3b04bbe6de7ec0dc9cbf30bb5feea084cbddd`.

### WebP predictor spans

Commit `0d92eb5688` selects each predictor once per tile row and reconstructs left and top
predictor spans with SIMD. This follow-up compares it with the already optimized build
through `cc5407d2f9` in nine rotating samples per implementation. All nine inputs had matching
Swag pixel checksums. Elapsed times vary between the two runs. The table uses the baselines
and references measured alongside this patch.

| Fixture | Swag before spans (ms) | Swag with spans (ms) | libwebp (ms) | ImageMagick (ms) |
| --- | ---: | ---: | ---: | ---: |
| VP8L photo, 4275 × 2451 | 378.680 | 359.871 | 227.311 | 493.605 |
| VP8L photo, 1254 × 1254 | 81.561 | 75.196 | 41.051 | 64.742 |
| VP8L interface, 1280 × 800 | 24.277 | 21.449 | 11.618 | 27.619 |
| VP8L interface with alpha, 600 × 401 | 5.457 | 4.592 | 2.649 | 6.845 |
| VP8 with compressed alpha, 1921 × 1081 | 69.482 | 65.135 | 32.966 | 70.643 |
| VP8 with indexed alpha, 400 × 301 | 3.952 | 3.997 | 1.878 | 4.496 |
| FileSamples opaque VP8 | 298.471 | 299.539 | 142.243 | 401.082 |
| VP8L from the expanded corpus, 1009 × 673 | 35.074 | 33.331 | 22.387 | 32.887 |
| VP8 with gradient alpha, 1281 × 847 | 42.651 | 43.596 | 23.634 | 45.366 |
