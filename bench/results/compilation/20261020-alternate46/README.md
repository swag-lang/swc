# Alternating compiler campaigns, 2026-10-20

This session alternates prompt 4 (structurally proven compiler savings) and
prompt 6 (mechanical compiler cleanup) until 18:00 Europe/Paris. It starts at
`cd4d84eca7`. Each retained batch is validated in its own external worktree,
merged directly into local `master`, and then synchronized with that merge.

The worktrees are `prompt4` and `prompt6` under
`C:/Users/chris/AppData/Local/swc-agent-builds/alternate46-20261020-1347`.
Their branches are `perf/prompt4-alternate-20261020-1347` and
`quality/prompt6-alternate-20261020-1347`. Logs and inspection probes stay in
the parent session directory. `SWC_BUILD_NUM` remains 1173.

No compilation benchmark, profiler, timing comparison, or quantitative speed or
memory claim is made. Prompt 4 uses only the checkout-local DevMode compiler.
Prompt 6 additionally builds Release when a batch changes a shared header.
All builds and tests have fresh machine-load admission and six-worker bounds.

## Retained batches

| Prompt | Code batch | Source evidence | Validation |
| --- | --- | --- | --- |
| 4 | `3963b0227` Move the completed replacement result | Transfer final string storage instead of copying its bytes; source-aliased views remain valid until processing finishes. | DevMode build; 1,517 default C++ tests. |
| 6 | `177d0a08e` Share scalar hash combination | The 64-bit overload folds its input as before and uses the existing 32-bit formula. All three overloads have identical disassembly. | DevMode build; 1,516 default C++ tests. |
| 4 | `7022033e9` Borrow the original replacement input | Remove the initial owning copy; construct iterative state only when another replacement pass is needed. Tests cover repeated source-aliased views. | DevMode build; 1,517 default C++ tests. |
| 6 | `f2510a041` Share web-renaming memory keys | One file-local key/hash pair replaces two identical pairs. Fields, equality, hash, table operations and order are unchanged. Both affected bodies retain their extent, calls and stack reservation. | DevMode build; 1,517 default C++ tests. |
| 4 | `6b382e504` Erase reference payloads through one probe | Clear the slot already found, preserving occupied keys, collision chains and live counts. Const lookup keeps its original emitted shape. | DevMode build; 1,580 full C++ tests; 3,917 native tests and expected recovery checks. |
| 6 | `006f19030` Share little-endian word helpers | Read/write families and looped appends share their bodies. The 16-bit append stays unrolled; the storage append helper is force-inlined. All nine entry points retain extent, calls and stack reservation. | DevMode build; 1,518 default C++ tests, including literal byte-order and neighbour checks. |
| 4 | Current shift-reuse batch | Reuse the shift computed during power-of-two validation for multiply and unsigned division, removing a repeated integer-word walk. The main pass retains its stack reservation and call count, with a 56-byte smaller extent. | DevMode build; 1,518 default C++ tests; both selected native `pow2` inputs pass. |

Counts belong to each batch's tested revision. A conflict-free merge does not
claim that every suite was rerun on the combined revision. The full C++/native
milestone belongs to `6b382e504`; later independent checks are listed separately.

## Commands

Builds use MSBuild with `/t:Build /p:Configuration=DevMode /p:Platform=x64
/m:6 /p:SwcCompileJobs=6`; applicable prompt-6 builds also use `Release`.
Focused commands run from the corresponding worktree:

```text
bin/swc.dm.exe unittest --num-cores 6
bin/swc.dm.exe unittest --dev-full --num-cores 6
bin/swc.dm.exe --num-cores 6 tools/unittests.swgs dm native --num-cores 6 --rebuild
bin/swc.dm.exe --num-cores 6 tools/unittests.swgs dm native --file-filter pow2 --num-cores 6 --rebuild
```

The full native tool exits zero. Its deliberate panic and hardware-exception
recovery probes print expected failures, separately from the 3,917 passing tests.

## Rejected trial and remaining scope

Replacing `integerLog2` with `std::countl_zero` passed correctness checks but
introduced CPU-capability dispatch, outlined helpers and additional calls.
That trial and its trial-only test are restored; shift reuse leaves the original
integer-logarithm implementation unchanged.

The general ByteArray append helper initially added a tail jump, and forcing it
inline through `pushBack` then added a per-byte call. The retained helper operates
on the existing storage, preserving the original loop bodies. The distinct short
unrolled 16-bit append is deliberately retained.

The backlog and benchmark history are unchanged. This is an ongoing, time-bounded
pass, not a claim of whole-tree code-health coverage or completed speed targets.
