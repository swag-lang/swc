# Empty value-borrow registry fast path, 2026-10-16

The retained runtime returns from a guarded pointer write when an atomic load proves
the shared registry head empty. Head stores are atomic under the existing writer
lock. Active lists still use the counting filter, epoch validation, writer lock and
exact overlap test. Record layout, shared-storage identity, checkpoints and cleanup
are unchanged. No check is removed for a live borrow, and guard-free code gains no
new guard or call.

## Focused measurements

Both variants use the same normal Release compiler from 48b13fb2c, SHA256
`b4f1964fbe513748ce40a4be762fbcb7595e75fca83413c9fe2dabe25e11f1bc`,
with separate adjacent runtime snapshots. The timing prototype and retained runtime
differ only in formatter whitespace. Program configuration is devmode; all safety
except ValueBorrow is disabled. Every workload checks its result with an explicit
panic outside the timed loop. Duration never decides whether a test passes.

The opt-in fixture is bin/unittests/native/functions/value_borrow_cost.swg. Small
uses 2,000,000 aggregate calls; block uses 50,000 calls summing 128 u64s. Empty-write
uses 2,000,000 non-inline scalar pointer writes with no aggregate borrow. Active-write
uses the same number of writes while an independent small aggregate is borrowed.
Each invocation produces five samples per workload. Order reverses in round 1.

Raw values are QueryPerformanceCounter ticks at 10,000,000 Hz.

| Round | Runtime | Guards | Small | Block | Empty-write | Active-write |
| ---: | --- | --- | --- | --- | --- | --- |
| 0 | control | on | 922668 , 901591 , 878332 , 998152 , 1095954 | 48072 , 45959 , 41928 , 32664 , 35096 | 71904 , 80023 , 77465 , 76912 , 72739 | 196939 , 208647 , 203966 , 223416 , 194692 |
| 0 | control | off | 10188 , 11156 , 11187 , 11387 , 11604 | 21574 , 20407 , 18851 , 19241 , 18028 | 9216 , 9570 , 9654 , 9704 , 9564 | 9545 , 9654 , 13411 , 12764 , 8034 |
| 0 | candidate | on | 849674 , 835395 , 855494 , 848347 , 881336 | 35420 , 34533 , 35050 , 51028 , 30384 | 36011 , 37082 , 39417 , 37936 , 37986 | 144671 , 146639 , 150582 , 148911 , 148309 |
| 0 | candidate | off | 11655 , 11778 , 11523 , 11917 , 11776 | 20780 , 19729 , 19259 , 17951 , 18362 | 6803 , 7267 , 6781 , 8120 , 7158 | 10068 , 10070 , 9866 , 9797 , 9777 |
| 1 | candidate | on | 817997 , 805083 , 838453 , 815572 , 811337 | 32552 , 34701 , 30892 , 31833 , 32370 | 37819 , 36058 , 35535 , 36966 , 37332 | 141078 , 137206 , 140776 , 144939 , 139247 |
| 1 | candidate | off | 9774 , 10391 , 10113 , 10637 , 10684 | 19295 , 18625 , 18326 , 18336 , 17826 | 6196 , 6622 , 6684 , 6812 , 6838 | 9796 , 9841 , 9587 , 9560 , 9498 |
| 1 | control | on | 865770 , 814460 , 811070 , 808393 , 810531 | 34719 , 33937 , 34417 , 34091 , 34523 | 63161 , 71853 , 57695 , 64497 , 58645 | 140508 , 142079 , 137696 , 141469 , 147894 |
| 1 | control | off | 11580 , 13006 , 11544 , 11618 , 12091 | 20463 , 20415 , 20385 , 18613 , 18504 | 6526 , 6364 , 6940 , 13022 , 9476 | 8215 , 8207 , 8608 , 8930 , 9276 |

Guarded empty-write medians fell from 7.6912 to 3.7936 ms in round 0 and from
6.3161 to 3.6966 ms in round 1. Round-1 active-write medians were 14.1469 ms for
control and 14.0776 ms for candidate; the first round was less stable. Guard-free
controls drifted too, so these are focused shared-machine observations, not a
quiet-machine overhead bound or a prediction for an application. The empty-path
work reduction is structural; no reproducible active-path slowdown appeared here.

## Validation and reproduction

Both checkout-local compiler executables passed 125 native value-borrow tests and
four cross-module consumer tests after rebuilding both modules. The transition
fixture value_borrow_empty.swg exercises writes before a borrow, overlapping writes
during it, panic cleanup, and writes afterward. Existing four-worker small/wide,
callback, interface, allocator, erased-value and checkpoint tests remain enabled.
The opt-in benchmark passed all four checksum tests in all eight invocations.

Use the reproduction command in 20261016-value-borrow.md, with every generated Win32
API file, --num-cores 6 and separate external output/work directories. Select
MeasureValueBorrow and optionally ValueBorrowOn. Preserve the baseline executable
and its adjacent runtime before editing, use the same compiler for both runtimes,
and retain reversed-order guarded and guard-free samples. Admit each invocation.

The compiler-wide timing panel remains inconclusive; see
[the static-cost report](20261016-moved-writes-and-sanity.md). A quiet A/A control and
a representative application are still required by compiler.safety.030.
