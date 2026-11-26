# CPU vector paths with Swag and AGG

Each workload draws 1,200 shapes at 1,200 by 900 pixels on an opaque
BGRA surface. Both engines use the same coordinates and black ink. The
fill closes the polyline against a straight baseline under nonzero
winding. The stroke uses a width of 2.25 pixels, round joins and butt caps.
The runner alternates the engines and includes one warmup inside every
process. Surface setup, geometry preparation and painting are timed.
Coverage is the sum of the darkened blue channel after painting.

## Linux results

Thirteen interleaved Release runs used one AMD EPYC 7763 logical CPU.
Swag scanlines use `3e33c0033e` and the single-contour triangle route
uses `f9f4c471d5`. AGG uses revision
`c4f36b4432142f22c0bf82c6fbdb41567a236be2`.
[Timings and coverage](linux-epyc.json)

| Workload | Swag triangle route, ms | Swag scanline route, ms | AGG, ms |
| --- | ---: | ---: | ---: |
| Fills | 65.10 | 27.34 | 11.66 |
| Strokes | | 36.46 | 20.20 |

The explicit winding rule is the overload used by PDF and SVG. Its
recording phase takes 1.44 ms in the fills test. The plain single-contour
overload tessellates and takes 14.48 ms to record. The scanline route
intersects four vertical sample lines per row. AGG walks fixed-point
edges, accumulating covered area and vertical coverage in cells, then
emits spans. Its stroker also builds the two joined sides of a contour.
Total ink differs by about 0.08% for the scanline fills and 0.29% for
the strokes. Edge pixel values reflect different antialiasing.
[AGG cell accumulation](https://github.com/ghaerr/agg-2.6/blob/c4f36b4432142f22c0bf82c6fbdb41567a236be2/agg-src/include/agg_rasterizer_cells_aa.h)
[AGG stroke outline](https://github.com/ghaerr/agg-2.6/blob/c4f36b4432142f22c0bf82c6fbdb41567a236be2/agg-src/src/agg_vcgen_stroke.cpp)

## Reproducing

Build Swag with the intended standard library and its matching runtime.
Build the reference with the pinned AGG checkout under `/tmp/agg-2.6`.

```sh
swc build -d bench/workloads/cpuvectors/src \
  --module-file bench/workloads/cpuvectors/module.swg -bc release \
  -n vectors --out-dir /tmp/cpuvectors/out --work-dir /tmp/cpuvectors/work

git clone https://github.com/ghaerr/agg-2.6.git /tmp/agg-2.6
git -C /tmp/agg-2.6 checkout c4f36b4432142f22c0bf82c6fbdb41567a236be2
c++ -O3 -std=c++17 -I/tmp/agg-2.6/agg-src/include \
  bench/workloads/cpuvectors/agg.cpp /tmp/agg-2.6/agg-src/src/agg_vcgen_stroke.cpp \
  -o /tmp/cpuvectors/agg
python3 bench/workloads/cpuvectors/run.py --swag /tmp/cpuvectors/out/vectors \
  --agg /tmp/cpuvectors/agg --cpu 4 --output /tmp/cpuvectors/results.json
```
