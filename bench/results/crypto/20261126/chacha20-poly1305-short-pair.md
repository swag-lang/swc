# Interleaved ChaCha20-Poly1305 short seals

For a nonempty payload of at most 64 bytes, sealing interleaves the
ChaCha20 rounds for block zero and the first payload block. The two
blocks share the initial nonce and key rows. Block zero supplies the
Poly1305 key and block one encrypts the payload. The ciphertext and
associated data then enter the existing MAC framing.

Both builds used the same integrated Release compiler. The comparison
used 13 interleaved process-CPU samples on one pinned EPYC 9V74 core,
with a one-byte input offset. OpenSSL 4.1.0 and libsodium 1.0.22 matched
the ciphertext and tag in all 18 timed layouts and an empty-message
verification run.

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| chacha20-poly1305 | 1 | 1 | fast | base | GB/s | 0.00289 | 0.00228 | 1.27 [1.21, 1.31] |
| chacha20-poly1305 | 15 | 1 | fast | base | GB/s | 0.042 | 0.0334 | 1.28 [1.2, 1.3] |
| chacha20-poly1305 | 16 | 1 | fast | base | GB/s | 0.0492 | 0.0378 | 1.29 [1.26, 1.34] |
| chacha20-poly1305 | 31 | 1 | fast | base | GB/s | 0.0823 | 0.065 | 1.28 [1.21, 1.34] |
| chacha20-poly1305 | 63 | 1 | fast | base | GB/s | 0.161 | 0.128 | 1.27 [1.23, 1.29] |
| chacha20-poly1305 | 64 | 1 | fast | base | GB/s | 0.179 | 0.139 | 1.28 [1.27, 1.36] |
| chacha20-poly1305 | 65 | 1 | fast | base | GB/s | 0.109 | 0.108 | 1.01 [1, 1.04] |
| chacha20-poly1305 | 128 | 1 | fast | base | GB/s | 0.202 | 0.204 | 0.977 [0.93, 1.02] |
| chacha20-poly1305 | 320 | 1 | fast | base | GB/s | 0.408 | 0.404 | 0.996 [0.953, 1.02] |
| chacha20-poly1305 | 4096 | 1 | fast | base | GB/s | 0.945 | 0.95 | 0.999 [0.986, 1.04] |
| chacha20-poly1305 | 4194304 | 1 | fast | base | GB/s | 1.03 | 1.04 | 0.994 [0.952, 1.01] |

The targeted native suites passed 21 tests in Release and Release-safe,
with one worker and with four workers. The new reference cases cover
each short-vector boundary, the 64-byte cutoff, exact in-place sealing
and opening, and bytes beyond the destination slice.

[Raw timing and output checks](chacha20-poly1305-short-pair.json) ·
[Empty-message output checks](chacha20-poly1305-short-pair-empty.json).
