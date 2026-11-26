# Controlled placement of the CRC-64/ECMA-182 hot loop

The two linked Swag executables contain the same 362-byte staging and
512-bit folding region. The old region occupies `0x474AA0` through
`0x474C09` and the final region occupies `0x470780` through `0x4708E9`.
Both have SHA-256
`8035215bf7eb01c6fb12b08e7adc72a3b082861e69ad461ee880455588bc8597`.
The old region starts at offset 32 modulo 64 and the final region starts
at offset 0. The 38-byte inner shuffle loop starts at offset 16 and 48
respectively within a cache line.

This test assembles two copies of those same bytes with the measured
placements. It gives both copies the same input and exactly the same
aligned state address. It checks that the resulting state bytes match
before and after timing. The second build reverses the order of the
copies in the executable. Each sample measures thread CPU time on
CPU 2 of the AMD EPYC 9V74 host. The cases cover 4 KiB, 64 KiB and
1 MiB, offsets 0, 1 and 31, and 13 alternating trials per case.

| Copy order | 1 MiB offset | Old placement | Final placement | Paired speed ratio |
| --- | ---: | ---: | ---: | ---: |
| Old first | 0 | 23.523 GB/s | 19.864 GB/s | 0.843× |
| Old first | 31 | 23.505 GB/s | 19.850 GB/s | 0.844× |
| Final first | 0 | 22.631 GB/s | 18.818 GB/s | 0.820× |
| Final first | 31 | 22.942 GB/s | 19.500 GB/s | 0.851× |

Across all inputs the paired ratios were 0.832–0.859× with the old
copy first and 0.820–0.866× with the final copy first. The measured
placement change reproduces the throughput loss on this EPYC host.
The test moves the whole hot region, including both inner loops.

The test requires x86-64 with AVX-512F, VPCLMULQDQ and operating-system
support for ZMM state. From this directory with GCC and GNU assembler,
run both builds on an assigned CPU.

```sh
gcc -std=c11 -O3 -Wall -Wextra -fno-pie -no-pie hot-loop.c hot-loop.S -o /tmp/crc64-old-first
gcc -std=c11 -O3 -Wall -Wextra -fno-pie -no-pie -DREVERSE_PLACEMENT hot-loop.c hot-loop.S -o /tmp/crc64-final-first
taskset -c 2 /tmp/crc64-old-first
taskset -c 2 /tmp/crc64-final-first
```

Each output row gives the input bytes, offset, round, old-placement
GB/s and final-placement GB/s.

[Old-first timings](old-first-timings.txt) · [Final-first timings](new-first-timings.txt) · [C driver](hot-loop.c) · [Assembly wrapper](hot-loop.S) · [Verified instruction bytes](hot-region.inc).
