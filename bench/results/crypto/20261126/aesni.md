# AES-NI dispatch for AES and GCM

AES block encryption, decryption and key expansion select AES-NI only when the
CPU advertises it. GHASH checks PCLMUL independently. All 31 focused native Release
tests passed on Linux and under QEMU with AES and PCLMUL masked separately and together.
The timed outputs and 20 additional unaligned cases matched OpenSSL 3.5.7.
The baseline uses software AES at the start of the campaign.

On CPU 2 of the AMD EPYC 9V74, the common workload used 11 paired process CPU-time
trials per size. Every measured output matched. Rates are decimal GB/s.

| Bytes | Before | After | OpenSSL | Paired speedup (95% CI) |
| ---: | ---: | ---: | ---: | ---: |
| 64 | 0.000357 | 0.118 | 0.18 | 325 [301, 364] |
| 4096 | 0.000559 | 0.326 | 5.13 | 583 [571, 610] |
| 65536 | 0.000567 | 0.332 | 9.93 | 587 [498, 591] |
| 1048576 | 0.000551 | 0.33 | 10.2 | 598 [477, 620] |

[Raw trials and output fingerprints](aesni.json).
