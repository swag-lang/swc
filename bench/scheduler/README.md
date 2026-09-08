# Scheduler cost against worker count

```powershell
bin/swc.dm.exe run -f src/scheduler.swg --module-file bench/scheduler/module.swg -bc release --num-cores 6
```

This benchmark prices the process scheduler in `bin/runtime` rather than any one construction. It
answers four questions, each at 1, 2, 4, 8 and every worker the machine allows:

| Case | What it submits | What it prices |
| --- | --- | --- |
| `forkjoin` | A recursive halving of one million elements, six leaf sizes | One submission, at six grains |
| `spawn-group` | Every partition spawns 512 children into a `Swag.TaskGroup` | Concurrent submission, plus the group's own storage |
| `spawn-task` | The same children through plain `Swag.Task` values the partition owns | Concurrent submission alone |
| `flat` / `nested` | The same work as one range, then as a range inside a range | What a nested parallel region costs |
| `herd` | 20,000 short tasks on the caller while every worker is busy, with and without one parked observer per worker | One completion, while other threads wait for their own work |

The pool only grows, so the worker steps run in ascending order and the last step asks for more
workers than any host provides. Absolute microseconds are not comparable between two runs on a
shared or hybrid machine, so every case carries a control measured **in the same process**: the
one-worker step for the submission cases, the flat range for the nested one, and the unobserved
stream for the herd. Read the ratios, not the microseconds.

`forkjoin`'s cut-off sweep is also how the grain in the language reference was chosen: the leaf
size at which adding workers stops costing and starts paying is what "a task must carry real work"
means in numbers.

## Measuring a scheduler change

The machine this repository is developed on is an Intel Core Ultra 9 185H: 6 P-cores with
hyper-threading, 8 E-cores and 2 low-power E-cores, 22 logical processors in three performance
classes. Two runs of the same binary differed by a factor of three here while another agent was
building. A single before/after pair is not evidence.

What worked is a second worktree at the base commit, the same benchmark source copied into it, and
alternating `base, candidate, candidate, base` rounds, reading the median of the per-round paired
ratios. Copy one compiler binary into both worktrees and use that same copy for the whole campaign:
`bin/swc.dm.exe` in a shared checkout can be rebuilt underneath a measurement, and a compiler that
no longer matches the `bin/runtime` sources beside it fails in ways that look like the change.

## Result of 2026-09-08

Four alternating rounds on an otherwise idle machine, comparing `a2c0a8aa2` with targeted
completion signalling and task-group inline storage. The figure is the median of the four paired
ratios, candidate over baseline, so below one is faster.

| Case | 1 worker | 2 | 4 | 8 | 22 |
| --- | ---: | ---: | ---: | ---: | ---: |
| `herd`, one observer per worker | 0.35 | 0.19 | 0.09 | 0.04 | **0.01** |
| `herd`, no observer | 1.06 | 1.01 | 1.20 | 1.13 | 0.92 |
| `forkjoin`, 64-element leaves | 0.51 | 0.34 | 0.46 | 0.72 | 1.02 |
| `forkjoin`, 256-element leaves | 0.70 | 0.64 | 0.64 | 0.74 | 1.10 |
| `forkjoin`, 4096-element leaves | 1.27 | 0.97 | 1.05 | 1.01 | 1.19 |
| `spawn-group` | 0.73 | 0.80 | 0.89 | 0.96 | 1.03 |
| `spawn-task` | 0.97 | 0.96 | 1.09 | 0.99 | 1.08 |
| `nested` | 1.10 | 1.08 | 1.21 | 1.04 | 1.04 |

The herd row is what the change was for. In absolute terms, one pair of runs measured the same
20,000-task stream as:

| Parked observers | Before | After |
| ---: | ---: | ---: |
| 0 | 3346 us | 4574 us |
| 1 | 14040 us | 4595 us |
| 2 | 23545 us | 4332 us |
| 4 | 49205 us | 3962 us |
| 8 | 163400 us | 4344 us |
| 22 | 645868 us | 4106 us |

Before the change, a completed unit woke every parked observer in the process, so the stream's cost
grew with the number of threads waiting for something else entirely. After it, the observed stream
costs what the unobserved one costs, and the row is flat.

Fine-grained fork/join follows from the same cause: a joining thread that parks is an observer, so
a deep recursion made every completion wake every level. It is 1.4 to 3 times faster below 8
workers. `spawn-group` gains where a group no longer reserves a page for its first children, and
`spawn-task`, which never had that storage, stays where it was and confirms the change is specific.
The coarse `forkjoin` rows and the `nested` rows sit within the round-to-round spread of these
short measurements; nothing there is claimed.

## What this run did not fix

At 22 workers every ratio returns to one. The remaining cost is the shared ready stack under one
mutex and the placement of 22 threads across three classes of core: 64-element leaves cost 115 ms
on 22 workers against 13.7 ms on one, and `spawn-task` throughput falls from 2.1 to 0.5 children
per microsecond over the same range. Neither is a completion problem, and neither is addressed
here. `language.parallelism.006` carries that work with these numbers as its evidence.
