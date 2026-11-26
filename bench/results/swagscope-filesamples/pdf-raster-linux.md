# CPU PDF raster comparison on Linux

The corpus adds 26 public PDFs from Mozilla PDF.js and Apache PDFBox to the three original
FileSamples documents. It covers 31 pages across 29 files, with selected later pages from a
research paper. The public fixtures can be fetched by upstream revision and checked by SHA-256.
[Benchmark and fixture manifest](../../workloads/pdfraster/README.md)

On 2026-11-26 both engines ran on one logical AMD EPYC 7763 CPU. Swag used its Release CPU bitmap renderer.
PDFium 159.0.8149.0 used its default AGG backend through pypdfium2 5.15.2. Both reopened the
document, loaded the selected page, and rendered it to an opaque BGRA bitmap. The timed render
includes bitmap allocation and initialization. The suite measures five interleaved samples
after warm-up at 1200 px and on four pages at 2400 px. The two-scan check uses 14 samples.
The baseline was `740046dbe4`. The candidate applied the packed grayscale change
from `cc38f29c01` to the same snapshot. The Swag dimensions, item counts, and bitmap CRC-32
match between builds in all recorded cases.
[Raw 1200 px timings](pdf-raster-linux.json) · [Raw 2400 px timings](pdf-raster-linux-2400.json) · [Raw two-scan timings](pdf-raster-linux-bilevel.json)

## Where the time goes

- **Image loading.** The 2550 × 3300 one-bit grayscale PDF.js scan ran Swag's generic floating-point
  sample conversion 8,415,000 times. Reusing the SIMD unpack and grayscale expansion drops Swag's
  load from 332.63 to 30.64 ms and its total from 422.34 to 121.15 ms. PDFium takes
  25.94 ms end to end. On `sample1.pdf`, Swag loads full JPEG images and masks during page
  loading. Compare the end-to-end totals because PDFium can decode the same images during rendering.
  [Swag PDF image decode](../../../bin/std/modules/gui/src/controls/pdf/decode.image.swg) · [PDFium JPEG scanline decoder](https://github.com/chromium/pdfium/blob/main/core/fxcodec/jpeg/jpegmodule.cpp)
- **Image rendering.** On `pdfbox-jpeg.pdf`, Swag spends 0.99 ms loading the page and
  35.43 ms rendering it. A diagnostic build attributed around 34 ms to the textured
  triangle draws, with negligible image recording
  and texture upload. The PDFBox scan is a second case where painting the scaled image dominates.
  The Swag sampler interpolates triangle coordinates and samples the image per output pixel.
  PDFium's AGG image path has an axis-aligned stretch engine with separate horizontal and vertical
  weights and scanline composition.
  [Swag CPU rasterizer](../../../bin/std/modules/pixel/src/render/cpu/rendercpu.swg) · [PDFium AGG image path](https://github.com/chromium/pdfium/blob/main/core/fxge/agg/cfx_agg_devicedriver.cpp) · [PDFium stretch engine](https://github.com/chromium/pdfium/blob/main/core/fxge/dib/cstretchengine.cpp)
- **Vector paths and clips.** The curves stress page submits about 3.15 million Swag triangles.
  A probe spent roughly 0.8 s recording paths and 0.9 s accumulating their stroke coverage.
  On the clips page, Swag's load takes 172.62 ms versus PDFium's 7.29 ms. Swag flattens and
  intersects nested clips during load, tessellates their paths during recording, and writes
  stencil coverage while rendering. AGG
  composites coverage spans from its path rasterizer. Subpixel dashes on `sample3.pdf`
  also generate stroke triangles before the rasterizer can reject empty coverage.
  [Swag clip decoding](../../../bin/std/modules/gui/src/controls/pdf/decode.swg) · [PDFium AGG path drawing](https://github.com/chromium/pdfium/blob/main/core/fxge/agg/cfx_agg_devicedriver.cpp)
- **Text.** `sample3.pdf` has 937 Swag text items and 142 PDFium text objects. Swag emits separate
  items for strings inside `TJ` arrays and rebuilds a CPU glyph atlas per bitmap render.
  The transformed-text stress page isolates the raster cost. In the probe, MSDF triangle
  draws took around 0.79 s out of 0.95 s of replay. PDFium can cache FreeType glyph masks
  and composite the masks directly. SIMD speeds up the existing kernels, while these
  differences in the amount and type of work remain.
  [Swag page recording and bitmap render](../../../bin/std/modules/gui/src/controls/pdf/render.swg) · [PDFium text rendering](https://github.com/chromium/pdfium/blob/main/core/fxge/cfx_renderdevice.cpp)

## 1200 px results

Times are medians in milliseconds. Each total is the median of the per-sample sums.
The ratios across the 27 cases below with a reported ratio range from 1.15× to
31.51×, with a median of 3.58×. The mixed-CMap and tiling
pattern fixtures render white in Swag. The Type 3 and transparency soft-mask pages show large
ink coverage differences. Their timings are listed without speed ratios. The ink counts
come from a coarse grid, so the other ratios remain timing measurements with visual parity
unverified.

| PDF | Page | Swag open | Swag load | Swag render | Swag total | PDFium open | PDFium load | PDFium render | PDFium total | Ratio |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `sample1.pdf` | 1 | 0.44 | 13.71 | 36.39 | 50.43 | 0.33 | 2.26 | 22.16 | 24.96 | 2.02× |
| `sample2.pdf` | 1 | 0.18 | 2.50 | 12.35 | 15.01 | 0.10 | 0.79 | 3.45 | 4.34 | 3.46× |
| `sample3.pdf` | 1 | 0.96 | 6.70 | 37.31 | 45.06 | 0.31 | 5.16 | 6.53 | 11.99 | 3.76× |
| `pdfbox-tiger.pdf` | 1 | 0.15 | 1.99 | 77.87 | 79.99 | 0.14 | 2.92 | 10.42 | 13.43 | 5.96× |
| `pdfbox-jpeg.pdf` | 1 | 0.12 | 0.99 | 35.43 | 37.81 | 0.05 | 0.04 | 2.81 | 2.89 | 13.07× |
| `pdfbox-ligatures.pdf` | 1 | 0.15 | 1.03 | 7.16 | 8.37 | 0.15 | 0.88 | 2.08 | 3.15 | 2.66× |
| `pdfbox-rotation.pdf` | 1 | 0.13 | 0.11 | 4.28 | 4.55 | 0.19 | 0.35 | 0.61 | 1.27 | 3.58× |
| `pdfbox-scan.pdf` | 1 | 0.12 | 0.37 | 49.79 | 50.36 | 0.05 | 0.04 | 1.46 | 1.60 | 31.51× |
| `tracemonkey.pdf` | 1 | 0.75 | 2.74 | 15.56 | 18.99 | 0.22 | 3.76 | 6.01 | 9.96 | 1.91× |
| `tracemonkey.pdf` | 6 | 0.68 | 3.79 | 18.52 | 23.01 | 0.26 | 9.79 | 7.08 | 17.12 | 1.34× |
| `tracemonkey.pdf` | 9 | 0.82 | 2.69 | 11.98 | 15.67 | 0.21 | 2.65 | 5.62 | 8.69 | 1.80× |
| `perf_paths_operators.pdf` | 1 | 0.30 | 16.49 | 299.95 | 315.71 | 0.08 | 12.97 | 54.62 | 67.29 | 4.69× |
| `perf_paths_polygons.pdf` | 1 | 0.36 | 23.30 | 359.49 | 383.11 | 0.10 | 19.71 | 83.93 | 103.13 | 3.71× |
| `perf_paths_curves.pdf` | 1 | 0.30 | 13.12 | 1784.90 | 1798.32 | 0.14 | 14.89 | 245.38 | 258.94 | 6.95× |
| `perf_paths_map.pdf` | 1 | 0.25 | 11.66 | 352.04 | 364.19 | 0.08 | 11.99 | 96.68 | 109.35 | 3.33× |
| `perf_paths_hairlines.pdf` | 1 | 0.25 | 29.10 | 241.67 | 272.18 | 0.09 | 17.29 | 93.76 | 110.72 | 2.46× |
| `perf_paths_clips.pdf` | 1 | 0.36 | 172.62 | 405.64 | 575.57 | 0.08 | 7.29 | 34.53 | 42.14 | 13.66× |
| `perf_text_cmap_mixed.pdf` | 1 | 0.16 | 2.16 | 2.63 | 5.00 | 0.07 | 3.66 | 7.09 | 10.82 | — |
| `perf_text_transformed.pdf` | 1 | 0.23 | 5.21 | 1003.60 | 1008.46 | 0.13 | 4.85 | 169.31 | 175.18 | 5.76× |
| `perf_text_type3_vector.pdf` | 1 | 0.14 | 0.70 | 44.63 | 46.06 | 0.12 | 1.50 | 36.85 | 38.45 | — |
| `perf_images_jpeg_large.pdf` | 1 | 0.56 | 68.79 | 86.42 | 155.46 | 0.08 | 0.26 | 98.35 | 98.64 | 1.58× |
| `perf_images_jpeg_thumbnails.pdf` | 1 | 0.48 | 40.64 | 94.60 | 135.83 | 0.16 | 1.39 | 65.81 | 67.36 | 2.02× |
| `perf_images_repeated.pdf` | 1 | 0.12 | 14.70 | 93.30 | 109.68 | 0.07 | 1.87 | 93.12 | 95.42 | 1.15× |
| `perf_images_scan_gray.pdf` | 1 | 0.72 | 51.88 | 83.40 | 135.50 | 0.09 | 1.30 | 32.24 | 33.56 | 4.04× |
| `perf_images_scan_bilevel.pdf` | 1 | 0.17 | 30.40 | 85.55 | 116.10 | 0.10 | 0.95 | 24.34 | 25.40 | 4.57× |
| `perf_images_flate_predictor.pdf` | 1 | 1.22 | 73.38 | 90.35 | 168.04 | 0.08 | 0.41 | 44.95 | 45.41 | 3.70× |
| `perf_images_smask.pdf` | 1 | 0.90 | 30.53 | 108.52 | 140.03 | 0.08 | 0.47 | 42.63 | 43.22 | 3.24× |
| `perf_structure_forms.pdf` | 1 | 0.30 | 52.67 | 361.73 | 413.43 | 0.14 | 47.56 | 112.66 | 160.44 | 2.58× |
| `perf_transparency_blend_modes.pdf` | 1 | 0.34 | 11.36 | 372.23 | 390.09 | 0.09 | 5.80 | 80.93 | 90.15 | 4.33× |
| `perf_transparency_soft_masks.pdf` | 1 | 0.22 | 758.19 | 149.31 | 900.88 | 0.08 | 0.34 | 90.10 | 90.49 | — |
| `perf_patterns_tiling_images.pdf` | 1 | 0.08 | 0.30 | 2.45 | 2.87 | 0.13 | 0.41 | 30.19 | 31.80 | — |

## 2400 px results

| PDF | Page | Swag open | Swag load | Swag render | Swag total | PDFium open | PDFium load | PDFium render | PDFium total | Ratio |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `sample1.pdf` | 1 | 0.44 | 15.14 | 121.12 | 137.34 | 0.33 | 2.51 | 36.90 | 39.90 | 3.44× |
| `sample2.pdf` | 1 | 0.18 | 2.50 | 48.04 | 51.00 | 0.08 | 0.78 | 7.14 | 8.06 | 6.33× |
| `sample3.pdf` | 1 | 0.96 | 6.94 | 75.20 | 83.15 | 0.33 | 4.82 | 10.03 | 15.17 | 5.48× |
| `pdfbox-jpeg.pdf` | 1 | 0.13 | 0.84 | 152.58 | 153.68 | 0.05 | 0.05 | 5.95 | 6.05 | 25.41× |

## Direct CPU scan conversion of PDF paths

The CPU painter can now record closed contours for antialiased solid fills and clips.
A solid single-segment stroke with flat ends records its four outline points. During
replay, the CPU renderer resolves winding and fractional coverage with the same
scan converter used by SVG, then composites directly into the bitmap or the clip
mask. Coverage buffers are reused across draws. The row writer visits the
horizontal interval of the crossings.

The comparison used Release builds on one logical AMD EPYC 7763 CPU, with
`b031932f1c` as the baseline and PDFium 159.0.8149.0 as the reference.
Both engines rendered a 1200 px long side. Each value below is a median in
milliseconds from five interleaved measurements following warm-up. The full
31-case corpus was also rerun with three interleaved measurements per case.
[Raw before, after, and PDFium data](pdf-raster-linux-scanlines.json)

| Page | Swag before | Swag scanlines | PDFium | Swag render before | Swag render scanlines | PDFium render |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `sample3.pdf` | 42.75 | 44.60 | 10.84 | 35.05 | 36.33 | 5.77 |
| `pdfbox-tiger.pdf` | 85.54 | 32.99 | 13.59 | 82.09 | 30.86 | 10.41 |
| `perf_paths_polygons.pdf` | 256.64 | 139.67 | 107.16 | 231.27 | 113.63 | 79.12 |
| `perf_paths_map.pdf` | 368.46 | 337.75 | 104.17 | 356.51 | 324.58 | 93.64 |
| `perf_paths_hairlines.pdf` | 275.48 | 136.24 | 112.43 | 245.93 | 104.74 | 96.17 |
| `perf_paths_clips.pdf` | 666.94 | 214.77 | 37.05 | 463.20 | 43.10 | 30.09 |

The clip fixture spends about 170 ms loading the revised Swag page. Nested clips
still flatten and intersect contours before recording. PDFium loads it in 7 ms.
On the full run, the forms fixture dropped from 594 to 306 ms end to end, with
PDFium at 166 ms. The curves fixture is dominated by multi-segment and dashed
strokes. Its Swag raster checksum matched the baseline and its total stayed
around 1.6–1.7 seconds, against 255 ms for PDFium.

Scan coverage changes the antialiasing on some edges. Across ten inspected pages,
the mean absolute difference per 8-bit RGB channel from PDFium decreased or stayed
within 0.01 levels. On the polygons it moved from 3.67 to 3.53, on the hairlines
from 30.87 to 22.69, and on the map from 34.63 to 7.80. The map changes coverage
on 34.91% of pixels. The three FileSamples change coverage or color on 0.13–1.46%
of pixels, with total timings similar to the baseline. All six generated SVG
benchmark fixtures kept their Swag CRC-64.

## Nested clips in device space

The decoder retains the authored shapes and their parents. The opaque CPU bitmap
path intersects their filled intervals at the four vertical sample positions,
then resolves coverage once. The polygon fallback is materialized on demand for
textured clips, transparent bitmap output and the general painter. Interior
coverage accumulation, color blending and writing the intersected clip mask
process four pixels at a time with SIMD.

These are Release medians of 14 interleaved measurements on one AMD EPYC 7763
logical CPU, against Swag `838d348519` and PDFium 159.0.8149.0. Each measurement
reopens and renders the clip fixture into a BGRA bitmap. Times are milliseconds.
[Raw phase timings, full corpus and RGB measurements](pdf-raster-linux-nested-clips.json)

| Long side | Previous load | Swag load | PDFium load | Previous total | Swag total | PDFium total |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 600 | 194.82 | 7.43 | 7.07 | 218.95 | 31.53 | 22.38 |
| 1200 | 189.27 | 7.52 | 7.36 | 244.36 | 54.46 | 42.73 |
| 2400 | 178.25 | 7.17 | 6.98 | 314.85 | 110.51 | 97.05 |

Comparing the new coverage kernels with the same intersection code using scalar
composition took the 1200 px clip fixture from 59.43 to 50.06 ms and the
polygons fixture from 139.24 to 116.61 ms, with PDFium at 41.19 and 106.97 ms
in that interleaved run. The three pages in that comparison kept their Swag
CRC-32 after SIMD. All 31 cases in the full corpus kept their CRC-32 after SIMD.
Compared with the published baseline, 30 of 31 pages kept their CRC-32.
Only the nested-clip fixture changed. Its mean absolute 8-bit RGB difference
from PDFium was 3.0642 before and 3.0618 after at 1200 px. The mean difference
also decreased at 600 and 2400 px.
