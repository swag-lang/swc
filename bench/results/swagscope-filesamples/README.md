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

Times are below 0.2 ms and mixed; this is not a current optimization lead without a larger font
corpus and a character-map or page-level workload.

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

The seven raw timing samples for this report's new comparisons are preserved in
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
