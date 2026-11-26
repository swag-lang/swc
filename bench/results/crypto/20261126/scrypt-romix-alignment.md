# scrypt ROMix storage alignment

The ROMix scratch allocation requests 64-byte alignment so its
64-byte Salsa20/8 chunks do not straddle cache lines on the tested
machine. The matrix and alternating block are covered by the
existing secure clear when the derivation finishes.

Both native Release builds used library `fc5207d2e5` and compiler
`44e09064f1`. Seventeen shuffled paired rounds ran on CPU 2 of an
AMD EPYC 9V74 under Linux 6.18.57. The profiles used one lane, one
worker and a 32-byte result. Every derived key matched libsodium
1.0.18, Python’s OpenSSL build and the native OpenSSL 4.1.0 probe.

The table shows median process CPU milliseconds and paired 95%
candidate-to-baseline time ratios.

| N | r | Before | Aligned | libsodium | OpenSSL 4.1.0 | Aligned / before |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1024 | 1 | 0.205 | 0.199 | 0.196 | 0.275 | 1.040 [0.952, 1.174] |
| 16384 | 8 | 25.382 | 25.527 | 27.891 | 39.611 | 1.007 [0.952, 1.126] |
| 65536 | 8 | 118.935 | 113.788 | 140.796 | 166.422 | 0.969 [0.934, 0.990] |

At 64 MiB, the aligned allocation used 3.1% less CPU. A seven-round
screen gave 4.8% less CPU for that profile. The 128 KiB and 16 MiB
CPU intervals included parity. A separate 31-round 128 KiB replay
gave a CPU ratio of 1.000 [1.000, 1.011]. The primary elapsed-time
intervals included parity in all three profiles.

Twelve focused Core cases passed in each of native Release and
Release-safe, including the RFC 7914 sixteen-lane scrypt vector.

[Reproduction](../../../workloads/kdf-replay/README.md#standalone-openssl-versions) · [Raw samples and keys](scrypt-romix-alignment.json)
