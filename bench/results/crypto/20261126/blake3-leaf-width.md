# BLAKE3 leaf compression at SIMD widths four and eight

The same C++ round schedule was compiled with GCC 14.2.0 for SSE4.1
with four lanes and AVX2 with four or eight lanes. A fourth arm was
the official BLAKE3 C 1.8.7 leaf compression API, which selected
SIMD width 16 on this AMD EPYC 9V74. Timing covers the leaf
compression and output of each 32-byte chaining value. Tree updates
and digest finalization are outside this workload.

The fixture checker compared every chaining value before and after
timing. Thirty fixtures covered five input lengths, three alignment
offsets and keyed and unkeyed flags. All exercised a chunk counter that
crossed 2³². A single process on CPU 1 obtained 11 paired interleaved
samples per size with a 20 ms target per sample.

| Input | SSE4.1 width 4 GB/s | AVX2 width 4 GB/s | AVX2 width 8 GB/s | Official width 16 GB/s | AVX2 8 / 4 with 95% CI |
| --- | ---: | ---: | ---: | ---: | ---: |
| 8 KiB | 1.872 | 2.033 | 3.993 | 5.923 | 1.97× [1.84, 2.02] |
| 64 KiB | 1.984 | 2.069 | 4.016 | 7.035 | 1.94× [1.93, 2.17] |
| 1 MiB | 1.942 | 2.035 | 3.933 | 6.899 | 1.94× [1.80, 2.17] |
| 8 MiB | 1.761 | 1.973 | 3.800 | 6.533 | 1.92× [1.87, 2.86] |
| 32 MiB | 1.731 | 1.814 | 3.238 | 5.001 | 1.80× [1.77, 1.83] |

`objdump` shows 2,556 instructions in the AVX2 four-lane kernel and
2,638 in the eight-lane kernel. Their code sizes are 13,795 and 15,054
bytes and the static stack-address operand counts are 705 and 715.
The stack adjustments increase from 352 to 808 bytes. The wider lanes
process twice as much input with a similar number of instructions and
stack references. The eight-lane result is a reference for future
Swag code generation and applies only to the measured AMD host.

[Raw process CPU and wall samples](blake3-leaf-width.json) ·
[Workload and build instructions](../../../workloads/blake3/leaf-width/README.md)
