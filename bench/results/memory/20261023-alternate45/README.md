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

## Incremental ValueBorrow SSA lifetime check

The value-borrow fast path keeps its own thread-local `MicroSsaState`. It previously called
`clear()` without the next function's slot count, so it could not apply the existing outlier-release
policy used by the shared pre-RA SSA state. The candidate passes the function's slot count to
`clear`, preserving reuse for similarly sized functions and releasing an oversized state before a
much smaller guarded function.

Three alternating six-worker `core_rebuild` pairs compared the candidate with the same source
revision before this change. Maximum working set was 923.1 MiB candidate and 942.1 MiB baseline;
peak commit was 947.9 and 962.0 MiB. Paired median candidate/baseline ratios were 1.017 wall,
1.035 CPU, 0.991 commit, and 0.979 working set. This initial check suggests about 19 MiB lower
working-set peak, with a small and unconfirmed timing cost; it is incremental evidence, not a
campaign-wide result.

Rejected follow-up: `CoffSymbolRecord` temporarily borrowed the symbol-name storage already owned
by the object description, section relocations, debug result, or builder, avoiding per-record name
copies. The candidate passed the native suite (3,937 tests), but three alternating six-worker
`core_rebuild` pairs did not lower process peaks: maximum working set was 923.3 MiB candidate and
914.4 MiB baseline; peak commit was 949.3 and 936.8 MiB. Paired median candidate/baseline ratios
were 1.120 wall, 1.101 CPU, 1.007 commit, and 1.013 working set. The sample is variable, but it
shows no memory gain, so the change was reverted.

Rejected follow-up: trivially destructible auxiliary CodeGen payloads temporarily used the
per-function payload arena instead of the compiler worker's longer-lived thread arena. Three
alternating six-worker `core_rebuild` pairs against binaries built from the same source revision
showed no peak-memory reduction: maximum working set was 924.7 MiB candidate and 924.4 MiB
baseline; peak commit was 940.7 MiB candidate and 937.9 MiB baseline. Paired median ratios were
0.944 wall time, 0.931 CPU time, 0.999 commit, and 1.006 working set. Because the process peaks did
not improve, the source change was reverted.

Rejected follow-up: the per-worker SSA propagation scratch temporarily cleared its known-value,
canonical-value, flags, and erase vectors at every function boundary, releasing their capacities
after an outlier function when any exceeded twice the next function's instruction-slot count (with
a 4096-entry floor). Three alternating six-worker `core_rebuild` pairs did not reduce process
peaks: maximum working set was 923.7 MiB candidate and 921.7 MiB baseline; peak commit was 943.6
MiB candidate and 941.2 MiB baseline. Paired median candidate/baseline ratios were 0.618 wall,
0.629 CPU, 1.007 commit, and 1.011 working set. Timing varied widely across pairs, and neither
memory measure improved, so the change was reverted.
