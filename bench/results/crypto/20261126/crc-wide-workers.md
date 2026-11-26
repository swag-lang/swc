# Worker scaling for reflected CRC-64 with VPCLMULQDQ

Swag measured four configured workers with the prior and wide folding
kernels. ISA-L used a single worker. The same Linux CPU affinity
0–3 applied to all processes. Eleven interleaved wall-clock rounds per
profile used a 22 ms target. All CRCs matched byte for byte.

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| crc64-iso | 2097152 | 0 | baseline | ISA-L | GB/s | 23.5 | 56.7 | 0.415 [0.394, 0.447] |
| crc64-iso | 2097152 | 0 | wide | ISA-L | GB/s | 34.9 | 56.7 | 0.612 [0.408, 0.713] |
| crc64-iso | 2097152 | 0 | wide | baseline | GB/s | 34.9 | 23.5 | 1.5 [1.16, 1.66] |
| crc64-iso | 16777216 | 0 | baseline | ISA-L | GB/s | 43 | 52.7 | 0.813 [0.78, 0.873] |
| crc64-iso | 16777216 | 0 | wide | ISA-L | GB/s | 70.5 | 52.7 | 1.34 [1.25, 1.38] |
| crc64-iso | 16777216 | 0 | wide | baseline | GB/s | 70.5 | 43 | 1.63 [1.57, 1.72] |
| crc64-xz | 2097152 | 0 | baseline | ISA-L | GB/s | 23.7 | 56.7 | 0.429 [0.412, 0.485] |
| crc64-xz | 2097152 | 0 | wide | ISA-L | GB/s | 32.9 | 56.7 | 0.578 [0.486, 0.704] |
| crc64-xz | 2097152 | 0 | wide | baseline | GB/s | 32.9 | 23.7 | 1.4 [1, 1.57] |
| crc64-xz | 16777216 | 0 | baseline | ISA-L | GB/s | 34.5 | 51.9 | 0.699 [0.612, 0.764] |
| crc64-xz | 16777216 | 0 | wide | ISA-L | GB/s | 57.2 | 51.9 | 1.15 [1.04, 1.34] |
| crc64-xz | 16777216 | 0 | wide | baseline | GB/s | 57.2 | 34.5 | 1.7 [1.39, 1.95] |

At 16 MiB, CRC-64 ISO reached 70.5 GB/s with four Swag workers and
52.7 GB/s with one ISA-L worker. CRC-64 XZ reached 57.2 and 51.9 GB/s
with the same allocations. The serial library comparison is a
separate campaign.

[Raw wall and process CPU trials](crc-wide-workers.json) · [One-worker folding comparison](crc-wide-instructions.md).
