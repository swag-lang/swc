# KMAC bytepad and empty-customization initialization

The empty-customization path uses the precomputed public KMAC cSHAKE seed.
The other short key and customization blocks assemble bytepad in one
buffer and then absorb it. The generic path handles longer encodings.

The native Release experiment used 15 rotated samples and the thread CPU
clock on AMD EPYC 9V74 CPU 0. OpenSSL 3.5.7 selected tag and customization
options before timing. Both implementations received the raw key per call.
Times are nanoseconds per tag for 64-byte messages.

| KMAC security bits | Key bytes | Customization bytes | Before | After | OpenSSL | Paired speedup (95% CI) |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 128 | 32 | 0 | 1188 | 768 | 971 | 1.543 [1.446, 1.606] |
| 128 | 32 | 12 | 1209 | 1150 | 972 | 1.031 [1.014, 1.159] |
| 256 | 32 | 0 | 1203 | 795 | 963 | 1.512 [1.443, 1.564] |
| 256 | 32 | 12 | 1178 | 1130 | 965 | 1.042 [1.011, 1.111] |
| 128 | 321 | 0 | 1526 | 1136 | 1252 | 1.366 [1.329, 1.413] |
| 128 | 321 | 258 | 1905 | 1759 | 1522 | 1.051 [1.045, 1.150] |
| 256 | 321 | 0 | 1827 | 1460 | 1507 | 1.273 [1.186, 1.305] |
| 256 | 321 | 258 | 2146 | 2129 | 1782 | 1.036 [1.009, 1.046] |

The 1 MiB KMAC measurements were within 1.1% of the baseline medians.
The separate SHA3-256 control was within 0.73% across measured sizes.
The external sweep matched 1,728 KMAC and KMACXOF cases, including
encoding, key, customization, message and squeeze boundaries.
Thirteen focused cases passed native Release, Release-safe and JIT.
The compile-time seed also passed an isolated Windows-target check for
all 50 lanes. Full Windows Core checking requires Win32 foreign calls.

[Raw short-key trials](kmac-bytepad.json) · [Long-key trials](kmac-bytepad-long.json) · [SHA3-256 control](kmac-sha3-control.json).
