# Paired software AES counters in GCM and CCM

AES-GCM and AES-CCM reuse the tower-basis two-block counter operation
from AES-CTR. Each mode encodes its validated counter in the same format
used by its hardware path. The original single-block code handles
remaining bytes and a partial final block.

| Algorithm | Bytes | Previous Swag (GB/s) | Paired Swag (GB/s) | OpenSSL 4.1.0 (GB/s) | Paired speed ratio (95% CI) |
| --- | ---: | ---: | ---: | ---: | ---: |
| AES-256-GCM | 64 | 0.0353 | 0.0480 | 0.0598 | 1.33 [1.29, 1.41] |
| AES-256-GCM | 4096 | 0.0674 | 0.130 | 0.470 | 1.94 [1.90, 1.98] |
| AES-256-GCM | 65536 | 0.0682 | 0.135 | 0.503 | 1.97 [1.94, 2.03] |
| AES-256-GCM | 1048576 | 0.0682 | 0.136 | 0.505 | 1.98 [1.95, 2.01] |
| AES-256-CCM | 64 | 0.0216 | 0.0262 | 0.0649 | 1.19 [1.18, 1.24] |
| AES-256-CCM | 4096 | 0.0336 | 0.0458 | 0.104 | 1.36 [1.31, 1.44] |
| AES-256-CCM | 65536 | 0.0344 | 0.0462 | 0.104 | 1.35 [1.32, 1.37] |
| AES-256-CCM | 1048576 | 0.0341 | 0.0456 | 0.104 | 1.35 [1.27, 1.38] |

## Method

Both Swag builds use one Release compiler and the same benchmark.
Timing builds exclude the AES-NI capability bit from the Swag runtime,
and OpenSSL 4.1.0 uses
`OPENSSL_ia32cap=~0x200000000000000:~0x20000000000` to disable AES-NI and
VAES. The AMD EPYC 9V74 measurements used one worker pinned to CPU 2
and 13 paired trials targeting 11 ms of process CPU time. AES-CTR
control intervals included parity at each software size. Separate
native AES trials used 11 rounds targeting 12 ms and had intervals
including parity for AES-GCM, AES-CCM and AES-CTR.
[Workload and build instructions](../../../workloads/crypto/README.md)

## Verification

GCM, CCM and CTR matched their complete OpenSSL outputs on 88
size-and-offset combinations each on the host and under QEMU with AES
disabled and with both AES and PCLMUL disabled. The four-worker
software path matched eight additional large inputs per mode. All 39
focused AES cases passed in Release and Release-safe on the host and
under both QEMU masks.

[Software trials](aes-aead-software-pairs.json) · [Native hardware controls](aes-aead-software-pairs-native.json) · [External verification](aes-aead-software-pairs-verification.json) · [Four-worker verification](aes-aead-software-pairs-workers-verification.json)
