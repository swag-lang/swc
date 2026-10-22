# Compiler health, 2026-10-22 afternoon

Prompt 6 starts at `74ba1680d3` in the external `prompt6` worktree under
`%LOCALAPPDATA%/swc-agent-builds/alternate46-20261022-1515`, on
`quality/prompt6-alternate-20261022-1515`, alternating with prompt 4 until
18:00 Europe/Paris. Builds/tests use fresh load admission, six workers and
checkout-local compilers. Temporary/cache roots are external. `SWC_BUILD_NUM`
is unchanged. No timing or peak-memory measurement is made.

| Batch | Mechanical change and equivalence | Validation |
| --- | --- | --- |
| 6.1 | Share the switch-case and case-expression collectors through one span-parameter helper. Both copies had the identical vector construction, valid-span guard, append and return; all seven callers now pass their original span. Allocation, order, invalid-span behavior and output are unchanged. The shared helper retains 34 instructions, three calls and a 0x40-byte stack reservation; each old copy had the same counts/frame. The inspected switch callbacks retain their instruction/call counts, final offsets and stack frames. | DevMode build; all 95 switch-focused native tests pass in `devmode`, including chunked lists, dynamic/interface switches and cross-AST inlining. |
| 6.2 | Share forty single-child/span AST clone callbacks through a file-local, compile-time member selector. Each retains its exact node kind, copied payload reset, field, inline clone context, node-versus-span routine and operation order. Node and span selection adds no runtime branch or indirection. All forty emitted callbacks retain their instruction counts, call counts, final instruction offsets and stack reservations; no helper is outlined. The DevMode executable remains 16,658,944 bytes, including the inherited owner-metadata change. | Incremental DevMode build; the complete JIT suite passes all 1,539 tests in `devmode`. |
| 6.3 | Share eight two-child AST clone callbacks with compile-time member selectors, retaining both field order and each inline clone context. Explicit inlining preserves the original callback boundary for the larger variable-declaration node. Forty-seven of the forty-eight shared callbacks retain their instruction/call counts, final offsets and stack frames; the variable callback changes from 145 instructions/10 calls/0x58 stack bytes to 118/8/0x48. No clone helper is outlined and no runtime dispatch is introduced. | Incremental DevMode build; the final compiler passes all 1,539 JIT tests in `devmode`, including the inherited byte-pair loop integration. |
| 6.4 | Unify node/span cloning across 66 callbacks, including fifteen mixed or longer child lists and the three aggregate declarations. Compile-time field selectors preserve every field, operation order and inline context. Each field assignment remains a separate full expression. Token spans, conditional children and distinct callable contexts keep their own policies. Sixty-one callbacks retain their complete code shape; the two conditional callbacks shrink, and three aggregate callbacks absorb their old outlined helper, removing that extra boundary. No callback's effective stack grows and no generic helper is outlined. | DevMode build; the final compiler passes all 1,539 JIT tests in `devmode`. Its source starts at `5ee1abfc1d`, before the later prompt-4 parser repair and narrowing-target batch are synchronized. |

Commands, from this worktree:

```text
MSBuild.exe swc.vcxproj /t:Build /p:Configuration=DevMode /p:Platform=x64 /m:6 /p:SwcCompileJobs=6
bin/swc.dm.exe --num-cores 6 tools/unittests.swgs dm native --file-filter switch --num-cores 6 --rebuild
bin/swc.dm.exe --num-cores 6 tools/unittests.swgs dm jit --num-cores 6 --rebuild
```

This file-local batch changes no shared header, architecture or conditional
source surface, so DevMode is sufficient. Static object comparison uses the
earlier session's unchanged switch source and the same configuration/toolchain.
Results belong to the source actually tested, before prompt-4 integration is
synchronized into this worktree.

The first two-child trial outlined the variable-node helper and added a call.
The retained explicit-inline form removes that boundary.

The first generic fold retained extra temporary-context stack slots across field
assignments. The retained per-field assignment helper restores their original
full-expression boundaries. The DevMode executable remains 16,658,944 bytes
against the same source base; this is binary-size evidence, not a timing claim.

The operand-error constructor family remains separate: full-factory and
caller-owned-diagnostic factoring trials grew the pair builders' stack by
16 bytes and changed scalar instruction counts. These layout/work differences
block retaining those trials under this mechanical campaign; all trial source
was reverted. No diagnostic text, span or expectation changes are retained.
