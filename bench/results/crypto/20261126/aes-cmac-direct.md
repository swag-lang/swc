# Direct AES-CMAC blocks

The update path processes full input blocks by address and retains the
last block for finalization. AES-SIV uses the same authenticator. The
incremental regression fixture checks all 146 split points of a
145-byte message.

The common native Release workload compares full tags and ciphertext to
OpenSSL 3.5.7. At 1 MiB, CMAC rose from 0.309 to 0.832 GB/s and SIV from
0.307 to 0.761 GB/s. OpenSSL reached 0.986 and 0.891 GB/s, respectively.
The SIV provider was selected before the timer. Each timed call passes
the raw key.

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| aes-256-cmac | 1048576 | 0 | serial | OpenSSL | GB/s | 0.309 | 0.986 | 0.315 [0.307, 0.328] |
| aes-256-cmac | 1048576 | 0 | direct | OpenSSL | GB/s | 0.832 | 0.986 | 0.845 [0.806, 0.866] |
| aes-256-cmac | 1048576 | 0 | direct | serial | GB/s | 0.832 | 0.309 | 2.64 [2.62, 2.81] |
| aes-256-siv | 1048576 | 0 | serial | OpenSSL | GB/s | 0.307 | 0.891 | 0.35 [0.336, 0.353] |
| aes-256-siv | 1048576 | 0 | direct | OpenSSL | GB/s | 0.761 | 0.891 | 0.855 [0.842, 0.867] |
| aes-256-siv | 1048576 | 0 | direct | serial | GB/s | 0.761 | 0.307 | 2.47 [2.39, 2.54] |

External verification matched 56 unaligned cases per operation, including
empty input, and four smoke cases each for existing XTS, CCM and HKDF.
The 36 focused AES cases passed in both native Release configurations and
under QEMU with AES and PCLMUL disabled.

[Raw paired trials](aes-cmac-direct.json) · [External verification](aes-cmac-direct-verification.json).
