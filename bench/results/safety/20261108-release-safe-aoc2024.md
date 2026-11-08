# Guarded release cost on the AoC 2024 console application

This diagnostic measurement uses the full `aoc2024` example application: all ten days,
both parts, and the checked-in inputs. The application reads the inputs at runtime.
Compilation is outside the clock; wall time includes process startup, input reads,
computation, and shutdown. This shared Linux host had five visible Xeon Platinum 8573C
CPUs. The compiler was the DevMode executable, SHA256
`2f40dfda669569ba4e341e4306158912df4416bde5cf4dc0f3b797d4406bac71`,
with `--num-cores 3`. Both programs were native x86-64 builds from this compiler.

The original source checks its results with `Swag.assert`. Since `release` omits
assertions, that would let the optimizer remove some work. In an external copy of
`bin/examples`, this experiment changed its 27 `Swag.assert(` calls to
`Swag.require(`. Both configurations therefore execute the same result checks;
each completed successfully. The source change is only in the benchmark copy.

The commands were `swc build --workspace <copied-examples> --workspace-module
aoc2024 --build-cfg <release|release-safe> --num-cores 3`, with the compiler,
runtime, `std`, and examples copied to the same external directory. The harness
warmed each executable once, then ran fifteen pairs in alternating order with
`SWAG_RUNTIME_THREADS=3`, using `time.perf_counter_ns` around each process.
Both programs exited zero and produced identical stdout and stderr.

| Configuration | Median wall time | Minimum | Maximum | Relative to `release` |
| --- | ---: | ---: | ---: | ---: |
| `release` | 428.857 ms | 390.110 ms | 484.555 ms | 1.00x |
| `release-safe` | 2613.418 ms | 2469.323 ms | 2860.572 ms | 6.09x |

The guarded preset is 509.39% slower on this workload. This is the cost of the
whole preset, including all runtime safety guards and its different nonfinite
floating-point policy; it does not isolate one guard. It is not a quiet-machine
acceptance threshold or a prediction for other applications. The large gap is
evidence for profiling this workload by guard family before changing the preset.

Raw wall times in milliseconds, in execution order after warmup:

| `release` | `release-safe` |
| --- | --- |
| 429.878, 390.110, 428.857, 408.133, 440.056, 446.973, 425.560, 484.555, 405.533, 432.542, 401.682, 439.219, 413.489, 447.442, 394.069 | 2469.323, 2760.098, 2534.927, 2793.766, 2477.262, 2476.132, 2726.157, 2557.777, 2735.841, 2537.211, 2643.187, 2518.845, 2797.001, 2613.418, 2860.572 |

## Guard-family attribution

A follow-up used the same source and inputs, with the same `release-safe` `O2`,
vectorization and floating-point policy. A temporary compiler variant changed
only the preset's `safetyGuards` from `.All` to `.All & ~.ValueBorrow`; both
programs were rebuilt with `--rebuild`. A compile-time `#safety` assertion in
the temporary application source verified the disabled flag. The compiler
source and build were restored after this experiment.

The two executable images were retained and run in alternating order, with
one warmup and twelve measured invocations each. Both exited zero, and their
stdout and stderr matched. The same active `Swag.require` result checks ran.

| Guard setting | Median wall time | Minimum | Maximum |
| --- | ---: | ---: | ---: |
| All guards | 2584.932 ms | 2439.209 ms | 3192.760 ms |
| All except `.ValueBorrow` | 545.494 ms | 476.121 ms | 927.055 ms |

The paired median ratio is 4.74x. Removing `.ValueBorrow` accounts for most
of this workload's guarded-release gap; the remaining difference from plain
`release` includes every other guard and the different floating-point policy.
Separate exploratory builds without `.BoundCheck` or `.Overflow` stayed near
the all-guard timing, so this application does not justify targeting those
guards first. This attribution is specific to the application and shared host.

Raw paired wall times in milliseconds, in execution order after warmup:

| All guards | All except `.ValueBorrow` |
| --- | --- |
| 2507.060, 3192.760, 2477.915, 2900.450, 2662.804, 2482.107, 2669.044, 2444.644, 2757.759, 2447.325, 2439.209, 2757.739 | 927.055, 541.021, 549.967, 498.459, 589.844, 539.536, 476.121, 577.822, 481.483, 551.715, 539.543, 555.945 |
