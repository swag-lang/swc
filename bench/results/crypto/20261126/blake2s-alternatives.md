# BLAKE2s vector rounds and keyed initialization alternatives

Two four-lane compression prototypes use byte shuffles for 16- and 8-bit rotates and pack their four message words from scalar loads. One indexes the round schedule at runtime. The other emits fixed word indexes for ten rounds. Both matched 896 independent Python hashlib digests over keyed and unkeyed one-shot and split input, with shortened digests and unaligned storage.

The four-lane prototypes achieved 0.31–0.35× the throughput of the published scalar pair code at 1 MiB. The tested vector implementations spend CPU on gathering each group of four message words and saving mutable vector state between steps. The library retains the scalar pair compression. [Vector comparison on CPU 1](blake2s-alternatives-vector-cpu1.json) · [Published BLAKE2s campaign](blake2s-paired-compression.md)

Two keyed-reset prototypes wrote the key directly into the state buffer. One explicitly zeroed its tail. The other relied on initialization and the preceding state clear. Both matched 1120 independent digests including reset after a previous keyed message. The second prototype also passed all four focused Core cases in each of native Release, native Release-safe and JIT.

The shortened keyed initialization improves throughput by 2.4–4.9% at 16–64 bytes in the keyed one-shot medians below, while the same build's unkeyed two-update throughput falls 3.1–5.2%. The explicit-clearing version showed smaller and less consistent effects. The library retains its existing reset path.

| Key bytes | Input mode | Input bytes | Previous Swag | Direct key buffer | Zero-initialized buffer |
| ---: | --- | ---: | ---: | ---: | ---: |
| 0 | one-shot | 16 | 3879.5 | 3851 | 3910.5 |
| 0 | one-shot | 64 | 4009.5 | 3854 | 3864 |
| 0 | one-shot | 1048576 | 10131.5 | 10054.5 | 10130.5 |
| 0 | two updates | 16 | 4443.5 | 4473.5 | 4587 |
| 0 | two updates | 64 | 4513.5 | 4615 | 4759 |
| 0 | two updates | 1048576 | 10072 | 10062 | 10121.5 |
| 32 | one-shot | 16 | 6401.5 | 6243 | 6215.5 |
| 32 | one-shot | 64 | 6383.5 | 6419 | 6233 |
| 32 | one-shot | 1048576 | 10199 | 10128 | 10105.5 |
| 32 | two updates | 16 | 7123.5 | 7343 | 6960 |
| 32 | two updates | 64 | 7134 | 7101.5 | 7070 |
| 32 | two updates | 1048576 | 10032.5 | 10112 | 10043 |

The table shows median microseconds per batch from four rotated runs with five batches each, pinned to CPU 3. The input patterns, complete digest checks and `CLOCK_THREAD_CPUTIME_ID` clock match the published BLAKE2s campaign. The earlier CPU 0 comparison also tested loading each selected word when its G step uses it, without a consistent improvement. All arms use the same Release compiler and runtime from `44e09064f1`, with the published BLAKE2s source at `567fc6edbc` as the baseline. [Keyed initialization retest](blake2s-alternatives-reset-cpu3.json) · [Keyed initialization and load-order pilot](blake2s-alternatives-reset-cpu0.json)
