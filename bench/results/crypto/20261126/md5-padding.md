# Direct MD5 padding and packed digest output

MD5 finalization places the suffix and length in the final one or two
blocks. One vector store serializes the full digest. The change also
applies to incremental contexts.

The native Release timing used the thread CPU clock on AMD EPYC 9V74.
The table reports nanoseconds per hash. All measured digests matched
OpenSSL 3.5.7.

| Mode | Bytes | Before | After | OpenSSL | Paired speedup (95% CI) |
| --- | ---: | ---: | ---: | ---: | ---: |
| one-shot | 16 | 100 | 101 | 106 | 0.986 [0.969, 0.998] |
| one-shot | 55 | 96 | 93 | 104 | 1.019 [0.983, 1.034] |
| one-shot | 56 | 199 | 190 | 188 | 1.053 [1.040, 1.068] |
| one-shot | 63 | 201 | 190 | 186 | 1.058 [1.054, 1.075] |
| one-shot | 64 | 193 | 187 | 190 | 1.034 [1.028, 1.096] |
| two updates | 16 | 113 | 107 | 112 | 1.053 [1.016, 1.080] |
| two updates | 55 | 114 | 106 | 110 | 1.085 [1.066, 1.091] |
| two updates | 56 | 205 | 197 | 193 | 1.036 [1.017, 1.040] |
| two updates | 63 | 206 | 198 | 195 | 1.036 [1.027, 1.053] |
| two updates | 64 | 202 | 199 | 195 | 1.018 [0.992, 1.035] |

A separate 25-sample repeat found 64 KiB and 1 MiB medians within 0.43%
of the previous Swag build. A second exact reference used OpenSSL 4.1.0.
The external sweep matched 6,112 digests, including every split of the
selected padding boundaries and of the unaligned 4,097-byte input.
All three focused cases passed JIT and native Release and Release-safe.

[Raw short trials](md5-padding.json) · [Bulk retest](md5-padding-bulk.json) · [OpenSSL 4.1.0 trials](md5-padding-openssl-current.json).
