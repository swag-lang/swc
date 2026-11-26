# CRC-32 and reflected CRC-64 with paired 256-bit products

The x64 CRC paths with VPCLMULQDQ use paired polynomial lanes from 1 KiB.
The CRC-32 smaller-buffer controller keeps its XMM path and collapses
the four lanes with independent products. The ECMA variant keeps its
16-byte lanes. Feature-off dispatch is exercised separately.

The native Release comparison used 11 paired process CPU-time rounds
on AMD EPYC 9V74 CPU 3 with one worker. At 1 MiB the new CRC-32 path
reached 24.5 GB/s. All checksums matched ISA-L, libdeflate or zlib
according to the operation.

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| crc32 | 64 | 0 | wide | baseline | GB/s | 4.21 | 4 | 1.06 [1.04, 1.1] |
| crc32 | 128 | 0 | wide | baseline | GB/s | 6.93 | 6.12 | 1.14 [1.11, 1.16] |
| crc32 | 512 | 0 | wide | baseline | GB/s | 13 | 13.2 | 0.984 [0.962, 0.993] |
| crc32 | 1024 | 0 | wide | baseline | GB/s | 16.7 | 13.5 | 1.24 [1.21, 1.27] |
| crc32 | 1048576 | 0 | wide | baseline | GB/s | 24.5 | 14.2 | 1.72 [0.696, 1.79] |
| crc64-ecma | 64 | 0 | wide | baseline | GB/s | 3.92 | 3.92 | 0.993 [0.969, 1.03] |
| crc64-ecma | 128 | 0 | wide | baseline | GB/s | 6.09 | 6.12 | 0.996 [0.983, 1.01] |
| crc64-ecma | 512 | 0 | wide | baseline | GB/s | 12.1 | 12.1 | 1 [0.868, 1.13] |
| crc64-ecma | 1024 | 0 | wide | baseline | GB/s | 13 | 13 | 0.986 [0.979, 1.03] |
| crc64-ecma | 1048576 | 0 | wide | baseline | GB/s | 14.1 | 14.2 | 0.997 [0.976, 1.01] |
| crc64-iso | 64 | 0 | wide | baseline | GB/s | 4.36 | 4.31 | 1.01 [1, 1.03] |
| crc64-iso | 128 | 0 | wide | baseline | GB/s | 5.87 | 5.84 | 1.01 [0.874, 1.02] |
| crc64-iso | 512 | 0 | wide | baseline | GB/s | 12 | 12.4 | 0.978 [0.878, 1.02] |
| crc64-iso | 1024 | 0 | wide | baseline | GB/s | 16.4 | 13.3 | 1.23 [1.21, 1.24] |
| crc64-iso | 1048576 | 0 | wide | baseline | GB/s | 24.5 | 14.3 | 1.73 [1.58, 1.79] |
| crc64-xz | 64 | 0 | wide | baseline | GB/s | 4.27 | 4.26 | 0.998 [0.967, 1.03] |
| crc64-xz | 128 | 0 | wide | baseline | GB/s | 5.7 | 5.73 | 0.975 [0.969, 1.02] |
| crc64-xz | 512 | 0 | wide | baseline | GB/s | 12.4 | 12.4 | 1 [0.969, 1.04] |
| crc64-xz | 1024 | 0 | wide | baseline | GB/s | 15.7 | 13.1 | 1.19 [1.18, 1.25] |
| crc64-xz | 1048576 | 0 | wide | baseline | GB/s | 24.6 | 14.3 | 1.73 [1.66, 1.74] |

At 512 bytes, CRC-32 throughput was 0.984× [0.962, 0.993] in the full
run. The aligned and offset-one replay was about 0.99× there. At 1 MiB
the same replay confirmed paired CRC-32 gains of 1.73× and 1.71× at the
two offsets.

Five focused cases passed in JIT and native Release with hardware
enabled and forced off. Boundary tests exercised protected pages and
the parallel CRC-64 test used four workers.

[Raw paired trials](crc-wide-instructions.json) · [Aligned and unaligned replay](crc-wide-offset-control.json) · [Compiler validation](wide-carryless-instruction.md).
