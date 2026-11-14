# Prompt 2 session through 18:00 (2026-10-22)

Three static batches are landed/retained, unconfirmed by a complete timing
campaign. No benchmark computation, workload, checksum or timed boundary changed.
SWC_BUILD_NUM remains 1173. Every code batch passed the full twelve-task checksum
and verbose Micro comparison; overload/lambda pairing was reviewed explicitly.

| Target / previous best rival | Bottleneck / mechanism | Executed machine work | Other tasks | Correctness | Decision |
| --- | --- | --- | --- | --- | --- |
| LZ77 / Zig | Byte bound/step overhead; ordered pair grouping | 24 -> 18 instructions per four matching bytes; same eight reads | Eleven kernels/runtime unchanged | 1,560 C++ tests; 6,550 source answers per JIT/native mode | Landed `30ca716f28`, eligibility repair `57ffab775e`; unconfirmed |
| Fannkuch / Rust | Two index steps; constant-left prefix peeling | 8 -> 7 instructions per first four swaps, same four accesses | Eleven kernels/runtime unchanged | 1,562 C++ tests; Release/guarded source JIT/native | Landed `571c8fd9ea`; unconfirmed |
| Fannkuch / Rust | Redundant first read; all-entry availability proof | First swap 7 -> 6 instructions, four -> three accesses | Eleven kernels/runtime unchanged | 54 graph forms; 6,174 paired executions; expanded source JIT/native | Retained in this commit; unconfirmed |

The full compilation/execution campaign was attempted twice. The earlier run
encountered `doc_std/subject` exit 3 with a Windows exception before HTML output.
The old driver's excerpt lost the failing instruction/task. The original subject,
preserved baseline, corrected DevMode/Release and integrated Release all later
passed fresh full documentation runs. No matching reproducer establishes its cause;
compiler.core.088 retains the exact next investigation. The independently reproduced
moving-base scan defect is fixed, but is not claimed as the documentation cause.
Failure output and explicit checkpoint files are now preserved by the harness.

The combined campaign at `0dee1480b9` was stopped during the edit-build loop after
hello samples repeatedly met external interference; it has no accepted task panel.
Its full log is retained. A previous execution-only attempt similarly stopped with
hello-only incomplete checkpoints. No partial result was published into history.
The reference full campaign takes about 93 minutes, exceeding the remaining slot.
The next Prompt 2 session must start with the final combined full campaign.

## Targeted timing before entry-value reuse

The probe used the harness's isolated jobs, P-core mask `0x55401`, program-reported
MS, warmed binaries, randomized A/B and B/A pairs, and unchanged A/A controls.
Thirty pairs per completed series; every checksum was validated. These compiled
binaries precede the final first-read removal. Ratios below are new/old, lower faster.

| Task | B/A estimate [95% interval] | A/A [95% interval] | Still contended | Interpretation |
| --- | --- | --- | --- | --- |
| fannkuch | 0.9648 [0.9449, 0.9924] | 0.9907 [0.9759, 1.0105] | 0.00% | No established move beyond the control band |
| lz77 | 0.9971 [0.9639, 1.0541] | 0.9850 [0.9556, 1.0295] | 1.67% | No established move beyond the control band |
| wordfreq | 1.0092 [0.9898, 1.0299] | 1.0126 [0.9840, 1.0352] | 0.00% | No established move beyond the control band |

The second independent panel was abandoned under sustained 14-23 foreign cores.
Its incomplete progress is in the log; only the three completed first panels
have raw samples. No two independent slowdowns beyond A/A were established.
Fannkuch has a favourable first signal; a separation from competition is unproven.
The final entry-value complement remains unmeasured.

## Last accepted competitive panel, unchanged by this session

Campaign `20261022-103425`, native Release, all twelve tasks. Winner excludes all
Swag subjects and references. Corrected index is the paired ratio against frozen
reference r1. The old prompt's `null.run.tasks` field is absent in protocol 3;
the baseline campaign's subject/reference A/A interval is shown instead. A new
accepted combined index is unavailable, so every new index remains unmeasured.

| Task | Best other runtime | Swag / rival | Previous corrected index | Baseline A/A interval | New index |
| --- | --- | --- | --- | --- | --- |
| wordfreq | d-ldc | 0.8785 | 0.9621 | [0.9441, 1.0243] | Not measured |
| csvagg | odin | 0.8813 | 0.8779 | [0.9194, 1.0916] | Not measured |
| sha256 | go | 0.8781 | 1.0120 | [0.9685, 1.0486] | Not measured |
| dijkstra | cpp-msvc | 0.9962 | 0.9813 | [0.9637, 1.0404] | Not measured |
| raytrace | odin | 0.9326 | 1.0183 | [0.9077, 1.0481] | Not measured |
| leven | d-ldc | 0.8715 | 0.9737 | [0.9292, 1.0697] | Not measured |
| chacha | cpp-clang-cl | 0.9549 | 1.0022 | [0.9720, 1.0220] | Not measured |
| nbody | zig | 0.8840 | 0.8941 | [0.9764, 1.0318] | Not measured |
| fannkuch | rust | 1.0299 | 0.9599 | [0.9531, 1.0504] | Not measured |
| binarytrees | java-hotspot | 1.1479 | 0.9765 | [0.9395, 1.0267] | Not measured |
| lz77 | zig | 1.0193 | 0.9969 | [0.9464, 1.0578] | Not measured |
| sort | cpp-msvc | 0.9745 | 1.0152 | [1.0001, 1.0761] | Not measured |

Geometric mean of Swag / per-task best rival over these **twelve tasks**: **0.9508**. The historical seven-task headline is a different panel and is not used here. No updated competitive aggregate is claimed.

Final validated Release compiler SHA-256: `644d25f9d912ea1d25af14e002c3ea61ba86d69b332aceb72e2a730571b06bfb`.
