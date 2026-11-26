# Further SHA3-256 Keccak bulk experiments

Balancing the parity XORs was within 1% at both 64 KiB and 1 MiB with the four-round alternating-state permutation. Reversing the Theta or Rho XOR operands reduced bulk throughput. Packed Theta and the fully unrolled lane remapping cost roughly 27% of throughput at 1 MiB in the initial screens.

The measurements used native Swag Release binaries pinned to CPU 3 on Linux x86-64 with an AMD EPYC 9V74. Each sample measures per-thread CPU time for roughly 4 MiB of SHA3-256 hashing with 64 KiB or 1 MiB unaligned inputs. Each arm in a group produced the same digest as OpenSSL-backed Python hashlib. The exploratory groups also included an OpenSSL 3.5.7 EVP reference.

The table reports control time divided by candidate time. The scalar expression-order group used 15 samples per arm with rotated execution order. The initial screens used five samples per arm.

| Candidate | Control | Samples per arm | 64 KiB | 1 MiB |
|---|---|---:|---:|---:|
| Reverse operands of the Theta XOR | Four inlined alternating rounds | 15 | 0.995× | 0.999× |
| Reverse operands of the Rho XOR | Four inlined alternating rounds | 15 | 0.987× | 0.985× |
| Balance the column-parity XOR tree | Four inlined alternating rounds | 15 | 0.995× | 1.005× |
| Compute paired column parity with 128-bit SIMD | Two inlined alternating rounds | 5 | 0.720× | 0.728× |
| Complement six lanes between rounds | Two inlined alternating rounds | 5 | 0.949× | 0.967× |
| Accumulate next-round parity while writing lanes | Two inlined alternating rounds | 5 | 0.944× | 0.948× |
| Call the round without inlining | Two inlined alternating rounds | 5 | 0.823× | 0.836× |
| Apply Rho and Pi around their in-place cycle | Fixed-lane rounds | 5 | 0.959× | 0.989× |
| Remap in-place lane positions across 24 unrolled rounds | Four inlined alternating rounds | 5 | 0.712× | 0.734× |

The published 1 MiB comparison measured 9,400 µs for Swag and 8,442 µs for OpenSSL EVP on the same payload.

[Raw timings and verified digests](sha3-bulk-experiments.json)
