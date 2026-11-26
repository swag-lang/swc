# CPU SVG raster benchmark

Run from the checkout with a Release compiler and [resvg 0.50.0](https://github.com/linebender/resvg/releases/tag/v0.50.0).
On Linux, copy `bin/runtime` beside an externally built compiler as described in
[the tool guide](../../../tools/README.md#linux-compiler-build).

```sh
python3 bench/workloads/svgraster/run.py --swc /path/to/swc --resvg /path/to/resvg
```

The generated corpus covers small drawings, curve fills, translucent strokes, short-lived
clip masks, one dense compound fill, and a large collection of independent paths. With
`--filesamples /path/to/filesamples/samples/image/svg`, the runner uses the four original
files described in [std.pixel.image.057](../../../backlog/std.pixel.image.md#stdpixelimage057--svg-cpu-rasterization-is-far-slower-than-resvg).
It verifies their SHA-256 digests and caps the largest output at 2048 pixels.

The runner prints separate parse, raster and combined medians from seven repetitions. Each
Swag sample warms the engine once and parses a fresh drawing before calling
`Svg.Drawing.rasterize(width, height, 1)`, the CPU path Scope uses for bitmap output. resvg
reports XML parsing, SVG parsing and rendering through `--perf`. File reading, image saving,
checksumming, window startup and presentation are excluded. `--workers` sets the number of
Swag runtime workers (one by default).

Pass `--against-bin /path/to/baseline/bin` to rebuild the same benchmark against a baseline
standard library with the same compiler. The runner alternates the Swag builds and checks
their raster CRC-64 values on every fixture. It prints ratios against resvg for timings.

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
