# Native KDF replay

Swag's `bfc8c126b5` standard library is the baseline. It includes the
initial scalar Argon2id optimization and predates the packed scrypt and
SHA-NI campaigns. The current snapshot is `d81f3cd6b5`. Both used the same
native Release compiler with the x64 full-width multiplication support
from `52a1ec78e9`.

The runs used CPU 2 of an AMD EPYC 9V74 under Linux 6.18.57. The tables
show median process CPU milliseconds and paired 95% time-ratio
intervals. Each comparator received the same cost parameters and inputs,
and every measured output matched byte for byte. The raw results include
wall times and all comparator intervals.

## Argon2id

Eleven pairs per profile used one worker, four Argon2id lanes, three
passes, Argon2 version 0x13 and a 32-byte result. The references were
OpenSSL 3.5.7 and libargon2 20190702 built with GCC 14.2 for Zen 4, using
its AVX-512 kernel.

| MiB | Baseline Swag | Current Swag | OpenSSL | libargon2 | Current / baseline | Current / libargon2 |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 2.081 | 1.386 | 1.613 | 0.841 | 0.672 [0.653, 0.687] | 1.659 [1.516, 1.748] |
| 64 | 170.352 | 119.865 | 144.667 | 89.548 | 0.710 [0.655, 0.725] | 1.349 [1.317, 1.390] |
| 256 | 874.520 | 652.020 | 649.689 | 446.404 | 0.761 [0.723, 0.858] | 1.546 [1.414, 1.690] |

Swag used 24–33% less CPU than its baseline. libargon2 retained the
lowest CPU time at all three sizes. Swag used less CPU than OpenSSL at
1 and 64 MiB, with the paired interval spanning parity at 256 MiB.

[Argon2id comparison and build instructions](../../../workloads/argon2/README.md#native-comparison-with-libargon2-and-openssl)

## scrypt

Fifteen paired rounds used one worker, one lane and a 32-byte result.
The references were Python's OpenSSL 3.5.8 and the libsodium 1.0.18
low-level function with explicit `N`, `r` and `p`.

| N | r | Baseline Swag | Current Swag | OpenSSL | libsodium | Current / baseline | Current / libsodium |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1024 | 1 | 0.600 | 0.201 | 0.280 | 0.183 | 0.329 [0.306, 0.344] | 1.066 [1.011, 1.121] |
| 16384 | 8 | 70.303 | 24.610 | 33.784 | 27.950 | 0.353 [0.336, 0.361] | 0.935 [0.832, 0.968] |
| 65536 | 8 | 292.179 | 109.527 | 160.531 | 123.010 | 0.372 [0.346, 0.382] | 0.904 [0.875, 0.964] |

Swag used 63–67% less CPU than its baseline. At 16 and 64 MiB it also
used 6.5% and 9.6% less CPU than libsodium. At 128 KiB, Swag used 6.6%
more CPU than libsodium in the paired estimate. Swag used less CPU than
OpenSSL at all three sizes.

## PBKDF2-HMAC

Fifteen paired rounds used Python's OpenSSL 3.5.8 and Nettle 3.10.1.
Nettle's SHA-224 profile uses its generic PBKDF2 interface with
HMAC-SHA-224.

| HMAC | Iterations | Password / salt / output bytes | Baseline Swag | Current Swag | OpenSSL | Nettle | Current / baseline | Current / Nettle |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| SHA-224 | 20000 | 8 / 16 / 80 | 68.374 | 5.496 | 8.313 | 7.086 | 0.081 [0.077, 0.082] | 0.784 [0.749, 0.794] |
| SHA-256 | 100000 | 8 / 16 / 32 | 118.939 | 8.580 | 13.389 | 11.634 | 0.072 [0.070, 0.074] | 0.741 [0.729, 0.749] |
| SHA-256 | 25000 | 200 / 150 / 96 | 159.350 | 6.383 | 9.919 | 8.645 | 0.040 [0.039, 0.040] | 0.735 [0.732, 0.743] |
| SHA-384 | 20000 | 200 / 150 / 100 | 157.800 | 30.121 | 24.457 | 31.891 | 0.189 [0.174, 0.195] | 0.940 [0.729, 0.982] |
| SHA-512 | 20000 | 8 / 16 / 64 | 36.773 | 10.087 | 8.043 | 10.858 | 0.275 [0.267, 0.287] | 0.908 [0.873, 0.968] |

Swag used 73–96% less CPU than its baseline. It also used 22–27% less
CPU than Nettle across the SHA-224 and SHA-256 profiles. OpenSSL had the
lowest median CPU times for SHA-384 and SHA-512. The paired SHA-384
interval against OpenSSL spans parity. The Swag SHA-512 profile used
21% more CPU than OpenSSL.

[Reproduction for scrypt and PBKDF2](../../../workloads/kdf-replay/README.md) · [Raw times and derived outputs](kdf-replay.json)
