# AES software rounds in the tower basis

The software path keeps the expanded key and round state in the tower
field basis. Fixed register maps implement the affine and column
linear transforms, with basis conversion at block boundaries. The
finite-field model checked all 256 byte values.

The paired native Release runs disabled AES-NI dispatch in Swag and
AES-NI and VAES in OpenSSL 4.1.0. At 64 KiB, GCM throughput rose from
0.0624 to 0.0683 GB/s, a paired 1.10×. CTR rose from 0.0599 to
0.0657 GB/s. At 4 KiB the XTS encryption and decryption gains were
about 11% and 7%.

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| aes-256-gcm | 64 | 0 | tower | current | GB/s | 0.0361 | 0.0335 | 1.09 [1.03, 1.11] |
| aes-256-gcm | 4096 | 0 | tower | current | GB/s | 0.0662 | 0.0616 | 1.08 [1.02, 1.09] |
| aes-256-gcm | 65536 | 0 | tower | current | GB/s | 0.0683 | 0.0624 | 1.1 [1.08, 1.2] |
| aes-256-ctr | 64 | 0 | tower | current | GB/s | 0.0496 | 0.0461 | 1.07 [1.04, 1.12] |
| aes-256-ctr | 4096 | 0 | tower | current | GB/s | 0.063 | 0.059 | 1.08 [1.06, 1.16] |
| aes-256-ctr | 65536 | 0 | tower | current | GB/s | 0.0657 | 0.0599 | 1.09 [1.06, 1.11] |
| aes-256-gcm-aad | 64 | 0 | tower | current | GB/s | 0.0772 | 0.0728 | 1.06 [1.02, 1.07] |
| aes-256-gcm-aad | 4096 | 0 | tower | current | GB/s | 2.43 | 2.57 | 1.02 [0.918, 1.12] |
| aes-256-gcm-aad | 65536 | 0 | tower | current | GB/s | 5.77 | 5.78 | 1 [0.976, 1.38] |
| aes-256-xts-encrypt | 64 | 0 | tower | current | GB/s | 0.0315 | 0.0291 | 1.09 [1.05, 1.14] |
| aes-256-xts-encrypt | 4096 | 0 | tower | current | GB/s | 0.0593 | 0.0541 | 1.11 [1.08, 1.13] |
| aes-256-xts-encrypt | 65536 | 0 | tower | current | GB/s | 0.0584 | 0.0546 | 1.06 [0.978, 1.14] |
| aes-256-xts-decrypt | 64 | 0 | tower | current | GB/s | 0.0317 | 0.0291 | 1.05 [1.03, 1.13] |
| aes-256-xts-decrypt | 4096 | 0 | tower | current | GB/s | 0.0492 | 0.0461 | 1.07 [1.02, 1.1] |
| aes-256-xts-decrypt | 65536 | 0 | tower | current | GB/s | 0.05 | 0.0468 | 1.07 [0.907, 1.07] |

The exact OpenSSL sweep compared 48 unaligned cases each for GCM, CTR
and AAD-only GCM and 56 per XTS direction. Both native Release
configurations passed 37 focused AES cases on the host, in QEMU with
AES disabled, and in QEMU with AES and PCLMUL disabled.

[Raw paired trials](aes-software-tower-rounds.json) · [External verification](aes-software-tower-verification.json) · [XTS trials](aes-software-tower-xts.json) · [XTS verification](aes-software-tower-xts-verification.json).
