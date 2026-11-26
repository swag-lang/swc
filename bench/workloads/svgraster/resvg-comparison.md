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

## Sharing contour traversal between columns

A prototype classified each flattened contour for both horizontal tiles
while visiting the left one. It queued the contours that reached the
right tile and used the usual tile-local interpolation in both. This
preserved the bitmap CRC-64s of the 1920 × 1280 and 5184 × 3456 originals
and of the generated dense fill.

The table reports median parse and first raster time in milliseconds
against `b031932f1c`. The originals used seven interleaved Release runs
per CPU budget. The generated dense fill used five.

| Source | Baseline, 1 worker | Shared traversal, 1 worker | Baseline, 4 workers | Shared traversal, 4 workers |
| --- | ---: | ---: | ---: | ---: |
| 1920 × 1280 | 44.84 | 44.74 | 34.19 | 37.44 |
| 5184 × 3456 | 249.95 | 250.43 | 208.48 | 218.53 |
| Generated dense fill | 49.65 | 51.63 | 30.21 | 32.04 |

On the largest bitmap, raster time went from 180.87 to 183.13 ms
at one worker and from 138.07 to 144.23 ms at four. resvg 0.50.0
measured 258.63 and 249.76 ms total under the same CPU affinities.
Queuing candidates in the left tile moved work out of the right tile's
pass. The combined raster phase was slower at both CPU budgets.
Limiting composition to covered columns improved the largest bitmap
in a five-run trial and slowed it in the seven-run confirmation at one
worker.

The benchmark now exposes this bitmap mode through `--scope`. It
uses Scope's parse option in both Swag builds while retaining the
runner's existing baseline CRC-64 check. [Benchmark runner](README.md)

An instrumented pass counted edges and buffer growth in the two largest
compound fills of the 5184 × 3456 original. At 2048 × 1365, 610,259 of
728,994 sloped edges crossed one sample row (84%), and recording 928,738
intersections grew a row buffer 32,418 times. At 320 × 213 with two
samples per axis, 214,584 of 220,338 sloped edges crossed one sample row
(97%). Those counts narrow the interpolation work to the single-row case
and identify where to measure row buffer growth separately.

## Cached scan sample positions

Each sample row now stores its tile-local Y alongside its crossing list.
The scanner computes Y when scratch grows and keeps it when the next
shape or tile clears the list. The cached value uses the previous f32
sample calculation widened to f64. Interpolation uses the same rounding
for one-row and multi-row edges. This scan path is shared by the SVG
renderer and CPU Painter fills.

These seven interleaved Release medians use `838d348519` as the
baseline, the Scope bitmap parse option and resvg 0.50.0. Both programs
use the same CPU affinity at each worker count. Times include parsing
and the first raster and are in milliseconds.

| Source size | Swag before, 1 worker | Swag after, 1 worker | resvg, 1 CPU | Swag before, 4 workers | Swag after, 4 workers | resvg, 4 CPUs |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 640 × 426 | 5.15 | 4.73 | 5.80 | 4.11 | 4.03 | 5.47 |
| 1280 × 853 | 20.04 | 19.15 | 21.87 | 16.30 | 15.63 | 21.77 |
| 1920 × 1280 | 45.92 | 44.99 | 47.03 | 34.17 | 33.37 | 48.33 |
| 5184 × 3456 | 244.18 | 239.79 | 244.90 | 203.21 | 189.96 | 263.22 |

On the largest output (2048 × 1365), the raster alone moves from 177.43
to 172.79 ms at one worker and from 133.86 to 124.32 ms at four. Its
320 × 213 thumbnail, rendered at two samples per axis, moves from 195.18
to 192.03 ms at one worker and from 166.74 to 155.66 ms at four. The
synthetic dense fill measures 47.25 versus 47.87 ms at one worker and
32.89 versus 32.49 ms at four. All bitmap, thumbnail and dense-fill
CRC-64s match the baseline.

The explicit one-row interpolation branch took 259.78 ms against a
255.78 ms baseline in the five-run trial on the largest bitmap at one
worker. An inline four-crossing buffer prototype with cached Y took
170.68 ms in the raster phase against a 184.51 ms baseline on that bitmap
and 44.34 versus 44.74 ms on the dense fill. This experiment also puts
more storage in each sample record, so it needs measurements on sparse
and parallel scans.

## Crossing storage on sparse and dense samples

The generated corpus now covers mostly empty sample rows
(`sparse-curves`) and very short contours grouped on a few sample rows
(`thin-edges`). The six existing generated documents retain their bytes.

A four-crossing inline buffer helped `sparse-curves`. At one worker
the raster median fell from 0.67 to 0.47 ms with direct inline storage.
On the largest original, the same implementation reduced the one-worker
raster median from 184 to 171 ms and increased the four-worker median
from 127 to 135 ms. Keeping owned overflow counts through the array API
also produced mixed results. Both variants kept all checked CRC-64s.

A single crossing store with per-row offsets reduced the number of
independent allocations. It kept the checked CRC-64s while raising the
largest one-worker raster median from 176 to 183 ms. Retaining each row's
reserved range across tiles still took 188 ms against 174 ms in a
separate nine-run series. The dense synthetic fill also took longer.
Those trials used the shared renderer with nested PDF clipping.

## Short SVG integers

One- and two-digit integers make up about 97% of the path coordinates
in the largest original. The reader can now finish those numbers once
it sees a following byte that rules out a longer integer, a decimal
or an exponent. It keeps the sign and cursor semantics of the general
number reader.

Here are nine interleaved Release medians in milliseconds against
`bf49559935`, using the Scope parse option and equal CPU affinity for
Swag and resvg 0.50.0. Each bitmap timing includes parsing and first
rasterization. The largest output is 2048 × 1365.

| Source size | Swag before, 1 worker | Swag after, 1 worker | resvg, 1 CPU | Swag before, 4 workers | Swag after, 4 workers | resvg, 4 CPUs |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 640 × 426 | 4.62 | 4.42 | 5.45 | 4.08 | 4.31 | 5.90 |
| 1280 × 853 | 19.12 | 18.71 | 20.99 | 14.56 | 14.54 | 22.27 |
| 1920 × 1280 | 49.75 | 46.15 | 46.15 | 33.62 | 35.49 | 49.01 |
| 5184 × 3456 | 240.15 | 240.13 | 247.47 | 198.06 | 191.99 | 275.16 |

The largest one-worker bitmap parse phase fell from 68.86 to 66.71 ms.
An earlier nine-run series measured 73.93 to 65.95 ms for the same
phase. Its 320 × 213 thumbnail, with two samples per axis, measured
190.73 to 181.57 ms total at one worker and 165.03 to 158.78 ms at four.
The four original bitmaps and thumbnails, `curves`, `dense`,
`sparse-curves` and `thin-edges` kept their comparison CRC-64s.

## Translucent stroke widths

The two generated stroke fixtures share 384 cubic curves and paint colors.
Only the pen width changes, from 0.5 to 4 device pixels. In resvg 0.50.0,
`stroke_path` passes the authored path to tiny-skia. With antialiasing and
an axis-aligned width at or below one pixel, tiny-skia uses its hairline
scanner. A wider stroke is converted to an outline and filled.
Swag promotes narrow strokes in `Painter` and builds distance-stroke
triangles. Its CPU renderer rasterizes their coverage before blending
it once per stroke.
[resvg stroke dispatch](https://github.com/linebender/resvg/blob/v0.50.0/crates/resvg/src/path.rs#L77)
[tiny-skia hairline selection](https://github.com/linebender/tiny-skia/blob/e48b9027762d33731e60e40eb17eaa4f583b0185/src/painter.rs#L544)
[Swag stroke coverage](../../../bin/std/modules/pixel/src/render/cpu/rendercpu.swg#L2528)

Seven interleaved Release runs at `70a3961487` measured parse-plus-raster
milliseconds with the Scope options and matching CPU affinity.

| Pen width | Swag, 1 worker | resvg, 1 CPU | Swag, 4 workers | resvg, 4 CPUs |
| --- | ---: | ---: | ---: | ---: |
| 0.5 px | 33.16 | 6.12 | 42.95 | 8.00 |
| 4 px | 43.82 | 13.05 | 49.92 | 14.13 |

The separate `strokes` fixture uses one-pixel pens and longer curves. At
one worker, about 17% of CPU samples landed in the solid stroke coverage
loop and 9% in triangle setup. Another 6% landed in the overlap alpha
clear. Those samples came from optimized native code built with debug
information and timed independently of the Release benchmark.

## CPU target readback

Scope's colored bitmap path recovers straight-alpha pixels from a black
and a white matte. When the CPU renderer shares coverage between the two
mattes, their target images are read in place after submission. At two
samples per axis, the first matte keeps its copy while the second is
read directly. The regression compares tiled colored output with the
readback path at both sample counts, including translucent overlaps,
curved clips and incomplete bottom and right tiles.

Release medians below use four workers and the Scope options, with nine
runs per build at one sample per axis and seven at two samples per axis.
The earlier source was `70a3961487`. Times are parse plus first raster
in milliseconds. All tested Swag CRC-64s stayed the same.

| Fixture | One sample before | After | Two samples before | After |
| --- | ---: | ---: | ---: | ---: |
| Small drawing | 4.35 | 2.07 | 11.97 | 8.16 |
| Curve fills | 22.82 | 20.07 | 62.88 | 57.64 |
| Strokes | 122.15 | 116.87 | 396.87 | 403.18 |
| Clip masks | 43.44 | 42.86 | 122.55 | 119.20 |
| Large drawing | 632.84 | 652.37 | | |

At one worker the clipped bitmap went from 41.17 to 38.16 ms. The
large drawing spends most of its time creating and compositing path
coverage before the final readback.

## Direct scan conversion on color mattes

The Scope bitmap path records solid fills, outlines and clip masks as contours
on its opaque CPU targets. Eligible shapes reach the rasterizer without
building a temporary texture per fill. The shared coverage pass writes both
color mattes, including when a stroke crosses a partially covered clip.
The screenshot-independent comparison still uses the author's fill rules and
paint order.

The table shows one-worker Release medians in milliseconds from seven
interleaved samples on one AMD EPYC 7763 logical CPU. The Swag baseline is
`e3e4f7f37a` and the reference is resvg 0.50.0. See the
[phase timings and pixel checks](mixed-geometry-linux.json).

| Fixture | Swag before | Swag after | resvg | Mean difference from resvg before | Mean difference after |
| --- | ---: | ---: | ---: | ---: | ---: |
| `small.svg` | 7.59 | 6.42 | 2.28 | 0.0230 | 0.0230 |
| `curves.svg` | 37.64 | 20.67 | 17.61 | 0.3967 | 0.3967 |
| `strokes.svg` | 175.37 | 114.42 | 25.63 | 3.1819 | 2.6642 |
| `clipped.svg` | 66.43 | 18.43 | 17.37 | 0.2319 | 0.1567 |
| `dense.svg` | 82.23 | 83.21 | 79.53 | 2.5406 | 2.5406 |
| `large.svg` | 1087.96 | 396.30 | 570.10 | 1.0466 | 1.0466 |
| `sparse-curves.svg` | 1.25 | 1.25 | 1.58 | 0.0060 | 0.0060 |
| `thin-edges.svg` | 2.08 | 2.56 | 2.45 | 0.0052 | 0.0052 |

Mean difference averages the absolute 8-bit deltas in premultiplied RGB and
alpha. Six fixtures matched the baseline CRC-64, including the 16,000-path
drawing. The changed strokes and clips have smaller mean differences from
resvg. The maximum delta from the previous raster is 113 on the strokes and
195 on the clipped fixture. A focused test verifies a translucent stroke
behind a fractional clip in both a tiled and an untiled render.

## Preparing undashed strokes

The solid-stroke paths only need flattened points, their bounds, and a
check for a degenerate contour. Winding and simplicity stay deferred until
an operation requests them. Dashed strokes still measure the perimeter
used by their pattern. The regression checks a freshly flattened contour,
a contour with cached metrics, and a short two-point contour.

After direct CPU scan conversion and target readback, nine interleaved
Release runs measured these parse-plus-raster medians in milliseconds.
The benchmark used Scope's CPU bitmap options.

| Fixture | Before, 1 worker | After | Before, 4 workers | After |
| --- | ---: | ---: | ---: | ---: |
| One-pixel strokes | 70.67 | 64.29 | 71.37 | 67.69 |
| 0.5 px strokes | 21.78 | 20.78 | 21.96 | 21.04 |
| 4 px strokes | 29.99 | 28.51 | 29.07 | 28.90 |

At two samples per axis, the one-pixel stroke fixture took 414.92 versus
389.84 ms at one worker and 453.64 versus 416.06 ms at four. All six
bitmap controls and the three supersampled stroke fixtures matched their
baseline CRC-64s.

## Projection across scan bands

`dense-colored` renders two 8,000-contour fills with different colors and
partial opacity. It follows the shared CPU matte path and exposes the
cost of reprojecting every vertex for each short band. The renderer now
projects the contours once and skips the ones whose vertical bounds miss
the band. Crossings still use the same tile-local subtraction, sample
positions, winding and blend order. The device-point cache is capped at
one million points, with its bounds stored per contour.

Nine Release runs per build used the Scope options and matching CPU
sets. Medians include parsing and first rasterization in milliseconds.

| CPU budget | Swag before | Swag after | resvg 0.50.0 |
| --- | ---: | ---: | ---: |
| One logical CPU | 805.59 | 96.27 | 49.71 |
| Four logical CPUs | 853.19 | 103.64 | 59.43 |

All original bitmaps and thumbnails, the eleven generated fixtures, and
thirteen public resvg fixtures matched their Swag baseline CRC-64s. A
regression checks fractional coverage against individually drawn contours
across several clipped scan bands.

## Embedded images on shared CPU mattes

Swag samples the embedded bitmap once and mixes the sampled color into
both SVG mattes. For straight RGB and RGBA images with sixteen-bit
components, the CPU sampler quantizes each texel with integer arithmetic.
Those colors enter the same interpolation as eight-bit texels. Separable
axis-aligned sampling and cached horizontal rows apply to magnified
sixteen-bit PNGs.

One-core Release medians in milliseconds use eleven interleaved samples
on an AMD EPYC 7763 logical CPU. The baseline is Swag `60a2e9e772` and
the reference is resvg 0.50.0. Both public fixtures use 1200 by 1200 pixels.
[Phase timings and comparisons](bitmap-mattes-linux.json)

| Fixture | Swag total before | Swag total after | resvg total | Raster before | Raster after | resvg raster |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `resvg-clip.svg` | 16.38 | 11.58 | 46.01 | 16.28 | 11.48 | 45.80 |
| `resvg-embedded-rgb16.svg` | 619.36 | 24.02 | 69.84 | 619.02 | 23.66 | 69.54 |

Of 23 generated and public cases, 22 kept their Swag CRC-64. The PNG
fixture's coordinate rounding changed by at most two levels out of 255,
with a 0.0041 mean difference in premultiplied RGBA. Its mean error
against resvg decreased from 0.2661 to 0.2646. The image-under-clip
fixture kept the same pixels. A focused test gives equivalent
sixteen-bit and eight-bit images the same translucent placement and
checks their complete output.

## Sharing supersampled color coverage

CPU SVG rasterization can draw both color mattes in one pass at up to
eight samples per axis, then resolve each matte with the existing box
filter. Alpha restoration writes only the active target. Coverage for
fills and strokes still reaches both mattes. The tests compare the
paired results against separate draws at one, two, four and eight
samples per axis.

Nine interleaved Release runs at 1280 × 853 and two samples per axis
measured the following parse-plus-raster times in milliseconds. Both
builds used the Scope options and kept the same CRC-64s.

| Fixture | Before, 1 worker | After | Before, 4 workers | After |
| --- | ---: | ---: | ---: | ---: |
| Small drawing | 11.32 | 12.67 | 9.08 | 8.15 |
| Curve fills | 68.87 | 72.11 | 63.41 | 61.74 |
| One-pixel strokes | 397.31 | 263.11 | 396.00 | 231.07 |
| Clip masks | 124.18 | 81.74 | 124.14 | 78.66 |
| 0.5 px strokes | 104.01 | 69.00 | 104.60 | 61.78 |
| 4 px strokes | 149.95 | 99.55 | 131.20 | 82.71 |

The thirteen public fixtures also kept their CRC-64s at four samples
per axis. After the embedded-image sampling change, the 16-bit PNG case
kept its CRC and went from 1041 to 686 ms at four workers on the same
four-sample setting.

## Parallel processing of scan bands

A projected compound fill can give disjoint row bands to different CPU
workers. Each worker reuses its own crossing scratch. The scratch
budget limits concurrent work, and a fill joins before the next paint
command starts. The per-band transform, winding and blend rules stay
identical to the serial path.

Nine interleaved Release runs measured the colored compound fixture
with Scope's options. The table gives median parse-plus-raster times
in milliseconds under matching CPU affinities.

| CPU budget | Swag before | Swag after | resvg 0.50.0 |
| --- | ---: | ---: | ---: |
| One logical CPU | 98.69 | 98.96 | 50.44 |
| Two logical CPUs | 98.67 | 71.54 | 52.13 |
| Four logical CPUs | 104.06 | 44.83 | 55.04 |

Swag kept the same CRC-64 across the three worker counts. A four-worker
prototype's process peak on this fixture rose from 24,880 to 25,904 KiB.

## Rejecting contours outside the horizontal clip

A closed contour fully outside the target's horizontal range contributes
pairs of crossings clamped to the same boundary. Its winding cancels
without changing the covered spans. The projection step now measures
horizontal bounds along with vertical ones. It leaves a pixel of room for
rounding and uses the ordinary collection path for large coordinates.

Eleven interleaved Release runs on `dense-colored` used the Scope options
with parallel band processing. These are median parse-plus-raster times
in milliseconds under matching CPU affinities.

| CPU budget | Swag before | Swag after | resvg 0.50.0 |
| --- | ---: | ---: | ---: |
| One logical CPU | 98.65 | 63.64 | 50.07 |
| Two logical CPUs | 78.79 | 53.66 | 50.32 |
| Four logical CPUs | 47.88 | 38.91 | 50.10 |

The compound fixture, original bitmaps and thumbnails, synthetic controls
and thirteen public SVGs retain their CRC-64s. The scan-band regression
clips the same contours on both horizontal sides and compares the raster
with individual draws.

## Indexing projected contours by scan band

Short contours now enter only their intersecting scan bands, in drawing
order. Each worker reads the shared index. The renderer falls back to
checking bounds per band if the index would require more than eight
references per contour on average.

Thirteen interleaved Release runs on `dense-colored` used the Scope options.
Median parse-plus-raster times are in milliseconds under matching CPU affinities.

| CPU budget | Swag before | Swag after | resvg 0.50.0 |
| --- | ---: | ---: | ---: |
| One logical CPU | 61.78 | 54.19 | 50.11 |
| Two logical CPUs | 52.00 | 46.31 | 49.87 |
| Four logical CPUs | 44.15 | 37.47 | 51.01 |

The generated `tall-bands` fixture drives the fallback with two overlapping
fills of tall contours. Its CRC-64 matches at one, two and four workers.
Timings on that fallback varied across worker counts. The original bitmaps
and thumbnails, generated controls and thirteen public fixtures retain their
CRC-64s. The scan-band regression compares a clipped compound path containing
short contours and one contour spanning all bands with the individual fills.
