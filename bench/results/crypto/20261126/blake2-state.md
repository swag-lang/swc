# BLAKE2 packed state and add dependencies

Both BLAKE2 compressors use packed loads and stores for state initialization
and feed-forward. In each G half, adding the message word to the first state
word can begin independently of the second. Existing secure clears cover
the local message and state arrays.

Both Swag builds used native Release with `1858c17b50` as the standard
library baseline. Fifteen paired samples per profile ran on CPU 2 of an
AMD EPYC 9V74 under Linux 6.18.57, targeting 30 ms each. The references were
OpenSSL 3.5.7, libb2 0.98.1 and libsodium 1.0.18. The table shows median
process CPU nanoseconds per one-shot digest and paired 95% time-ratio
intervals.

| Algorithm | Bytes | Before | Packed | OpenSSL | libb2 | libsodium | Packed / before |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| BLAKE2b | 16 | 325 | 320 | 232 | 182 | 148 | 0.983 [0.930, 1.001] |
| BLAKE2b | 64 | 325 | 313 | 237 | 187 | 152 | 0.974 [0.869, 1.013] |
| BLAKE2b | 128 | 327 | 304 | 235 | 183 | 147 | 0.940 [0.881, 0.962] |
| BLAKE2b | 4096 | 7107 | 6760 | 4390 | 5277 | 3963 | 0.950 [0.932, 0.959] |
| BLAKE2b | 1048576 | 1817075 | 1703170 | 1093302 | 1351371 | 1015806 | 0.940 [0.881, 0.959] |
| BLAKE2s | 16 | 298 | 281 | 189 | 140 | — | 0.942 [0.931, 0.964] |
| BLAKE2s | 64 | 293 | 290 | 185 | 142 | — | 0.929 [0.909, 1.131] |
| BLAKE2s | 128 | 488 | 455 | 299 | 261 | — | 0.926 [0.894, 0.943] |
| BLAKE2s | 4096 | 11899 | 11257 | 7296 | 7747 | — | 0.938 [0.934, 0.946] |
| BLAKE2s | 1048576 | 3026931 | 2838048 | 1874379 | 1973544 | — | 0.940 [0.908, 0.943] |

BLAKE2b used 5–6% less CPU from 128 bytes through 1 MiB. BLAKE2s used
6–8% less CPU at 16, 128, 4096 and 1048576 bytes. The same seven
elapsed-time intervals excluded parity. At 1 MiB, the fastest references
were libsodium for BLAKE2b and OpenSSL for BLAKE2s. Swag took about
1.68 and 1.51 times their CPU time respectively. libb2 led the 16- and
64-byte BLAKE2s profiles.

Every timed digest agreed across the paired builds and references.
Thirty-six additional fixtures covered empty, unaligned and
block-boundary inputs with the optional libraries. The default reference
build also passed its four-fixture smoke. Ten focused Core cases passed
in each of native Release and Release-safe, including incremental and
keyed vectors.

[Reproduction](../../../workloads/crypto/README.md#blake2-references) · [Raw samples and verification fingerprints](blake2-state.json)
