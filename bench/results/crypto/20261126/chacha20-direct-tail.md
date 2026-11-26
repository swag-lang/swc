# Direct ChaCha20 tail XOR

After full four-block batches, the final one to four blocks previously
built complete keystream arrays and repeated setup for each call. The new
tail reuses the initial key rows, applies complete vectors from the round
output and reads only the remaining bytes of a partial vector. It wipes
the tail scratch once, after the last block. The public single-block
operation shares the key-row setup.

Release builds were compared on one pinned AMD EPYC 9V74 core over 11
interleaved process-CPU samples per layout, using a one-byte input offset.
OpenSSL 4.1.0 and libsodium 1.0.22 matched the ciphertext and, where
applicable, the authentication tag across all 46 layouts.

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| chacha20 | 1 | 1 | tail | baseline | GB/s | 0.00665 | 0.00621 | 1.07 [1.05, 1.09] |
| chacha20 | 64 | 1 | tail | baseline | GB/s | 0.419 | 0.386 | 1.09 [1.05, 1.11] |
| chacha20 | 65 | 1 | tail | baseline | GB/s | 0.254 | 0.228 | 1.12 [1.09, 1.19] |
| chacha20 | 128 | 1 | tail | baseline | GB/s | 0.496 | 0.45 | 1.11 [1.07, 1.22] |
| chacha20 | 192 | 1 | tail | baseline | GB/s | 0.531 | 0.469 | 1.14 [1.11, 1.35] |
| chacha20 | 255 | 1 | tail | baseline | GB/s | 0.528 | 0.457 | 1.14 [1.1, 1.33] |
| chacha20 | 256 | 1 | tail | baseline | GB/s | 0.974 | 0.966 | 1.01 [0.94, 1.46] |
| chacha20 | 511 | 1 | tail | baseline | GB/s | 0.721 | 0.66 | 1.11 [1.07, 1.14] |
| chacha20 | 512 | 1 | tail | baseline | GB/s | 1.12 | 1.12 | 0.999 [0.969, 1.01] |
| chacha20 | 4096 | 1 | tail | baseline | GB/s | 1.31 | 1.32 | 0.996 [0.85, 1] |
| chacha20 | 4194304 | 1 | tail | baseline | GB/s | 1.32 | 1.32 | 0.997 [0.866, 1.03] |
| chacha20-poly1305 | 1 | 1 | tail | baseline | GB/s | 0.00228 | 0.0021 | 1.08 [1.06, 1.17] |
| chacha20-poly1305 | 64 | 1 | tail | baseline | GB/s | 0.138 | 0.126 | 1.09 [0.982, 1.24] |
| chacha20-poly1305 | 65 | 1 | tail | baseline | GB/s | 0.104 | 0.0994 | 1.07 [1.04, 1.09] |
| chacha20-poly1305 | 128 | 1 | tail | baseline | GB/s | 0.21 | 0.193 | 1.08 [1.05, 1.14] |
| chacha20-poly1305 | 192 | 1 | tail | baseline | GB/s | 0.253 | 0.226 | 1.12 [1.08, 1.28] |
| chacha20-poly1305 | 255 | 1 | tail | baseline | GB/s | 0.274 | 0.249 | 1.1 [0.997, 1.15] |
| chacha20-poly1305 | 256 | 1 | tail | baseline | GB/s | 0.362 | 0.356 | 1.02 [0.982, 1.18] |
| chacha20-poly1305 | 511 | 1 | tail | baseline | GB/s | 0.382 | 0.365 | 1.05 [1.03, 1.11] |
| chacha20-poly1305 | 512 | 1 | tail | baseline | GB/s | 0.471 | 0.452 | 1.01 [0.986, 1.13] |
| chacha20-poly1305 | 4096 | 1 | tail | baseline | GB/s | 0.797 | 0.81 | 0.979 [0.894, 1.14] |
| chacha20-poly1305 | 4194304 | 1 | tail | baseline | GB/s | 0.866 | 0.905 | 0.988 [0.901, 1.07] |

The native Release and Release-safe suites each passed 19 cases with
one worker and with four workers. The boundary fixture checks 30 lengths,
exact in-place operation, untouched bytes beyond the input and the end
of the counter range. Existing ChaCha20-Poly1305 and XChaCha20-Poly1305
vectors also passed.

[Raw timing and output checks](chacha20-direct-tail.json).
