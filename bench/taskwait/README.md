# Task join CPU usage

```powershell
bin/swc.dm.exe run -f src/taskwait.swg --module-file bench/taskwait/module.swg -bc release --num-cores 6
```

This Windows benchmark measures elapsed time and CPU time of the joining thread with four
runtime workers. The short control submits and joins 20,000 tiny tasks per sample. The long
case submits ten tasks that each sleep for 50 milliseconds; it observes each task starting on
a worker before joining, so the caller cannot execute the sleep itself. Every completed task
is counted, and three samples run for each case.

Caller CPU time includes both kernel and user time reported by
[GetThreadTimes](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-getthreadtimes).
Its accounting granularity is visible in the samples: a reported zero means below the observed
accounting quantum, not zero processor instructions. Windows sleep resolution can also extend
the nominal half-second duration.

Admit each command with the repository's machine-load check and avoid concurrent builds while
measuring. On 2026-09-08, the same DevMode compiler built this Release program before and after
replacing repeated spin/yield joins with a short spin followed by a condition wait. Admission CPU
load was 5% before and 6% after. Medians, in microseconds:

| Case | Before elapsed | After elapsed | Before caller CPU | After caller CPU |
| --- | ---: | ---: | ---: | ---: |
| 20,000 short tasks | 22314 | 25305 | 15625 | 15625 |
| 10 long tasks | 573885 | 571264 | 468750 | 0 |

Long-wait CPU samples fell from 453125–468750 microseconds to 0–15625 microseconds, with
comparable elapsed time. The short control's median increased by about 13% in this pair;
individual samples ranged from 20296 to 25659 before and 18494 to 25484 after. The change adds
an atomic observer-count check to completion and can park a short task that outlasts the spin.
These controls do not establish an exact throughput cost on a shared machine.

The existing `bench/parallelrange` was also run on both sides. Its four-worker medians were:

| Case | Before | After |
| --- | ---: | ---: |
| Cheap | 10515 | 8105 |
| Uniform | 15034 | 15246 |
| Heavy first quarter | 15712 | 16935 |
| Heavy last quarter | 20508 | 17072 |
| Four expensive iterations | 3620 | 3799 |

Those samples remain variable; the benefit established here is removal of sustained busy
waiting, not a general compute speedup. Parking still occupies the caller's thread. It does not
implement asynchronous suspension or make mutually dependent blocking tasks safe.
