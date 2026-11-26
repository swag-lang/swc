# Frozen-source KDF and HMAC replay

The current standard-library snapshot is `10bf72c650`. The KDF
baseline is `bfc8c126b5`, which includes the initial scalar Argon2
campaign. HMAC uses `df76cc4757` as its baseline because the common
probe at `da13763b7b` uses API additions published after the KDF
baseline. Each pair used the same native Release compiler with
EVEX, IFMA, wide multiply addends and packed multiply mask elision.

All profiles ran with one worker on CPU 2 of an AMD EPYC 9V74 under
Linux 6.18.57. Every candidate, baseline and reference output
matched byte for byte. The selected external reference in each row
is the one with the lowest CPU median in that row. The raw samples
retain the other references, paired rounds and elapsed timings.

## Argon2id

Eleven paired rounds used four lanes, three passes, Argon2 version
0x13 and a 32-byte tag. The references used OpenSSL 3.5.7 and 4.1.0
and libargon2 20190702 built with GCC 14.2 for Zen 4 and AVX-512.
Times are process CPU milliseconds per derivation. Ratios carry
paired 95% intervals.

| MiB | Before | Current | Reference | Reference CPU ms | Current / before | Current / reference |
| ---: | ---: | ---: | --- | ---: | ---: | ---: |
| 1 | 2.122 | 1.195 | libargon2 AVX-512 | 0.836 | 0.568 [0.546, 0.588] | 1.433 [1.386, 1.480] |
| 64 | 179.253 | 109.750 | libargon2 AVX-512 | 91.403 | 0.633 [0.591, 0.711] | 1.179 [1.084, 1.252] |
| 256 | 878.747 | 588.609 | libargon2 AVX-512 | 442.266 | 0.670 [0.563, 0.698] | 1.309 [1.254, 1.368] |

## scrypt and PBKDF2-HMAC

Fifteen paired rounds used native OpenSSL 3.5.9 and 4.1.0, Python’s
OpenSSL, and libsodium 1.0.18 for scrypt or Nettle 3.10.1 for PBKDF2.
scrypt used one lane and a 32-byte result. Times are CPU milliseconds
per derivation.

| N | r | Before | Current | Reference | Reference CPU ms | Current / before | Current / reference |
| ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: |
| 1024 | 1 | 0.597 | 0.193 | libsodium 1.0.18 | 0.182 | 0.330 [0.300, 0.360] | 1.049 [0.888, 1.077] |
| 16384 | 8 | 68.426 | 23.203 | libsodium 1.0.18 | 24.396 | 0.337 [0.335, 0.350] | 0.948 [0.847, 1.034] |
| 65536 | 8 | 286.371 | 106.011 | libsodium 1.0.18 | 118.604 | 0.366 [0.361, 0.381] | 0.935 [0.875, 0.977] |

| HMAC | Iterations | Password / salt / output bytes | Before | Current | Reference | Reference CPU ms | Current / before | Current / reference |
| --- | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: |
| SHA-224 | 20000 | 8 / 16 / 80 | 65.423 | 5.416 | Nettle 3.10.1 | 6.841 | 0.083 [0.082, 0.083] | 0.790 [0.786, 0.793] |
| SHA-256 | 100000 | 8 / 16 / 32 | 117.071 | 8.493 | Nettle 3.10.1 | 11.610 | 0.073 [0.072, 0.076] | 0.735 [0.725, 0.762] |
| SHA-256 | 25000 | 200 / 150 / 96 | 158.468 | 6.363 | Nettle 3.10.1 | 8.686 | 0.040 [0.040, 0.040] | 0.731 [0.729, 0.737] |
| SHA-384 | 20000 | 200 / 150 / 100 | 148.503 | 26.229 | OpenSSL 4.1.0 | 22.792 | 0.177 [0.176, 0.178] | 1.153 [1.145, 1.158] |
| SHA-512 | 20000 | 8 / 16 / 64 | 34.589 | 8.866 | OpenSSL 4.1.0 | 7.622 | 0.255 [0.253, 0.264] | 1.151 [1.144, 1.241] |

## HMAC

Thirteen paired rounds included native OpenSSL 3.5.9 and 4.1.0,
and Nettle 3.10.1 for SHA-224 and SHA-256. Each operation includes
key setup with the same 32-byte key. Swag clears its keyed context
before returning. Times are CPU nanoseconds per tag.

| HMAC | Bytes | Before | Current | Reference | Reference CPU ns | Current / before | Current / reference |
| --- | ---: | ---: | ---: | --- | ---: | ---: | ---: |
| SHA-224 | 16 | 284.7 | 185.5 | Nettle 3.10.1 | 193.2 | 0.650 [0.624, 0.660] | 0.960 [0.950, 0.975] |
| SHA-224 | 128 | 361.6 | 251.1 | Nettle 3.10.1 | 269.3 | 0.698 [0.638, 0.708] | 0.933 [0.922, 0.978] |
| SHA-224 | 4096 | 2620.3 | 2494.1 | Nettle 3.10.1 | 2487.1 | 0.955 [0.946, 0.963] | 1.003 [0.999, 1.009] |
| SHA-256 | 16 | 347.4 | 208.2 | Nettle 3.10.1 | 198.1 | 0.603 [0.582, 0.615] | 1.044 [1.033, 1.065] |
| SHA-256 | 128 | 417.3 | 272.5 | Nettle 3.10.1 | 273.4 | 0.648 [0.634, 0.672] | 0.996 [0.969, 1.081] |
| SHA-256 | 4096 | 2679.4 | 2524.3 | Nettle 3.10.1 | 2477.8 | 0.935 [0.921, 0.953] | 1.016 [1.005, 1.031] |
| SHA-384 | 16 | 1121.3 | 1050.3 | OpenSSL 4.1.0 | 770.9 | 0.935 [0.918, 0.960] | 1.378 [1.349, 1.401] |
| SHA-384 | 128 | 1343.9 | 1209.0 | OpenSSL 4.1.0 | 908.8 | 0.907 [0.891, 0.930] | 1.334 [1.321, 1.363] |
| SHA-384 | 4096 | 7563.0 | 7376.1 | OpenSSL 4.1.0 | 5489.1 | 0.979 [0.958, 0.995] | 1.347 [1.331, 1.375] |
| SHA-512 | 16 | 1112.6 | 1008.5 | OpenSSL 4.1.0 | 761.9 | 0.904 [0.854, 0.942] | 1.321 [1.291, 1.376] |
| SHA-512 | 128 | 1349.8 | 1214.4 | OpenSSL 4.1.0 | 918.9 | 0.892 [0.878, 0.937] | 1.324 [1.301, 1.367] |
| SHA-512 | 4096 | 7619.4 | 7445.3 | OpenSSL 4.1.0 | 5542.0 | 0.981 [0.966, 1.011] | 1.349 [1.315, 1.389] |

[Argon2id reproduction](../../../workloads/argon2/README.md#comparing-openssl-versions) · [scrypt and PBKDF2 reproduction](../../../workloads/kdf-replay/README.md) · [HMAC reproduction](../../../workloads/crypto/README.md) · [Raw samples and output checks](kdf-frozen-replay.json)
