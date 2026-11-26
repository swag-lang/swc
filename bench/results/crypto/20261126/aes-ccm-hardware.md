# AES-CCM hardware CBC-MAC and CTR

AES-CCM keeps its authentication state in vector registers and uses the
batched AES-CTR path for payload blocks. CCM's message-length bounds
constrain the counter to its designated bytes. The added fixture uses a
13-byte nonce and checks exact in-place encryption over a partial block.

The common native Release process-clock comparison measured complete
ciphertexts and 16-byte tags against OpenSSL 3.5.7. At 1 MiB throughput
rose from 0.192 to 0.753 GB/s, with a paired speedup of 3.93×. OpenSSL
measured 1.01 GB/s. The provider's tag and nonce lengths were set outside
the timer. Keys and nonce were passed per message.

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| aes-256-ccm | 64 | 0 | vector-mac-ctr | OpenSSL | GB/s | 0.167 | 0.264 | 0.633 [0.521, 0.652] |
| aes-256-ccm | 64 | 0 | vector-mac-ctr | serial | GB/s | 0.167 | 0.0988 | 1.73 [1.38, 1.9] |
| aes-256-ccm | 4096 | 0 | vector-mac-ctr | OpenSSL | GB/s | 0.718 | 0.969 | 0.742 [0.722, 0.762] |
| aes-256-ccm | 4096 | 0 | vector-mac-ctr | serial | GB/s | 0.718 | 0.19 | 3.8 [3.66, 4.84] |
| aes-256-ccm | 65536 | 0 | vector-mac-ctr | OpenSSL | GB/s | 0.764 | 1.01 | 0.755 [0.751, 0.76] |
| aes-256-ccm | 65536 | 0 | vector-mac-ctr | serial | GB/s | 0.764 | 0.192 | 3.97 [3.93, 4.08] |
| aes-256-ccm | 1048576 | 0 | vector-mac-ctr | OpenSSL | GB/s | 0.753 | 1.01 | 0.745 [0.721, 0.76] |
| aes-256-ccm | 1048576 | 0 | vector-mac-ctr | serial | GB/s | 0.753 | 0.192 | 3.93 [3.86, 4.14] |

Five focused cases passed in each native Release configuration and under
QEMU with AES and PCLMUL disabled. The cases include the parallel stress
fixture and failed-tag handling. The external sweep checked 56 unaligned
inputs. Existing XTS and HKDF workloads passed their smoke profiles.

[Raw paired trials](aes-ccm-hardware.json) · [External verification](aes-ccm-hardware-verification.json).
