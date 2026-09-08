# Filtered image resize

Run the native Release-program benchmark with the checkout-local compiler:

```powershell
bin/swc.dm.exe test -f src/resize.test.swg --module-file bench/resize/module.swg -bc release --no-test-jit --num-cores 6
```

The benchmark resizes patterned RGBA8 images from `(2 * size + 1, 2 * size - 1)`
to square destinations with Bicubic filtering. It includes contribution-table allocation,
both filtering passes, and image destruction. Each size has one warm-up and three samples;
each sample covers at least 131,072 destination pixels. Equality checks outside the timer
verify repeatability. The module's resize tests separately compare all seven filters with
direct sequential kernels, including nested parallel calls and integer/float formats.

One worker runs before four because the runtime pool can grow but cannot shrink. These
samples are neither interleaved nor affinity-pinned; treat the numbers as local scheduling
evidence, not as a cross-machine performance guarantee.

On 2026-09-08, before the small-pass threshold, the 8 x 8 case took a median 44,067 us
for 2,048 calls with four workers versus 17,163 us with one. After the threshold and
native `parallel for` migration, the same case took 24,299 us with four workers versus
22,743 us with one. The serial control also slowed between runs, so the before/after
ratio alone does not isolate the change. The worker penalty on tiny images disappeared.

After the change, median one-worker/four-worker times were 14,817/8,568 us at 64 x 64,
16,139/6,456 us at 256 x 256, and 336,528/108,618 us at 1024 x 1024. Large passes still
benefit from distributing independent rows and columns. That revision kept passes below 1,024
destination pixels sequential. The runtime's cost hints now replace this pixel-specific
threshold; the same benchmark measures whether cheap passes stay local and larger passes scale.

With runtime adaptation and no pixel-count gate, a standalone native run of the same body on
2026-09-08, admitted at 3% average CPU, produced these medians:

| Destination | One worker (us) | Four workers (us) |
| --- | --- | --- |
| 8 x 8 | 10335 | 10610 |
| 32 x 32 | 8094 | 6057 |
| 64 x 64 | 7794 | 3392 |
| 256 x 256 | 7612 | 2594 |
| 1024 x 1024 | 144488 | 52579 |

Tiny passes remain close to the one-worker control, and large passes still scale. The control
also improved relative to earlier sessions, so do not attribute the full absolute reduction to
the scheduling change.
