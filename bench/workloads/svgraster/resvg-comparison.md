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
