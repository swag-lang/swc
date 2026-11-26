# scrypt packed Salsa20/8 and ROMix

November 26, 2026, on an AMD EPYC 9V74 Linux x86-64 virtual machine. The
[comparison](../../../workloads/scrypt/README.md) used 13 paired rounds on CPU 1.
Both Swag executables used the Release compiler built at `d9bfeae85f` and the
`release` program configuration. The standard-library baseline was `bfc8c126b5`.
The reference was Python 3.12.14 `hashlib.scrypt` with OpenSSL 3.5.8. Every
implementation matched all 32 derived bytes in every round. Allocation and
secure clearing were timed. One warm-up preceded each measured call.

Each profile uses one worker and one scrypt lane. Ratios are medians of the paired
candidate/reference times with exact 95% intervals.

| N | r | ROMix MiB | Baseline CPU ms | Candidate CPU ms | OpenSSL CPU ms | Candidate / baseline | Candidate / OpenSSL |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1024 | 1 | 0.125 | 0.612 | 0.207 | 0.263 | 0.343 [0.333, 0.382] | 0.793 [0.719, 0.904] |
| 16384 | 8 | 16 | 72.698 | 28.148 | 34.623 | 0.395 [0.368, 0.408] | 0.813 [0.777, 0.841] |
| 65536 | 8 | 64 | 308.754 | 125.185 | 168.684 | 0.409 [0.371, 0.502] | 0.724 [0.635, 0.917] |

Swag cut process CPU time by 59–66% over its baseline and 19–28% compared with
OpenSSL on these profiles. At 16 and 64 MiB, the wall-time intervals against
both references also excluded parity. The 128 KiB wall-time intervals spanned
parity under concurrent VM work.

The ROMix matrix stays in Salsa20/8's SIMD layout. BlockMix writes each chunk
to its final even or odd position, then exchanges the input and output buffers.
The outer operation still restores ordinary byte order before the final PBKDF2
call and clears the whole scratch allocation.

The native Release Core selection `--test-file scrypt.swg` passed three functional
cases and one RFC 7914 stress case with 16 lanes.
[Raw CPU times, wall times, and tags](scrypt.json)
