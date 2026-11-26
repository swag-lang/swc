# Centered Adler-32 byte weights

Subtracting 32 from each byte's weight keeps the four partial weight
vectors in signed 16-bit lanes. Each pair total is between −22,950 and
23,970. Their sum needs just one widening multiply-add for 64 input
bytes. The reduction restores the original weights by adding 32 times
the byte sum it already computes.

Both variants used the Linux Release compiler and program configuration
on AMD EPYC 9V74 CPU 2. Measurements used one worker and process CPU
time. The first run used 11 paired rounds at offsets 0 and 31. The
short-input repeat used 13 rounds with the same offsets. Every reported
input matched libdeflate 1.26 and zlib 1.3.1.

| Input | Previous Swag | Centered weights | libdeflate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | ---: | ---: |
| 128 B | 11.3 GB/s | 11.5 GB/s | 19.3 GB/s | 1.02× [1.01, 1.05] |
| 255 B | 10.5 GB/s | 10.1 GB/s | 32.9 GB/s | 0.962× [0.941, 0.992] |
| 512 B | 22.1 GB/s | 23.5 GB/s | 48.5 GB/s | 1.09× [1.01, 1.10] |
| 5,504 B | 31.4 GB/s | 37.0 GB/s | 98.1 GB/s | 1.18× [1.11, 1.21] |
| 1 MiB | 32.3 GB/s | 37.4 GB/s | 87.1 GB/s | 1.16× [1.12, 1.18] |
| 8 MiB | 31.7 GB/s | 37.4 GB/s | 87.3 GB/s | 1.17× [1.14, 1.19] |

The first five rows use the repeat at offset zero. The 8 MiB row uses
the original run. At offset 31 the repeat measured a 1.16× ratio for
1 MiB and a 0.969× ratio for 255 B. A separate cutoff implementation
lost more throughput from 128 through 511 bytes, so the centered kernel
is used for every full block in the large-input loop.

The focused Adler-32 and zlib tests passed all 10 cases in JIT and
native Release. The fixtures exercise split updates, unaligned input,
all-`0xFF` input and the modulo-reduction boundary.

[Raw paired trials](adler-centered-weights.json) · [Short-input and cutoff repeat](adler-centered-weights-short-control.json).
