# CRC-64 four-worker replay and short-input experiments

The 512-bit CRC-64 implementation was replayed against the preceding
kernels with both Swag executables configured for four runtime workers.
The baseline uses 128-bit folds for ECMA-182 and 256-bit folds for ISO
and XZ. Both executables use the same Linux Release compiler and program
configuration. The AMD EPYC 9V74 replay used CPUs 0–3, elapsed wall time
and 11 paired rounds at offset zero. ISA-L 2.32.1 and liblzma 5.8.1 ran
one worker per call. The faster reference for each row is shown.

The cgroup recorded zero throttled periods across 122 periods.

| Algorithm | Buffer | Previous Swag | 512-bit Swag | Reference | Paired Swag ratio (95% CI) |
| --- | ---: | ---: | ---: | ---: | ---: |
| CRC-64/ECMA-182 | 2 MiB | 20.7 GB/s | 31.1 GB/s | 51.6 GB/s (ISA-L) | 1.43× [1.28, 1.56] |
| CRC-64/ECMA-182 | 16 MiB | 36.7 GB/s | 51.7 GB/s | 49.6 GB/s (ISA-L) | 1.31× [1.17, 1.58] |
| CRC-64/ECMA-182 | 32 MiB | 33.7 GB/s | 44.1 GB/s | 27.4 GB/s (ISA-L) | 1.27× [1.06, 1.55] |
| CRC-64/ISO | 2 MiB | 35.6 GB/s | 49.5 GB/s | 56 GB/s (ISA-L) | 1.34× [1.29, 1.66] |
| CRC-64/ISO | 16 MiB | 60.4 GB/s | 106 GB/s | 53.3 GB/s (ISA-L) | 1.72× [1.57, 1.89] |
| CRC-64/ISO | 32 MiB | 57.1 GB/s | 84.2 GB/s | 26.6 GB/s (ISA-L) | 1.46× [1.31, 2.11] |
| CRC-64/XZ | 2 MiB | 34.9 GB/s | 48.5 GB/s | 56.7 GB/s (ISA-L) | 1.41× [1.29, 1.54] |
| CRC-64/XZ | 16 MiB | 68.6 GB/s | 105 GB/s | 53.7 GB/s (ISA-L) | 1.52× [1.4, 1.79] |
| CRC-64/XZ | 32 MiB | 58.7 GB/s | 81.4 GB/s | 28.6 GB/s (ISA-L) | 1.35× [1.27, 1.85] |

All benchmark outputs matched their reference checksums.

[Raw four-worker trials](crc64-512-workers-final.json) · [512-bit reflected folding](crc-reflected-512.md) · [512-bit ECMA-182 folding](crc-ecma-512.md).

## Portable short and trailing inputs

A separate scalar prototype replaced the byte loop after slicing by
eight with table lookups over 4-byte, 2-byte and 1-byte groups. It uses
the same polynomial and initial value and accepts unaligned inputs.
The 13-round process CPU-time experiment on CPU 2 matched 84 CRC variant
and input combinations across offsets 0 and 31. Four focused Core cases
also passed in JIT and native Release with carry-less multiplication
masked off.

Two follow-ups tried returning immediately with zero bytes remaining,
or with zero or one byte remaining. The table shows the ranges of
paired medians across the three CRCs and offsets 0 and 31 in the
nine-round follow-up. Ratios compare each prototype to the same
production baseline.

| Input | Grouped tail | Return at zero | Return at zero or one |
| --- | ---: | ---: | ---: |
| 1 B | 0.938–0.965× | 0.943–0.973× | 0.971–1.03× |
| 2 B | 1.03–1.07× | 0.997–1.00× | 0.905–0.940× |
| 7 B | 1.25–1.31× | 1.20–1.30× | 1.14–1.23× |
| 8 B | 0.877–0.915× | 0.949–0.964× | 0.912–0.960× |
| 15 B | 1.18–1.25× | 1.22–1.31× | 1.20–1.24× |
| 31 B | 1.08–1.13× | 1.11–1.17× | 1.07–1.13× |
| 1 KiB | 0.992–1.00× | 0.989–1.00× | 0.989–1.01× |

The grouped tails improve 7 and 15 byte inputs consistently. Every
prototype regresses at least one neighboring input size. A separate
32–63 byte carry-less variant improved exact 32 and 48 byte inputs,
while the 47 byte input measured 0.79–0.80× across the three CRCs.
These are screening results for the short-input kernels.

[Grouped-tail trials](crc64-tail-experiment.json) · [Early-return trials](crc64-tail-branches.json) · [32–63 byte carry-less screen](crc64-short-fold-screen.json).
