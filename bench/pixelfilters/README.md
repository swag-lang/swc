# Parallel pixel-filter overhead

Run from the repository root after the machine-load admission check:

```powershell
bin/swc.dm.exe run -f src/pixelfilters.swg --module-file bench/pixelfilters/module.swg -bc release --num-cores 6
```

The benchmark inverts patterned RGBA8 images with one runtime worker, then four. The pool can
grow but cannot shrink, so that order is deliberate. Each image gets two untimed inversions
and three samples. Every sample performs an even number of inversions; an untimed byte comparison
checks the entire image, including alpha. Assertions remain enabled in Release builds.

Pool startup and allocation stay outside the timer. Small images process 1,048,576 pixels per
sample; the 2048 x 2048 case runs four inversions. These local samples are not interleaved or
affinity-pinned, and a loaded machine can obscure both scheduling and throughput comparisons.

To separate compilation from measurement, build once with an explicit ignored output directory:

```powershell
$benchOutput = Join-Path $PWD '.tmp/parallel-cost-bench'
bin/swc.dm.exe build -f src/pixelfilters.swg --module-file bench/pixelfilters/module.swg -bc release --out-dir $benchOutput --num-cores 6
.tmp/parallel-cost-bench/pixelfilters.exe
```

Admit the build and each executable run separately. Use a quiet machine for timing comparisons.

Before runtime adaptation, on 2026-09-08, median one-worker/four-worker times in microseconds were:

| Image | Iterations | One worker | Four workers |
| --- | --- | --- | --- |
| 8 x 8 | 16384 | 607 | 84936 |
| 32 x 32 | 1024 | 234 | 5248 |
| 128 x 128 | 64 | 208 | 449 |
| 512 x 512 | 4 | 207 | 162 |
| 2048 x 2048 | 4 | 4525 | 1935 |

The original measurement used the same body as a native `#test`; the standalone entry now makes
it possible to rerun the executable without rebuilding its imports.

With the runtime cost hints, a run admitted at 7% average CPU on the same day gave these medians:

| Image | One worker (us) | Four workers (us) |
| --- | --- | --- |
| 8 x 8 | 865 | 787 |
| 32 x 32 | 307 | 340 |
| 128 x 128 | 563 | 185 |
| 512 x 512 | 254 | 132 |
| 2048 x 2048 | 4752 | 2002 |

There were visible scheduling outliers, including a 3680 us one-worker sample at 128 x 128.
The useful result is that the tiny-image worker penalty disappears while large buffers still
benefit from several workers; these samples do not establish an exact portable speedup.
