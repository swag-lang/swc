# Paired software AES-CTR blocks

The software AES-CTR path encrypts two consecutive counters in parallel
with the same tower-basis round key. A complete pair uses SIMD XOR for
the payload and clears both software AES states after use. Counter
addition carries into the high 64 bits, and the public range check rejects
counter overflow before writing output.

| AES-256-CTR bytes | Previous Swag (GB/s) | Paired Swag (GB/s) | OpenSSL 4.1.0 (GB/s) | Paired speed ratio (95% CI) |
| ---: | ---: | ---: | ---: | ---: |
| 64 | 0.0500 | 0.0846 | 0.0961 | 1.69 [1.67, 1.71] |
| 128 | 0.0552 | 0.103 | 0.265 | 1.88 [1.83, 2.00] |
| 4096 | 0.0648 | 0.137 | 0.523 | 2.09 [2.04, 2.12] |
| 65536 | 0.0656 | 0.138 | 0.539 | 2.09 [2.01, 2.15] |
| 1048576 | 0.0646 | 0.137 | 0.533 | 2.10 [2.08, 2.14] |

## Method

Both Swag builds use the same Release compiler and benchmark. For
throughput, the runtime source in the two scratch builds excludes the
AES-NI capability bit and runs on the physical CPU. The OpenSSL reference
uses `OPENSSL_ia32cap=~0x200000000000000:~0x20000000000` to disable AES-NI
and VAES. One worker on CPU 2 of an AMD EPYC 9V74 ran 15 interleaved
trials targeting 15 ms of process CPU time each. An 11-trial panel using
hardware AES had intervals spanning parity at every size and measured
7.89 GB/s and 7.93 GB/s at 1 MiB for the two Swag builds.
[Workload and build instructions](../../../workloads/crypto/README.md)

## Verification

The exact comparison matched OpenSSL for 88 input combinations on the
host, with the scratch runtime mask, and with native dispatch under QEMU
with AES and PCLMUL disabled. The four-worker software path also matched
16 inputs. Release and Release-safe each passed 39 focused AES cases on
both the host and under the same QEMU mask. The new in-place CTR case
covers a low-word carry between the two blocks of a pair and a partial tail.

[Software trials](aes-ctr-software-pairs.json) · [Native hardware controls](aes-ctr-software-pairs-native.json) · [External verification](aes-ctr-software-pairs-verification.json) · [Four-worker verification](aes-ctr-software-pairs-workers-verification.json)
