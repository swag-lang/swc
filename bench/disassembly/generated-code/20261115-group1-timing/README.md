# First three batches: Linux paired veto check

Combined revision `5d38c841ae` versus the initial compiler's freshly compiled programs.
The target changes are `a9654c9f5f` (Leven carries), `da83050d23` (frame-address arguments),
and `4032c0f8cb` (floating spill cache). Each was integrated after its complete twelve-task
static/checksum verification. All three remain **landed, unconfirmed**.

This check uses the repository process-isolation runner, pinned to the first allowed CPU,
and each benchmark's own timed region. Sources, runtime contents, configurations, module
names, inputs and three-worker compilation limits match; caches/outputs are separate.
Both programs were warmed, and no own builds or tests ran alongside measurement. Two
independent blocks each contain six A/A controls and six alternating A/B and B/A pairs.
Every sample, warmup, checksum, binary hash, CPU/cgroup context and load reading is retained
in [samples.json.gz](samples.json.gz). The host is an AMD EPYC 9V74 cloud machine with a
four-core cgroup quota; this is not the Windows performance-core cohort.

| Task | A/A median by block | New/old median by block | A/A min / max, both blocks |
| --- | --- | --- | --- |
| Leven | 0.923 / 1.026 | 0.997 / 1.031 | 0.631 / 1.254 |
| Binarytrees | 1.130 / 0.961 | 0.936 / 1.110 | 0.859 / 1.410 |
| Nbody | 1.007 / 1.004 | 0.998 / 1.043 | 0.682 / 1.222 |
| Raytrace sentinel | 0.982 / 1.010 | 0.993 / 0.961 | 0.919 / 1.106 |

These dispersions and block drift do not establish a gain or a clear repeatable slowdown
beyond the unchanged controls. No batch is confirmed or vetoed by these samples. Raytrace's
kernel is unchanged, and its noisy move supplies no evidence for an emitter placement defect.
No Windows history entry or inferred corrected index was written. The required full combined
Windows campaign, corrected indices and null bands remain pending the next compatible host.
