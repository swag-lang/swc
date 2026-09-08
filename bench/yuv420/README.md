# Planar YUV420 conversion

```powershell
bin/swc.dm.exe run -f src/yuv420.swg --module-file bench/yuv420/module.swg -bc release --num-cores 6
```

The benchmark converts varying luma and chroma samples into a reused RGB image, with one worker
and then four. Sizes cover a tiny image, a thumbnail with an odd height, 1080p, and a 4K-width
image with an odd height. Allocation, input generation, and byte-for-byte comparison against
`convertRowsToRgb` stay outside the timed region. Each case warms up 32 times and records three
samples. The printed duration covers all repetitions in that sample.

The input allocation includes sixteen trailing bytes so the same source can measure the older
converter, whose SIMD chroma reads exceeded the visible plane. The pixel module's
`yuv.win32.test.swg` separately checks tightly bounded chroma planes against an inaccessible page;
`yuv.parallel.test.swg` checks every pixel against scalar color arithmetic, across all three
matrices and both ranges, with odd dimensions and padded strides.

Admit each command with the repository's machine-load check. Do not benchmark beside another
build. On 2026-09-08, the same DevMode compiler built the Release program before and after
replacing worker-sized bands with runtime-scheduled row pairs and restricting SIMD chroma reads
to eight bytes. Admission CPU load was 5% for both runs. Medians, in microseconds:

| Size | Repetitions | Before, one worker | After, one worker | Before, four workers | After, four workers |
| --- | ---: | ---: | ---: | ---: | ---: |
| 16 x 16 | 10000 | 7540 | 7105 | 7828 | 7144 |
| 320 x 181 | 200 | 31201 | 23148 | 9874 | 7930 |
| 1920 x 1080 | 20 | 108962 | 85612 | 25184 | 22432 |
| 3840 x 2161 | 5 | 89389 | 78319 | 24284 | 23106 |

Four-worker times fall by about 5% to 20% in this pair. These measurements cover both changes;
they do not isolate scheduler gains from the narrower SIMD loads. Shared-machine and frequency
variation remain visible, particularly in the one-worker and tiny-image samples. The tiny-image
test also verifies separately that conversion does not start an unused worker pool.
