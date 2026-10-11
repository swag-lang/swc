# Prompt 2 session measurement

The full campaign at `78ccdd423` (three integrated batches) passed all twelve
checksums across every runtime, but the harness rejected its timings.
The reference workload moved 54.8% across the campaign, beyond the 40% limit,
and unchanged build controls diverged by 27.6%, beyond the 25% limit.
The complete record is [20261011-195347.json](../../rejected/20261011-195347.json).
No new history entry was accepted. The previous accepted campaign remains
`20261011-163035`; its indices and competitive ratios are not updated from
these rejected samples. All three batches remain landed, unconfirmed.

Command: `bin\swc.exe --num-cores 6 tools\bench.swgs --no-build --swc-cores 6
--label "prompt 2 20261011 group 1"`, using the Release compiler built from the
measured revision with six MSBuild and C++ compilation workers. No session
builds or tests ran alongside the measurements.

## Accepted five-batch campaign

[20261011-205413](../../20261011-205413.json) measured clean revision
`b1ef958c9` with the same full command and the label `prompt 2 20261011 group 2`.
All twelve checksums agreed across all runtimes; the fourteen allocator workloads
also completed. The harness accepted a 27.4% worst local reference departure
and 17.8% unchanged build-control spread. End-to-start reference drift was -16.4%.
Execution context correction was +8.2% from 135 controls, compilation +7.7%
from 87 controls. The Release compiler SHA-256 was
`720b667da8c2daec410fb09ce74438c38175fb3de9085317f159e76839a13ea4`.
No session builds or tests overlapped these measurements.

The table compares corrected indices with the previous accepted campaign,
`20261011-163035`. The null band applies to the after/before ratio, not to the
absolute corrected index. Winners exclude every native and JIT Swag variant;
close rankings remain within the campaign's measurement uncertainty.

| Task | Index before | Index after | Movement | Current null band | Fastest other runtime | Swag / other |
| --- | ---: | ---: | ---: | --- | --- | ---: |
| wordfreq | 0.68507 | 0.70127 | +2.36% | [0.93845, 1.10407] | cpp-clang-cl | 0.949x |
| csvagg | 0.62380 | 0.57253 | -8.22% | [0.85147, 1.21856] | odin | 0.934x |
| sha256 | 0.55442 | 0.55371 | -0.13% | [0.95709, 1.33043] | go | 0.874x |
| dijkstra | 0.65752 | 0.61096 | -7.08% | [0.94540, 1.09510] | cpp-msvc | 0.935x |
| raytrace | 0.48057 | 0.54577 | +13.57% | [0.93682, 1.14311] | odin | 0.964x |
| leven | 0.55711 | 0.54514 | -2.15% | [0.89453, 1.12958] | odin | 0.914x |
| chacha | 0.67887 | 0.67225 | -0.97% | [0.92116, 1.14627] | odin | 0.788x |
| nbody | 0.79957 | 0.75005 | -6.19% | [0.89197, 1.26443] | zig | 1.276x |
| fannkuch | 0.89402 | 0.95731 | +7.08% | [0.88886, 1.05496] | rust | 0.985x |
| binarytrees | 0.29756 | 0.25420 | -14.57% | [0.81110, 1.29854] | java-hotspot | 1.389x |
| lz77 | 0.86493 | 0.90643 | +4.80% | [0.92186, 1.13573] | odin | 1.098x |
| sort | 0.97456 | 0.96408 | -1.08% | [0.92151, 1.03928] | d-ldc | 1.009x |

The geometric mean of the twelve per-task competitive ratios is **0.99755x**
(previously 1.01943x on the same task set). The separate historical seven-task
headline is **1.00636x**. Nbody (1.276x) and binarytrees (1.389x) still exceed the
1.25x individual milestone.

All five batches remain **landed, unconfirmed**: their target movements stay
inside their task bands. Dijkstra moved below its current band, but its timed
code did not change, so this does not confirm a batch gain. Raytrace's +13.57%
move is inside its current band. Fannkuch's +7.08% exceeded its +5.50% upper
band and was investigated immediately, before further compiler work.

### Fannkuch follow-up

The preserved executables from both accepted campaigns have exactly the same
270-byte hot loop (SHA-256
`d1ff5a6f78776a4fb9979465bc187cb206beda9ee2ae87de0ab843982d580d02`).
Its RVA moved from `0x2c80` to `0x8ba0`: every instruction retains its offset
modulo 32; offsets modulo 64 differ by 32. The reversal and prefix-copy loops
retain their instruction groups without a new 32-byte boundary crossing.
See [the byte comparison](fannkuch-placement-check.json).

Two independent warmed series used the harness job isolation and the same
`0x55401` performance-core affinity. Each retained 48 adjacent A/B ratios,
alternating AB and BA, and 48 A/A ratios against a byte-identical baseline copy.
All checksums were 8629030. No builds or other session tests overlapped them.

| Series | Median B/A | A/A median | A/A 10th-90th percentiles |
| --- | ---: | ---: | --- |
| [First](paired-fannkuch-first.json) | 1.01780 | 1.00553 | [0.97508, 1.06031] |
| [Second](paired-fannkuch-second.json) | 1.01265 | 0.99804 | [0.95423, 1.03497] |

The campaign's 7.08% slowdown did not reproduce beyond the unchanged control's
spread in either series. No timing veto or unproven layout rewrite was applied.
The campaign index remains recorded as measured; these follow-ups do not replace
it. Full samples and binary hashes are retained in the linked records.

The history update preserves all earlier entries byte for byte; 209 numerical
serialization differences introduced by the report launcher were checked to be
within 1e-12 relative tolerance and removed from the historical prefix.
