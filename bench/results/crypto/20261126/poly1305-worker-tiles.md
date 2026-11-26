# Poly1305 parallel tiles

Large updates compute independent message-tile accumulators and combine
them in message order with the required powers. The one-worker result
uses the same serial path as before. The authenticated-encryption fixture
checks the full ciphertext and tag across the tile split.

The common native Release workload used CPU affinity 0–3 and configured
one or four Swag workers. It paired 11 interleaved 25 ms target samples.
All complete outputs matched OpenSSL 3.5.7 and libsodium 1.0.22. The
table shows four-worker wall throughput.

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| poly1305 | 4194304 | 1 | tile-4 | base-4 | GB/s | 7.26 | 2.95 | 2.49 [2.33, 2.86] |
| poly1305 | 16777216 | 1 | tile-4 | base-4 | GB/s | 7.83 | 2.86 | 2.84 [2.15, 4.54] |
| chacha20-poly1305 | 4194304 | 1 | tile-4 | base-4 | GB/s | 1.82 | 1.36 | 1.38 [1.19, 1.66] |
| chacha20-poly1305 | 16777216 | 1 | tile-4 | base-4 | GB/s | 2.46 | 1.61 | 1.64 [1.41, 1.82] |

At 4 and 16 MiB standalone Poly1305 processed about 20% and 10% less
data per aggregate CPU second. The four-worker elapsed-time gains were
2.49× and 2.84×. The authenticated cipher used similar aggregate CPU
throughput at both sizes, with 1.38× and 1.64× elapsed-time gains.

Nineteen focused four-worker tests passed each native Release
configuration. A separate OpenSSL fixture checked exact continuation
after a split.

[Raw wall and aggregate CPU trials](poly1305-worker-tiles.json).
