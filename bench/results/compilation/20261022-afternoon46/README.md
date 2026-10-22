# Alternating compiler campaigns, 2026-10-22 afternoon

This bounded session starts at `74ba1680d3` and alternates prompts 4 and 6
until 18:00 Europe/Paris. The separate external worktrees are under
`%LOCALAPPDATA%/swc-agent-builds/alternate46-20261022-1515`, on
`perf/prompt4-alternate-20261022-1515` and
`quality/prompt6-alternate-20261022-1515`. Each build/test has fresh machine-load
admission and at most six workers. Temporary files and caches stay outside
the checkouts. `SWC_BUILD_NUM` is unchanged. No timing, profiler or peak-memory
campaign runs; compilation-speed targets remain unverified.

| Batch | Change and equivalence | Validation |
| --- | --- | --- |
| 4.1 | Resolve structure-operator owners from the operand's existing metadata. Reference/non-null pointer payload selection, alias-only normalization, invalid-payload fallback and enum preservation remain. Remove the ordinary type-table lookup and the final lookup after normalization; no persistent storage or allocation is added. The DevMode helper has 65 instructions and eight calls instead of 130 and fourteen, and reserves 0x50 rather than 0x80 stack bytes. These are code-shape observations, not timing measurements. | DevMode build; all 248 native spec-operator tests pass in `devmode`. |
| 4.2 | Reuse normalized metadata for overloaded slice bounds and unary operators. The existing alias-only metadata API preserves enum wrappers, reference handling and invalid-payload fallback. Bounds lose the generic expansion call for ordinary types and the final type-table lookup; unary resolution loses its redundant initial/final lookups. No storage or allocation is added. The bounds helper changes from 356 instructions/42 calls/0x128 stack bytes to 342/39/0x108; unary resolution changes from 313/31/0x2C8 to 239/24/0x290. | Incremental DevMode build; all 248 native spec-operator tests pass in `devmode`, including slice and unary operators. |
| 4.3 | Allocate PE placement indices without first zeroing them. `iota` writes every slot before stable sorting or placement reads it. Preserve empty-list allocation behavior, byte capacity, sort stability and section order. Remove one four-byte zero write per section; no persistent storage or allocation is added. Placement changes from 264 instructions/16 calls to 250/15 with the same 0x1088-byte stack. Image emission and debug-info emission retain their original instruction/call counts and frames. | Incremental DevMode build; five-batch milestone below. |
| 4, repair | A comma following a completed statement cannot start the next statement. Report the existing unexpected-token diagnostic on that comma instead of suggesting an unusable semicolon insertion. The recovery path and real missing-separator diagnostics remain. No accepted syntax or catalog wording changes. | The new two-case parser fixture fails with both old separator messages before the fix. DevMode rebuild; it and the existing missing-separator fixture pass expected-diagnostic verification (30 inputs including runtime, zero runtime test bodies). The original rejected narrowing probe also shows one precise comma underline and no separator help. |
| 4.4 | Search multi-assignment targets directly in their immutable AST chunks during nullable narrowing. `AssignList` inherits the span-only collector, and reference resolution does not mutate the list. Keep the same valid-span guard, target order and first matching target; remove the temporary reference vector, its copies, possible allocation and destruction. The helper's local code grows from 264 instructions/26 calls to 297/28 as span access moves into it, while its stack falls from 0x258 to 0x198 bytes and the separate collector/copy path disappears. No persistent storage is added. | DevMode build; the flow and inline narrowing inputs pass four JIT tests in `devmode`. The new case reassigns two previously narrowed pointers to every null/present combination and checks the absent-guard path. Formatting is stable on the second pass. |
| 4.5 | Reuse the owner already resolved by member-access checking. A file-local inline policy helper receives that owner after the caller's public/non-field/absent-owner guards. Module/type checks, short-circuiting, diagnostics and the standalone access predicate remain. Remove the second owner-map lookup/cast and repeated public/absent-owner checks. The standalone predicate retains 74 instructions/four calls/0x38 stack bytes; checking changes from 96/eight/0xA8 to 86/eight/0xA0. No persistent storage or allocation is added. | DevMode build; the private/readonly access fixtures and their shared type definitions pass semantic expected-diagnostic checking (31 inputs including runtime, zero runtime test bodies). |

Commands, from the corresponding campaign worktree:

```text
MSBuild.exe swc.vcxproj /t:Build /p:Configuration=DevMode /p:Platform=x64 /m:6 /p:SwcCompileJobs=6
bin/swc.dm.exe --num-cores 6 tools/unittests.swgs dm native --file-filter '\specops\' --num-cores 6 --rebuild
```

The static comparison uses the earlier session's object with an identical
`SemaSpecOp.Resolve.cpp` source against this batch's object, built with the same
DevMode configuration/toolchain. Assembly includes local labels. Validation
belongs to the batch tested; a conflict-free integration alone does not certify
subsequent concurrent changes on `master`.

## Five-batch correctness milestone

The combined compiler based on `20c8631e46` with batch 4.3 passes all
1,621 C++ tests with `--dev-full` and all 3,927 native tests in `devmode`.
The native suite's idle, pending-work and hardware recovery probes deliberately
fail their child processes; the enclosing tool exits zero. The final C++ run
follows the last source edit. These checks include both retained AST-clone and
operator-metadata batches; no diagnostic-sharing trial is present in this compiler.

```text
bin/swc.dm.exe unittest --dev-full --num-cores 6
bin/swc.dm.exe --num-cores 6 tools/unittests.swgs dm native --num-cores 6 --rebuild
```

Two additional PE index-array trials were discarded: the image-emission variant
grew its stack by 48 bytes, and the debug-info variant increased local instruction
and call counts after the first trial was removed. Only placement is retained.

The diagnostic repair is a separate defect batch, not a speed claim. Its command is:

```text
bin/swc.dm.exe test -f bin/unittests/errors/parser/parser_err_unexpected_comma_after_statement.swg -f bin/unittests/errors/parser/parser_err_expected_sep_stmt.swg --syntax-only --verbose-verify --num-cores 6 --rebuild
```

```text
bin/swc.dm.exe --num-cores 6 tools/unittests.swgs dm jit --file-filter nullable_narrow --num-cores 6 --rebuild
```

```text
bin/swc.dm.exe test -f bin/unittests/errors/sema/field_access_types.swg -f bin/unittests/errors/sema/sema_err_field_private.swg -f bin/unittests/errors/sema/sema_err_field_readonly.swg --sema-only --num-cores 6 --rebuild
```
