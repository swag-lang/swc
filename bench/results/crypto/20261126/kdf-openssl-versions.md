# Native KDF comparison with OpenSSL 4.1

This replay tests Swag's `d81f3cd6b5` library with the native Release
compiler from `52a1ec78e9`. Each native reference probe was compiled
against the system OpenSSL 3.5.7 headers and shared library or the
OpenSSL 4.1.0 headers and static library. These are measurements of
the named builds, which differ in linkage and build configuration.

The runs used CPU 2 of an AMD EPYC 9V74 under Linux 6.18.57. Every
measured derivation matched byte for byte. The tables show median
process CPU milliseconds and paired 95% time-ratio intervals.

## Argon2id

Eleven paired rounds used four lanes, one worker, three passes,
Argon2 version 0x13 and a 32-byte result. libargon2 20190702 was built
with GCC 14.2 for Zen 4 and uses its AVX-512 kernel.

| MiB | Swag | OpenSSL 3.5.7 | OpenSSL 4.1.0 | libargon2 | Swag / OpenSSL 4.1.0 |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 1.396 | 1.663 | 1.602 | 0.866 | 0.878 [0.840, 0.894] |
| 64 | 122.894 | 140.684 | 143.638 | 91.489 | 0.858 [0.799, 1.346] |
| 256 | 752.913 | 718.025 | 728.927 | 475.202 | 1.018 [0.783, 1.159] |

Swag used 12% less CPU than OpenSSL 4.1.0 at 1 MiB. The paired
intervals included parity at 64 and 256 MiB. The tested libargon2
build used less CPU than Swag in all three profiles.

[Argon2id reproduction](../../../workloads/argon2/README.md#comparing-openssl-versions)

## PBKDF2-HMAC

Fifteen paired rounds also included Python’s OpenSSL 3.5.8 and
Nettle 3.10.1. The raw results retain those samples, the earlier Swag
baseline and all pairwise candidate ratios.

| HMAC | Iterations | Password / salt / output bytes | Swag | OpenSSL 3.5.7 | OpenSSL 4.1.0 | Nettle | Swag / OpenSSL 4.1.0 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| SHA-224 | 20000 | 8 / 16 / 80 | 5.434 | 8.754 | 7.284 | 7.002 | 0.744 [0.736, 0.755] |
| SHA-256 | 100000 | 8 / 16 / 32 | 8.487 | 14.449 | 12.056 | 11.689 | 0.706 [0.688, 0.709] |
| SHA-256 | 25000 | 200 / 150 / 96 | 6.389 | 11.062 | 9.039 | 8.710 | 0.701 [0.675, 0.729] |
| SHA-384 | 20000 | 200 / 150 / 100 | 29.998 | 25.399 | 23.099 | 30.362 | 1.288 [1.254, 1.365] |
| SHA-512 | 20000 | 8 / 16 / 64 | 9.562 | 8.502 | 7.611 | 10.182 | 1.256 [1.250, 1.272] |

Swag used 26–30% less CPU than OpenSSL 4.1.0 for SHA-224 and SHA-256.
OpenSSL 4.1.0 had the lowest measured CPU time for SHA-384 and
SHA-512. Swag used 29% and 26% more CPU in those paired profiles.

[PBKDF2 reproduction](../../../workloads/kdf-replay/README.md#standalone-openssl-versions)

The direct BlockMix report contains the equivalent scrypt profiles
against both OpenSSL builds and libsodium.

[scrypt](scrypt-direct-blockmix.md) · [Raw samples and derived outputs](kdf-openssl-versions.json)
