# CPU rasterization load balance

```powershell
bin/swc.dm.exe run -f src/rasterbalance.swg --module-file bench/rasterbalance/module.swg -bc release --num-cores 6
```

The benchmark records a real `Pixel.Painter` stream and repeatedly draws it with `Pixel.RenderCpu`.
Sixteen translucent rectangles cover either the whole surface or its first or last quarter. A
full-surface background keeps the batch bounds identical in all three cases. The small control
uses a 32 by 32 surface; the other cases use 512 by 512 surfaces.

Each case warms up four times and records three samples of two draws. Painter recording,
surface allocation, readback, and comparison stay outside the timed region. Every four-worker
result is compared byte for byte with the owned image produced by the one-worker control.
The process increases its worker count from one to four and never needs to shrink the pool.

Admit each build and run with the repository's machine-load check. The same benchmark source
must be used on both sides of a comparison; do not run a timing measurement beside another build.

On 2026-09-08, the same DevMode compiler built this Release program before and after replacing
one raster band per worker with fixed sixteen-row blocks. Admission CPU load was 2% for both
runs. These are medians of three samples, in microseconds:

| Scene | Before, one worker | After, one worker | Before, four workers | After, four workers |
| --- | ---: | ---: | ---: | ---: |
| Small | 2762 | 2732 | 4955 | 2826 |
| Uniform | 675390 | 660036 | 186075 | 191885 |
| Heavy first quarter | 194959 | 184662 | 176384 | 53013 |
| Heavy last quarter | 200021 | 201635 | 172644 | 55325 |

The localized-overdraw cases improve by about 3.1 to 3.3 times with four workers. The uniform
four-worker case is about 3% slower in this pair; more blocks repeat more triangle setup.
Shared-machine variance is visible in the small control, so these results establish neither
a universal speedup nor a precise small-draw improvement.

Raster blocks keep exclusive row ownership and preserve triangle order for each pixel. The
pixel-area threshold and the serial whole-range path remain: subdividing a tiny drawing or
rescanning its triangles on one worker would add work without useful parallelism. Small draws
now take that decision before querying the worker count, so they do not start an unused pool.
