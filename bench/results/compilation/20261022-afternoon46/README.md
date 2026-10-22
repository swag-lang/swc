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
