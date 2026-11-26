# CRC-32 and reflected CRC-64 with 512-bit folding

CRC-32, CRC-64/ISO and CRC-64/XZ fold four independent 512-bit
accumulators from 1,024 bytes when the processor and operating system
support the instructions. Aligning the folding state within the stack
allocation avoids spills associated with aligning the whole frame.
The implementation reduces the four 128-bit lanes in input order and
uses independent 128-bit products for complete groups in the tail.

Both builds used the same Linux Release compiler and program
configuration. The comparison used CPU 2 of an AMD EPYC 9V74, one worker,
process CPU time and 11 paired rounds per input. The baseline is the
preceding 256-bit implementation. The intervals below compare the two
Swag builds. Reference throughput is the fastest applicable reference
at that size, from libdeflate 1.26 or ISA-L 2.32.1.

| Algorithm | Input | Previous Swag | New Swag | Reference | Paired speed ratio (95% CI) |
| --- | ---: | ---: | ---: | ---: | ---: |
| CRC-32 | 1 KiB | 17.0 GB/s | 19.6 GB/s | 46.1 GB/s | 1.14× [0.995, 1.16] |
| CRC-32 | 2 KiB | 20.3 GB/s | 27.0 GB/s | 51.3 GB/s | 1.32× [1.30, 1.36] |
| CRC-32 | 1 MiB | 24.9 GB/s | 42.0 GB/s | 56.4 GB/s | 1.68× [1.52, 1.70] |
| CRC-64/ISO | 1 KiB | 15.9 GB/s | 17.5 GB/s | 47.1 GB/s | 1.12× [0.990, 1.18] |
| CRC-64/ISO | 2 KiB | 19.6 GB/s | 25.4 GB/s | 52.6 GB/s | 1.30× [1.27, 1.33] |
| CRC-64/ISO | 1 MiB | 24.3 GB/s | 42.2 GB/s | 57.0 GB/s | 1.73× [1.69, 1.79] |
| CRC-64/XZ | 1 KiB | 15.5 GB/s | 17.5 GB/s | 46.0 GB/s | 1.12× [1.08, 1.14] |
| CRC-64/XZ | 2 KiB | 19.5 GB/s | 25.0 GB/s | 52.5 GB/s | 1.26× [1.15, 1.31] |
| CRC-64/XZ | 1 MiB | 24.9 GB/s | 42.1 GB/s | 57.2 GB/s | 1.70× [1.66, 1.70] |

At 512 bytes CRC-32 measured 0.989× [0.940, 0.998]. This size uses
128-bit folding. At 64 bytes it measured 1.01× [0.968, 1.03].
The same campaign includes CRC-64/ECMA-182 timings as a control.

All 168 differential cases across CRC-32 and the three CRC-64 forms
matched at offsets 0, 1 and 31. Focused JIT and native Release tests
passed with normal dispatch, with the ZMM operating-system state masked,
and with the VPCLMULQDQ capability masked. Protected page tests covered
loads at both ends of the input. The Core tests also exercised compile-time
checksums, seeded updates and four-worker CRC-64.

[Raw paired trials](crc-reflected-512.json) · [Differential cases](crc-reflected-512-verify.json) · [Compiler validation](carryless-512-instruction.md).
