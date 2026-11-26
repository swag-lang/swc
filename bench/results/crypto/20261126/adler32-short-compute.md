# Adler-32 one-shot short buffers

The short one-shot path computes the Adler sums directly with packed
four-byte steps. The special handling of 22 and 23 all-one bytes exercises
the upper bound of the unreduced sum.

Eleven paired process CPU-time trials on AMD EPYC 9V74 showed the strongest
gains between 8 and 31 bytes. Throughput at 1 MiB was about 31.7 GB/s.
The ten two-update control profiles gave equivalent streaming rates.

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| adler32 | 1 | 0 | candidate | baseline | GB/s | 0.207 | 0.154 | 1.37 [1.34, 1.64] |
| adler32 | 2 | 0 | candidate | baseline | GB/s | 0.392 | 0.262 | 1.47 [1.18, 1.73] |
| adler32 | 3 | 0 | candidate | baseline | GB/s | 0.532 | 0.399 | 1.35 [1.31, 1.43] |
| adler32 | 4 | 0 | candidate | baseline | GB/s | 0.749 | 0.501 | 1.5 [1.29, 1.92] |
| adler32 | 7 | 0 | candidate | baseline | GB/s | 1.13 | 0.806 | 1.41 [1.38, 1.48] |
| adler32 | 8 | 0 | candidate | baseline | GB/s | 1.24 | 0.898 | 1.39 [1.31, 1.43] |
| adler32 | 12 | 0 | candidate | baseline | GB/s | 1.49 | 1.2 | 1.24 [1.22, 1.27] |
| adler32 | 15 | 0 | candidate | baseline | GB/s | 1.66 | 1.37 | 1.22 [1.09, 1.34] |
| adler32 | 16 | 0 | candidate | baseline | GB/s | 2.92 | 2.1 | 1.4 [1.26, 1.51] |
| adler32 | 19 | 0 | candidate | baseline | GB/s | 3.08 | 2.24 | 1.36 [1.32, 1.38] |
| adler32 | 22 | 0 | candidate | baseline | GB/s | 3.15 | 2.18 | 1.46 [1.22, 1.55] |
| adler32 | 23 | 0 | candidate | baseline | GB/s | 3.08 | 2.13 | 1.49 [1.46, 1.61] |
| adler32 | 31 | 0 | candidate | baseline | GB/s | 2.89 | 2.06 | 1.41 [1.27, 1.43] |
| adler32 | 32 | 0 | candidate | baseline | GB/s | 5.17 | 3.9 | 1.33 [1.31, 1.4] |
| adler32 | 63 | 0 | candidate | baseline | GB/s | 4.82 | 3.9 | 1.24 [1.17, 1.25] |
| adler32 | 64 | 0 | candidate | baseline | GB/s | 7.86 | 6.94 | 1.14 [1.12, 1.17] |
| adler32 | 127 | 0 | candidate | baseline | GB/s | 7.02 | 6.36 | 1.1 [1.08, 1.12] |
| adler32 | 128 | 0 | candidate | baseline | GB/s | 11.1 | 10.4 | 1.08 [1.03, 1.27] |
| adler32 | 4096 | 0 | candidate | baseline | GB/s | 30.7 | 30.6 | 1.01 [0.954, 1.02] |
| adler32 | 1048576 | 0 | candidate | baseline | GB/s | 31.7 | 31.6 | 1 [0.956, 1.03] |

Focused Release JIT and native cases passed. Protected end-of-page
buffers covered 516 boundary layouts.

[Raw one-shot trials](adler32-short-compute.json) · [Streaming control](adler32-short-stream-control.json).
