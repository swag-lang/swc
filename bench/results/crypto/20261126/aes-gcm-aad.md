# AES-256-GCM with associated data only

This comparison authenticates one in-memory AAD buffer and emits the 16-byte AES-GCM tag.
The plaintext is empty, so GHASH is the work that scales with input size. Both implementations
initialize AES-256 and finish the tag for every operation. The key and nonce are synthetic,
and OpenSSL reuses its EVP context container.

The Release compiler and program ran on an AMD EPYC 9V74, with one worker pinned to CPU 2
and OpenSSL 3.5.7. Swag Core was built from `f2a0eb3fa2`. The runner interleaved eleven
CPU-time trials per implementation and size. The complete tags agreed in every trial
and in 56 additional cases at offsets 1 and 7 around block, batch, and 64 KiB boundaries.
[AES-GCM AAD trials](aes-gcm-aad.json) · [Unaligned verification](aes-gcm-aad-verify.json)

| AAD bytes | Swag GB/s | OpenSSL GB/s | Swag / OpenSSL (95% CI) |
| ---: | ---: | ---: | ---: |
| 64 | 0.176 | 0.205 | 0.853 [0.679, 0.880] |
| 4096 | 4.15 | 7.73 | 0.542 [0.514, 0.549] |
| 65536 | 6.10 | 20.6 | 0.297 [0.295, 0.305] |
| 1048576 | 6.28 | 22.4 | 0.281 [0.274, 0.313] |

Build the Swag and C binaries with the standard crypto workload instructions, then select the
AAD-only operation. [Crypto workload](../../../workloads/crypto/README.md)

```sh
python3 -B "$REPO/bench/workloads/crypto/run.py" \
  --swag "Swag=$WORK/swag-bin/swag-crypto" --reference "$WORK/reference" \
  --algorithm aes-256-gcm-aad --cpu 2 --clock cpu --scratch "$WORK" \
  --output "$WORK/aes-gcm-aad.json"
```
