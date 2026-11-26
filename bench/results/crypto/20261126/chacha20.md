# Packed ChaCha20 block output

The ChaCha quarter-round keeps four packed rows. The four-block kernel transposes
its output directly to the destination and the remaining full rows use packed XOR.
Poly1305 was the same on both sides. All 17 selected native Core tests passed under
both Release and Release-safe. They include RFC outputs, in-place buffers, counter
limits, nested parallel work and unchanged output after failed authentication.

Twenty paired CPU-time samples per build ran on CPU 3 of the AMD EPYC 9V74 with
one runtime worker. Full runs alternated order, using 8 MiB of input per sample.
The output checksums matched throughout. Rates are GiB/s.

| Operation | Bytes | Before | After | Paired speedup (95% CI) |
| --- | ---: | ---: | ---: | ---: |
| ChaCha20 | 64 | 0.329 | 0.358 | 1.09 [1.06, 1.1] |
| ChaCha20 | 1024 | 0.738 | 1.03 | 1.41 [1.39, 1.44] |
| ChaCha20 | 16384 | 0.747 | 1.07 | 1.45 [1.36, 1.51] |
| ChaCha20 | 262144 | 0.773 | 1.07 | 1.39 [1.35, 1.54] |
| ChaCha20 | 4194304 | 0.773 | 1.07 | 1.39 [1.33, 1.42] |
| ChaCha20-Poly1305 seal | 64 | 0.088 | 0.0942 | 1.06 [1.01, 1.12] |
| ChaCha20-Poly1305 seal | 1024 | 0.383 | 0.469 | 1.21 [1.15, 1.27] |
| ChaCha20-Poly1305 seal | 16384 | 0.482 | 0.604 | 1.26 [1.23, 1.3] |
| ChaCha20-Poly1305 seal | 262144 | 0.498 | 0.614 | 1.23 [1.19, 1.23] |
| ChaCha20-Poly1305 seal | 4194304 | 0.491 | 0.608 | 1.23 [1.22, 1.31] |

[Raw trials](chacha20.json).
