# HMAC-SHA3 pad reuse

HMAC-SHA3 uses a single word-sized pad buffer for inner and outer state
initialization. The long-key path calls the one-shot SHA-3 implementation.

Fifteen paired process CPU-time rounds used one AMD EPYC 9V74 CPU and a
fresh keyed call in each iteration. Times are nanoseconds per HMAC-SHA3-256
tag. The additional 30-round 1 MiB retest found median times within 0.35%
for all three keys.

| Key bytes | Message bytes | Before | After | OpenSSL | Paired speedup (95% CI) |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 32 | 0 | 1782 | 1532 | 1356 | 1.151 [1.133, 1.175] |
| 32 | 64 | 1758 | 1506 | 1345 | 1.163 [1.155, 1.210] |
| 32 | 1024 | 3913 | 3614 | 3231 | 1.064 [1.023, 1.084] |
| 136 | 0 | 1790 | 1507 | 1344 | 1.170 [1.098, 1.179] |
| 136 | 64 | 1767 | 1583 | 1369 | 1.114 [1.093, 1.156] |
| 136 | 1024 | 3919 | 3726 | 3260 | 1.052 [1.035, 1.068] |
| 256 | 0 | 2487 | 2195 | 2015 | 1.140 [1.112, 1.159] |
| 256 | 64 | 2553 | 2155 | 2017 | 1.149 [1.101, 1.173] |
| 256 | 1024 | 4676 | 4273 | 3938 | 1.075 [1.050, 1.113] |

All 648 exact OpenSSL comparisons matched across the four digest sizes and
one-shot and reused streaming contexts. The four focused tests passed native
Release, Release-safe and JIT.

[Raw paired trials](hmac-sha3-pads.json) · [1 MiB retest](hmac-sha3-pads-bulk.json).
