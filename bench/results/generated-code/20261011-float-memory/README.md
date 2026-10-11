# Scalar memory operands with an independent destination

Baseline: `15f83c1ae`. Accepted on static evidence; runtime timing not measured.

The x64 backend could fold a scalar load into destructive arithmetic, but kept
the load when a VEX instruction needed an independent destination. The new
`OpBinaryRegRegMem` represents `dst = left op [base + offset]` for scalar
addition, subtraction, multiplication, division, minimum and maximum. It reads
the original scalar width and preserves the left source's upper lanes. It does
not widen a scalar read to a packed memory operand.

The post-allocation fold requires a dead loaded carrier, a stable address,
no intervening memory write or control-flow boundary, and an unclaimed motion
window. It moves one RIP relocation to the consumer. Operand order is retained;
commuting addition or multiplication additionally requires the no-NaN policy
and dead destination upper lanes. Existing contraction and result-copy rules
run first. A product with a potential later accumulation remains in registers
until queued rewrites settle, so memory folding does not consume a future FMA.

| Actual native work | Before | After |
| --- | ---: | ---: |
| nbody useful instructions per timestep | 424 | 421 |
| nbody encountered padding instructions | 0 | 2 |
| nbody total instructions per timestep | 424 | 423 |
| nbody memory / RSP operands | 155 / 24 | 155 / 24 |
| nbody fused operations / calls | 65 / 0 | 65 / 0 |
| raytrace intersection instructions | 173 | 170 |
| raytrace intersection memory / RSP operands | 44 / 22 | 44 / 22 |
| raytrace intersection fused operations / calls | 16 / 0 | 16 / 0 |

The timestep counts include all five executions of the unchanged 13-instruction
position loop. Three separate reload instructions disappear per timestep:
1,500,000 useful instructions over 500,000 steps. Alignment introduces two NOPs
per timestep, so the total executed instruction reduction is 500,000. Frames
and saved-register sets are unchanged. The three raytrace folds occur in the
coordinate calculations before each sphere's conditional intersection work.
[Native addresses, counts and executable hashes](native-counts.json).

The latest accepted campaign, `20261011-205413`, names Zig as nbody's fastest
other runtime (Swag ratio 1.276x) and Odin as raytrace's (0.964x). Actual Zig
0.15.2 code, built with `-O ReleaseFast -target x86_64-windows-msvc -lc`, has
348 instructions and 101 memory operands per timestep, with packed arithmetic
that this batch does not introduce. The actual Odin executable, built with
`odin build bench/src/odin/raytrace.odin -file -o:speed`, has 201 instructions,
49 memory operands and nine scalar memory arithmetic instructions in its
four-sphere intersection routine. Its version is
`dev-2026-09-nightly:a2fb372`; executable SHA-256 is
`120b09113b1672e9ec4f69236f74c6a3021ffa88fb49ff5a129778141bf9dbbe`.
[Odin addresses and operations](odin-intersect.json). Static counts do not
establish a latency ranking. The unchanged benchmark sources retain their FP
policies; no unsafe reassociation is enabled by this batch.

Validation used the checkout-local DevMode compiler and six workers. All
**1,437 C++ tests passed**, including 456 JIT executions comparing optimized and
unoptimized scalar results, NaN payloads, signed zeros and all preserved lanes.
Encoding cases cover both widths, extended registers, stack addressing and RIP
relocation. Motion tests reject aliasing writes, base changes, live carriers,
live upper lanes, pending claims, forbidden commutation and pending contraction.
A filesystem test initially reached its 15-second subprocess timeout while
other checks ran; the complete rerun without those concurrent builds passed.

All twelve original benchmarks were rebuilt as Release programs using
`swc.dm.exe --num-cores 6 --rebuild --validate-micro`; all checksums match.
The [full body comparison](body-comparison.json) changes only `Nbody.__main_0`,
`Nbody.advance`, `Nbody.energy` and `Raytrace.intersect`. All other application
and shared runtime bodies are unchanged. The [Micro counts](microdiff.json)
also show no loss; [commands and checksums](validation.json) retain provenance.

The added scan is linear in function length with a twelve-instruction consumer
window and a twelve-instruction contraction lookahead. Eligible candidates
reuse the existing backward lane analysis: a block suffix scan, with a CFG
fixed-point fallback if local liveness cannot decide. Repeated candidate queries
can therefore revisit a block or the full CFG; this is not a constant-time
liveness check. An A/B/B/A DevMode build probe on the same nbody sources and
Release configuration is retained in [compile-cost.json](compile-cost.json).
Its two-sample medians were 583.4 / 495.6 ms wall time, 1625.0 / 1648.4 ms CPU,
and 271.1 / 272.7 MB peak committed process memory. These short diagnostics do
not establish a compilation speed change; the grouped Release campaign owns
that comparison.

A separate countdown-unrolling hypothesis was rejected and its code restored.
It increased the nbody timestep to 434 instructions and 172 memory operands,
losing packed position updates and FMA while retaining pointer steps. The
[rejected experiment](rejected-countdown.json) changes the next action in
`compiler.optimization.104`: solve address, fusion and pressure costs together
before retrying unrolling. The archived patch remains in the external session
directory and is not part of this batch.
