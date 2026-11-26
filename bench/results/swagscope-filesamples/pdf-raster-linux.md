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

## Axis-aligned image resampling

On opaque CPU bitmaps, Swag computes bilinear coordinates by axis for large
axis-aligned texture spans. It reuses column indices and weights across the scan
lines and caches horizontally filtered source rows for enlargements. The
existing quantized horizontal and vertical color interpolation is applied
to those separable samples.

The corpus now has 41 files and 44 cases. The 12 additional public files
cover progressive grayscale JPEG, CMYK, long-axis JPEG downscaling,
inline and indexed rasters, one-bit and sixteen-bit samples, image masks,
and real publication pages. Swag rejects `cmykjpeg.pdf` during load because
its four-component JPEG uses 2 × 2 sampling. That page has a PDFium timing
and no Swag timing. The supported CMYK stress page has a mean RGB difference
of around 20 levels from PDFium, so its timing needs that fidelity context.

Release builds used one logical AMD EPYC 7763 CPU, with `d9bfeae85f` as
the Swag baseline and PDFium 159.0.8149.0 as the reference. Times are
medians in milliseconds from ten interleaved measurements at 1200 px and
five at 2400 px. The full corpus uses three measurements per case.
[Raw timings and RGB measurements](pdf-raster-linux-image-spans.json)

| PDF | Long side | Swag before | Swag after | PDFium | Render before | Render after | PDFium render |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `sample1.pdf` | 1200 | 60.93 | 45.57 | 29.30 | 44.32 | 30.83 | 26.24 |
| `sample2.pdf` | 1200 | 16.16 | 12.34 | 4.72 | 13.29 | 9.62 | 3.81 |
| `sample3.pdf` | 1200 | 41.83 | 41.24 | 11.59 | 33.96 | 33.37 | 6.32 |
| `pdfbox-jpeg.pdf` | 1200 | 37.95 | 12.12 | 4.08 | 36.95 | 11.18 | 3.95 |
| `pdfbox-scan.pdf` | 1200 | 46.36 | 10.81 | 1.74 | 45.97 | 10.25 | 1.65 |
| `perf_images_jpeg_large.pdf` | 1200 | 155.29 | 107.24 | 110.99 | 85.60 | 36.21 | 110.43 |
| `perf_images_scan_gray.pdf` | 1200 | 141.16 | 81.82 | 41.84 | 88.07 | 31.35 | 40.45 |
| `large_jpeg_downscale.pdf` | 1200 | 117.22 | 77.83 | 70.34 | 38.98 | 18.99 | 70.15 |
| `pdfbox-jpeg.pdf` | 2400 | 145.68 | 39.99 | 6.12 | 144.70 | 38.86 | 6.01 |
| `pdfbox-scan.pdf` | 2400 | 180.95 | 39.97 | 5.67 | 180.53 | 39.47 | 5.57 |
| `perf_images_jpeg_large.pdf` | 2400 | 425.85 | 238.34 | 124.81 | 335.07 | 152.45 | 124.27 |
| `perf_images_scan_gray.pdf` | 2400 | 391.17 | 201.46 | 50.72 | 326.28 | 128.83 | 49.42 |

Separable coordinates change float rounding before the existing fixed-width
color lerps. Across the 20 pixel comparisons, the maximum channel delta was
2 levels out of 255 and the largest per-case mean absolute RGB change
was 0.0165. The focused Pixel regression exercises clamped samples,
straight-alpha composition and mirroring on both axes.

## Joined and dashed stroke spans

The opaque CPU bitmap painter converts the bodies, joins and caps of an eligible
stroke to consistently wound contours. It merges their covered intervals before
blending the stroke. The existing dash walker retains the dash placement and cap
sizes. At a self-intersection, translucent ink is composited once. A flat
one-segment stroke still uses its four-edge recording path.

PDFium's AGG path driver also passes complete stroked contours to its scanline
rasterizer, which accumulates subpixel cell area. Swag integrates four vertical
samples and still builds all the dash bodies and joins, leaving more work on dense
artwork. [PDFium path driver](https://github.com/chromium/pdfium/blob/main/core/fxge/agg/cfx_agg_devicedriver.cpp)

These one-core Release medians use five interleaved measurements at 1200 and
2400 px against Swag `8890aed342` and PDFium 159.0.8149.0. The flat
hairline recheck uses ten pairs of two samples. Times are milliseconds.
[Phase timings, corpus and RGB measurements](pdf-raster-linux-joined-strokes.json)

| PDF | Long side | Swag before | Swag after | PDFium | Render before | Render after | PDFium render |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `sample1.pdf` | 1200 | 46.99 | 43.27 | 26.93 | 30.42 | 28.90 | 24.34 |
| `sample2.pdf` | 1200 | 11.63 | 11.21 | 4.48 | 8.98 | 8.71 | 3.67 |
| `sample3.pdf` | 1200 | 42.72 | 35.82 | 11.70 | 35.12 | 27.86 | 6.33 |
| `pdfbox-tiger.pdf` | 1200 | 29.59 | 25.72 | 13.54 | 27.45 | 23.53 | 10.52 |
| `perf_paths_operators.pdf` | 1200 | 188.64 | 125.76 | 71.97 | 173.29 | 108.14 | 56.99 |
| `perf_paths_curves.pdf` | 1200 | 1530.54 | 897.77 | 342.88 | 1517.24 | 874.74 | 320.59 |
| `perf_paths_map.pdf` | 1200 | 290.34 | 208.26 | 142.85 | 276.18 | 191.99 | 130.82 |
| `sample3.pdf` | 2400 | 74.78 | 68.44 | 14.42 | 67.05 | 59.70 | 9.44 |
| `perf_paths_curves.pdf` | 2400 | 2731.97 | 1806.67 | 626.39 | 2718.57 | 1792.61 | 614.58 |
| `perf_paths_map.pdf` | 2400 | 511.23 | 339.88 | 203.83 | 498.46 | 328.54 | 193.30 |
| `perf_paths_hairlines.pdf` | 1200 | 151.24 | 154.45 | 147.26 | 117.06 | 120.80 | 129.90 |

Of 43 supported cases in the full corpus, 33 retained their Swag CRC-32.
On the dense curves at 1200 px, 40.91% of pixels changed, and mean absolute
RGB error from PDFium decreased from 16.55 to 15.46 out of 255. The map,
PDF operators page and tiger also moved closer to PDFium at both sizes.
Across the original FileSamples pages at 1200 px, fewer than 0.62% of pixels
changed on each page. The mean difference from PDFium fell on `sample1.pdf`
and rose by 0.003 and 0.035 on `sample2.pdf` and `sample3.pdf`, respectively.
The flat hairline fixture matched pixel for pixel at both sizes. The focused
painter test covers a crossing translucent stroke and round-capped dashes.

## Indexed image decoding

Swag converts each palette entry to RGB once per image. Packed samples up
to eight bits use a table that accounts for the image's Decode array, and
sixteen-bit indexed samples share the converted palette. Color-key masks
still compare the original packed values.

These one-core Release medians use seven interleaved measurements at
each size. Both Swag builds have the joined stroke changes. PDFium
159.0.8149.0 defers most image work until render, so compare the totals
across engines. Times are milliseconds.
[Phase timings and corpus checksums](pdf-raster-linux-indexed-decode.json)

| PDF | Page | Long side | Swag before | Swag after | PDFium | Load before | Load after | PDFium load |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `perf_images_indexed.pdf` | 1 | 1200 | 389.32 | 54.56 | 33.66 | 356.29 | 20.00 | 0.13 |
| `perf_structure_colorspace_images.pdf` | 1 | 1200 | 96.33 | 95.98 | 85.99 | 65.08 | 65.58 | 0.70 |
| `pdfbox-survey.pdf` | 1 | 1200 | 25.98 | 20.32 | 10.02 | 11.41 | 5.68 | 4.93 |
| `pdfbox-survey.pdf` | 5 | 1200 | 19.31 | 19.09 | 9.75 | 6.67 | 6.99 | 5.89 |
| `perf_images_indexed.pdf` | 1 | 2400 | 488.39 | 151.97 | 53.49 | 362.12 | 19.05 | 0.14 |
| `perf_structure_colorspace_images.pdf` | 1 | 2400 | 158.02 | 154.62 | 91.44 | 67.33 | 67.22 | 0.41 |
| `pdfbox-survey.pdf` | 1 | 2400 | 51.28 | 47.44 | 14.83 | 11.04 | 5.49 | 4.88 |
| `pdfbox-survey.pdf` | 5 | 2400 | 40.09 | 40.63 | 13.67 | 6.43 | 6.51 | 5.65 |

All 43 supported page cases produced the same Swag bitmap CRC-32. A
focused test covers two odd-width rows of four-bit samples with a reversed
Decode range and a raw color key.

## Sixteen-bit RGB images

Big-endian RGB samples with the default Decode range use an exact integer
conversion in SIMD. Eight-bit components are the rounded quotients of the
original samples divided by 257. Decode overrides and color-key masks keep
their existing semantics. The functional suite checks all 65,536 sample
values against the previous floating-point conversion and covers partial
vectors.

Release medians on one logical AMD EPYC 7763 CPU, from 11 interleaved
runs at each size of the PDF.js `perf_images_16bit.pdf` page. Both Swag
builds use the indexed palette change. PDFium performs the decoding during
render. Times are milliseconds.
[Phase timings and corpus checksums](pdf-raster-linux-rgb16.json)

| Long side | Swag before | Swag after | PDFium | Load before | Load after | PDFium load |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1200 | 130.21 | 49.16 | 19.59 | 97.81 | 17.54 | 0.22 |
| 2400 | 187.29 | 104.84 | 27.10 | 96.36 | 18.25 | 0.27 |

The Swag raster CRC-32 matched at both sizes and on every supported page
of the 44-case corpus. At 2400 px, 86 ms of the remaining 105 ms are in
render.

## SIMD for cached image rows

The CPU sampler interpolates four pixels at once between two rows that
were already filtered horizontally. A signed multiply-high preserves the
16.16 fixed-point vertical interpolation, including weights on either
side of one half. The same loop writes opaque RGB and blends straight-alpha
images into BGRA targets.

One-core Release medians below use 11 interleaved measurements at each
size, against `b50a786180` and PDFium 159.0.8149.0. Times are milliseconds.
The SIMD loop applies to enlargements with cached horizontal rows.
[Phase timings and corpus checksums](pdf-raster-linux-image-simd.json)

| PDF | Long side | Swag render before | Swag render after | PDFium render | Swag total before | Swag total after | PDFium total |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `pdfbox-jpeg.pdf` | 1200 | 11.33 | 8.30 | 2.69 | 12.45 | 9.33 | 2.79 |
| `pdfbox-scan.pdf` | 1200 | 10.34 | 6.82 | 1.75 | 10.77 | 7.22 | 1.83 |
| `perf_images_jpeg_large.pdf` | 1200 | 32.82 | 39.84 | 95.59 | 101.33 | 104.18 | 96.03 |
| `perf_images_scan_gray.pdf` | 1200 | 31.67 | 31.66 | 33.23 | 83.95 | 85.31 | 34.50 |
| `perf_images_indexed.pdf` | 1200 | 32.61 | 33.60 | 31.77 | 51.91 | 52.40 | 31.95 |
| `perf_images_16bit.pdf` | 1200 | 30.44 | 31.27 | 16.17 | 47.89 | 48.86 | 16.51 |
| `pdfbox-jpeg.pdf` | 2400 | 44.54 | 32.00 | 6.17 | 45.57 | 33.19 | 6.39 |
| `pdfbox-scan.pdf` | 2400 | 41.98 | 27.51 | 5.41 | 42.44 | 28.13 | 5.51 |
| `perf_images_jpeg_large.pdf` | 2400 | 126.26 | 132.18 | 130.76 | 196.45 | 203.28 | 131.25 |
| `perf_images_scan_gray.pdf` | 2400 | 131.28 | 132.81 | 51.07 | 188.46 | 190.48 | 52.51 |
| `perf_images_indexed.pdf` | 2400 | 137.88 | 125.45 | 52.89 | 157.98 | 145.07 | 53.09 |
| `perf_images_16bit.pdf` | 2400 | 84.73 | 60.61 | 27.32 | 102.45 | 80.93 | 27.66 |

All 43 supported corpus pages and the focused pages at both resolutions
produced the same Swag CRC-32. The Pixel suite checks all 65,537 weights
against the scalar expression and exercises mirrored blending with
transparent texels. Large downscaled images still filter their source
rows separately.

## Direct coverage for transformed glyph outlines

Swag's opaque CPU export can scan-convert embedded glyph outlines for
rotated or sheared runs whose effective size is between 12 and 128 pixels.
The render keeps the glyph mapping, font baseline, and PDF advances.
It caches the owned outlines for reuse on the page. Profiling the
transformed text fixture showed that evaluating four distance-field
taps per covered pixel dominated the former path. PDFium uses transformed FreeType glyph
masks and composites them through AGG.

Release medians in milliseconds use seven interleaved runs at each size
on one logical AMD EPYC 7763 CPU, with `b50a786180` as the Swag baseline
and PDFium 159.0.8149.0 as the reference.
[Phase timings and pixel measurements](pdf-raster-linux-transformed-text.json)

| PDF | Long side | Swag before | Swag after | PDFium | Render before | Render after | PDFium render |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `sample1.pdf` | 1200 | 44.70 | 34.64 | 25.55 | 29.54 | 20.41 | 22.76 |
| `sample2.pdf` | 1200 | 11.37 | 10.84 | 4.35 | 8.87 | 8.32 | 3.49 |
| `sample3.pdf` | 1200 | 34.01 | 23.33 | 10.66 | 26.42 | 15.97 | 5.60 |
| `perf_text_cmap_mixed.pdf` | 1200 | 5.38 | 5.11 | 10.84 | 3.18 | 2.95 | 7.01 |
| `perf_text_transformed.pdf` | 1200 | 974.37 | 389.40 | 163.19 | 968.87 | 384.52 | 157.19 |
| `sample1.pdf` | 2400 | 134.73 | 92.74 | 45.08 | 96.88 | 75.25 | 42.47 |
| `sample2.pdf` | 2400 | 34.66 | 34.13 | 9.01 | 31.97 | 30.87 | 8.03 |
| `sample3.pdf` | 2400 | 72.88 | 47.24 | 17.34 | 65.07 | 39.64 | 11.31 |
| `perf_text_cmap_mixed.pdf` | 2400 | 24.80 | 33.02 | 27.28 | 22.53 | 29.79 | 21.93 |
| `perf_text_transformed.pdf` | 2400 | 5132.81 | 1371.87 | 291.79 | 5125.78 | 1366.27 | 286.47 |

Of 43 supported cases, 39 kept their Swag CRC-32. On the dense transformed
text fixture, the mean absolute RGB error from PDFium fell from 23.84 to
21.61 at 1200 px and from 17.95 to 17.11 at 2400 px, out of 255. The same
metric improved on the nested forms fixture and `sample3.pdf`. It rose
from 8.588 to 8.632 on `sample1.pdf` at 1200 px, with 0.46% of pixels
changing. A test renders two rotated embedded glyphs and checks their
position, spacing and counters.

## Applying soft mask coverage to images

The soft mask sampler reuses its horizontal lookup across the image
rows when the transform preserves the axes. SIMD gathers four coverage
texels and multiplies their alpha by the destination's alpha. The
general affine path also reads the mask bytes directly after clipping
each coordinate. The transformed mask fixture applies its coverage to
more than 17 million image samples during load.

Nine interleaved Release runs at each size on one AMD EPYC 7763 logical
CPU compare Swag `d3150abf15` and PDFium 159.0.8149.0. Both Swag
builds use the same compiler and software SHA-1 and SHA-256 sources.
Times are milliseconds.
[Phase timings and corpus checksums](pdf-raster-linux-soft-mask-simd.json)

| PDF | Long side | Swag before | Swag after | PDFium | Load before | Load after | PDFium load |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `sample1.pdf` | 1200 | 43.16 | 54.37 | 28.26 | 14.52 | 16.83 | 2.48 |
| `perf_images_smask.pdf` | 1200 | 88.44 | 93.32 | 55.98 | 33.75 | 34.16 | 0.38 |
| `perf_transparency_soft_masks.pdf` | 1200 | 926.92 | 173.64 | 105.60 | 840.17 | 82.53 | 0.48 |
| `sample1.pdf` | 2400 | 81.80 | 81.99 | 39.94 | 14.44 | 17.81 | 2.35 |
| `perf_images_smask.pdf` | 2400 | 138.65 | 121.35 | 67.96 | 31.67 | 29.90 | 0.48 |
| `perf_transparency_soft_masks.pdf` | 2400 | 1064.25 | 326.23 | 246.73 | 805.09 | 76.55 | 0.37 |

All 43 supported cases kept the same Swag bitmap CRC-32. The
targeted image test exercises a four-pixel block and its tail,
mirrored axes, and a rotated image sampling beyond the mask edges.


## Shared PNG predictor kernels

Flate image streams with PNG predictors use the same row restoration
as PNG files. The shared kernels copy zero residuals and use SIMD for
the filters they can reconstruct in parallel. The PDF.js fixture
contains 1,940 RGB rows and uses each PNG filter equally often.

Nine interleaved Release runs at each size on one AMD EPYC 7763 logical
CPU compare the change with Swag `52207f6934` and PDFium 159.0.8149.0.
Both Swag builds use the same compiler and Core at `60a2e9e772`.
Times are milliseconds.
[Phase timings and corpus checksums](pdf-raster-linux-png-predictors.json)

| PDF | Long side | Swag before | Swag after | PDFium | Load before | Load after | PDFium load |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `sample1.pdf` | 1200 | 34.60 | 35.14 | 26.13 | 13.53 | 13.44 | 2.35 |
| `perf_images_flate_predictor.pdf` | 1200 | 107.20 | 70.71 | 48.41 | 68.20 | 36.76 | 0.31 |
| `perf_images_16bit.pdf` | 1200 | 50.58 | 49.66 | 17.13 | 17.25 | 17.59 | 0.22 |
| `sample1.pdf` | 2400 | 79.12 | 76.36 | 38.48 | 13.95 | 15.65 | 2.36 |
| `perf_images_flate_predictor.pdf` | 2400 | 198.15 | 168.05 | 42.77 | 65.80 | 36.77 | 0.34 |
| `perf_images_16bit.pdf` | 2400 | 78.87 | 79.18 | 29.07 | 17.65 | 17.89 | 0.26 |

The 43 supported cases retain the same Swag raster checksums. The
PDF and PNG suites pass 131 and 52 tests respectively.


## Reusing translated soft masks

The decoder shares a mask group across integral translations when
the transform preserves the axes at unit scale. Up to 16 cached groups
can each keep one raster of at most 512 KiB. Repeated image placements
with the same mask bounds in group coordinates reuse that coverage.
The mode and backdrop are part of the key.

Nine interleaved Release runs at each size on one AMD EPYC 7763 logical
CPU compare Swag `3f81024a37` and PDFium 159.0.8149.0.
Times are milliseconds.
[Phase timings and corpus checksums](pdf-raster-linux-translated-masks.json)

| PDF | Long side | Swag before | Swag after | PDFium | Load before | Load after | PDFium load |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `perf_transparency_soft_masks.pdf` | 1200 | 173.91 | 112.68 | 93.51 | 69.34 | 38.07 | 0.32 |
| `perf_transparency_soft_masks.pdf` | 2400 | 296.99 | 287.28 | 223.53 | 66.81 | 38.66 | 0.33 |

All 43 supported cases retain their Swag bitmap checksums, with both
focused sizes also exact. The 132 PDF tests include an image masked at two
translations and a luminosity mask that references the same group as an
alpha mask.


## Packed sampling for reduced images

Axis-aligned BGRA8 and RGBA8 spans gather four two-texel pairs at a time
when consecutive output rows rarely reuse the same source rows. The
horizontal and vertical interpolations both keep the scalar byte
quantization, including alpha. A scalar prefix and tail follow the
triangle's span boundaries.

Nine interleaved Release runs at each size and a 13-run recheck at 2400 px
compare Swag `99d1a8be6e` and PDFium 159.0.8149.0 on one AMD EPYC 7763
logical CPU. Both Swag builds use the same compiler and Core at
`3f81024a37`. Times are milliseconds.
[Phase timings and corpus checksums](pdf-raster-linux-packed-downscale.json)

| PDF | Series | Render before | Render after | Total before | Total after | PDFium total |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `perf_images_smask.pdf` | 1200 | 72.30 | 30.91 | 108.78 | 70.48 | 70.90 |
| `perf_transparency_soft_masks.pdf` | 1200 | 104.21 | 71.07 | 173.03 | 146.91 | 114.73 |
| `perf_images_jpeg_large.pdf` | 2400 | 166.02 | 132.98 | 262.01 | 206.68 | 141.26 |
| `perf_images_smask.pdf` | 2400 recheck | 96.92 | 90.46 | 140.26 | 123.16 | 67.65 |
| `perf_transparency_soft_masks.pdf` | 2400 recheck | 232.85 | 111.11 | 274.39 | 161.46 | 233.48 |
| `large_jpeg_downscale.pdf` | 2400 recheck | 48.08 | 46.37 | 116.55 | 121.78 | 67.47 |

All 43 supported cases and every focused comparison keep their Swag
raster checksums. The focused Pixel suite also compares mirrored RGBA8
and BGRA8 downscales with scalar reference samples across span tails.


## Sharing immutable decoded images

A decoded image and its cache entry now share the same pixel allocation.
Pages own references that can outlive their reader. A page-specific
transparency change copies the image before editing shared pixels.

These median Release times cover loads from a warmed reader, keeping
each returned page alive. The first image decode is outside the timed
interval. The reference is Swag `c488c3c599` on one AMD EPYC 7763 logical
CPU. Peak RSS is the maximum across the nine processes in each series.
[Timings, memory measurements, and checksums](pdf-raster-linux-shared-images.json)

| PDF | Pages retained | Load before, ms | Load after, ms | Peak RSS before, KiB | Peak RSS after, KiB |
| --- | ---: | ---: | ---: | ---: | ---: |
| `perf_images_jpeg_large.pdf` | 16 | 227.81 | 0.072 | 624,876 | 79,212 |
| `sample1.pdf` | 24 | 75.19 | 32.54 | 151,316 | 31,508 |

For a fresh 1200 px load, the repeated image fixture drops from 8.12
to 6.92 ms and the transformed soft-mask fixture from 43.66 to 29.56 ms
in the focused comparison. All 43 supported cases keep their Swag
checksums against the matched build at `5d769d9d98`. The 138 PDF tests
include a retained page that outlives its reader and a detached alpha edit.


## Public resource and graphics-state fixtures

Six additional Mozilla PDF.js files exercise Flate CMYK images, inline
masks, graphics state changes, shared resources, embedded CFF variants
and transparency groups. The manifest now selects 53 page cases from 47
PDFs, including all four pages of the shared-resource file.

Seven interleaved Release runs at 1200 px use one AMD EPYC 7763 logical
CPU and PDFium 159.0.8149.0. Swag uses the shared-image and JPEG retention
changes based on `5d769d9d98`. Each sample opens a fresh reader.
[Timings and checksums](pdf-raster-linux-expanded-resources.json)

| PDF | Page | Swag, ms | PDFium, ms |
| --- | ---: | ---: | ---: |
| `perf_images_cmyk.pdf` | 1 | 56.78 | 67.49 |
| `perf_images_masks.pdf` | 1 | 98.92 | 84.49 |
| `perf_structure_graphics_states.pdf` | 1 | 339.18 | 226.03 |
| `perf_structure_shared_resources.pdf` | 1 | 54.05 | 28.79 |
| `perf_structure_shared_resources.pdf` | 2 | 55.35 | 26.22 |
| `perf_structure_shared_resources.pdf` | 3 | 56.96 | 28.95 |
| `perf_structure_shared_resources.pdf` | 4 | 71.92 | 27.30 |
| `perf_text_cff_embedded_variants.pdf` | 1 | 14.71 | 9.46 |
| `perf_transparency_groups.pdf` | 1 | 16.31 | 14.33 |

Both engines render all nine added page cases at the same output
dimensions. Shared-resource pages remain dominated by their first
image load when opened separately.


## Sharing device images across page resources

Direct DeviceRGB, DeviceGray and DeviceCMYK images with no mask are
cached by image object. Named color spaces and masked images retain
their page resource context. The reader checks both caches against one
byte budget.

Nine interleaved native Release runs on one AMD EPYC 7763 logical CPU
compare Swag `7477a81726` before and after the change using the same compiler
and Core at `5d769d9d98`. The test warms page 1, then loads each page
in order and retains it. Times are milliseconds.
[Raw samples, memory measurements, and corpus checksums](pdf-raster-linux-device-resources.json)

| Document | Pages | Before | After | Peak RSS before, KiB | Peak RSS after, KiB |
| --- | ---: | ---: | ---: | ---: | ---: |
| `perf_structure_shared_resources.pdf` | 4 | 49.41 | 1.83 | 36,068 | 24,484 |
| Generated repeated-image document | 8 | 118.58 | 0.133 | 72,940 | 28,588 |

All 52 supported cases in the expanded corpus keep their Swag raster
checksums. The 141 PDF tests include both direct image reuse and an image
whose named color space resolves differently on two pages.

## Integrating edge area for small simple outlines

The CPU painter clips each directed edge to device rows and cells. It
adds its signed vertical coverage and trapezoid area to the row, then
accumulates coverage from left to right. Simple contours up to 32 points
with bounded scratch use area integration. Compound and crossing paths
and stencil writes use four vertical samples per row.

Nine alternating native Release runs with two samples per batch use one
AMD EPYC 7763 logical CPU, baseline `5c169b416c`, and PDFium
159.0.8149.0. Times include opening the PDF, loading the page, and
rendering. [Raw phases, checksums, and pixel deltas](pdf-raster-linux-edge-area.json)

| PDF | 1200 px before, ms | After, ms | PDFium, ms | 2400 px before, ms | After, ms | PDFium, ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `sample1.pdf` | 31.53 | 31.11 | 25.47 | 65.18 | 60.45 | 37.91 |
| `sample2.pdf` | 10.77 | 10.35 | 4.43 | 28.62 | 28.53 | 8.63 |
| `sample3.pdf` | 22.35 | 21.37 | 11.19 | 43.51 | 42.21 | 15.51 |
| `perf_paths_polygons.pdf` | 108.72 | 82.38 | 96.60 | 273.88 | 197.35 | 214.66 |
| `perf_paths_hairlines.pdf` | 132.58 | 99.62 | 114.01 | 262.02 | 223.50 | 220.90 |
| `perf_structure_graphics_states.pdf` | 274.12 | 273.38 | 193.88 | 575.61 | 530.94 | 410.68 |

On `sample3.pdf`, an earlier experimental 2400 px run had totals of
45.80 and 60.57 ms. A subsequent run on one executable with the
analytic path switched on and off measured 35.63 and 38.01 ms for
rendering. The final matched binaries measure 35.36 and 36.49 ms
for the same phase. These series are included alongside the timings
for the final bounded sort.

The baseline and candidate render 52 of the 53 corpus cases. Of those,
31 rasters match exactly. The other 21 have antialiasing changes.
On the hairline page the mean absolute RGB change is 1.056 on a scale
of 255, and the mean distance to PDFium drops from 22.69 to 22.35.
On the three FileSamples pages the mean change stays below 0.108.
The 973 Pixel and 141 PDF tests pass, including analytic coverage of
clipped and wide diagonal edges and detection of a self-crossing path.

## Public scan and fax fixtures

Three more pinned PDF.js files extend the manifest to 56 page cases
from 50 PDFs. The added cases cover a large Group 4 fax image, mixed fax
modes and end-of-block flags, and a high-resolution RGB scan with text.
Both engines render all three at the same dimensions.

Nine interleaved Release runs with two samples each use one AMD EPYC
7763 logical CPU and PDFium 159.0.8149.0. Times include opening each
file, loading the page, and rendering at 1200 px.
[Timings and raster checksums](pdf-raster-linux-public-scans.json)

| PDF | Swag, ms | PDFium, ms |
| --- | ---: | ---: |
| `perf_codecs_ccitt.pdf` | 89.08 | 28.22 |
| `ccitt_EndOfBlock_false.pdf` | 6.88 | 1.28 |
| `scan-bad.pdf` | 54.09 | 55.55 |

## Advancing reference transitions during fax decoding

A CCITT 2D line now advances through the reference transitions once.
The decoder restarts the search if a damaged code moves backwards.
It also writes whole black bytes when possible, reads MSB-first
codes from three bytes, and exchanges the two line buffers.

Eleven interleaved native Release runs with two samples each use
baseline `2534d3961d`, PDFium 159.0.8149.0, and one AMD EPYC 7763
logical CPU. The large Group 4 scan at 1200 px takes 98.66 ms before
and 70.05 ms after, with PDFium at 29.95 ms. Swag's page load falls
from 61.63 to 34.10 ms. An earlier series measured 52.42 to 27.10 ms
for that phase under a lighter host load.
[Timing series and corpus checksums](pdf-raster-linux-fax.json)

All 55 supported cases keep their Swag raster checksums. The 144 PDF
tests pass, including the reference Group 4 fixture at both bit
polarities and white padding after an early end.

## Sampling decoded page images in place

The bitmap export holds the page and its decoded image references for the
entire render. Its CPU texture handles sample those buffers directly.
Premultiplied inputs use an owned straight-alpha conversion.

Nine interleaved native Release runs with two samples per batch use
baseline `2534d3961d`, one AMD EPYC 7763 logical CPU, and PDFium
159.0.8149.0. Times include opening, loading and rendering at 1200 px.
[Raw phases, checksums, and peak memory](pdf-raster-linux-borrowed-textures.json)

| PDF | Swag before, ms | Swag after, ms | PDFium, ms |
| --- | ---: | ---: | ---: |
| `perf_images_jpeg_large.pdf` | 95.13 | 91.90 | 96.60 |
| `large_jpeg_downscale.pdf` | 52.23 | 45.87 | 56.15 |
| `perf_images_repeated.pdf` | 97.23 | 92.42 | 74.51 |
| `perf_transparency_soft_masks.pdf` | 72.39 | 67.50 | 94.75 |

The large JPEG render phase drops from 33.18 to 28.71 ms. The process
peak stays near 128 MiB in the seven-sample memory check. All 55
supported raster checksums, 987 Pixel tests, and 144 PDF tests pass.

## Decoding opaque images into their final row layout

Unmasked device images can write straight to the bottom-up output
buffer. Eight-bit gray samples and expanded one-bit gray samples use
one byte per pixel, with the same quantized bilinear filtering. RGB and
CMYK samples on this path also skip the top-down intermediate buffer.

Nine alternating Release runs of two samples use a single AMD EPYC 7763
logical CPU, baseline `238120e726`, and PDFium 159.0.8149.0. Totals cover
open, load, and rendering to a 1200 px long side. Peak RSS is the median
from seven additional runs for the three large grayscale scans.
[Raw phases, raster checksums, and memory](pdf-raster-linux-packed-gray.json)

| PDF | Swag before, ms | Swag after, ms | PDFium, ms | Peak RSS before, KiB | Peak RSS after, KiB |
| --- | ---: | ---: | ---: | ---: | ---: |
| `perf_codecs_ccitt.pdf` | 70.74 | 38.06 | 30.35 | 100,596 | 43,368 |
| `perf_images_scan_bilevel.pdf` | 89.28 | 36.17 | 28.12 | 101,208 | 43,892 |
| `perf_images_scan_gray.pdf` | 124.84 | 49.10 | 37.41 | 110,080 | 58,912 |
| `perf_images_16bit.pdf` | 59.81 | 49.27 | 17.75 | | |
| `pdfbox-scan.pdf` | 8.55 | 9.84 | 1.79 | | |

All 55 supported corpus rasters are byte-identical to baseline.
The 145 PDF and 992 Pixel tests pass. The odd-width bilevel
regression checks both the compact format and bit polarity.

## Keeping JPEG channel order through rendering

The PDF reader keeps an unmasked JPEG's decoder-native BGR8 pixels.
Both renderer backends and the writer already accept BGR8. Matching
soft masks still compose straight RGBA from either channel order.

Nine alternating native Release runs on one AMD EPYC 7763 logical CPU
use baseline `238120e726` and PDFium 159.0.8149.0. Times include opening,
loading, and rendering at 1200 px.
[Raw phases and raster checksums](pdf-raster-linux-native-jpeg.json)

| PDF | Swag before, ms | Swag after, ms | PDFium, ms |
| --- | ---: | ---: | ---: |
| `sample1.pdf` | 31.19 | 30.16 | 26.01 |
| `sample2.pdf` | 11.06 | 10.53 | 4.58 |
| `perf_images_jpeg_large.pdf` | 91.95 | 79.91 | 98.31 |
| `large_jpeg_downscale.pdf` | 60.10 | 43.59 | 57.61 |

All 55 supported pages keep their raster checksums. The 124 focused
PDF tests include retained source JPEGs and same-size soft masks.

## SIMD bilinear filtering for eight-bit grayscale

The CPU renderer filters four independent Gray8 samples together. Each
axis retains the original integer rounding and the four output pixels
keep the destination alpha. The renderer still reads one byte per
source texel, including at row boundaries.

Nine paired Release batches of two samples on one AMD EPYC 7763
logical CPU compare `e43cc4c68b` with the SIMD change and PDFium
159.0.8149.0. Times include open, load, and rasterization.
[1200 px data](pdf-raster-linux-simd-gray-1200.json)
[2400 px data](pdf-raster-linux-simd-gray-2400.json)

| PDF | 1200 px before / after / PDFium, ms | 2400 px before / after / PDFium, ms |
| --- | ---: | ---: |
| `pdfbox-scan.pdf` | 6.78 / 6.75 / 1.70 | 27.54 / 26.28 / 6.40 |
| `perf_images_scan_gray.pdf` | 45.81 / 27.92 / 37.10 | 154.90 / 53.95 / 60.70 |
| `perf_images_scan_bilevel.pdf` | 32.25 / 12.23 / 26.08 | 146.40 / 44.60 / 45.69 |
| `perf_images_16bit.pdf` | 47.03 / 47.94 / 18.04 | 80.38 / 80.87 / 28.95 |
| `perf_codecs_ccitt.pdf` | 35.08 / 15.05 / 28.46 | 134.74 / 48.18 / 48.51 |

All 55 supported corpus pages keep their raster CRC. The 996 Pixel
tests include an odd-width, fractional-position grayscale image whose
output is compared pixel for pixel with the same image in RGB8.

## Single-component JPEG output

PDF decoding requests Gray8 for unmasked DeviceGray JPEGs. The JPEG
codec emits the decoded grayscale scanline directly when it fits the
destination row and copies only visible samples on padded rows. The
saved PDF can still retain the original compressed stream.

On a single AMD EPYC 7763 logical CPU, nine paired Release batches of
two samples measure opening, loading and rendering the progressive
JPEG fixture. The Swag baseline is `747be17d13`. PDFium is 159.0.8149.0.
[Raw timings and checksums](pdf-raster-linux-jpeg-gray.json)

| Long side | Swag before, ms | Swag after, ms | PDFium, ms |
| --- | ---: | ---: | ---: |
| 1200 px | 78.77 | 55.77 | 74.20 |
| 2400 px | 208.50 | 115.92 | 91.12 |

All 55 supported pages in the 56-page pre-expansion corpus retain their
raster CRC. The 39 JPEG tests check exact equality with the existing
three-channel output for baseline, progressive and 1 × 1 images.
