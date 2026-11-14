# Packed fused arithmetic

Baseline: `3cfe08f58` (compiler code `d7ceec857`). Accepted on static evidence;
runtime timing not measured.

Packed multiplication followed by addition or subtraction previously kept two
arithmetic instructions even when scalar contraction was permitted. Eight
internal packed operations now express the four existing fused operand roles
for both element widths. Contraction requires `fpMathFma` and `fpMathNoNaN`,
matching widths, unchanged factors and a dead product in every lane. The existing
bounded motion and pending-rewrite checks remain in force. There is no expression
reassociation. A dead full-width load can fold into the fused third operand;
packed binary memory arithmetic is deliberately outside this change.

| Actual nbody native work per timestep | Before | After |
| --- | ---: | ---: |
| Useful instructions | 415 | 405 |
| Encountered padding | 2 | 0 |
| Total instructions | 417 | 405 |
| Memory operands / RSP operands | 155 / 24 | 155 / 24 |
| Fused instructions / calls | 70 / 0 | 75 / 0 |

The position loop executes five times per timestep and falls from twelve to ten
instructions. Its packed multiply, addend reload and addition become one
`vfmadd213pd` with a memory operand. This removes 5,000,000 useful instructions
over the unchanged 500,000-step benchmark, with unchanged memory traffic, frame
and save plan. The actual emitted loop is retained in [native counts](native-counts.json).
The raytrace intersection stays at 169 instructions and 44 memory operands.

All **1,390 normal C++ tests passed** using the DevMode compiler and six workers.
The new tests execute 704 JIT cases: packed register/memory equivalence covers
all eight operations, both full-width load forms, NaNs, signaling NaNs,
infinities and signed zeros; contraction compares every lane with scalar FMA,
including cancellation residuals, destination/factor overlap and distinct
products. Negative tests protect policy, mixed element widths, live products,
changed factors, branches and pending rewrites. Existing memory-motion and
relocation tests now also cover 128-bit inputs. Eight encoder byte cases cover
all packed operations and extended registers, stack and RIP addresses.

All twelve original benchmark sources were rebuilt as Release programs using
`swc.dm.exe --num-cores 6 --rebuild --validate-micro`; every checksum matches.
The [complete body comparison](body-comparison.json) changes only
`Nbody.__main_0` and `Nbody.advance`. All other application and shared-runtime
bodies are unchanged. [Micro counts](microdiff.json) and
[commands and checksums](validation.json) preserve the comparison.

The implementation reuses the existing lane analysis and bounded six-instruction
contraction and twelve-instruction load windows. Its expanded candidate set is
packed floating arithmetic. An [A/B/B/A compilation probe](compile-cost.json)
used identical nbody sources, six workers and isolated rebuild outputs. Wall-time
medians were 525.8 / 1102.2 ms, CPU 1882.8 / 3539.1 ms and peak committed process
memory 260.5 / 273.2 MB. The two B wall samples were 1549.2 and 655.3 ms; these
short noisy DevMode samples do not establish a compilation speed change. The
combined Release campaign remains responsible for shipped compilation timing.

The last accepted cross-language campaign is still `20261011-205413`: nbody was
1.276x Zig 0.15.2. The subsequent eight-batch campaign was rejected by its opening
machine reference, so it supplies no timing confirmation. Competitor sources,
options and the remaining packed-root/division gap are documented in the
[scalar memory batch](../20261011-float-memory/README.md).
