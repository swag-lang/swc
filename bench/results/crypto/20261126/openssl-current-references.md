# OpenSSL release comparison

The common workload compared the system OpenSSL 3.5.7 with OpenSSL 3.5.9
LTS and OpenSSL 4.1.0. The new reference executables statically linked
the upstream AMD64 release libraries built with GCC 14 and assembly
dispatch enabled. Each verifies the same output before and during timing.

The Swag build uses standard library revision `5963afe762`. The 24 profiles
used 11 interleaved 25 ms target process CPU-time trials on AMD EPYC 9V74
CPU 4. The table shows 1 MiB median throughput in GB/s.

| Operation | Swag | OpenSSL 3.5.7 | OpenSSL 3.5.9 | OpenSSL 4.1.0 |
| --- | ---: | ---: | ---: | ---: |
| md5 | 0.486 | 0.769 | 0.781 | 0.78 |
| sha1 | 1.82 | 1.76 | 1.84 | 1.82 |
| sha256 | 1.62 | 1.69 | 1.66 | 1.66 |
| sha512 | 0.534 | 0.856 | 0.86 | 0.85 |
| sha3-256 | 0.442 | 0.489 | 0.491 | 0.493 |
| poly1305 | 2.95 | 12.6 | 12.6 | 12.6 |
| chacha20 | 1.33 | 5.18 | 5.18 | 5.16 |
| chacha20-poly1305 | 0.916 | 3.69 | 3.69 | 3.65 |
| aes-256-gcm | 3.25 | 10.3 | 10.3 | 10.3 |
| aes-256-xts-encrypt | 5.97 | 13.7 | 13.7 | 13.7 |
| aes-256-ccm | 0.759 | 1 | 1 | 1.01 |
| aes-256-siv | 0.762 | 0.888 | 0.896 | 0.895 |

The OpenSSL medians at 1 MiB were close across these releases. The raw
trials include the 64-byte profiles and the iteration and timing counts.
The additional exact-output sweep includes HKDF and P-256 operations.

The source archives were checksum verified against the upstream release.
OpenSSL 4.1.0 SHA-256 is
`50c17baf54cb008f6ce42d50deb4b28050a1aad711636cabd4b241c7e90cc2fd`.
OpenSSL 3.5.9 SHA-256 is
`603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a`.
[OpenSSL upstream release index](https://www.openssl-library.org/source/).

[Raw paired trials](openssl-current-references.json) · [External verification](openssl-current-verification.json) · [Reproduction](../../../workloads/crypto/README.md).
