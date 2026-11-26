# CPU SVG raster benchmark

Run from the checkout with a Release compiler and [resvg 0.50.0](https://github.com/linebender/resvg/releases/tag/v0.50.0).
On Linux, copy `bin/runtime` beside an externally built compiler as described in
[the tool guide](../../../tools/README.md#linux-compiler-build).

```sh
python3 bench/workloads/svgraster/run.py --swc /path/to/swc --resvg /path/to/resvg
```

The generated corpus covers small drawings, curve fills, translucent strokes, short-lived
clip masks, one dense compound fill, and a large collection of independent paths. The
`sparse-curves` fixture distributes curved contours over mostly empty sample rows.
`thin-edges` concentrates subpixel contours on a few sample rows, with many crossings
per active row. `hairline-strokes` and `wide-strokes` draw the same translucent
curves with 0.5 px and 4 px pens. Pass `--filesamples /path/to/filesamples/samples/image/svg`
to use the four originals described in [std.pixel.image.057](../../../backlog/std.pixel.image.md#stdpixelimage057--svg-cpu-rasterization-is-far-slower-than-resvg).
It verifies their SHA-256 digests and caps the largest output at 2048 pixels.

Add `--public` to include 13 fixtures from the pinned resvg 0.50.0 test suite.
They exercise clip paths, fill rules, acute and round joins, square caps,
transformed rectangles, dash patterns, and an embedded 16-bit PNG. The
runner downloads and verifies each file against its SHA-256 in the
[public fixture manifest](public-fixtures.json).

The runner prints separate parse, raster and combined medians from seven repetitions. Each
Swag sample warms the engine once and parses a fresh drawing before calling
`Svg.Drawing.rasterize(width, height, 1)`. Pass `--scope` to measure the bitmap path
with Scope's `preferScanFills` parse option. When comparing a baseline in this mode, use
standard-library sources that also support the option. resvg reports XML parsing, SVG
parsing and rendering through `--perf`. File reading, image saving,
checksumming, window startup and presentation are excluded. `--workers` sets the number of
Swag runtime workers (one by default).

Pass `--against-bin /path/to/baseline/bin` to rebuild the same benchmark against a baseline
standard library with the same compiler. The runner alternates the Swag builds and checks
their raster CRC-64 values on every fixture. For antialiasing changes, add
`--report-raster-differences` to print both checksums for each changed fixture.
Each build must still produce deterministic output across repetitions.
The runner prints ratios against resvg for timings.

On Linux x86-64 (AMD EPYC 9V45), with one worker and seven interleaved repetitions, the generated
corpus gave the following median parse-plus-raster times in milliseconds. The baseline was
`6105c47674`. Every Swag output matched the baseline CRC-64.

| Fixture | Baseline | Swag | resvg 0.50.0 |
| --- | ---: | ---: | ---: |
| Small drawing | 12.46 | 6.43 | 1.36 |
| Curve fills | 67.49 | 59.11 | 9.94 |
| Strokes | 352.78 | 305.95 | 16.43 |
| Clip masks | 107.59 | 68.18 | 10.34 |
| Dense compound fill | 295.11 | 74.04 | 49.58 |
| Large drawing | 1899.13 | 1799.01 | 291.15 |

The next comparison uses `051f71a467` as the baseline. It measures the same generated corpus
after sharing geometry and coverage between the two CPU mattes, compositing solid strokes from
their coverage, and indexing large parallel batches by row band. All Swag raster CRC-64 values
matched the corresponding baseline. Results are median parse-plus-raster milliseconds on the
same Linux host, with seven one-worker repetitions and three four-worker repetitions.

| Fixture | One worker baseline | Swag | resvg | Four workers baseline | Swag | resvg |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Small drawing | 6.28 | 4.92 | 1.34 | 25.53 | 8.92 | 2.22 |
| Curve fills | 63.69 | 43.75 | 9.65 | 88.96 | 32.34 | 13.12 |
| Strokes | 288.15 | 117.25 | 16.73 | 407.60 | 125.87 | 18.71 |
| Clip masks | 68.29 | 44.46 | 10.39 | 77.66 | 42.05 | 11.35 |
| Dense compound fill | 74.46 | 70.71 | 50.94 | 74.84 | 68.54 | 74.42 |
| Large drawing | 1896.49 | 1312.27 | 315.09 | 2296.20 | 896.15 | 280.98 |

## Original FileSamples SVGs

The four SHA-256-verified originals were measured against `844f2af028` on the same Linux
x86-64 host. The one-worker run used seven interleaved repetitions pinned to one CPU. The
four-worker run used three interleaved repetitions pinned to four CPUs. Each Swag output
matched its baseline CRC-64 in both runs.

| SVG source | Output px | One worker baseline (ms) | Swag (ms) | resvg (ms) | Four workers baseline (ms) | Swag (ms) | resvg (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `sample_640×426.svg` | 640 × 426 | 90.80 | 84.28 | 5.87 | 85.48 | 74.85 | 7.50 |
| `sample_1280×853.svg` | 1280 × 853 | 1427.01 | 136.10 | 21.31 | 1389.61 | 146.40 | 22.34 |
| `sample_1920×1280.svg` | 1920 × 1280 | 273.76 | 211.71 | 53.60 | 232.83 | 174.76 | 45.97 |
| `sample_5184×3456.svg` | 2048 × 1365 | 2545.78 | 1510.16 | 254.74 | 2445.01 | 1542.69 | 249.80 |

On the 1280 × 853 input, segment intersection tests took about 80% of the baseline CPU
profile. Contour edge bounds reject disjoint groups before those tests run. All four drawings
use black ink, so one white matte recovers their coverage. Releasing oversized tessellation
and fill scratch tables reduces the cost of small regions that follow large compound paths.

The [comparison with the resvg and tiny-skia code](resvg-comparison.md) measures the effect
of selecting scan conversion, keeping a drawing for a second render and changing the tile
size. It also compares the resulting alpha coverage.
