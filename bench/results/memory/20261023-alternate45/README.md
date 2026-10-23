# Compiler memory, 2026-10-23

The change retains `MicroSsaState` buffers across functions of similar size but drops the entire
thread-local state when its instruction-info capacity exceeds twice the next function's Micro
instruction-slot count (with a 4096-slot floor). This prevents a large function from making every
later small function's optimization on that worker carry its retained SSA buffers through the rest
of the module.

The external sampled heap profile on one six-worker DevMode `core` rebuild showed its largest
sampled allocation groups under `MicroSsaState::build`, including the constant-folding and
value-borrow fast-path passes. The instrumented run peaked at 1141 MiB working set, versus about
999 MiB without instrumentation, so that profile is attribution evidence only. Its estimated live
requested bytes are sampled allocator data, not resident memory.

The table compares a clean compiler built from the shared pre-change source revision against the
candidate, in three alternating rounds, with six compiler workers. Working set and commit are the
largest observed peaks across each compiler's three rounds; wall and CPU are medians. The runner's
paired median ratios are candidate divided by baseline.

| Workload | Baseline wall | Candidate wall | Baseline peak working set | Candidate peak working set | Baseline commit peak | Candidate commit peak |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `core_rebuild` | 7360 ms | 6338 ms | 1008.9 MiB | 957.4 MiB | 1028.7 MiB | 978.5 MiB |
| `hello_build` | 259 ms | 258 ms | 139.8 MiB | 138.1 MiB | 262.4 MiB | 260.6 MiB |

For `core_rebuild`, the paired median candidate/baseline ratios were 0.861 for wall time, 0.832
for CPU time, 0.944 for commit peak, and 0.940 for working-set peak. For `hello_build`, they were
0.992, 1.064, 1.008, and 1.001 respectively. Three rounds are an initial check, not a campaign
wide result. Both workloads remain above their 250 MiB and 50 MiB working-set targets.

## Incremental CodeGen payload lifetime check

After the SSA change, both compilers were built from the same source revision. The candidate
places trivial `CodeGenNodePayload` objects in an arena owned by the per-function `CodeGen` job;
paused jobs retain that arena until they resume and finish. Three alternating six-worker
`core_rebuild` rounds measured a 933.7 MiB candidate peak working set versus 940.6 MiB baseline,
and a 953.1 MiB candidate peak commit versus 965.8 MiB baseline. Paired median candidate/baseline
ratios were 0.837 wall time, 0.771 CPU time, 0.980 commit peak, and 0.986 working-set peak.
The resident-memory reduction is modest, while the paired timing indicates no speed cost in this
sample. This is an incremental check on the existing SSA candidate, not a fresh comparison against
the original compiler or a campaign-wide result.

Rejected follow-up: moving object-file buffers from `NativeObjDescription` into the prepared
`LinkJob` removed the copy in `collectArchiveMembers` by construction, but five alternating
six-worker `core_rebuild` rounds measured no process-peak reduction: maximum working set was
934.2 MiB baseline and 933.7 MiB candidate, and peak commit was 953.1 and 953.4 MiB. Paired median
ratios were 1.054 wall time, 1.008 CPU time, and 1.000 for both memory measures. The source change
was reverted because it did not improve the campaign's peak-memory target.

Rejected follow-up: the register allocator released retained instruction-indexed liveness buffers
when the next function was less than half the prior function's size (with a 4096-instruction
floor). This is safe at the start of a new allocation run because the default pass pipeline is
thread-local and reused across functions. The candidate passed the native suite (3,937 tests), but
three alternating six-worker `core_rebuild` pairs did not reduce peak working set: candidate was
930.3 MiB and baseline 930.2 MiB. Peak commit was 942.2 MiB candidate and 954.6 MiB baseline, but
paired median ratios were highly variable: candidate/baseline 1.170 wall, 1.256 CPU, 0.987 commit,
and 0.999 working set. With no resident-memory reduction and an inconclusive commit change, the
scratch-release change was reverted rather than retain possible per-function reallocation cost.
