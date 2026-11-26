# Constant-time byte equality

Swag compares short inputs using overlapping scalar or vector loads that
stay inside each input slice. The length selects the load widths and offsets.
The longer loop uses an in-bounds final vector to cover a partial tail and
reduces the accumulated difference once.

Both builds used native Release, with `5f4e9e02be` as the standard library
baseline. Fifteen paired samples per profile ran on CPU 2 of an AMD EPYC
9V74 under Linux 6.18.57, targeting 15 ms per sample. The table shows
median process CPU nanoseconds per equal-input comparison and paired
95% time-ratio intervals. The raw results also cover first- and last-byte
mismatches.

| Bytes | Swag before | Swag after | OpenSSL 3.5.7 | libsodium 1.0.18 | After / before |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 2.51 | 1.95 | 2.26 | 3.66 | 0.777 [0.767, 0.784] |
| 2 | 3.04 | 1.79 | 2.63 | 3.87 | 0.591 [0.546, 0.634] |
| 7 | 4.70 | 2.21 | 3.87 | 6.61 | 0.470 [0.466, 0.471] |
| 8 | 5.21 | 2.22 | 4.36 | 7.55 | 0.427 [0.419, 0.431] |
| 15 | 8.80 | 2.21 | 8.09 | 13.97 | 0.251 [0.250, 0.252] |
| 16 | 3.32 | 1.94 | 2.48 | 15.43 | 0.583 [0.580, 0.603] |
| 17 | 3.14 | 2.56 | 9.16 | 16.95 | 0.811 [0.746, 0.824] |
| 31 | 9.31 | 2.50 | 16.31 | 34.96 | 0.268 [0.265, 0.270] |
| 32 | 3.86 | 2.48 | 16.96 | 36.41 | 0.643 [0.641, 0.646] |
| 33 | 3.60 | 2.21 | 17.47 | 37.95 | 0.613 [0.603, 0.616] |
| 48 | 4.56 | 2.26 | 26.32 | 63.66 | 0.499 [0.483, 0.504] |
| 63 | 10.13 | 2.21 | 33.79 | 87.86 | 0.220 [0.218, 0.224] |
| 64 | 3.34 | 2.23 | 38.01 | 90.57 | 0.668 [0.655, 0.674] |
| 65 | 3.59 | 3.60 | 34.77 | 92.28 | 1.003 [0.995, 1.097] |
| 4096 | 72.37 | 72.34 | 2272.62 | 8601.17 | 0.999 [0.994, 1.012] |
| 1048576 | 22263.31 | 22256.39 | 589631.19 | 2267073.29 | 0.997 [0.988, 1.013] |

The profiles through 64 bytes used 19–78% less CPU than the previous
Swag build, including the selected mismatch positions, and all their
elapsed-time intervals excluded parity. The larger profiles' intervals
included parity. The new Swag build used less median CPU time than both
external libraries in all 30 timed profiles.

All 120 additional aligned and unaligned fixtures matched the references.
Both Swag executables passed 67,336 guarded comparisons, including every
single-byte mismatch for lengths through 257 and comparisons against an
empty sequence. Twenty-five focused Core tests passed in each of native
Release and Release-safe, including AES-GCM and ChaCha20-Poly1305 verification.

In the Linux x86-64 Release and Release-safe function bodies, conditional
branches use the input lengths or iteration offsets. The length mismatch
returns before reading input bytes. For matching lengths, byte values
affect the fixed-width arithmetic and the returned equality result.

[Reproduction and disassembly command](../../../workloads/constant-time/README.md) · [Raw timings and verification fingerprints](constant-time-equal.json)
