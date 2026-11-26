# P-256 verification with signed sparse windows

The public-point multiplier uses width-five signed non-adjacent digits:
nonzero digits select one of eight odd multiples and are at least five
bit positions apart. A separate integer model reconstructed 10,259 input
values, including every single-bit position. The verification scalar
for this multiplier depends only on the public signature. ECDH still
scans fixed windows with masks. The generator multiplier also remains
masked for the scalar derived from the message digest.

Nineteen paired process CPU-time trials ran on CPU 4 of the AMD EPYC
9V74 with native Release builds. The fixed-window baseline is
`cb96f22f4e`. The faster external implementation in this panel was
OpenSSL 4.1.0. Inputs and complete outputs matched in all comparisons.

| Profile | Fixed-window ops/s | Sparse-window ops/s | OpenSSL 4.1.0 ops/s | Paired speed ratio (95% CI) |
| --- | ---: | ---: | ---: | ---: |
| Valid 64 B | 2,890 | 3,280 | 14,600 | 1.12 [1.11, 1.17] |
| Valid 4 KiB | 2,860 | 3,230 | 13,900 | 1.12 [1.09, 1.16] |
| Rejected 64 B | 2,950 | 3,120 | 14,400 | 1.09 [1.06, 1.12] |
| Rejected 4 KiB | 2,960 | 3,280 | 14,200 | 1.11 [1.10, 1.12] |
| ECDH control | 3,820 | 3,820 | 21,700 | 1.00 [0.991, 1.01] |

A separate 793-case corpus matched the OpenSSL 4.0.1 verification decision
in native Release and Release-safe. It covered both representatives of S,
mutated signatures and messages, out-of-range signature components, the
point at infinity, and every single-bit position of the public scalar.
Seven focused Core cases passed JIT and native in both configurations.

[Raw paired trials](p256-verify-wnaf.json) · [Exact verification corpus](p256-verify-wnaf-fixtures.json)
