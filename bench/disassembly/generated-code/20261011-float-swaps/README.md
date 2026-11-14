# Remove unobserved floating register exchanges

Baseline: `88b410f15` (compiler code unchanged since `b1ef958c9`).
Decision: accepted on static evidence; runtime timing not measured.

The native nbody timestep exchanged two XMM values through a temporary, did
independent work, then exchanged them back before either value was observed.
Both temporaries were fully overwritten before their next read. The bounded
post-allocation rule removes these six full-width copies; it does not change
register allocation, arithmetic order, memory, or live-range lengths. It admits
both orientations of the inverse exchange and a different second temporary.
Any observation, partial overwrite, branch, call, or pending rewrite rejects
the candidate. The proof claims the complete intervening instruction window.

| Executed timestep work | Before | After |
| --- | ---: | ---: |
| Useful native instructions | 430 | 424 |
| Padding instructions encountered | 1 | 0 |
| Total native instructions | 431 | 424 |
| Memory operands | 155 | 155 |
| RSP memory operands | 24 | 24 |
| Calls | 0 | 0 |

The six removed copies save 3,000,000 instructions over 500,000 timesteps.
The additional disappearing NOP is incidental placement, not the optimization's
causal gain. Counts include all five executions of the 13-instruction position
update loop: a plain outer-loop listing counts that nested loop only once and
would report 378 to 372 useful instructions and 131 memory operands. The frame
and save plan are unchanged. [Native counts](native-loop-counts.json).

The accepted campaign `20261011-205413` names Zig as nbody's fastest other
runtime at a 1.276x Swag ratio; that campaign predates this batch. The preserved
actual Zig 0.15.2 executable was compiled with `-O ReleaseFast -target
x86_64-windows-msvc -lc`. Its timestep has 348 native instructions and 101 memory
operands, with four packed and two scalar roots/divisions each. Both sources
perform 500,000 steps on the same five bodies and retain exact checksum
169096566666. This copy cleanup does not claim to close the packed arithmetic gap.

Validation: DevMode compiler built with six C++ workers; all **1,433 C++ tests**
passed, including JIT execution comparing every 128-bit lane before and after
optimization. Focused cases reject observed values, non-inverse exchanges,
partial copies, partial scratch writes, control-flow boundaries and claimed
instructions. All twelve unchanged benchmark sources were built as Release
programs with `swc.dm.exe --num-cores 6 --rebuild --validate-micro`; every checksum
passed. This covers the actual native consumer as well as JIT machine execution.
The [full body comparison](body-comparison.json) changes only `Nbody.__main_0`;
every other application and shared runtime body is unchanged. The [count
comparison](microdiff.json) records the same bounded result.

Analysis cost is at most 64 straight-line instructions per full-width floating
copy, O(64C) time and fixed local storage. No function-wide dataflow solve is
added. The final comment-only clarification followed the tested build.
