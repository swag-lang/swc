# HMAC-SHA-384 and SHA-512 pad reuse and direct outer blocks

Each HMAC reuses one scratch block for the inner and outer key pads.
Its inner hash finalizes in place, and the resulting words are serialized
directly into the outer context’s padded digest block. Finalization
securely clears the whole context after exporting the tag. Re-keying
and scope exit clear an active context.

The native Release builds were based on library `80f6b45045` and
used the same combined compiler with EVEX, IFMA and packed multiply
mask elimination. Seventeen shuffled pairs ran on CPU 2 of an AMD
EPYC 9V74 under Linux 6.18.57. The probes supplied the same 32-byte
key for each operation and checked the complete tag against both
OpenSSL releases. The table shows median process CPU nanoseconds
and paired 95% candidate-to-baseline ratios.

| HMAC | Bytes | Before | Pad reuse only | Direct | OpenSSL 4.1.0 | OpenSSL 3.5.9 | Direct / before |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| SHA-384 | 16 | 1165.4 | 1042.8 | 1025.5 | 771.6 | 803.6 | 0.877 [0.864, 0.899] |
| SHA-384 | 32 | 1120.2 | 1028.3 | 996.2 | 760.3 | 790.9 | 0.886 [0.880, 0.906] |
| SHA-384 | 111 | 1165.0 | 1057.1 | 1014.9 | 780.6 | 790.5 | 0.892 [0.840, 0.916] |
| SHA-384 | 112 | 1368.0 | 1296.1 | 1269.8 | 940.9 | 954.9 | 0.921 [0.899, 0.949] |
| SHA-384 | 128 | 1341.4 | 1241.5 | 1226.1 | 918.7 | 937.0 | 0.905 [0.889, 0.944] |
| SHA-384 | 4096 | 7793.5 | 7682.2 | 7583.1 | 5641.0 | 5725.8 | 0.977 [0.954, 1.014] |
| SHA-512 | 16 | 1111.6 | 1006.6 | 1003.9 | 782.6 | 838.8 | 0.904 [0.861, 0.950] |
| SHA-512 | 32 | 1111.1 | 959.0 | 954.0 | 763.2 | 824.2 | 0.852 [0.819, 0.885] |
| SHA-512 | 111 | 1158.4 | 1082.0 | 995.8 | 792.0 | 843.0 | 0.837 [0.821, 0.867] |
| SHA-512 | 112 | 1362.4 | 1246.8 | 1179.0 | 925.8 | 971.0 | 0.884 [0.851, 0.922] |
| SHA-512 | 128 | 1328.9 | 1174.7 | 1161.6 | 910.9 | 936.5 | 0.875 [0.861, 0.890] |
| SHA-512 | 4096 | 7476.1 | 7390.0 | 7380.0 | 5489.3 | 5533.3 | 0.985 [0.978, 1.002] |

At 16–128 bytes, CPU time fell 7.9–12.3% for HMAC-SHA-384 and
9.6–16.3% for HMAC-SHA-512. The 4 KiB intervals included parity.
OpenSSL 4.1.0 used less CPU at every tested size.

Ten plain SHA-384 and SHA-512 timing profiles from 16 bytes through
1 MiB had paired intervals that included parity. The verification
sweep matched both OpenSSL builds in 136 aligned and unaligned
HMAC and plain SHA profiles, including empty input and the
111/112-byte padding boundary.

Twenty focused Core tests passed in each of native Release and
Release-safe. They covered long-key HMAC, re-keying and cleared
storage, SHA-512/224 and SHA-512/256, HKDF and PBKDF2.

[Benchmark reproduction](../../../workloads/crypto/README.md) · [Raw times and fingerprints](hmac-sha384-sha512-outer.json)
