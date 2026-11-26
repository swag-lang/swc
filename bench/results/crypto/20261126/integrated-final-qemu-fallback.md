# Final crypto checks with hardware instructions disabled

The native Release binary of `10bf72c650` matched the reference outputs
for all 114 profiles under Linux user-mode QEMU 10.0.13. The pass checks
19 operations at 0, 7, 64, 255, 1024 and 8193 bytes with input offset 1.
It disables AES-NI, SHA-NI and the configured carry-less and wide integer
instruction features on the emulated CPU. Reference implementations run
natively on the host. The pass checks bytes and records verification data.

Use a wrapper like this as the `--swag` executable. Select the original
19 operations, the six message sizes, `--offset 1` and `--verify-only`
in the common workload.

```sh
exec qemu-x86_64 \
  -cpu max,-aes,-pclmulqdq,-sha-ni,-avx512f,-avx512ifma,-vaes,-vpclmulqdq \
  "$SWAG_CRYPTO_BINARY" "$@"
```

[Raw differential results](integrated-final-qemu-fallback.json) · [Integrated timing panel](integrated-final.md) · [Reproduction](../../../workloads/crypto/README.md)
