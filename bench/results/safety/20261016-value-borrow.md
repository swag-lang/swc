# Value-borrow safety cost: focused evidence, 2026-10-16

These are diagnostic measurements on a shared, busy Windows machine, not an accepted
quiet-machine benchmark campaign. Timing never decides whether a regression test passes.
The guard-free control changed between rounds; the absolute numbers must not be generalized
to an application or used to claim a compiler-wide speedup.

## Inputs

- Release compiler, native x86_64, program configuration `devmode`, no debug information.
- Baseline compiler: pre-campaign binary, SHA256
  `1FFDFE2D03CD80C91F011282B9960BB3E6C7C81EAED1277247F0ACA3B6ED6601`.
- Candidate: `e6084a753` plus the local-write guard elision in this change,
  SHA256 `F60916298F5DF68724D978905EBDF25549C743806F03410A1EBE2CB7E8FCE733`.
  Each compiler loads its own adjacent runtime snapshot.
- Fixture: `bin/unittests/native/functions/value_borrow_cost.swg`.
  All runtime safety is disabled except `.ValueBorrow` in the guarded variant.
  Both variants perform the same work and validate the same checksums.
- Small: 2,000,000 non-inline calls with a 16-byte value and an independent output pointer.
- Block: 50,000 non-inline calls summing 128 u64 elements, with an independent output pointer.
- Five samples per workload and invocation; QueryPerformanceCounter frequency 10,000,000 Hz.

## Runtime samples

All cells contain raw counter ticks. Each row is one invocation; compilation/linking is
outside the fixture clock. The second round starts with the candidate, reversing the first.

| Round | Compiler | Guards | Small samples | Block samples |
| --- | --- | --- | --- | --- |
| 1 | baseline | on | 5794842, 5985745, 5618364, 6343821, 7797932 | 3107023, 4976417, 3840780, 3574968, 4475331 |
| 1 | baseline | off | 17345, 17508, 17873, 17907, 18578 | 31357, 30985, 31425, 34820, 37667 |
| 1 | store optimization | on | 2003154, 1987999, 1827530, 1865795, 1977775 | 1008496, 971715, 1110013, 1017884, 1068152 |
| 1 | store optimization | off | 27727, 23769, 23055, 23438, 23091 | 43538, 44325, 40892, 40880, 41579 |
| 2 | local elision + stores | on | 1875716, 1962561, 1996989, 1912612, 1898929 | 93157, 80242, 132549, 142486, 161049 |
| 2 | local elision + stores | off | 23355, 21178, 21117, 20713, 20562 | 37296, 40622, 37406, 34892, 33737 |
| 2 | baseline | on | 3566060, 3965179, 4152858, 3987545, 4171058 | 1687552, 1587433, 1575476, 1611261, 1534214 |
| 2 | baseline | off | 22760, 24388, 22766, 22763, 22757 | 42308, 42196, 43087, 41417, 41989 |

In round 2, guarded median time is 191.2612 ms (small) and 13.2549 ms (block),
versus 398.7545 ms and 158.7433 ms for the baseline. Guard-free controls are
2.1117/3.7296 ms for the candidate and 2.2763/4.2196 ms for the baseline.
The remaining candidate overhead over its control is about 94.6 ns per small call
and 190.5 ns per block call on this run. These deliberately tiny calls magnify fixed
registration cost. No ratio here predicts the cost in a representative application.

Static evidence is less sensitive to machine load: the block accumulator no longer calls
`__valueBorrowWrite` on every iteration. Pointer writes still do. The existing registry
writer lock serializes filter updates; atomic loads/stores retain publication to readers
without redundant locked read-modify-write operations. Exact overlap checks, counting
filter, wide ranges, panic cleanup, and cross-module registry sharing remain active.

## Compiler time and memory

Command: `build --workspace bin/std --workspace-module core --build-cfg devmode
--rebuild --num-cores 6`. Each invocation has fresh rebuild semantics and independent
machine-load admission. Peak job memory includes the process tree; CPU is process-tree
CPU time from `bench/winproc.py`. Order alternates A/B then B/A.

| Panel | Pair | Compiler | Wall ms | CPU ms | Peak job bytes | Peak working set bytes |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| stores only | 0 | before | 3043.569 | 13750.000 | 593043456 | 567214080 |
| stores only | 0 | after | 4083.124 | 16984.375 | 595857408 | 565710848 |
| stores only | 1 | after | 6228.585 | 28093.750 | 589754368 | 563974144 |
| stores only | 1 | before | 4359.636 | 18796.875 | 573140992 | 539664384 |
| stores only | 2 | before | 5355.779 | 22750.000 | 578662400 | 553435136 |
| stores only | 2 | after | 8274.908 | 36906.250 | 594489344 | 563343360 |
| local elision + stores | 0 | combined | 5250.728 | 22796.875 | 582787072 | 555778048 |
| local elision + stores | 0 | control | 5682.894 | 24062.500 | 571174912 | 544735232 |
| local elision + stores | 1 | control | 7999.003 | 34187.500 | 575422464 | 546480128 |
| local elision + stores | 1 | combined | 8403.734 | 36031.250 | 571867136 | 537640960 |
| local elision + stores | 2 | combined | 9639.865 | 41468.750 | 564580352 | 537509888 |
| local elision + stores | 2 | control | 11204.213 | 46765.625 | 579571712 | 553054208 |

The first panel drifted strongly upward and suggested a slowdown. The second panel
does not reproduce that direction: candidate/control wall ratios are 0.924, 1.051,
0.860, and CPU ratios 0.947, 1.054, 0.887. Memory has no consistent direction either.
This is insufficient evidence for a compiler-time improvement or a tight regression bound.
Sanitizer-specific CPU/state/visit attribution remains `compiler.safety.019`.

## Reproduction

Prepare the worktree Win32 module API outside the runtime measurement:

```powershell
bin/swc.exe build --workspace bin/std --workspace-module win32 --num-cores 6
$apiArgs = @()
Get-ChildItem bin/std/.output/win32/export/devmode/x86_64 -Filter *.swg | ForEach-Object {
$apiArgs += "--import-api-file", $_.FullName
}
bin/swc.exe test --file bin/unittests/native/functions/value_borrow_cost.swg `
  --tag MeasureValueBorrow --tag ValueBorrowOn --no-test-jit --num-cores 6 `
  --out-dir <external-output> --work-dir <external-work> @apiArgs
```

Run without `--tag ValueBorrowOn` for the control, with separate output/work paths.
Use every generated API file: the umbrella `win32.swg` alone omits the kernel32 functions.
Preserve the baseline executable together with its adjacent runtime outside the checkout,
set `SWAG_PATH` to the worktree bin, and retain all samples in alternating invocations.
A quiet-machine follow-up with an unchanged A/A control and a representative application
is still needed; see `compiler.safety.030`.

## Correctness evidence

- Full DevMode compiler C++ suite: 1,477 passed, including guard-count regression tests
  and the repaired native termination fixtures.
- Full sanity suite: 76 passed. Safety suite: 142 passed and 15 expected panic cases verified.
- Full native suite: 3,886 passed, including new four-worker small/wide registry stress tests.
- Cross-module value-borrow consumer: 4 passed; indirect release import fixture passed.
- Earlier indirect release summary batch was also checked with both compiler executables
  and both program configurations. These focused checks do not establish a whole-tree guarantee.

Integration verification (separate from the timing panel above):

- `fb1a7c4ed`: DevMode compiler full C++ suite (1,477), full native suite (3,886),
  sanity, safety, and cross-module checks passed.
- `67cd8f31d`, including the later native function deduplication change: both compiler
  executables passed the 124 value-borrow native tests, the four cross-module value-borrow
  tests, and the indirect-release importer in both program configurations. Release also
  passed sanity and safety; DevMode's four PrintMicro guard counts and execution checks passed.
- The final shared-constant refactors were rebuilt with DevMode, and sanity passed again.
  No additional timing claim is made for these integration checks.
