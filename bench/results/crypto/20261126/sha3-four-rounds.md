# Four-round Keccak state alternation

The permutation alternates two lane arrays across groups of four inlined rounds.
The ten focused native Release SHA3, SHAKE, HMAC and KMAC tests passed. The timed
SHA3-256 digests matched OpenSSL 3.5.7 and hashlib.

Twenty rotating thread CPU-time trials ran on AMD EPYC 9V74 CPU 3. Times in
microseconds cover 75,000 calls for 16 and 64 bytes, and 4 MiB for longer messages.

| Bytes | Before | Four rounds | OpenSSL | Paired speedup (95% CI) |
| ---: | ---: | ---: | ---: | ---: |
| 16 | 39093 | 32272 | 24333 | 1.20 [1.14, 1.26] |
| 64 | 33766 | 27951 | 21088 | 1.20 [1.17, 1.27] |
| 1024 | 12140 | 10393 | 9279 | 1.17 [1.14, 1.20] |
| 16384 | 10698 | 9399 | 8456 | 1.14 [1.14, 1.16] |
| 65536 | 10664 | 9360 | 8420 | 1.14 [1.14, 1.16] |
| 1048576 | 10739 | 9357 | 8442 | 1.14 [1.14, 1.16] |

[Raw samples and matching digest fingerprints](sha3-four-rounds.json).
