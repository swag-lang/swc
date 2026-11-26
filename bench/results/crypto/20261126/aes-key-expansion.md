# Packed AES key expansion

AES-128 and AES-256 build their round keys with packed AES-NI operations.
AES-192 and targets without AES-NI use the existing schedule. The workload
initializes a fresh key schedule per message and includes the cost of clearing
key material.

The strongest measured gain is on short AES-256-CTR messages. At 64 bytes
the new rate was 0.458 GB/s, against 0.306 for the previous Swag build and
0.273 for OpenSSL 3.5.7. The GCM gain is clearest for 256 bytes and for
associated-data-only calls of 64 and 256 bytes.

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| aes-256-gcm-aad | 16 | 0 | packed-key | current | GB/s | 0.059 | 0.0471 | 1.25 [0.88, 1.34] |
| aes-256-gcm-aad | 64 | 0 | packed-key | current | GB/s | 0.221 | 0.178 | 1.23 [1.14, 1.33] |
| aes-256-gcm-aad | 256 | 0 | packed-key | current | GB/s | 0.795 | 0.661 | 1.22 [1.17, 1.23] |
| aes-256-gcm-aad | 4096 | 0 | packed-key | current | GB/s | 4.28 | 4.1 | 1.06 [0.94, 1.12] |
| aes-256-gcm | 16 | 0 | packed-key | current | GB/s | 0.0522 | 0.0423 | 1.23 [1.05, 1.28] |
| aes-256-gcm | 64 | 0 | packed-key | current | GB/s | 0.189 | 0.156 | 1.19 [0.849, 1.31] |
| aes-256-gcm | 256 | 0 | packed-key | current | GB/s | 0.671 | 0.569 | 1.17 [1.04, 1.29] |
| aes-256-gcm | 4096 | 0 | packed-key | current | GB/s | 2.65 | 2.53 | 1.04 [0.972, 1.09] |
| aes-256-ctr | 16 | 0 | packed-key | current | GB/s | 0.113 | 0.0768 | 1.5 [1.36, 1.61] |
| aes-256-ctr | 64 | 0 | packed-key | current | GB/s | 0.458 | 0.306 | 1.5 [1.15, 2.14] |
| aes-256-ctr | 256 | 0 | packed-key | current | GB/s | 1.54 | 1.06 | 1.46 [1.18, 1.6] |
| aes-256-ctr | 4096 | 0 | packed-key | current | GB/s | 5.61 | 4.99 | 1.1 [1.04, 1.15] |

Native Release passed 33 focused cases. Three key-vector cases passed
Release-safe and all 33 Release cases also passed under QEMU with AES and
PCLMUL disabled. Another 168 exact comparisons checked OpenSSL ciphertext
and tags for empty, partial and unaligned inputs.

[Raw paired trials](aes-key-expansion.json) · [External verification cases](aes-key-expansion-verification.json).
