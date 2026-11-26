# PBKDF2-HMAC-SHA-224/256 fixed final blocks

Later PBKDF2 iterations hash one digest after each keyed pad. Swag prepares
the final SHA block once per output block and reuses its padding and length.
Each iteration copies the eight keyed state words and invokes the existing
SHA compressor. Packed stores serialize the digest and accumulate the
outer digest with XOR. Temporary blocks, states and digests are cleared.

Both Swag executables use native Release and the SHA extensions from
`62a7adb588`. They ran on CPU 1 of an AMD EPYC 9V74 under Linux 6.18.57.
The workload verified every derived byte and ran 15 shuffled paired
rounds per profile. Process CPU medians are in milliseconds. The ratio
columns show paired candidate time ratios and 95% intervals.

| HMAC | Iterations | Password / salt / output bytes | Prefix reuse | Fixed blocks | OpenSSL 3.5.8 | Fixed / prefixes | Fixed / OpenSSL |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| SHA-224 | 20000 | 8 / 16 / 80 | 8.756 | 5.444 | 8.157 | 0.623 [0.615, 0.633] | 0.669 [0.656, 0.674] |
| SHA-256 | 100000 | 8 / 16 / 32 | 15.007 | 8.557 | 13.183 | 0.572 [0.557, 0.589] | 0.653 [0.643, 0.667] |
| SHA-256 | 25000 | 200 / 150 / 96 | 11.239 | 6.416 | 9.810 | 0.576 [0.570, 0.611] | 0.656 [0.647, 0.704] |
| SHA-384 | 20000 | 200 / 150 / 100 | 45.169 | 45.444 | 25.204 | 0.996 [0.973, 1.034] | 1.794 [1.752, 1.818] |
| SHA-512 | 20000 | 8 / 16 / 64 | 15.025 | 15.074 | 8.810 | 1.001 [0.978, 1.008] | 1.708 [1.683, 1.732] |

The SHA-224/256 profiles used 38–43% less CPU than the prefix-reuse
baseline and 33–35% less than OpenSSL. Their elapsed-time intervals also
excluded parity against both comparators. In a separate retest with
SHA-NI enabled on both Swag builds, prefix reuse reduced SHA-224/256 CPU
time by 50–72% compared with the previous derivation and used 5–12% more
CPU than OpenSSL.

The focused Core selection passed 20 native Release cases, the same 20
with SHA instructions masked under QEMU 10.0.13, and 20 Release JIT cases.
The selection covers SHA, HMAC lifecycle, PBKDF2 output tails and overlap,
and the scrypt consumer.

[Reproduction](../../../workloads/pbkdf2/README.md) · [Raw times and derived outputs](pbkdf2-fixed-blocks.json)
