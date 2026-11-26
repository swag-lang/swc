# CRC-64/ECMA-182 throughput and linked code placement

The final executable reproduces a CRC-64/ECMA-182 slowdown against the
16:19 checkpoint. At 1 MiB it ran at a paired 0.838× [0.828, 0.861]
for offset zero and 0.852× [0.844, 0.861] for offset 31. Every result
matched ISA-L. Each comparison used 17 process CPU-time rounds on one
AMD EPYC 9V74 CPU. The final integrated gain against the original
portable implementation is 479×.

Crossing library snapshots and compilers gave 23.2–23.3 GB/s for the
16:19 library with all three compilers. The final library reached
19.7 GB/s with both the wide multiplication compiler and the compiler
with the subsequent SIMD mask optimization. CRC-64/ISO as a control
remained around 42 GB/s.

Eight Core snapshots share the same CRC source and use the same final
Release compiler. In all eight, the 362-byte hot normalization and
folding region has SHA-256
`8035215bf7eb01c6fb12b08e7adc72a3b082861e69ad461ee880455588bc8597`.
The table varies the placement of the same 38-byte inner loop in the
linked executable. The final 17-pair panel measures 1 MiB at offset zero.

| Core revision | Loop start modulo 64 | Crosses a 64-byte boundary | GB/s |
| --- | ---: | --- | ---: |
| `bd4cfab5c1` | 16 | No | 23.08 |
| `86cfe53193` | 16 | No | 23.05 |
| `23f91fc6e2` | 48 | Yes | 19.51 |
| `8dbfcb0eeb` | 48 | Yes | 19.50 |
| `5f68346f72` | 48 | Yes | 19.51 |
| `91d8444346` | 48 | Yes | 19.49 |
| `fe1474ed3f` | 16 | No | 23.10 |
| `10bf72c650` | 48 | Yes | 19.55 |

The two throughput bands follow the loop position across these builds.
The measurements cover the complete linked executables and correlate the
loop position with the observed cost. ISA-L measured around 52 GB/s.

[Compiler crossover](crc64-ecma-crossover.json) · [Placement timings](crc64-ecma-placements.json) · [ELF layout evidence](crc64-ecma-placements-layout.json) · [Aligned checkpoint replay](crc64-ecma-checkpoint-offset0.json) · [Offset 31 checkpoint replay](crc64-ecma-checkpoint-offset31.json)

[Controlled placement replay with identical bytes](crc64-ecma-placement/README.md).
