# CRC-64/ECMA-182 with 512-bit folding

The ECMA-182 CRC represents its polynomial coefficients most-significant
bit first. Above the 2 KiB cutoff, it prepares up to four groups of
input in that order and then feeds the 512-bit folding state. The
batch gives the 128-bit preparation stores time to complete before the
wide loads. A 2 KiB cutoff improved the measured inputs near the
boundary. The feature gate and fallback match the reflected CRCs.

Both builds use the same Linux Release compiler. The comparison used
CPU 2 of an AMD EPYC 9V74, one worker, process CPU time and 11 paired
rounds. The baseline already includes 512-bit folding for the reflected
forms and uses 128-bit folding for ECMA-182. ISA-L 2.32.1 supplies the
external comparison. Intervals compare the two Swag builds.

| Input | Offset | Previous Swag | New Swag | ISA-L | Paired speed ratio (95% CI) |
| --- | ---: | ---: | ---: | ---: | ---: |
| 2 KiB | 0 | 13.9 GB/s | 16.0 GB/s | 44.8 GB/s | 1.15× [1.09, 1.17] |
| 2 KiB | 31 | 13.7 GB/s | 15.7 GB/s | 44.0 GB/s | 1.14× [1.11, 1.19] |
| 8 KiB | 0 | 14.2 GB/s | 20.7 GB/s | 48.3 GB/s | 1.46× [1.41, 1.49] |
| 8 KiB | 31 | 13.8 GB/s | 20.4 GB/s | 1.47× [1.23, 1.53] |
| 1 MiB | 0 | 14.3 GB/s | 23.1 GB/s | 52.2 GB/s | 1.61× [1.58, 1.62] |
| 1 MiB | 31 | 14.3 GB/s | 23.0 GB/s | 50.5 GB/s | 1.61× [1.49, 1.65] |

Both offsets measured about 1.00× at 64, 128 and 1,024 bytes. The
8 MiB repeat ranged from 1.57× to 1.62× across four offsets. At
32 MiB, offset 31 measured 0.913× [0.813, 0.957] in the first run and
0.997× [0.929, 1.040] in the repeat. The 64 MiB repeat ranged from
0.935× to 1.08×, depending on offset. The measurements at those sizes
show less consistent gains near and above this machine's 32 MiB L3.

All 34 ECMA-182 benchmark inputs matched ISA-L. The Core tests passed
in JIT and native Release, including compile-time evaluation, seeded
updates and parallel stress. Protected boundaries passed with normal
dispatch, with the ZMM operating-system state masked, and with the
VPCLMULQDQ capability masked.

[Raw paired trials](crc-ecma-512.json) · [Reflected controls](crc-ecma-512-controls.json) · [Large-buffer repeat](crc-ecma-512-memory.json) · [Compiler validation](carryless-512-instruction.md).
