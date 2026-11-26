# Packed SHA-512 message schedule

SHA-512 expands two words of its schedule together. The 13 focused native Release
Core tests passed, including truncated SHA-512 variants and HMAC, HKDF, and Ed25519.
The SHA-224 and SHA-512 test fixtures also passed on Release-safe after constraining
synthetic input byte generation before narrowing.

CPU 3 of the AMD EPYC 9V74 was pinned for 15 CPU-time samples per build and size.
Timing series used alternating processes and all digests matched hashlib.
The baseline includes the preceding portable SHA block change.

| Bytes | Before (µs) | After (µs) | Speedup (95% CI) |
| ---: | ---: | ---: | ---: |
| 16 | 76728 | 74506 | 1.030 [1.004, 1.057] |
| 64 | 50513 | 47451 | 1.065 [1.047, 1.082] |
| 1024 | 26928 | 25220 | 1.068 [1.051, 1.085] |
| 16384 | 23711 | 22396 | 1.059 [1.043, 1.074] |
| 65536 | 23384 | 22513 | 1.039 [0.949, 1.136] |
| 1048576 | 23524 | 22178 | 1.061 [1.046, 1.075] |

[Raw trials and digest fingerprints](sha512-schedule.json).
