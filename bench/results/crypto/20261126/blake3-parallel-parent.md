# BLAKE3 parallel parent reduction

At 32 MiB, Swag with four configured workers reached 4.56 GB/s,
up from 3.44 GB/s. The median paired speed ratio was **1.39×
[1.11, 1.62]**. BLAKE3 C 1.8.7 with oneTBB 2022.1.0 reached 16.4
GB/s at the same configured worker limit.

Each worker now finishes an aligned eight-chunk subtree before handing
its chaining value to the serial tree stack. It uses the existing four
SIMD lanes for the first four parent nodes, then merges the remaining
three parents. An aligned worker range therefore transfers one chaining
value per eight chunks. The serialized tree stores each complete subtree
at its matching height. Short and unaligned ranges can use individual
chunk outputs, and the final block stays available for root output.

## Four-worker wall time

The table reports GB/s and paired speed ratios with 95% confidence
intervals. Both Swag variants use the same Release compiler, worker budget
and input. The four-worker C comparator selects the 16-lane AVX-512 path
with a oneTBB concurrency limit of four.

Linux x86-64 on AMD EPYC 9V74, aligned input, CPUs 0–3, 11 shuffled rounds
and a 17 ms target. The cgroup recorded zero throttled periods during this
run. [Wall samples](blake3-parallel-parent-wall.json)

| Input | Swag before | Swag subtree | C oneTBB 4 | Paired speed ratio |
| --- | ---: | ---: | ---: | ---: |
| 1 MiB | 3.14 | 4.37 | 16.4 | 1.38 [1.32, 1.58] |
| 8 MiB | 3.41 | 4.50 | 22.1 | 1.31 [1.20, 1.58] |
| 32 MiB | 3.44 | 4.56 | 16.4 | 1.39 [1.11, 1.62] |

Median process CPU divided by wall time rose from 2.27, 2.38 and 2.52
to 2.88, 3.14 and 3.14 across these sizes. C oneTBB used 3.92, 3.78
and 3.75. These ratios describe observed CPU use under the configured
worker limits.

The one-worker CPU-time run measured paired ratios of 1.05 [1.03, 1.12]
at 64 KiB and 1.05 [1.00, 1.14] at 1 MiB. The 4 and 8 KiB confidence
intervals included parity. In the samples the shared-source candidate
is labeled `generic` for the four-worker run and `parent` for the
one-worker run. The alternate proof variants preserve the other measured
controls. [One-worker samples](blake3-parallel-parent-cpu.json)

## Validation

The focused native Core suite passed six tests each in Release and
Release-safe. A separate official 131-byte fixture passed in both
configurations for unkeyed, keyed, and derived-key output with four
workers and staggered streaming updates. The candidate matched the
official C driver on 192 additional inputs across one-shot, 4 KiB,
64 KiB, and 1 MiB streaming profiles, with offsets of 0, 1 and 15 and
both worker budgets. [Differential fixtures](blake3-parallel-parent-verify.json)

The baseline uses the 32-chunk cutoff from commit `81a3bce04b`. To
repeat the four-worker panel, use `run-tbb.py` with the baseline and
current release binaries, set both worker counts to four and select
sizes `1048576`, `8388608` and `33554432`. Select CPU time and one
worker for the serial measurements.
[Build and timing commands](../../../workloads/blake3/README.md)
