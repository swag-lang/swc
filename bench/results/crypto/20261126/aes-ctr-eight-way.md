# Eight independent AES-NI counters

Swag schedules eight independent AES-CTR blocks with one round key per
iteration. The main counter loop selects this batch where low-word addition
stays within the validated counter range. The existing four-block and
single-block loops handle shorter spans and counters that cross the low-word
boundary. AES-CCM also uses the 64-bit counter kernel for its separate CTR
pass.

At 4 KiB, AES-256-CTR reached 6.18 GB/s, up from 5.42. At 64 KiB, it
reached 7.74 GB/s, up from 6.56. In the 1 MiB repeat, Swag reached
7.72 GB/s and OpenSSL 4.1.0 reached 7.88 GB/s.

| AES-256-CTR bytes | Four blocks (GB/s) | Eight blocks (GB/s) | OpenSSL 4.1.0 (GB/s) | Paired speed ratio (95% CI) |
| ---: | ---: | ---: | ---: | ---: |
| 64 | 0.455 | 0.434 | 0.427 | 0.94 [0.78, 1.12] |
| 128 | 0.867 | 0.888 | 0.791 | 1.01 [0.86, 1.05] |
| 4096 | 5.42 | 6.18 | 6.30 | 1.14 [1.09, 1.16] |
| 65536 | 6.56 | 7.74 | 7.88 | 1.17 [1.13, 1.22] |
| 1048576 (repeat) | 6.66 | 7.72 | 7.88 | 1.16 [1.14, 1.17] |

## Method

Both Swag builds use the same Release compiler, library snapshot and
harness. The initial panel compares AES-CTR and AES-CCM with 13 interleaved
trials targeting 12 ms of process CPU time per implementation and input.
The 1 MiB CTR interval included parity in that panel. The repeat used 17
trials targeting 22 ms and confirmed the bulk gain. AES-CCM intervals in the
initial panel include parity. The comparison ran on CPU 2 of an AMD EPYC
9V74 with one worker. Rates reflect the input bytes processed, including
the per-operation key schedule cost in the timing.
[Workload and build instructions](../../../workloads/crypto/README.md)

## Verification

All 92 size-and-offset combinations matched OpenSSL 4.1.0 in native
AES-256-CTR and under QEMU with AES and PCLMUL disabled. A four-worker
verification matched 16 AES-CTR and 16 AES-CCM cases at lengths of 64 KiB
and above. All 38 focused AES tests passed in Release and Release-safe
on the host and under the same QEMU mask. The new unaligned AES-192-CTR
test checks in-place encryption, decryption and both buffer guards across
an eight-block batch and a partial tail.

[Initial paired trials](aes-ctr-eight-way.json) · [1 MiB repeat](aes-ctr-eight-way-large.json) · [CTR verification](aes-ctr-eight-way-verification.json) · [Four-worker verification](aes-ctr-eight-way-workers-verification.json)
