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
| 6.5 | Share the wait-source reference fallback for AST and source-code references. Compile-time selectors keep the current-state check/read, guarded owner getter and invalid fallback in the same order. The two state assignments retain their order. No runtime member-pointer dispatch, storage or allocation is introduced. The containing wait-state helper retains 121 instructions, zero calls, its final instruction offset and 0x20-byte stack. | DevMode build; all 1,540 JIT tests pass in `devmode`, including the synchronized parser repair and nullable-target regression. |
| 6.6 | Remove the builder-service include from `Symbol.Function.h`: its builder uses require only a forward declaration, while register values and instruction constants get their own direct leaf includes. Add the builder include to eleven implementations that actually use it, preserving unit-test guards. The header's project include closure falls from 68 to 63 headers, removing the builder, CFG, printer, storage and runtime-backend configuration services from 117 direct consumers. No declarations, field layouts or expressions change. | DevMode build, final guarded-test incremental build and complete Release build pass. This include-only batch is validated at its compilation boundary. Its source base is `8fcb9c07ae`, before later cast-target reuse and byte-pair alias integration. |
| 6.7 | Move the unchanged `MicroRegPrintMode` enum to its own leaf header. Builder and pass contracts depend on that enum instead of the printer service. Keep the namespace, underlying type, enumerators, defaults and all function declarations. Give the prolog/epilog pass direct includes for its register, operand-bit and vector values, and forward-declare its call-convention reference. `MicroPass.h` has 3 project headers in its closure instead of 18 across 26 direct consumers. The builder's closure remains 25, replacing the printer with the leaf contract across 136 direct consumers. | Final DevMode and Release builds pass. Project XML parses and contains the new header exactly once; this repository has no root project filters file. The four implementation/test users of the printer already include it directly. This include-only batch uses source base `d98f7bf130`, before the latest non-null and indexed-assignment metadata batches are synchronized. |

Commands, from this worktree:

```text
MSBuild.exe swc.vcxproj /t:Build /p:Configuration=DevMode /p:Platform=x64 /m:6 /p:SwcCompileJobs=6
MSBuild.exe swc.vcxproj /t:Build /p:Configuration=Release /p:Platform=x64 /m:6 /p:SwcCompileJobs=6
bin/swc.dm.exe --num-cores 6 tools/unittests.swgs dm native --file-filter switch --num-cores 6 --rebuild
bin/swc.dm.exe --num-cores 6 tools/unittests.swgs dm jit --num-cores 6 --rebuild
```

The file-local batches 6.1 through 6.5 change no shared header, architecture or
conditional source surface, so DevMode is sufficient for them. Shared-header
batches 6.6 and 6.7 also pass Release. Static object comparison uses the earlier
session's unchanged switch source and the same configuration/toolchain.
Results belong to the source actually tested, before prompt-4 integration is
synchronized into this worktree.

The first printer-include removal missed the enum declaration; splitting that
contract also exposed the prolog/epilog pass's transitive value-type dependencies.
The retained batch supplies those dependencies and both final builds pass.

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

## Ten-batch correctness milestone

The prompt-4 compiler source at `bfc51d7dac` passes all 1,623 C++ tests with
`--dev-full` and all 3,928 native tests in `devmode`. The idle, pending-work
and hardware recovery probes have their deliberate child failures and the
enclosing tool exits zero. Both checks use separate fresh external cache roots.
This milestone includes the 66-callback clone policy, statement-comma repair,
nullable assignment-target traversal, member-owner reuse and inherited byte-pair
loop integration. It precedes the JIT reference-fallback cleanup in batch 6.5.

```text
bin/swc.dm.exe unittest --dev-full --num-cores 6
bin/swc.dm.exe --num-cores 6 tools/unittests.swgs dm native --num-cores 6 --rebuild
```
