# P-256 verification in Jacobian coordinates

ECDSA verification compares the projective X coordinate with the two
possible affine representatives after multiplying by the squared scale.
Since the field prime is below twice the group order, the candidates
are the signature's r and, when in range, r plus the order. This removes
the final field inversion. The new fixture has a recovered X above the
group order and matches OpenSSL.

Seventeen paired native Release process CPU-time trials ran on CPU 4 of
the AMD EPYC 9V74. The workload prepares a raw deterministic signature
before timing and imports the public key per call. The output includes
the verification decision and the full signature.

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| p256-verify | 64 | 0 | projective-x | OpenSSL | ops/s | 2.44e+03 | 1.43e+04 | 0.172 [0.169, 0.174] |
| p256-verify | 64 | 0 | projective-x | affine-x | ops/s | 2.44e+03 | 2.38e+03 | 1.03 [0.994, 1.06] |
| p256-verify | 4096 | 0 | projective-x | OpenSSL | ops/s | 2.45e+03 | 1.36e+04 | 0.179 [0.178, 0.182] |
| p256-verify | 4096 | 0 | projective-x | affine-x | ops/s | 2.45e+03 | 2.36e+03 | 1.04 [1.02, 1.07] |
| p256-verify-reject | 64 | 0 | projective-x | OpenSSL | ops/s | 2.41e+03 | 1.36e+04 | 0.175 [0.169, 0.179] |
| p256-verify-reject | 64 | 0 | projective-x | affine-x | ops/s | 2.41e+03 | 2.28e+03 | 1.05 [1.03, 1.08] |
| p256-verify-reject | 4096 | 0 | projective-x | OpenSSL | ops/s | 2.43e+03 | 1.36e+04 | 0.181 [0.175, 0.183] |
| p256-verify-reject | 4096 | 0 | projective-x | affine-x | ops/s | 2.43e+03 | 2.37e+03 | 1.03 [1.01, 1.07] |

The 4 KiB valid case improved by a paired 1.04×. The short valid case's
interval included parity. Thirty-two empty, unaligned and boundary
verification fixtures matched OpenSSL 3.5.7. Four ECDH smoke cases also
matched. Seven focused P-256 cases passed native Release and Release-safe.

[Raw paired trials](p256-projective-verify.json) · [Verification fixtures](p256-projective-verify-fixtures.json) · [ECDH smoke](p256-ecdh-smoke.json) · [Reproduction](../../../workloads/crypto/README.md).
