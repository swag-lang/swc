# SHA-512 block batches and packed schedule additions

The complete-block loop reuses its schedule allocation across blocks.
Packed schedule expansion adds round constants before consumption.
The shared compression path covers SHA-384 and both truncated SHA-512 variants.

Native Release used 15 rotated thread CPU-time samples on CPU 0 of the
AMD EPYC 9V74 and OpenSSL 3.5.7 EVP for exact comparison. The selected
profile medians are nanoseconds per hash.

| Algorithm | Message bytes | Before | After | OpenSSL | Paired speedup (95% CI) |
| --- | ---: | ---: | ---: | ---: | ---: |
| sha512 | 16 | 260 | 246 | 203 | 1.058 [0.969, 1.157] |
| sha512 | 64 | 286 | 256 | 201 | 1.088 [1.056, 1.158] |
| sha384 | 16 | 262 | 252 | 201 | 1.047 [1.015, 1.060] |
| sha384 | 64 | 264 | 257 | 198 | 1.033 [1.016, 1.059] |
| sha512-224 | 16 | 261 | 251 | 199 | 1.043 [1.030, 1.058] |
| sha512-224 | 64 | 265 | 252 | 198 | 1.046 [1.037, 1.057] |
| sha512-256 | 16 | 267 | 250 | 198 | 1.062 [1.047, 1.084] |
| sha512-256 | 64 | 266 | 250 | 199 | 1.056 [1.049, 1.149] |
| sha512 | 1048576 | 1919250 | 1743000 | 1207500 | 1.099 [1.074, 1.111] |
| sha384 | 1048576 | 1929750 | 1756500 | 1210500 | 1.105 [1.086, 1.152] |
| sha512-224 | 1048576 | 1928500 | 1739000 | 1208000 | 1.108 [1.105, 1.190] |
| sha512-256 | 1048576 | 1961000 | 1734500 | 1206750 | 1.128 [1.110, 1.203] |

The 1 MiB family profiles improved by 10–13%. The common PBKDF2 replay
matched all outputs and measured lower median CPU time for SHA-384 and
SHA-512. Another 432 one-shot and streaming boundary cases matched OpenSSL.
The 17 focused SHA-512, HMAC, HKDF and PBKDF2 cases passed native Release,
Release-safe and JIT.

[Raw full profiles](sha512-block-batch.json) · [Short-input retest](sha512-block-batch-short.json) · [PBKDF2 control](sha512-block-batch-pbkdf2.json).
