# SHA-512 schedule expansion and round groups

The compression function consumes the original sixteen words first. It
then expands eight schedule words immediately before their eight rounds,
using the same paired rotations throughout. This applies to SHA-384, SHA-512
and the SHA-512/224 and SHA-512/256 variants.

Both Swag builds used native Release, with `51ea340903` as the standard
library baseline. Fifteen paired samples per profile ran on CPU 2 of an
AMD EPYC 9V74 under Linux 6.18.57, targeting 30 ms each. The table shows
median process CPU nanoseconds per operation and paired 95% time-ratio
intervals. The raw samples include the 111-, 112- and 128-byte profiles.

| Algorithm | Message bytes | Before | Phased | OpenSSL 3.5.7 | Phased / before |
| --- | ---: | ---: | ---: | ---: | ---: |
| SHA-384 | 16 | 355 | 268 | 213 | 0.759 [0.728, 0.766] |
| SHA-384 | 4096 | 10781 | 7922 | 5098 | 0.737 [0.724, 0.744] |
| SHA-384 | 1048576 | 2662152 | 1966895 | 1244452 | 0.740 [0.727, 0.777] |
| SHA-512 | 16 | 351 | 272 | 203 | 0.761 [0.752, 0.790] |
| SHA-512 | 4096 | 10645 | 7901 | 4991 | 0.741 [0.733, 0.749] |
| SHA-512 | 1048576 | 2654928 | 1941179 | 1234656 | 0.733 [0.698, 0.737] |
| HMAC-SHA-384 | 16 | 1515 | 1215 | 841 | 0.774 [0.698, 0.821] |
| HMAC-SHA-384 | 4096 | 11850 | 8758 | 5614 | 0.748 [0.732, 0.752] |
| HMAC-SHA-384 | 1048576 | 2649554 | 1950257 | 1228091 | 0.739 [0.729, 0.742] |
| HMAC-SHA-512 | 16 | 1516 | 1149 | 834 | 0.753 [0.734, 0.791] |
| HMAC-SHA-512 | 4096 | 11902 | 8896 | 5613 | 0.749 [0.734, 0.766] |
| HMAC-SHA-512 | 1048576 | 2699559 | 1971101 | 1238699 | 0.729 [0.693, 0.737] |

All 24 profiles used 22–27% less CPU time. Every paired elapsed-time
interval also excluded parity. At 1 MiB the Swag digests and tags took
about 1.6 times OpenSSL's CPU time.

Every timed digest and tag matched OpenSSL. An additional 32 unaligned
fixtures covered empty inputs and the padding and block boundaries.
Seventeen focused Core cases passed in both native Release and
Release-safe, including the truncated SHA-512 variants, HMAC vectors,
PBKDF2 and HKDF.

[Reproduction](../../../workloads/crypto/README.md) · [Raw samples and verification fingerprints](sha512-interleaving.json)
