# Portable SHA block processing

SHA-1, SHA-224/256 and SHA-384/512 now process complete input blocks directly,
keep byte-order conversions wide and use typed rotates in the scalar round paths.
The 22 selected Core native Release tests passed, including HMAC, HKDF and Ed25519
consumers. All timed digests agreed with Python hashlib on unaligned messages.

On CPU 3 of the AMD EPYC 9V74 Linux host, each build yielded 15 thread CPU-time
samples in alternating five-sample processes. Each row below hashes 8 MiB in
1 MiB messages. The interval compares the before and after series medians.

| Digest | Before (µs) | After (µs) | Speedup (95% CI) |
| --- | ---: | ---: | ---: |
| sha1 | 35038 | 27848 | 1.258 [1.216, 1.301] |
| sha224 | 39329 | 30757 | 1.279 [1.258, 1.299] |
| sha256 | 38658 | 30746 | 1.257 [1.241, 1.274] |
| sha384 | 27765 | 23448 | 1.184 [1.170, 1.198] |
| sha512 | 27672 | 23647 | 1.170 [1.149, 1.191] |

[Raw trials and digests for six message sizes](sha-portable.json).
