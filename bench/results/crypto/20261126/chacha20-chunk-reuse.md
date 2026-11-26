# ChaCha20 key and nonce reuse across batches

The serial path loads the key and nonce once per chunk of up to 16
four-block batches. It clears the chunk's working storage once. Dispatch
on a single short batch and the public counter range remain available.
The new fixture covers exact in-place encryption around the chunk boundary.

The common native Release workload ran 11 paired process CPU-time trials
on AMD EPYC 9V74 CPU 3. Inputs were offset by one byte. All 18 measured
ciphertexts and tags matched OpenSSL 3.5.7. At 4 MiB, throughput increased
from 1.18 to 1.31 GB/s for ChaCha20 and from 0.709 to 0.780 GB/s for
ChaCha20-Poly1305.

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| chacha20 | 64 | 1 | chacha-chunks-direct | chacha-byte-base | GB/s | 0.387 | 0.384 | 1.01 [0.984, 1.03] |
| chacha20 | 255 | 1 | chacha-chunks-direct | chacha-byte-base | GB/s | 0.472 | 0.43 | 1.07 [1.01, 1.13] |
| chacha20 | 256 | 1 | chacha-chunks-direct | chacha-byte-base | GB/s | 0.958 | 0.942 | 1.03 [0.92, 1.37] |
| chacha20 | 257 | 1 | chacha-chunks-direct | chacha-byte-base | GB/s | 0.641 | 0.647 | 0.981 [0.87, 1.02] |
| chacha20 | 512 | 1 | chacha-chunks-direct | chacha-byte-base | GB/s | 1.11 | 1.02 | 1.08 [0.986, 1.13] |
| chacha20 | 1024 | 1 | chacha-chunks-direct | chacha-byte-base | GB/s | 1.21 | 1.1 | 1.1 [1.06, 1.67] |
| chacha20 | 4096 | 1 | chacha-chunks-direct | chacha-byte-base | GB/s | 1.32 | 1.17 | 1.13 [1.12, 1.27] |
| chacha20 | 4097 | 1 | chacha-chunks-direct | chacha-byte-base | GB/s | 1.22 | 1.08 | 1.11 [0.975, 1.73] |
| chacha20 | 4194304 | 1 | chacha-chunks-direct | chacha-byte-base | GB/s | 1.31 | 1.18 | 1.11 [0.888, 1.12] |
| chacha20-poly1305 | 64 | 1 | chacha-chunks-direct | chacha-byte-base | GB/s | 0.121 | 0.121 | 0.977 [0.918, 1.11] |
| chacha20-poly1305 | 255 | 1 | chacha-chunks-direct | chacha-byte-base | GB/s | 0.241 | 0.242 | 0.995 [0.933, 1.01] |
| chacha20-poly1305 | 256 | 1 | chacha-chunks-direct | chacha-byte-base | GB/s | 0.337 | 0.345 | 0.986 [0.958, 1.1] |
| chacha20-poly1305 | 257 | 1 | chacha-chunks-direct | chacha-byte-base | GB/s | 0.274 | 0.273 | 1.01 [0.852, 1.07] |
| chacha20-poly1305 | 512 | 1 | chacha-chunks-direct | chacha-byte-base | GB/s | 0.455 | 0.434 | 1.03 [0.917, 1.12] |
| chacha20-poly1305 | 1024 | 1 | chacha-chunks-direct | chacha-byte-base | GB/s | 0.518 | 0.517 | 1.04 [0.819, 1.09] |
| chacha20-poly1305 | 4096 | 1 | chacha-chunks-direct | chacha-byte-base | GB/s | 0.709 | 0.666 | 1.07 [0.84, 1.4] |
| chacha20-poly1305 | 4097 | 1 | chacha-chunks-direct | chacha-byte-base | GB/s | 0.692 | 0.538 | 1.3 [1.07, 1.46] |
| chacha20-poly1305 | 4194304 | 1 | chacha-chunks-direct | chacha-byte-base | GB/s | 0.78 | 0.709 | 1.11 [1.07, 1.33] |

Eighteen focused native Release and Release-safe cases passed, including
parallel and nested-worker coverage and counters at the end of the permitted range.

[Raw trials and output fingerprints](chacha20-chunk-reuse.json).
