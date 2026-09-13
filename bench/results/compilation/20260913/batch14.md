# Static micro-pass batch 14: SSA consumers and conditional analyses

Build 544, source commits `cc5658ebc` and `6af3a0435`.
The two source commits share one functional validation and integration batch.
All checks passed with exit code 0:

- [DevMode build 544](batch14-build.log), MSBuild `/m:6 /p:SwcCompileJobs=6`.
- [C++ suite](batch14-cpp.log): 751 passed, including eight added tests.
- [Native devmode](batch14-native-devmode.log): 3,131 passed; generated executable passed.
- [Native release](batch14-native-release.log): 3,131 passed; generated executable passed.

The checkout-local tool commands retain six workers and the user's load-admission waiver.
`git diff --check` passed. No backlog metadata changed.

| Change | Removed work | Preserved invariant |
| --- | --- | --- |
| Both dominator builders stop after one sweep on forward-only CFGs | A redundant fixed-point confirmation sweep | No backward edge implies a DAG, whose reverse postorder is topological. Component filtering and the general cyclic path remain unchanged. |
| SSA skips final scope restores after the last renamed instruction | Timeline writes and restore loops that no query can observe | All phi inputs are assigned before descending; every block is nonempty, and reaching queries use positions below N. |
| Physical liveness reuses instruction-effect and live-out buffers | Clearing data that is overwritten and seeding exits before the worklist | Every instruction effect is replaced before valid=true; every node enters the worklist, propagation reads only zero-seeded live-in, and live-out is written on its first visit. |
| Vector load folding removes a subsumed scalar-access predicate | Lazy loop analysis for a condition already decided by frame/relocation guards | (A or B) and insideLoop, or A or B, equals A or B; all later queries see the same immutable snapshot. |

Two added C++ tests cover liveness-buffer reuse across growing/shrinking instruction lists and changing ABI roots, plus forward-only SSA roots joining previously visited components. The restore test now rebuilds twice and checks the final definition. The every-entry dominance oracle was expanded in batch 12 before this algorithm change.

Independent cross-review covers the changed pass families. No generated-code optimization rule or iteration budget changes.

## Scalar and loop consumers

| Change | Removed work | Preserved invariant |
| --- | --- | --- |
| Constant folding collects constant addresses at its first eligible memory load | Eager relocation-table construction for functions without an eligible load | Collection observes the same immutable relocation list, keeps the last valid entry and rejects the same forms and null targets. Known-empty results disable later probes. |
| InstructionCombine skips dominance and natural-loop construction without a backward edge | Analyses that can only produce an empty loop set | Entry-count and unsupported-control-flow guards remain ahead of this shortcut. |
| Shift-mask folding uses its already resolved SSA value | A duplicate definition lookup | The existing reaching definition is valid and non-phi, and the capped use count is unchanged. |
| Vector-loop promotion delays its function model until a natural loop exists | Whole-function model construction for rejected loop-free CFGs | Dominance and loop discovery are read-only; subsequent planning sees the same IR. |

Three added C++ tests cover filtered relocation order and constant-memory widths, frame-memory folding across CFG guards, and a backward jump with no actual cycle. The relocation collector fixture calls the pass directly because duplicate/missing metadata intentionally does not satisfy the full pipeline relocation invariant.

| Change | Removed work | Preserved invariant |
| --- | --- | --- |
| InstructionCombine reuses five already resolved reaching values | Repeated register/definition lookup in six possible queries | Each value was resolved for the same explicit register, is valid and non-phi, and the capped use-count query remains identical. Less restrictive callers are unchanged. |
| Post-RA loop hoisting jumps over the carried load/store interval | Checking an interval whose register effects could never reject this candidate | Original rejection tests only apply outside the inclusive interval; all external checks retain their order. |

Induction-variable analysis stops retaining sum candidates once a product has selected
its candidate family. It still performs the same analysis in the same order; rejecting all
product carriers later does not enable a sum fallback. The added priority test checks sums
before and after a successful product, an unrepresentable product delta, and the no-product
control, including exact carrier registers and retained steps.

Existing instruction-combine cases exercise shared inputs, masks, shifts and addresses. The carried-register blocking test now checks both a use before the load and a use after the store.

## Dead-code elimination and LICM

For SSA graphs without phis, DCE replaces repeated searches from the beginning of each
use list with a cursor to its first surviving instruction consumer. Initialization replaces
the usage collection already required after the first changing sweep; unchanged passes
allocate no cursor storage. The former phi worklist owns the per-value uint32 cursors,
which adds linear scratch storage on this no-phi changing path.

Deleting a non-witness consumer does not scan the list. Deleting its witness advances the
cursor across dead entries, each at most once after initialization. Repeated operands are
allowed: an already exhausted cursor is checked before indexing. The used-value bitmap is
published only between sweeps, retaining the old erasure order and dynamic CPU-flag checks.
Every deletion still triggers another sweep even if no data-use cursor changes. The phi
propagation path is unchanged, and no SSA instruction is inserted or recycled during DCE.

Two added tests cover unequal fan-out chains with an optional live consumer, physical and
undefined inputs, and delayed flag-consumer deletion with repeated read-modify-write inputs.
Existing long-chain and phi-cycle tests remain applicable. Independent review found and
corrected the repeated-input bound before compilation.

LICM returns from frame-privacy analysis after its closure when no frame-derived register
exists: every operand in the later escape scan would otherwise be ignored, including the
stack pointer itself. Existing invalid-stack-pointer handling remains unchanged.

Loop exits are collected once, at the first retained multi-definition web that reaches its
exit-consistency check. An explicit initialized flag also caches a genuinely empty result.
The loop body, CFG and successor order are fixed through all planning retries; emission
remains later. Loops without such a candidate avoid the scan entirely.

These two removals retain existing LICM decisions and are covered by the invariant-load,
frame-privacy and web-consistency fixtures plus the native optimizer suite. Independent
cross-review confirmed the early-return and immutable-analysis invariants.

No benchmark execution or performance comparison belongs to this batch.
