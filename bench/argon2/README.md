# Argon2 native lane scaling

Run from the repository root, after the machine-load admission check:

```powershell
bin/swc.dm.exe test -f src/argon2.test.swg --module-file bench/argon2/module.swg -bc release --no-test-jit --num-cores 6
```

The native test derives a 32-byte Argon2id tag with four lanes and three passes. It uses the
same scalar compression kernel, input, allocation, clearing and parameters for one and four
runtime workers. Each profile has one untimed warm-up and three timed samples; every tag must
match the one-worker result. Pool startup is outside the timer. The test runs the one-worker
profiles first because the runtime pool can grow but cannot shrink. These are local timing
samples, not an interleaved machine-wide performance campaign.

The 256 MiB profile matches Swag Vault's production slot-key costs. Its unit-test profile uses
one lane and 32 KiB, so ordinary Vault unit tests do not measure that production computation.

Measured 2026-09-08 06:30 on an Intel Core Ultra 9 185H, using the DevMode compiler and the
`release` program configuration:

| Memory | One-worker samples (us) | Four-worker samples (us) | Median speedup |
| --- | --- | --- | --- |
| 64 MiB | 204105, 206413, 209873 | 72815, 70645, 70480 | 2.92x |
| 256 MiB | 858210, 862168, 862776 | 311284, 308269, 305569 | 2.80x |

To evaluate a future SIMD kernel, compare it at the same worker count. Changing lane count
changes the derived key and is not a sequential baseline.
