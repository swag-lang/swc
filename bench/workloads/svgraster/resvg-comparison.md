# Where Swag spends more time than resvg

## Scope of the comparison

Swag Scope keeps a `Svg.Drawing` for the image viewer. `ImageView.paintDrawing` paints
the visible vector content at the current zoom through the application's renderer,
normally OpenGL. `loadViewerImage` uses the CPU bitmap path with a supersampling factor of one and a
2048 px limit. `loadThumbnail` uses the actual thumbnail size and two samples per axis.
The measurements here exercise the one-sample bitmap path. [Scope load paths](../../../bin/apps/modules/swagscope/src/viewers/image/viewer.swg#L106)
[Vector paint](../../../bin/std/modules/gui/src/controls/widgets/imageview.swg#L217)
[Default GUI renderer](../../../bin/std/modules/gui/src/application.swg#L1265)

All four originals contain cubic paths in an opaque black group with no stroke,
clip, mask, filter or embedded image. The group applies a scale and a Y flip.
Subpaths are counted from the SVG move commands.

| Source size | Paths | Subpaths | Subpaths in the two largest paths |
| --- | ---: | ---: | ---: |
| 640 × 426 | 223 | 782 | 419 and 135 |
| 1280 × 853 | 1,091 | 2,999 | 1,375 and 459 |
| 1920 × 1280 | 2,805 | 7,385 | 2,942 and 1,424 |
| 5184 × 3456 | 21,066 | 48,185 | 14,488 and 9,953 |

## Code paths

1. **Parsing and geometry.** `usvg` parses XML and uses `SimplifyingPathParser` and
   `PathBuilder` to keep the authored subpaths as path verbs and points. Swag's
   `emitShape` flattens ordinary compound fills, walks contour containment and
   can split one SVG path into several islands. An eligible fill with at least
   512 contours or 8192 counted segments takes Swag's existing `ScanFill` path
   and bypasses that containment walk. [resvg's locked dependency versions](https://github.com/linebender/resvg/blob/v0.50.0/Cargo.lock#L691)
   [usvg path conversion](https://github.com/linebender/resvg/blob/v0.50.0/crates/usvg/src/parser/shapes.rs#L31)
   [Swag dispatch](../../../bin/std/modules/pixel/src/svg/parse.swg#L2294)
   [Swag compound fills](../../../bin/std/modules/pixel/src/svg/parse.swg#L2443)

2. **Coverage.** resvg forwards the transformed path and its winding rule to
   tiny-skia 0.12.0. Its edge builder produces line, quadratic and cubic edges.
   The scan converter sorts by starting row and X and advances the active edges
   in fixed point. An edge's X normally advances by adding its slope, and changes
   in winding delimit horizontal spans. Antialiasing accumulates spans at a 4×
   subpixel scale into runs of coverage. Swag's ordinary path normalizes polygons
   as needed, tessellates regions, computes fringe offsets and submits filled and
   fringe triangles. Cached geometry avoids rebuilding the mesh on a repeat,
   which still submits the triangles. The CPU renderer transforms vertices and
   evaluates edge equations and coverage across the triangle bounds.
   [resvg fill dispatch](https://github.com/linebender/resvg/blob/v0.50.0/crates/resvg/src/path.rs#L26)
   [tiny-skia edge builder](https://github.com/linebender/tiny-skia/blob/e48b9027762d33731e60e40eb17eaa4f583b0185/src/edge_builder.rs#L72)
   [Active edges](https://github.com/linebender/tiny-skia/blob/e48b9027762d33731e60e40eb17eaa4f583b0185/src/scan/path.rs#L199)
   [Antialiasing](https://github.com/linebender/tiny-skia/blob/e48b9027762d33731e60e40eb17eaa4f583b0185/src/scan/path_aa.rs#L20)
   [Swag fill preparation](../../../bin/std/modules/pixel/src/painter/fillpath.swg#L300)
   [Swag triangle rasterization](../../../bin/std/modules/pixel/src/render/cpu/rendercpu.swg#L1863)

3. **Compositing.** resvg paints this group into the final premultiplied pixmap.
   Opaque solid spans can use tiny-skia's constant-color fill. The pixmap sizes
   in this benchmark are below its 8191 px tiling limit. Swag's bitmap API
   targets 1024 px tiles, paints one opaque white matte for these black inputs,
   reads back each tile and reconstructs straight-alpha output. Its `ScanFill`
   also has a separate cost. It records floating-point crossings for each
   subrow, sorts each subrow, integrates coverage into an RGBA image and submits
   that image as a texture. A direct span writer can skip that intermediate
   texture in the CPU bitmap path. [resvg group dispatch](https://github.com/linebender/resvg/blob/v0.50.0/crates/resvg/src/render.rs#L49)
   [tiny-skia blitter](https://github.com/linebender/tiny-skia/blob/e48b9027762d33731e60e40eb17eaa4f583b0185/src/pipeline/blitter.rs#L58)
   [tiny-skia tiling](https://github.com/linebender/tiny-skia/blob/e48b9027762d33731e60e40eb17eaa4f583b0185/src/painter.rs#L612)
   [Swag bitmap rendering](../../../bin/std/modules/pixel/src/svg/parse.swg#L6079)
   [Swag scan fill](../../../bin/std/modules/pixel/src/svg/scanfill.swg#L161)

## Controlled comparison

Release builds at Swag commit `749e606048` and resvg 0.50.0 ran on the same
AMD EPYC 9V45, pinned to one logical CPU. The benchmark runner supplies the four
SHA-256 checks and output dimensions. Each Swag
process warms up on a separate drawing, then measures parse and first
rasterization of a fresh drawing. A third call rasterizes the same drawing
again to measure reuse of geometry and scan textures. File I/O and PNG work are
outside the timed intervals. The median of seven interleaved runs is reported.
[Benchmark runner](run.py)

The experiments change two independent decisions in temporary standard-library copies.
One raises `RasterSampleTileSide` from 1024 to 2048. The other sends every black
fill that passes the existing `usesScanFill` paint checks through `ScanFill`, before
the size check. Its own internal 1024 px texture tiles are still used.

| Source size | Swag parse | Swag first raster | Swag repeat raster | Swag total | Swag one tile total | Swag forced scan total | Swag forced scan and one tile total | resvg parse | resvg raster | resvg total |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 640 × 426 | 7.19 | 72.44 | 16.22 | 79.83 | 74.21 | 7.28 | 7.45 | 1.50 | 4.33 | 5.77 |
| 1280 × 853 | 17.22 | 110.71 | 49.83 | 127.93 | 119.52 | 38.66 | 37.04 | 5.41 | 15.16 | 20.60 |
| 1920 × 1280 | 12.25 | 180.22 | 96.10 | 192.24 | 187.47 | 92.43 | 93.59 | 11.57 | 33.37 | 45.07 |
| 5184 × 3456 | 116.14 | 1440.86 | 490.01 | 1558.35 | 1484.96 | 460.34 | 602.59 | 88.32 | 163.01 | 253.74 |

All timings are in milliseconds. The last output is 2048 × 1365. The 640 × 426
control already fits one tile, so the variation between the two tile settings on
that input shows the timing noise at this scale.

Forcing scans closes 68–98% of the total time difference from resvg across the
four inputs. The geometry preparation cost is apparent on a repeat of the same
drawing and in the drop in parsing time when the containment pass is skipped.
The one-tile experiment saves about 5% on the current largest case. Combining
it with forced scans slows that case, so increasing the target limit alone
has little leverage.

An additional five-run median kept either the two SVG paths with the most
subpaths or all remaining paths, preserving dimensions, group and path order.
Rendering the subsets independently changes scene setup and culling, so their
timings are reported separately.

| Source size | Two paths Swag | Two paths forced scan | Two paths resvg | Remaining paths Swag | Remaining paths forced scan | Remaining paths resvg |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 640 × 426 | 69.30 | 7.00 | 4.49 | 7.31 | 2.07 | 1.28 |
| 1280 × 853 | 95.94 | 33.73 | 15.86 | 54.90 | 11.91 | 6.63 |
| 1920 × 1280 | 76.40 | 77.86 | 32.88 | 148.96 | 39.85 | 16.68 |
| 5184 × 3456 | 242.70 | 258.92 | 167.54 | 1200.28 | 230.41 | 95.66 |

The smallest file concentrates the overhead in its two compound paths. For the
largest file, the 21,064 other paths take 1.20 s alone and account for most of
the available gain. Its two largest paths already use scan conversion.

## First raster costs

Separate instrumented builds accumulate timers around `paintImpl`, the CPU
renderer submission and matte readback. Nested timers cover the scan image
build, `buildRegionTessellation` (including the fringe offsets or fallback) and
`normalizedFill`. Each column is the median of three runs in milliseconds.
The nested columns are included in the `paintImpl` column. Recording outside
that call, setup and the final pixel recovery have their own cost.

| Source size | Dispatch | `paintImpl` | CPU submission | Matte readback | Scan image build | Tessellation and offsets | Normalization |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 640 × 426 | Current | 49.46 | 12.00 | 0.07 | 0.00 | 26.66 | 14.96 |
| 640 × 426 | Forced scan | 5.34 | 0.35 | 0.25 | 5.10 | 0.00 | 0.00 |
| 1280 × 853 | Current | 81.15 | 27.67 | 2.02 | 16.59 | 29.32 | 15.04 |
| 1280 × 853 | Forced scan | 31.64 | 2.52 | 0.81 | 29.97 | 0.00 | 0.00 |
| 1920 × 1280 | Current | 137.78 | 32.34 | 2.79 | 56.80 | 41.16 | 9.01 |
| 1920 × 1280 | Forced scan | 75.80 | 6.13 | 2.64 | 70.87 | 0.00 | 0.00 |
| 5184 × 3456 | Current | 1070.20 | 241.57 | 13.28 | 193.91 | 438.01 | 148.64 |
| 5184 × 3456 | Forced scan | 335.14 | 91.36 | 2.87 | 306.62 | 0.00 | 0.00 |

On the largest raster, normalization and building meshes take about 587 ms
inside `paintImpl`, and execution of the painter commands takes another 242 ms.
With forced scans, generating the intermediate scan images takes 307 ms and
compositing the recorded commands takes 91 ms. resvg's entire raster phase is
163 ms in the uninstrumented benchmark. The two costs to isolate next are
building and sorting Swag's crossings and sending their coverage through
intermediate textures.

## Output comparison

For the all-black corpus, the alpha channel measures visible coverage.
The comparison uses decoded alpha bytes in 0–255, irrespective of RGB where
alpha is zero. To compare geometry at the same scale on the largest image,
resvg is asked to fit to width 2048 and the extra bottom row is dropped.
The timing table uses the benchmark's usual width and height arguments.

| Source size | Pixels with changed alpha, forced scan vs Swag | Mean absolute alpha error, Swag vs resvg | Mean absolute alpha error, forced scan vs resvg |
| --- | ---: | ---: | ---: |
| 640 × 426 | 7.70% | 3.13 | 0.53 |
| 1280 × 853 | 3.42% | 4.49 | 0.50 |
| 1920 × 1280 | 2.02% | 2.95 | 0.51 |
| 5184 × 3456 | 5.62% | 9.00 | 0.96 |

The experiment's coverage is closer to resvg on this corpus. Its changed alpha
also means a wider dispatch needs explicit winding and edge-coverage regressions.
The one-tile experiment reproduced the current pixels on the first two inputs
and changed alpha in a handful of pixels on the other two.

## Direct CPU composition

Scope requests `Svg.ParseOptions.preferScanFills` when it needs an SVG bitmap
or thumbnail. Eligible paths preserve their authored contours. If the drawing
contains only unclipped scan fills in one solid color, the CPU rasterizer
composes coverage directly into the destination bitmap. The same row buffers
serve successive paths. Complex scenes still render through the painter.
Thumbnail samples compose before the box resolve, at the existing two samples
per axis.

The following Release medians use the same seven-run, one-CPU method and
dimension cap as the comparison above. The reference is `3bb8cc76d7`.
The scan texture column selects the same parse option and passes an explicit
`RenderCpu` through the renderer overload. The direct column uses the CPU
bitmap overload, as Scope does. Times include parsing and first rasterization.

| Source size | Previous Swag (ms) | Scan textures (ms) | Direct CPU (ms) | resvg (ms) |
| --- | ---: | ---: | ---: | ---: |
| 640 × 426 | 80.24 | 7.70 | 5.96 | 5.98 |
| 1280 × 853 | 132.10 | 38.56 | 28.04 | 21.39 |
| 1920 × 1280 | 221.86 | 98.03 | 77.56 | 55.96 |
| 5184 × 3456 | 1457.65 | 504.34 | 359.10 | 269.04 |

On the four originals, the direct bitmap differs from the scan texture
reference by at most two alpha levels (on an 8-bit scale). The mean absolute
alpha difference from resvg is 0.50–0.96 with matched scales. The default
parse options keep the existing raster CRC-64 on all four originals.

At Scope's 320 × 213 thumbnail size, with the two-sample setting on both
Swag builds, the totals were 75.09 → 5.79 ms, 98.14 → 17.59 ms,
140.90 → 36.22 ms and 1316.70 → 227.00 ms respectively.

## Contour culling and crossing sort

An active-edge prototype reused crossing order from one subrow to the next
and preserved the existing interpolation. In a three-run check it moved the
generated dense fill from 70.3 to 47.8 ms, and the largest original from
325.1 to 378.8 ms. The isolated rendering of its two largest compound paths
also took longer with the prototype, at 231.4 ms versus 212.7 ms.

The renderer discards flattened contours wholly outside either tile axis
when the transform is axis-aligned. The projected bounds carry a rounding
margin. Vertical edges reuse the same crossing on every subrow, and lines
of up to eight crossings use a short insertion sort.

Seven interleaved Release runs on one CPU compared the previous renderer
at `b31d712f65` with these changes. Both Swag builds used
`preferScanFills`, one sample per axis, and the output sizes from the
bitmap comparison above. Thumbnail timings preserve the existing
320 × 213 size and two samples per axis.

| Source size | Previous bitmap (ms) | Current bitmap (ms) | resvg (ms) | Previous thumbnail (ms) | Current thumbnail (ms) |
| --- | ---: | ---: | ---: | ---: | ---: |
| 640 × 426 | 5.71 | 5.57 | 5.48 | 6.14 | 6.39 |
| 1280 × 853 | 28.66 | 23.20 | 20.94 | 18.46 | 19.32 |
| 1920 × 1280 | 62.78 | 53.21 | 45.83 | 38.14 | 37.18 |
| 5184 × 3456 | 350.20 | 311.46 | 261.46 | 235.22 | 225.30 |

All bitmap and thumbnail CRC-64s matched the previous Swag build. The
largest bitmap saved 30 ms in the raster phase and 39 ms in total. The
generated dense fill went from 69.75 to 64.80 ms with the same CRC-64.

## Curve projection and parallel scan rows

An instrumented run of `76f5c0b911` on the largest original attributed
about 111 ms to flattening, 105 ms to collecting crossings and 47 ms to
sorting and compositing. The largest thumbnail spent about 113 ms flattening
and 65 ms collecting crossings, with about 10 ms left for sorting and
compositing. These timings include the instrumentation and are useful
for locating the work in each path.

Cubic flattening now reuses the normalized chord between the two
control-point projections. Scan conversion tests each projected vertex
for finiteness once and keeps each edge's interpolation constants across
subrows. For large compound fills, direct CPU composition distributes the
ready crossing lists and destination rows in 64-row bands. Each band
owns its output and scratch storage. The jobs join before the next fill
composites, preserving source order.

The Release measurements alternate the previous Swag implementation at
`76f5c0b911`, the revised implementation, and resvg 0.50.0. Each processor
budget has seven runs. Swag used its direct bitmap parse option. The
one-worker run was pinned to one logical CPU. The four-worker run let
both programs use the same four logical CPUs. resvg renders a single
SVG serially in both runs. Times include parsing and first rasterization.

| Source size | Swag before, 1 worker (ms) | Swag after, 1 worker (ms) | resvg (ms) | Swag before, 4 workers (ms) | Swag after, 4 workers (ms) | resvg (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 640 × 426 | 5.89 | 5.41 | 6.23 | 6.71 | 4.67 | 7.06 |
| 1280 × 853 | 24.13 | 22.26 | 21.08 | 26.36 | 18.84 | 23.51 |
| 1920 × 1280 | 57.33 | 55.68 | 48.26 | 66.49 | 45.62 | 55.38 |
| 5184 × 3456 | 308.64 | 288.74 | 266.21 | 307.40 | 263.38 | 254.70 |

The largest output remains 2048 × 1365. Its 320 × 213 thumbnail, with
two samples per axis, goes from 232.74 to 206.52 ms at one worker
and from 241.56 to 202.19 ms at four. Each bitmap and thumbnail
had the same CRC-64 across both Swag builds and both worker counts.
The default parse path also kept its four bitmap checksums. The generated
dense fill kept its checksum and went from 65.29 to 62.23 ms at one worker.

## Parallel contour preparation and shared sample rows

The direct CPU bitmap path prepares dense compound fills in independent
contour batches before collecting crossings. Jobs join before the first
tile scans the fill. The existing serial preparation handles fills with rows outside the
destination and buffers owned by custom allocators. Scan conversion computes
each projected vertex's sample row once and skips edges whose endpoints
fall in the same sample interval. This keeps the existing half-open
sampling, floating-point interpolation, winding and alpha composition.

The table reports seven interleaved Release medians in milliseconds,
including parsing and first rasterization. The reference is Swag
`eab46cd563` and the same resvg 0.50.0 CPU executable as above.
Swag used `preferScanFills` and one sample per axis. Both engines ran
under the same affinity for each comparison. Swag used one or four
workers while resvg rendered each document serially.

| Source size | Swag before, 1 worker | Swag after, 1 worker | resvg, 1 CPU | Swag before, 4 workers | Swag after, 4 workers | resvg, 4 CPUs |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 640 × 426 | 5.11 | 5.18 | 5.41 | 4.60 | 4.57 | 5.52 |
| 1280 × 853 | 21.17 | 21.89 | 20.40 | 19.53 | 17.24 | 22.89 |
| 1920 × 1280 | 51.95 | 51.91 | 46.31 | 44.67 | 38.26 | 46.51 |
| 5184 × 3456 | 258.82 | 253.01 | 242.51 | 266.80 | 238.14 | 282.92 |

The largest bitmap was rendered at 2048 × 1365. Its four-worker raster
phase took 158 ms against 175 ms for resvg. The 320 × 213 thumbnail,
at two samples per axis, went from 216.02 to 177.17 ms with four
workers and from 199.59 to 201.02 ms with one. A separate four-worker
series including destruction of the drawing reduced the largest
bitmap load from 267.76 to 224.22 ms and its thumbnail load from
207.93 to 177.79 ms. The smallest thumbnail measured 4.94 to 5.18 ms
with four workers.

The four bitmap and thumbnail CRC-64s matched the reference at both
worker counts. The generated dense fill kept its CRC-64 and went from
54.30 to 52.70 ms with one worker and from 36.09 to 36.28 ms with four.

With the default parse options, the largest bitmap also kept its
CRC-64. Its total moved from 1358 to 1331 ms at one worker and from
1489 to 1501 ms at four.

## Sorting medium scan lines

Each scan line with 9 to 127 crossings now uses a Shell sort with a final
insertion pass over the crossing coordinates. The existing short insertion
pass handles up to eight crossings and radix sorting handles longer lines.
Crossings at the same X contribute the same net winding before the next
covered span. A regression test compares shuffled, touching contours with
a single equivalent rectangle under both SVG fill rules.

These are seven interleaved Release medians in milliseconds against
`740046dbe4`, which contains the preceding SVG implementation. Swag used
the direct CPU path through `preferScanFills`. The programs had the same
CPU affinity in each pair and resvg 0.50.0 rendered each document serially.
The largest output was 2048 × 1365. The times include parsing and the first
bitmap raster.

| Source size | Swag before, 1 worker | Swag after, 1 worker | resvg, 1 CPU | Swag before, 4 workers | Swag after, 4 workers | resvg, 4 CPUs |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 640 × 426 | 5.02 | 4.78 | 5.45 | 4.38 | 4.15 | 5.61 |
| 1280 × 853 | 21.49 | 20.38 | 20.54 | 16.10 | 16.48 | 21.70 |
| 1920 × 1280 | 51.57 | 46.11 | 43.48 | 36.20 | 34.83 | 49.20 |
| 5184 × 3456 | 257.99 | 256.08 | 251.91 | 205.14 | 213.22 | 286.56 |

The 1920 × 1280 single-worker raster phase fell from 42.00 to 37.27 ms.
The synthetic dense fill went from 54.90 to 49.66 ms at one worker and
32.55 to 31.47 ms at four. A second series of nine runs on the largest
bitmap at four workers measured 210.01 versus 208.32 ms. The total time
varied between the two series while both raster medians stayed within
2 ms of baseline. The largest 320 × 213 thumbnail measured 188.66 versus
187.85 ms at one worker and 179.18 versus 169.63 ms at four, with two
samples per axis.

All four bitmaps, thumbnails and the generated dense fill kept their Swag
CRC-64 at both worker counts. An experiment that scanned a full-width strip
instead of handling horizontal tiles separately saved about 10 ms on the
largest single-worker bitmap. It changed alpha by one level in 242 pixels
of the 1920 × 1280 output and 438 pixels of the largest output, all in the
second horizontal tile. The generated dense fill also changed CRC-64. The
interpolation and coverage use coordinates relative to each tile, so sharing
more work across tiles still needs to preserve those local coordinates.
