# AES software substitution with cached field logarithms

The software AES substitution reuses two logarithm vectors within the
tower-field calculation. Register shuffles encode zero at the lookup and
keep the register-only substitution schedule. An independent model checked
all 256 pairs in the four-bit subfield.

The timing build disabled AES-NI dispatch and checked that PCLMUL remained
enabled. The OpenSSL 3.5.5 reference used
`OPENSSL_ia32cap='~0x200000000000000:~0x20000000000'` to clear AES-NI and
VAES. All measured outputs matched. The 64 KiB CTR and GCM comparisons
showed 13% higher paired throughput.

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| aes-256-ctr | 64 | 0 | cached-logs | tower | GB/s | 0.0464 | 0.0407 | 1.14 [1.07, 1.27] |
| aes-256-ctr | 4096 | 0 | cached-logs | tower | GB/s | 0.0598 | 0.0525 | 1.12 [0.916, 1.16] |
| aes-256-ctr | 65536 | 0 | cached-logs | tower | GB/s | 0.0592 | 0.0528 | 1.13 [1.1, 1.15] |
| aes-256-gcm | 64 | 0 | cached-logs | tower | GB/s | 0.0332 | 0.0298 | 1.12 [1.1, 1.17] |
| aes-256-gcm | 4096 | 0 | cached-logs | tower | GB/s | 0.0616 | 0.0546 | 1.13 [1.1, 1.24] |
| aes-256-gcm | 65536 | 0 | cached-logs | tower | GB/s | 0.0633 | 0.0561 | 1.13 [1.11, 1.14] |
| aes-256-gcm-aad | 64 | 0 | cached-logs | tower | GB/s | 0.0729 | 0.0669 | 1.1 [1.05, 1.13] |
| aes-256-gcm-aad | 4096 | 0 | cached-logs | tower | GB/s | 2.74 | 2.59 | 1.06 [1.05, 1.07] |
| aes-256-gcm-aad | 65536 | 0 | cached-logs | tower | GB/s | 5.92 | 5.88 | 1.01 [1.01, 1.01] |

Native Release passed 34 focused cases including the CCM stress case.
Native Release-safe passed the 33 functional AES cases. Both native
configurations passed those 33 cases in QEMU with AES and PCLMUL disabled.
The external sweep matched 168 complete ciphertext and tag cases, including
unaligned input. Release-safe exposed a fixture overflow in the wider CCM
stress selection and that fixture is tracked separately.

[Raw paired trials](aes-software-logs.json) · [External verification cases](aes-software-logs-verification.json).
