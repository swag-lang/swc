# SHA-512 round groups at fixed schedule offsets

The compression function identifies each of its ten eight-round groups
with a compile-time schedule offset. The same code handles all four
SHA-512 family digests and the fixed PBKDF2 final blocks.

The native Release main comparison used 15 rotated CPU-time rounds on
AMD EPYC 9V74. The 1 MiB table uses a dedicated 20-round repeat. Medians
are microseconds per trial of four hashes.

| Algorithm | Prior Swag | Fixed offsets | OpenSSL 3.5.7 | Paired speedup (95% CI) |
| --- | ---: | ---: | ---: | ---: |
| sha512 | 7102 | 6625 | 4942 | 1.094 [1.084, 1.119] |
| sha512 | 7025 | 6508 | 4919 | 1.086 [0.990, 1.107] |
| sha384 | 7014 | 6650 | 4848 | 1.087 [0.996, 1.099] |
| sha384 | 7208 | 6532 | 4892 | 1.103 [1.074, 1.130] |
| sha512-224 | 7357 | 6562 | 4897 | 1.107 [1.087, 1.125] |
| sha512-224 | 7083 | 6514 | 4866 | 1.091 [1.079, 1.127] |
| sha512-256 | 7154 | 6553 | 4928 | 1.088 [1.057, 1.128] |
| sha512-256 | 7115 | 6525 | 4916 | 1.090 [1.052, 1.118] |

The main 16- and 64-byte profiles improved by 8–13%. The benchmark
ELF .text section grew by 12,032 bytes. PBKDF2 matched all output bytes
and measured lower median CPU time for SHA-384 and SHA-512.

Another 432 external streaming cases matched. The 17 focused SHA-512,
HMAC, HKDF and PBKDF2 cases passed native Release, Release-safe and JIT.

[Raw main comparison](sha512-fixed-round-groups.json) · [Bulk repeat](sha512-fixed-round-bulk-repeat.json) · [PBKDF2 control](sha512-fixed-round-pbkdf2.json).
