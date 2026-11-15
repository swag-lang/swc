# Conditional owner returned after an early return

## Round 1

| Check | Tests | Sweep | Hits | Decision |
| --- | --- | --- | --- | --- |
| Return-storage replacement when a conditional selects a local | Added `conditional_owned_return.swg`: missing current and legacy paths select `current`; an existing legacy path selects `legacy`; an existing current path takes the early return. Each result is checked after another allocation, and a counting allocator verifies that all allocations are released when the scope ends. | No whole-tree sweep; this change repairs return ownership lowering and introduces no safety rule. | The focused native test failed before the fix when the false branches selected `current`. This was a compiler defect. No consumer hits. | Retained. Reject return-storage replacement when the expression may select the candidate local. |

## Validation

- DevMode compiler: focused `std/core` test passed in JIT and native execution.
- Release compiler with `release-safe` program configuration: focused `std/core` native test passed.
- The allocator ended with zero live allocations after all three returned strings and formatting temporaries left scope.
- The test fails on the original DevMode compiler in native execution, so it reproduces the defect rather than only exercising the repair.

## Commit

- Campaign batch: `f6335e16db` — `[prompt 3] Keep conditionally returned local alive`
- Integrated directly into local and remote `master` as `b3aec41590`.
