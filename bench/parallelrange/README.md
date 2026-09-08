# Parallel-loop load balance

```powershell
bin/swc.dm.exe run -f src/parallelrange.swg --module-file bench/parallelrange/module.swg -bc release --num-cores 6
```

This benchmark compares cheap loops, uniform CPU work, work concentrated in the first or last
quarter of a range, and four expensive iterations. Each case warms the same loop body 32
times, then records three samples. Every result is checked outside the timed region against a
sequential computation, with assertions enabled in the Release program.

One-worker controls run before four-worker measurements, so the process never needs to shrink
its pool. The arithmetic has a loop-carried dependency and its result reaches the checked buffer.
The concentrated cases keep most of their cost inside one of the old scheduler's static blocks.

Admit every build and run with the repository's machine-load check. Compare the same source and
compiler on a quiet machine before and after a runtime change; timing is evidence for these
workloads, not a portable performance assertion.

On 2026-09-08, the same DevMode compiler built this Release program with the previous static
partitioning and then with bounded dynamic blocks. CPU load at admission was 3% for both runs.
The table reports medians of three samples, in microseconds; the cheap case times 65,536 calls
and every other case times eight calls.

| Workload | Static, one worker | Dynamic, one worker | Static, four workers | Dynamic, four workers |
| --- | ---: | ---: | ---: | ---: |
| Cheap | 6853 | 6701 | 6859 | 6894 |
| Uniform | 46672 | 44861 | 11894 | 11713 |
| Heavy first quarter | 50308 | 48078 | 47398 | 12411 |
| Heavy last quarter | 51798 | 49813 | 46361 | 12944 |
| Four expensive iterations | 11449 | 12392 | 3259 | 2936 |

The concentrated cases improve by about 3.6 to 3.8 times with four workers. The cheap and uniform
controls are comparable in this pair. Earlier short runs showed visible shared-machine variance,
including slower one-worker controls, so these measurements do not establish small percentage
improvements. One indivisible expensive iteration, or one already claimed expensive block, can
still dominate completion: dynamic block assignment does not preempt a computation.
