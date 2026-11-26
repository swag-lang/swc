# BLAKE2b and BLAKE2s direct input blocks

Full nonfinal input blocks are read in place as little-endian words. Keyed hashing,
partial final blocks, and state clearing retain the same lifecycle. The ten selected
Core tests passed in native Release, including 14 OpenSSL-generated unaligned fixtures.

The common workload used 21 paired process CPU-time trials on CPU 2 of the AMD EPYC
9V74. Both builds matched OpenSSL 3.5.7 byte for byte. Rates are decimal GB/s.

| Algorithm | Bytes | Before | After | OpenSSL | Paired speedup (95% CI) |
| --- | ---: | ---: | ---: | ---: | ---: |
| BLAKE2s-256 | 64 | 0.197 | 0.214 | 0.338 | 1.10 [1.06, 1.16] |
| BLAKE2s-256 | 4096 | 0.304 | 0.333 | 0.536 | 1.10 [1.06, 1.12] |
| BLAKE2s-256 | 65536 | 0.309 | 0.345 | 0.566 | 1.12 [1.08, 1.14] |
| BLAKE2s-256 | 1048576 | 0.309 | 0.344 | 0.551 | 1.11 [1.10, 1.15] |
| BLAKE2b-512 | 64 | 0.164 | 0.201 | 0.278 | 1.22 [1.16, 1.28] |
| BLAKE2b-512 | 4096 | 0.468 | 0.550 | 0.921 | 1.20 [1.17, 1.23] |
| BLAKE2b-512 | 65536 | 0.486 | 0.577 | 0.954 | 1.19 [1.18, 1.24] |
| BLAKE2b-512 | 1048576 | 0.491 | 0.590 | 0.964 | 1.20 [1.19, 1.21] |

[Raw trials and output fingerprints](blake2-direct.json).
