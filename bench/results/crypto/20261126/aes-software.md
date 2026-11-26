# Portable AES substitution with register shuffles

The portable AES path implements the substitution through register shuffles and
GF(16) operations. All 32 native Release AES tests passed on the host and under QEMU
with AES and PCLMUL masked. This paired benchmark forces the software path in Swag
and masks AES-NI and VAES in OpenSSL 3.5.7.

On CPU 2 of the AMD EPYC 9V74, the common workload used 11 paired process CPU-time
trials per size. Every measured output matched. Rates are decimal GB/s.

| Bytes | Before | After | OpenSSL | Paired speedup (95% CI) |
| ---: | ---: | ---: | ---: | ---: |
| 64 | 0.000398 | 0.0297 | 0.0562 | 74.5 [62.8, 76] |
| 4096 | 0.000614 | 0.0537 | 0.458 | 86.8 [80.4, 90.5] |
| 65536 | 0.000623 | 0.0552 | 0.496 | 88.7 [87.7, 94.3] |

[Raw trials and output fingerprints](aes-software.json).
