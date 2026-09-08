# ChaCha20 native partition scaling

Run from the repository root after the machine-load admission check:

```powershell
bin/swc.dm.exe test -f src/chacha20.test.swg --module-file bench/chacha20/module.swg -bc release --no-test-jit --num-cores 6
```

This native test compares one and four runtime workers while keeping the four-block SIMD kernel,
key, nonce, counter and input fixed. Each sample encrypts approximately 16 MiB through repeated
calls at the stated message size. Pool startup, buffer allocation, warm-up and byte comparisons
are outside the timer. Every output must match the one-worker result.

The one-worker measurements precede the four-worker measurements because the pool can grow but
cannot shrink. These are local samples, not an interleaved performance campaign. In the original
implementation, the two sizes below 64 KiB exercised a forced sequential path.

Measured 2026-09-08 on an Intel Core Ultra 9 185H, using `swc.dm.exe` and the `release`
program configuration:

| Message bytes | Calls per sample | One-worker samples (us) | Four-worker samples (us) | Median speedup |
| --- | --- | --- | --- | --- |
| 16384 | 1024 | 39207, 42894, 53023 | 42717, 42311, 43620 | 1.00x |
| 65535 | 256 | 63089, 48449, 41836 | 53088, 45265, 47255 | 1.03x |
| 65536 | 256 | 41273, 42699, 40905 | 23923, 29151, 28541 | 1.45x |
| 262144 | 64 | 41274, 42354, 36659 | 29327, 25029, 21797 | 1.65x |
| 4194304 | 4 | 49785, 48748, 39379 | 24694, 21368, 25652 | 1.97x |

ChaCha20-Poly1305 uses this path for encryption and authenticated decryption. Its sequential
authentication cost is not included in these measurements; the ratios are for ChaCha20 XOR only.

After replacing the 64 KiB gate with runtime cost hints on 2026-09-08, the same body ran from
a standalone native entry with assertions enabled, admitted at 2% average CPU:

| Message bytes | One-worker median (us) | Four-worker median (us) | Median speedup |
| --- | --- | --- | --- |
| 16384 | 27926 | 16029 | 1.74x |
| 65535 | 28099 | 10569 | 2.66x |
| 65536 | 28556 | 10202 | 2.80x |
| 262144 | 28133 | 9226 | 3.05x |
| 4194304 | 28021 | 8259 | 3.39x |

The runtime can now use workers below the old byte threshold when the actual kernel cost
justifies them. The sequential controls also improved substantially between the two measurement
sessions, so their absolute before/after ratios do not isolate the runtime change.
