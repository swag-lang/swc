# COFF archive allocation reduction

The retained batch contains only `Archive.cpp`, `Archive.h`, their C++ regression tests,
and compiler identity 569. It was developed in the isolated `perf/artifact-latency`
worktree. Integration validation used master `5015ba6d3` and identity 567; the final merge also preserves the subsequent independent master commit `700211976`.
Three agents initially investigated startup, lexing, and archives. Subsequent work is solo.

## Retained change

Static archive construction borrows object bytes instead of copying them into intermediate
members. The output and symbol directory reserve their calculated sizes. Import records share
one reserved buffer. An input object aliasing the output retains its protective copy.
Loaded archives index names by views into owned immutable bytes; archives are move-only,
and reload clears the index before replacing its storage.

The inspected `core` static library has 18,774 COFF objects totaling 8,091,371 payload bytes.
The change eliminates 18,774 intermediate payload allocations and 7.72 MiB of copies/storage
for this artifact. Its import library has 1,914 records totaling 112,118 bytes, now held in one
intermediate buffer. These are structural savings within archive construction, not measured
reductions of overall process peak memory or elapsed compilation time.

## Timing evidence and rejected experiments

The initial baseline is `fa0ad9501`, build 563. Build 564 also changed keyword lookup and cached
workspace timestamps. Build 565 restored the original keyword lookup, reduced its setup work,
and removed a redundant path normalization. Both startup experiments were subsequently withdrawn:
the combined batch did not establish consistent process-to-artifact latency gains.

`combined-exploration.json` contains three completed alternating rounds of build 563 versus 565,
with six workers pinned to the same performance cores. Wall time covers process creation through
exit. Every measured command and cache preparation passed CPU/memory admission; a stricter 20%
CPU threshold was used. Background activity sometimes increased after admission.

| Workload | Baseline median | Combined candidate median | Median paired time change |
| --- | ---: | ---: | ---: |
| Linked hello world | 166.4 ms | 209.7 ms | +32.5% |
| Lex standard-library sources | 162.1 ms | 126.7 ms | -6.6% |
| Forced core rebuild | 5,346.8 ms | 4,269.6 ms | -14.0% |
| Unchanged core relaunch | 55.2 ms | 41.4 ms | -12.0% |
| Core after touching a source | 2,870.3 ms | 3,116.3 ms | +24.4% |

Ratios are paired by round, so they differ from ratios of the separate medians. Variance and
mixed outcomes prevent attributing these results to any individual optimization. They are not
evidence of an end-to-end speedup for the retained archive-only batch. The other two JSON files
are incomplete exploratory runs of build 564; they are preserved for transparency.

`measure.py` preserves the reproducible protocol using `bench/winproc.py`: binary hashes,
commands, outputs, admissions, wall/CPU time, background CPU and process-tree memory. Cache cases
prepare artifacts with the binary about to be measured, avoiding version-induced invalidation.

```powershell
python bench/results/compilation/20260914-artifact-latency/measure.py --baseline C:/temp/reference/swc.exe --candidate bin/swc.exe --rounds 5 --pin --output result.json
```

## Validation

The archive tests cover object bytes, long names, odd padding, empty archives, input/output
aliasing, duplicate symbols, move construction and assignment, vector relocation, reload and
failed load. Real workspace consumers exercise static archives, a DLL and an executable with
six workers and the devmode program preset.

Before integration, the combined candidate passed 809 DevMode C++ tests including filesystem
fixtures, both lexer suites, and forced linked consumers with DevMode and Release compilers.
These logs remain historical evidence; final archive-only validation is recorded separately.
The first C++ attempt was interrupted after starting before its admission check had finished;
it contributes no evidence. The successful rerun followed an explicit ready result.

Release was built from a baseline source snapshot under `.tmp/baseline-build`, preserving the
reference executable before applying changes. Copied changed source timestamps were advanced
to force recompilation. Integrated builds include master changes and use `/m:6` and
`/p:SwcCompileJobs=6`. The complete repository campaign is unnecessary for this archive-only batch.

## Integration results

- The integrated DevMode compiler (identity 567, parent `5015ba6d3`) builds successfully.
- Its forced devmode `consumer_exe` run rebuilds the three standard dependencies and six workspace
  modules, prints `SWAG_WORKSPACE_MAIN_RAN`, and exits successfully (`integrated-workspace.log`).
- The integrated C++ suite fails before reaching the new archive tests: a host access violation
  reads address `0x10`. The preserved master DevMode executable, built before this archive patch,
  reproduces the same failure and stack shape on the same source tree (`master-cpp-comparison.log`).
  This is an upstream failure, not a green integration C++ result. The earlier 809-test success
  remains the full-suite evidence for the unchanged archive implementation.
- The candidate DevMode SHA-256 is
  `a7e3b779e8e9bd94e72c5ba56ae2bb6eb07bad4c23929b4d74e810ef92a2950d`;
  the preserved master comparison is
  `a04eee1618426f8c60c1cecb33d627f3cf5e7f789586ac4588c526d3fcaeb9f8`.
- Master subsequently published additional JIT and attribute fixes in `700211976`. They preserve
  the archive ownership and call contract. The final source integration retains those changes
  and increments identity to 569. No fresh full compiler campaign is claimed for that final merge.
- The retained Archive source is identical to the Release-validated implementation. The queued
  integrated Release rebuild was cancelled before MSBuild started after the batch was narrowed.

The final compiler diff against master is limited to `Archive.cpp`, `Archive.h`, the two archive
unit tests, and `Version.h`. No lexer or workspace-cache experiment is retained. No end-to-end
latency improvement has been established for this archive-only batch.

## Working files

The repository instructions changed during this campaign to require external scratch space.
All owned baseline compiler copies, temporary sources, response/build files and probe outputs
were relocated after their commands finished to:
`C:/Users/chris/AppData/Local/Temp/swc-artifact-latency-20260914-session`.
The preserved compilers have explicit external `runtime` and `std` junctions to this worktree's
resources. The maintained benchmark now allocates its temporary workspace outside the checkout;
preserved compiler paths must likewise have their resource trees configured before running it.
The logs here are deliberately maintained evidence. No misplaced test-source output was found;
canonical project build outputs were preserved. Direct deletion was rejected by automatic review;
relocation completed the checkout cleanup instead.
