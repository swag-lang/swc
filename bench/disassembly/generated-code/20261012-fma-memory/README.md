# Fused scalar arithmetic with memory operands

Baseline: `a67f64fad`. Accepted on static evidence; runtime timing not measured.

A load feeding an existing scalar FMA needed a separate instruction because
Micro could not express its memory operand. Separately, folding a reload into
a multiplication hid that product from the later contraction pass. The new
`OpTernaryRegRegMem` closes both gaps while retaining the destination as an
input and preserving its upper lanes.

The four existing scalar fused operations keep their operand roles and 213/231
selectors. A dead loaded third operand can fold directly, without commuting
factors. A multiply with a memory operand can also contract with a following
addition or subtraction under `fpMathFma`, provided its original accumulator is
the destination. The product must die in every lane. Neither a memory write,
address/factor change, branch nor pending rewrite may intervene. The full motion
window is claimed, and one ordinary RIP relocation moves with the memory read.
Register-only contraction retains its existing behavior and scope.

| Actual native work | Before | After |
| --- | ---: | ---: |
| nbody useful instructions per timestep | 421 | 415 |
| nbody encountered padding instructions | 2 | 2 |
| nbody total instructions per timestep | 423 | 417 |
| nbody memory / RSP operands | 155 / 24 | 155 / 24 |
| nbody fused operations / calls | 65 / 0 | 70 / 0 |
| raytrace intersection instructions | 170 | 169 |
| raytrace intersection memory / RSP operands | 44 / 22 | 44 / 22 |
| raytrace intersection fused operations / calls | 16 / 0 | 16 / 0 |

The nbody position loop executes five times per timestep and falls from thirteen
to twelve instructions. One separate reload also disappears outside that loop.
The six-instruction reduction saves 3,000,000 instructions over the original
500,000 timesteps, with unchanged memory traffic, frames and save plans. The
raytrace fold removes a multiplier reload in the fourth sphere calculation.
Runtime timing has not been measured for this batch.

The comparison remains against actual Zig 0.15.2 and Odin
`dev-2026-09-nightly:a2fb372` from accepted campaign `20261011-205413`, with Swag
ratios 1.276x and 0.964x respectively. Their sources, actual build options and
machine-code evidence are documented in the [preceding batch](../20261011-float-memory/README.md).
Zig's packed roots and divisions remain a separate opportunity; this change
preserves the existing scalar expression association and uses only the already
permitted FMA contraction policy.

Validation: all **1,442 C++ tests passed** with the DevMode compiler and six
workers. New cases execute 2,064 JIT comparisons across both scalar widths,
all four fused operations, NaNs, signaling NaNs, infinities, signed zeros and
full preserved register lanes. Contraction tests include a cancellation where
separate multiplication rounds away the residual that FMA retains, both
memory-product shapes, disabled policy, aliasing writes, changed factors and
bases, live upper lanes, actual branches, pending claims and duplicate
relocations. Encoding tests cover extended registers, stack and RIP addressing.
The `MultiplyAdd` operation that explicitly requires separate rounding remains
unchanged.

All twelve unchanged benchmark sources were rebuilt as Release programs with
`swc.dm.exe --num-cores 6 --rebuild --validate-micro`; every checksum matches.
The [full body comparison](body-comparison.json) changes only `Nbody.__main_0`,
`Nbody.advance` and `Raytrace.intersect`. All other application and shared
runtime bodies are unchanged. [Micro counts](microdiff.json), [actual native
counts and addresses](native-counts.json), and [commands and checksums](validation.json)
retain the complete comparison.

The added eligibility checks reuse the existing twelve-instruction load window
and six-instruction separated-product window. Carrier liveness reuses the
existing block-suffix and CFG lane analyses; contraction uses the backward
function analysis already required by scalar FMA. No separate whole-function
solver is added. An interleaved same-workspace DevMode build probe is retained
alongside the grouped Release campaign, which owns the timing comparison.

The [A/B/B/A build probe](compile-cost.json) used the same nbody sources, Release
program configuration, six workers and isolated rebuild outputs. Two-sample
medians were 705.1 / 582.0 ms wall time, 1968.8 / 1812.5 ms CPU and 284.6 / 269.2 MB
peak committed process memory. These short diagnostic samples do not establish
a compilation speed change.
