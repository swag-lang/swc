# HMAC-SHA-224 and HMAC-SHA-256 key preparation

The normalized key, inner pad and outer pad share one 64-byte scratch
block. Packed XOR applies the pad masks, and packed stores serialize
digest words in big-endian order. Finalization clears the whole
context through the platform’s secure clearing routine. Re-keying
and scope exit clear an active context. Tests inspect cleared storage
after finalization and after an explicit clear.

Both Swag executables used native Release with standard-library
baseline `df76cc4757` and compiler `44e09064f1`. Seventeen shuffled
paired rounds ran on CPU 2 of an AMD EPYC 9V74 under Linux 6.18.57.
The native reference probes used static OpenSSL 3.5.9 and 4.1.0, and
Nettle 3.10.1. All timed calls set the same 32-byte key. OpenSSL
reuses the EVP_MAC container. The measured Swag calls include
clearing the keyed state before returning.

The table shows median process CPU nanoseconds per complete
authentication and the paired 95% candidate-to-baseline time ratio.

| HMAC | Bytes | Before | After | OpenSSL 4.1.0 | OpenSSL 3.5.9 | Nettle | After / before |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| SHA-224 | 16 | 286.3 | 223.6 | 241.7 | 264.9 | 195.1 | 0.770 [0.741, 0.789] |
| SHA-224 | 32 | 287.7 | 221.4 | 237.2 | 261.8 | 193.6 | 0.766 [0.744, 0.780] |
| SHA-224 | 55 | 306.7 | 232.0 | 237.9 | 262.6 | 200.6 | 0.765 [0.703, 0.821] |
| SHA-224 | 56 | 326.9 | 269.4 | 278.9 | 308.6 | 238.2 | 0.791 [0.754, 0.832] |
| SHA-224 | 128 | 367.9 | 297.4 | 321.3 | 350.6 | 273.4 | 0.814 [0.792, 0.826] |
| SHA-224 | 4096 | 2634.0 | 2549.1 | 2554.6 | 2585.9 | 2496.1 | 0.973 [0.964, 0.985] |
| SHA-256 | 16 | 354.7 | 236.9 | 243.0 | 271.4 | 200.0 | 0.670 [0.637, 0.684] |
| SHA-256 | 32 | 360.1 | 226.4 | 237.4 | 260.7 | 198.9 | 0.648 [0.595, 0.673] |
| SHA-256 | 55 | 341.4 | 224.8 | 233.3 | 258.7 | 197.7 | 0.656 [0.637, 0.694] |
| SHA-256 | 56 | 406.7 | 278.2 | 297.1 | 322.6 | 259.9 | 0.684 [0.670, 0.707] |
| SHA-256 | 128 | 412.8 | 286.4 | 314.0 | 334.4 | 270.9 | 0.700 [0.688, 0.748] |
| SHA-256 | 4096 | 2667.9 | 2540.1 | 2572.0 | 2581.1 | 2500.0 | 0.955 [0.942, 0.969] |

At 16–128 bytes, Swag used 19–24% less CPU for SHA-224 and 30–35%
less for SHA-256. The 4 KiB reductions were 2.7% and 4.5%.
Swag used less CPU than OpenSSL 4.1.0 in eight of the ten short
profiles with paired intervals below parity. Nettle had the lowest
median CPU time in all twelve. Swag used 6–19% more CPU than Nettle
on the short profiles and around 2% more at 4 KiB.

## Consumers

A separate 13-round comparison timed HKDF and deterministic P-256
signing using the same Swag builds and OpenSSL references. The
table uses median process CPU nanoseconds for complete derivations.

| HKDF | Digest blocks | Before | After | OpenSSL 4.1.0 | After / before |
| --- | ---: | ---: | ---: | ---: | ---: |
| SHA-224 | 1 | 651.2 | 515.0 | 1128.8 | 0.793 [0.748, 0.818] |
| SHA-224 | 4 | 1275.4 | 1137.7 | 1625.5 | 0.899 [0.858, 0.931] |
| SHA-224 | 32 | 6906.1 | 6671.7 | 6414.4 | 0.961 [0.936, 1.000] |
| SHA-224 | 255 | 51397.2 | 49997.6 | 43568.8 | 0.965 [0.945, 0.991] |
| SHA-256 | 1 | 745.9 | 510.0 | 1158.4 | 0.680 [0.622, 0.715] |
| SHA-256 | 4 | 1424.6 | 1094.9 | 1658.3 | 0.764 [0.733, 0.825] |
| SHA-256 | 32 | 7089.1 | 5903.1 | 6227.5 | 0.837 [0.801, 0.890] |
| SHA-256 | 255 | 50410.2 | 44164.4 | 43944.0 | 0.871 [0.848, 0.995] |

HKDF-SHA-224 used 21% less CPU at one digest block and 10% less
at four blocks. HKDF-SHA-256 used 13–32% less across the four
profiles. Both P-256 signing profiles gave identical signatures
and CPU intervals spanning parity. All five PBKDF2 control intervals
on the earlier `c88ba5bbc5` source base also spanned parity, with
identical derived bytes.

## Validation

Every measured result matched. The differential run checked 216
message and key profiles against both OpenSSL builds and Nettle,
with aligned and unaligned input, 0-, 32- and 131-byte keys, and
messages from 0 bytes through 4 KiB. The same candidate passed the
differential under QEMU without SHA-NI. The 30 default harness
profiles also passed using the ordinary OpenSSL build.

Thirty-two focused Core tests passed in native Release, Release-safe
and Release JIT on the earlier source base. The tests covered
HMAC known answers, re-keying, state clearing, HKDF, PBKDF2, scrypt
and P-256. The experimental two-pad SHA-NI interleave failed native
differential verification and was excluded.

[Benchmark commands](../../../workloads/crypto/README.md) · [Raw times and exact comparisons](hmac-sha224-sha256.json)
