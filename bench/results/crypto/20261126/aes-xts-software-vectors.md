# SIMD whitening in software AES-XTS

The software AES-XTS path applies the tweak with full-block SIMD XOR
loads and stores. It keeps the doubling state in a vector between
ordinary blocks and clears the temporary block after use. Ciphertext
stealing uses the same whitening helper on its complete blocks.

| AES-256-XTS operation | Bytes | Previous Swag (GB/s) | SIMD whitening (GB/s) | OpenSSL 4.1.0 (GB/s) | Paired speed ratio (95% CI) |
| --- | ---: | ---: | ---: | ---: | ---: |
| Encrypt | 4096 | 0.0583 | 0.0688 | 0.498 | 1.17 [1.10, 1.20] |
| Decrypt | 4096 | 0.0488 | 0.0559 | 0.424 | 1.14 [1.13, 1.18] |
| Encrypt | 1048576 | 0.0583 | 0.0680 | 0.516 | 1.15 [1.11, 1.21] |
| Decrypt | 1048576 | 0.0490 | 0.0551 | 0.423 | 1.14 [1.04, 1.24] |

## Method

Both Swag builds use the same Release compiler, standard library and
benchmark, with only the software XTS path changed. The sources used
for timing exclude the AES-NI bit from the Swag runtime capability
result. OpenSSL 4.1.0 uses
`OPENSSL_ia32cap=~0x200000000000000:~0x20000000000` to disable AES-NI and
VAES. Measurements used one worker on CPU 2 of an AMD EPYC 9V74 and 13
paired trials targeting 11 ms of process CPU time. A separate native
AES panel used nine paired trials targeting 10 ms. Its intervals included
parity for both operations and all four tested sizes.
[Workload and build instructions](../../../workloads/crypto/README.md)

## Verification

Both directions matched OpenSSL on 56 length-and-offset combinations
each, including ciphertext stealing and a real QEMU AES-off dispatch.
The focused four XTS cases passed in Release and Release-safe on the
host, under QEMU with AES disabled, and with both AES and PCLMUL
disabled.

[Software trials](aes-xts-software-vectors.json) · [Native hardware controls](aes-xts-software-vectors-native.json) · [External verification](aes-xts-software-vectors-verification.json)
