# Reuse the keyed CMAC state across AES-SIV inputs

AES-SIV prepares one CMAC key schedule for the sequence of associated
data and plaintext inputs. Each completed input restarts from the same
keyed state. The key is cleared when the sequence ends.

At 64 bytes, throughput rose from 0.0531 to 0.0845 GB/s with a paired
1.63× [1.49, 1.97] gain. OpenSSL 4.1.0 reached 0.0432 GB/s. At 4 KiB the
Swag throughput gain was about 6%. Standalone CMAC confidence intervals
included parity.

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| aes-256-siv | 16 | 0 | reuse | current | GB/s | 0.0244 | 0.0155 | 1.58 [1.45, 1.65] |
| aes-256-siv | 64 | 0 | reuse | current | GB/s | 0.0845 | 0.0531 | 1.63 [1.49, 1.97] |
| aes-256-siv | 4096 | 0 | reuse | current | GB/s | 0.643 | 0.61 | 1.06 [1.02, 1.09] |
| aes-256-siv | 65536 | 0 | reuse | current | GB/s | 0.745 | 0.73 | 1.01 [0.998, 1.04] |
| aes-256-cmac | 16 | 0 | reuse | current | GB/s | 0.0516 | 0.0498 | 1.04 [0.953, 1.21] |
| aes-256-cmac | 64 | 0 | reuse | current | GB/s | 0.159 | 0.162 | 0.966 [0.856, 1.09] |
| aes-256-cmac | 4096 | 0 | reuse | current | GB/s | 0.772 | 0.745 | 1.01 [0.985, 1.06] |
| aes-256-cmac | 65536 | 0 | reuse | current | GB/s | 0.845 | 0.85 | 0.996 [0.977, 1.01] |

OpenSSL 4.1.0 matched 56 SIV and 56 CMAC outputs. Both native Release
configurations passed 37 focused AES cases on the host and with AES and
PCLMUL disabled under QEMU.

[Raw paired trials](aes-siv-cmac-reuse.json) · [External verification](aes-siv-cmac-reuse-verification.json).
