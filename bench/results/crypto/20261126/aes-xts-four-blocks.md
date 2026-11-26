# Four-block AES-XTS

AES-XTS groups four independent blocks for the hardware AES kernel, keeping
the tweak and ciphertext-stealing rules of a data unit. The new regression
fixture covers identical input and output storage, two packed batches and
a final partial block. The portable path is exercised with AES and PCLMUL
disabled.

The comparison used 11 paired native Release process CPU-time trials on
AMD EPYC 9V74 CPU 2, at a 25 ms target. AES-256-XTS initializes two 256-bit
keys and one tweak per data unit. All expected ciphertext and plaintext
bytes matched OpenSSL 3.5.7.

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| aes-256-xts-encrypt | 16 | 0 | four-block | OpenSSL | GB/s | 0.0768 | 0.053 | 1.43 [1.28, 1.52] |
| aes-256-xts-encrypt | 16 | 0 | four-block | serial | GB/s | 0.0768 | 0.057 | 1.33 [1.17, 1.76] |
| aes-256-xts-encrypt | 64 | 0 | four-block | OpenSSL | GB/s | 0.285 | 0.205 | 1.42 [1.15, 1.5] |
| aes-256-xts-encrypt | 64 | 0 | four-block | serial | GB/s | 0.285 | 0.118 | 2.32 [1.95, 2.61] |
| aes-256-xts-encrypt | 4096 | 0 | four-block | OpenSSL | GB/s | 3.96 | 6.68 | 0.6 [0.57, 0.636] |
| aes-256-xts-encrypt | 4096 | 0 | four-block | serial | GB/s | 3.96 | 0.199 | 19.9 [18.8, 23.3] |
| aes-256-xts-encrypt | 65536 | 0 | four-block | OpenSSL | GB/s | 4.77 | 12.1 | 0.379 [0.368, 0.409] |
| aes-256-xts-encrypt | 65536 | 0 | four-block | serial | GB/s | 4.77 | 0.196 | 24.2 [22.7, 25] |
| aes-256-xts-encrypt | 1048576 | 0 | four-block | OpenSSL | GB/s | 5.01 | 13.5 | 0.375 [0.324, 0.381] |
| aes-256-xts-encrypt | 1048576 | 0 | four-block | serial | GB/s | 5.01 | 0.207 | 24.1 [21, 25] |
| aes-256-xts-decrypt | 16 | 0 | four-block | OpenSSL | GB/s | 0.0761 | 0.0553 | 1.37 [0.962, 1.48] |
| aes-256-xts-decrypt | 16 | 0 | four-block | serial | GB/s | 0.0761 | 0.0592 | 1.29 [0.922, 1.36] |
| aes-256-xts-decrypt | 64 | 0 | four-block | OpenSSL | GB/s | 0.299 | 0.206 | 1.46 [1.03, 1.53] |
| aes-256-xts-decrypt | 64 | 0 | four-block | serial | GB/s | 0.299 | 0.123 | 2.37 [1.95, 2.53] |
| aes-256-xts-decrypt | 4096 | 0 | four-block | OpenSSL | GB/s | 3.65 | 6.86 | 0.531 [0.486, 0.545] |
| aes-256-xts-decrypt | 4096 | 0 | four-block | serial | GB/s | 3.65 | 0.2 | 18.5 [17.8, 20.9] |
| aes-256-xts-decrypt | 65536 | 0 | four-block | OpenSSL | GB/s | 4.45 | 13.1 | 0.341 [0.328, 0.349] |
| aes-256-xts-decrypt | 65536 | 0 | four-block | serial | GB/s | 4.45 | 0.201 | 21.9 [20.6, 22.8] |
| aes-256-xts-decrypt | 1048576 | 0 | four-block | OpenSSL | GB/s | 4.57 | 13.7 | 0.334 [0.329, 0.342] |
| aes-256-xts-decrypt | 1048576 | 0 | four-block | serial | GB/s | 4.57 | 0.21 | 21.8 [21.2, 24.4] |

At 1 MiB encryption rose from 0.207 to 5.01 GB/s and decryption from 0.210
to 4.57 GB/s. OpenSSL reached 13.5 and 13.7 GB/s. The related AES-CTR and
AES-GCM timings had paired confidence intervals that included parity at
64 bytes, 4 KiB and 1 MiB.

The shared hardware kernel passed 34 focused cases in each native Release
configuration and with AES and PCLMUL masked in QEMU. The external sweep
verified 60 unaligned data units in each XTS direction. The combined
workload also passed four HKDF-SHA-256 verification profiles.

[Raw paired trials](aes-xts-four-blocks.json) · [External verification](aes-xts-four-blocks-verification.json) · [CTR and GCM regression trials](aes-xts-ctr-gcm-regression.json).
