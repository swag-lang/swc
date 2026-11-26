# Baseline public-key comparison

Native Release Swag at `d9bfeae85f` was compared with OpenSSL 3.5.7 in 11 paired process
CPU-time trials on CPU 4 of an AMD EPYC 9V74 under Linux. All serialized public keys,
shared secrets and deterministic Ed25519 signatures matched. An additional sweep
matched 20 empty, short and unaligned inputs.

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| x25519-public | 32 | 0 | d9bfeae85f | OpenSSL | ops/s | 710 | 2.73e+04 | 0.0262 [0.0257, 0.0264] |
| x25519-shared | 32 | 0 | d9bfeae85f | OpenSSL | ops/s | 711 | 1.41e+04 | 0.0502 [0.0491, 0.051] |
| ed25519-public | 32 | 0 | d9bfeae85f | OpenSSL | ops/s | 391 | 2.72e+04 | 0.0144 [0.0142, 0.0145] |
| ed25519-sign | 64 | 0 | d9bfeae85f | OpenSSL | ops/s | 190 | 1.32e+04 | 0.0143 [0.0121, 0.015] |
| ed25519-sign | 4096 | 0 | d9bfeae85f | OpenSSL | ops/s | 187 | 1.17e+04 | 0.0163 [0.0157, 0.0179] |
| p256-public | 32 | 0 | d9bfeae85f | OpenSSL | ops/s | 661 | 8.97e+04 | 0.00732 [0.00699, 0.00913] |

[Raw trials and output fingerprints](asymmetric-baseline.json) ·
[Reproduction and operation boundaries](../../../workloads/crypto/README.md).
