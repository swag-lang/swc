# Structural compiler-speed work, 2026-11-05

This session follows the existing compiler profiles and the retained DevMode
campaign report. It uses structural evidence from the current implementation.
No elapsed-time, profiling, benchmark, or load-test run was made.

## Earlier retained batches

The campaign branch also merged the following work after the previous
compilation report:

| Area | Retained work | Compiler work removed |
| --- | --- | --- |
| Loop, SLP, MemToReg and post-RA state | Flattened register, label, relocation, induction, block-membership and nested-loop lookup tables; indexed selected loop candidates. | Repeated linear or nested-table searches and per-candidate container construction on optimizer paths. |
| LICM, spills and record promotion | Reused worklists, eligibility sets, spill reachability marks, candidate buffers and record-state storage; released converged filters and skipped empty state setup. | Repeated scratch allocation, initialization and scans across acceptance rounds or candidates. |
| Early analysis gates | Skipped empty-pass setup, label-dependent CFG work without labels, branch SSA without flag producers, and constant-fold scans without known values or constant addresses. | Pass setup and whole-function analysis when the required instruction shape or input facts are absent. |
| Shared instruction and relocation walks | Collected local-base definitions and copies in existing walks, reused instruction-stream scans for sink analysis, propagated upper halves linearly, and shared linker alias and relocation facts. | Duplicate instruction, CFG and relocation traversals for facts produced by the same input walk. |

The address-taken label list remains in instruction order. Binary search on that
unsorted list was rejected; membership checks keep their original semantics.
Moving indirect-jump detection into the common branch layout scan was also
rejected: it removes a partial mention scan for indirect functions but adds an
opcode check to every instruction, and the net effect is unmeasured.
Searching split-child register hints only among active intervals was rejected:
a source interval may end at the output slot yet still cover the preceding
input slot used by the copy hint.
Indexing MemToReg slot overlaps was rejected for now: bounded overlap queries
need extra sorted and prefix-maximum storage, and their net tradeoff is unclear
without slot-count evidence.

| Retained change | Compiler work removed | Equivalence argument | Validation |
| --- | --- | --- | --- |
| Index loop induction candidates | Repeatedly scanning the discovered induction list for each register candidate | A packed-register `FlatKeyMap` records each candidate's existing vector index. Candidate order and the selected induction are unchanged. | DevMode build; all 1,678 C++ tests passed. |
| Bound MemToReg frame-range queries | Scanning every known frame extent to answer containment and overlap queries | The extents are sorted and disjoint; `upper_bound` starts at the only possible containing range and visits only ranges intersecting the query. | DevMode build; all 1,678 C++ tests passed. |
| Index escaped MemToReg frame objects | Scanning all frame objects for each escaped offset | The same sorted, disjoint frame extents are searched by their upper bound, poisoning only the containing object as before. | DevMode build; all 1,678 C++ tests passed. |
| Defer BranchSimplify ordinal indexing | Filling an instruction-reference ordinal table for functions whose branch transforms never query ordinals | The table is built on the first ordinal query from the same ordered instruction references; queried ordinals retain their prior values. | DevMode build; all 1,678 C++ tests passed. |
| Reuse the SSA fixed-point result in constant folding | Scanning every known-value flag after propagation to determine whether any value was inferred | The fixed-point routine returns whether its unresolved count changed, which is equivalent to checking the final flags. | DevMode build; all 1,678 C++ tests passed. |
| Mark selected MemToReg promotions | Scanning the promotion list for each candidate vector slot | A flag on each slot is set from the final overlap-filtered promotion list; the lane split consults that same final selection. | DevMode build; all 1,678 C++ tests passed. |
| Index register-allocation reservations | Scanning every reserved physical-register range for each candidate overlap or local-allocation query | Ranges are inserted in start order only after an overlap check, so they remain disjoint; lower-bound queries find the first range that could intersect without changing the allocator's decisions. | DevMode build; all 1,678 C++ tests passed. |
| Index sealed loop-region lookup | Scanning all sealed loop regions at every label during register allocation | Regions are collected by increasing instruction index; `lower_bound` locates a label's header while preserving the exact region selected. | DevMode build; all 1,678 C++ tests passed. |
| Advance register back-edge membership | Searching every active loop's back-edge list linearly at each instruction, then repeating the match during register protection | CFG predecessor lists are collected in source-instruction order; filtering keeps that order, so a monotonic cursor advances without sorting. Its match is reused by the immediately following protection scan. | DevMode build; all 1,678 C++ tests passed. |
| Skip dead prefixes in register interval queries | Rescanning earlier fragments for every `covers` and intersection query | The first fragment keeps a direct check; after it expires, the sorted and disjoint ranges use `upper_bound` to skip fragments that cannot contain or intersect the position. | DevMode build; all 1,678 C++ tests passed. |
| Stop loop-range scans past the current header | Checking every later loop range when finding loop-carried next uses | Loop ranges are collected by ascending header; once a header is beyond the current position, all following ranges are also ineligible. | DevMode build; all 1,678 C++ tests passed. |
| Gate loop-carried use scans by loop depth | Scanning all back-edge ranges for allocation positions outside every loop | The allocator's existing depth sweep counts precisely the back-edge ranges covering each instruction; zero depth proves no loop can match the election position. | DevMode build; all 1,678 C++ tests passed. |
| Reserve the initial interval worklist | Repeated vector growth while adding the original intervals to the allocator's unhandled queue | The upper bound is already `out.nodes.size()`; reserving once removes geometric growth during initial population while split children can still expand it later. | DevMode build; all 1,678 C++ tests passed. |
| Keep small loop-range lists inline | Allocating heap storage for the interval walk's temporary back-edge range list | `SmallVector` stores up to eight loop ranges inline and retains the same ordered list for larger functions. | DevMode build; all 1,678 C++ tests passed. |
| Keep the active interval set inline | Heap allocation for the linear scan's active intervals | At most one allocated interval owns each physical register, and the x64 register file has at most 31 pool registers; 32 inline entries cover the complete active set. | DevMode build; all 1,678 C++ tests passed. |
| Visit only the back-edge suffix | Testing every predecessor against its instruction index while building loop depth, loop candidates and loop headers | CFG predecessor lists are source-ordered, so back-edges are the suffix; reverse traversal stops at the first earlier predecessor, and the final-element check detects loop headers. | DevMode build; all 1,678 C++ tests passed. |
| Stop rejected guarded-call predecessor scans | Inspecting label predecessors after unsupported control flow, an address-taken label, or one invalid incoming edge has already rejected the slow-call guard candidate | Eligibility is a conjunction: the initial control-flow and address-taken checks must pass, and every non-fallthrough predecessor must be an earlier conditional jump. A failed check cannot be restored by later predecessors. | DevMode build; all 1,678 C++ tests passed. |
| Reuse post-RA reload proof worklists | Reconstructing four temporary vectors and flat tables for each eligible label | All four structures are reset before each edge walk; keeping them at pass scope preserves the same bounded walk and proof while reusing capacity across labels. | DevMode build; all 1,678 C++ tests passed. |
| Reuse frame-store proof visit marks | Clearing one byte for every CFG instruction before each candidate graph walk | A per-walk 8-bit generation distinguishes visited instructions in the same existing byte array; after initial zero-initialization, full clears occur only when the generation wraps. | DevMode build; all 1,678 C++ tests passed. |
| Index escaped-store object containment | Testing every known frame-object extent for each store byte range | Extents are sorted and disjoint; `lower_bound` by the end offset finds the only possible containing object, followed by the same inclusion checks. | DevMode build; all 1,678 C++ tests passed. |
| Index post-RA frame-object membership | Testing every frame object for each candidate source reload | `frameObjects()` sorts extents by offset and code generation assigns disjoint frame slots; `upper_bound` selects the only possible containing object, followed by the same size and containment checks. | DevMode build; all 1,678 C++ tests passed. |
| Index zero-extended frame-object membership | Scanning every zero-extended object for each frame read | The set is appended in the sorted frame-object order and only cleared before rebuilding; binary search by object offset preserves the membership result. | DevMode build; all 1,678 C++ tests passed. |
| Reuse MemToReg record reachability marks | Zeroing one byte per CFG instruction before analyzing each promoted partial-word record | A per-record 8-bit epoch distinguishes reached instructions in the same byte array; after initial zero-initialization, full clears occur only when the epoch wraps, and each reached node still receives its full state before reads. | DevMode build; all 1,678 C++ tests passed. |
| Bitset the bounded compared-load walk | Linear visited-list membership checks in a backward walk limited to 96 instructions | The walk validates `first < index < last` and `last - first <= 96`; two stack words cover every possible relative index and preserve the same revisit skip without a heap-backed visited vector. | DevMode build; all 1,678 C++ tests passed. |

At the latest compiler-validation checkpoint, DevMode passed all 1,678 C++ tests
with one warning; 114 filesystem tests were skipped by the default suite
configuration. The changes are structural; no speed or memory improvement is
claimed without a benchmark.

## Follow-up checkpoint, 2026-11-16

This follow-up continues the register-allocation work using the retained
DevMode and memory evidence above. It makes no timing, CPU or memory claims.
The static Micro comparison builds each task once and checks its listing and
checksum; it does not record elapsed time.

| Retained change | Compiler work removed | Equivalence argument | Validation |
| --- | --- | --- | --- |
| Build register position lists during dense-index collection | A second pass over each instruction's already-collected unique use/def indices | Each position is appended when its per-instruction dense index is first inserted; source instruction order is unchanged. | DevMode build; C++ suite passed. |
| Mark wide register requirements during indexing | A temporary list of wide instructions and its later instruction lookup/rescan | The same instruction flags the same unique virtual registers while its use/def lists are available. | DevMode build; C++ suite passed. |
| Report dense-index insertion directly | Re-reading the register table size and comparing it with the returned index at each insertion site | `ensure` sets the result only in its new-entry branch; the dense index and insertion behavior are unchanged. | DevMode build; C++ suite passed. |
| Grow sink counters on dense-index insertion | A register-table size comparison for each sink use/definition | The counter table is cleared with the index and grows once for each newly assigned dense index. | DevMode build; C++ suite passed. |
| Grow sanitizer stamps on dense-index insertion | A stamp-vector size comparison for each sanitizer use/definition | Both structures start empty in `computeChainLiveness`; new dense indices are sequential and each appends exactly one stamp slot. | DevMode build; C++ suite and sanity suite passed. |
| Grow global range lists on dense-index insertion | A range-table size comparison for each global range insertion | `clearState` clears the dense index and range table together; each newly assigned dense index gets one range list. | DevMode build; C++ suite and focused native register-pressure stages passed. |
| Cache loop residency use counts across removals | Recounting each mapped register's in-loop uses every time the residency cap drops another value | When at least two values must be dropped, use counts are computed once. The cached candidate list mirrors the allocator's swap-with-last removal, preserving tie order; one-drop cases retain the original scan. | DevMode build; 1,715 C++ tests and three focused native fixtures passed, including pressure and loop-carried cases. |
| Skip redundant liveness side-table resizes | Final `resize` checks after dense-index insertion has already grown each nonempty side table to its exact dense count | Dense insertion assigns consecutive indices and grows the parallel vector at each new index; the no-concrete-register case still clears stale touch lists. | DevMode build; 1,715 C++ tests and focused native register-pressure stages passed. |
| Mark loop-carried registers from live bits | Testing every virtual register against every loop header | Visit only set bits in header liveness rows, mark each qualifying state once, then allocate spill slots in the original dense-register order. | DevMode build; 1,715 C++ tests and full native suite passed. |
| Fuse loop-header discovery with live-bit marking | A temporary list of loop-header indices and its later readback | Headers are still visited in instruction order and each matching live row is marked once; the no-header path still returns before spill-slot allocation. | DevMode build; 1,715 C++ tests, full native suite (3/3 stages), and full compiler campaign (69/69 stages) passed. |
| Build loop preload candidates from live bits | Testing every dense virtual register at each loop header to select only live candidates | Set-bit iteration visits candidates in ascending dense-index order, preserving the stable use-count sort and its tie order. | DevMode build; 1,715 C++ tests, full native suite (3/3 stages), full compiler campaign (69/69 stages), and all twelve static Micro task checksums matched. |
| Cache loop back-edge ranges during copy coalescing | Rescanning predecessor lists up to every integer copy candidate inside a loop | The first query keeps its original CFG walk and records containing ranges in order; later queries scan only newly reached headers and cached ranges that still cover the copy. Strict shorter-span replacement preserves the selected range and ties. | DevMode build; full compiler campaign (69/69 stages, including 1,832 C++ tests and native), all twelve static Micro task checksums matched, and task-owned listings unchanged. |
| Index repeated copy-coalescing pairs after eight candidates | Scanning every previously collected candidate for each additional eligible copy | A canonical packed dense-register pair maps to the original candidate-vector index; small candidate sets keep the linear lookup, while duplicate updates and first-seen vector order stay unchanged. | DevMode build; full compiler campaign (69/69 stages, including 1,833 C++ tests, native and workspace stages); `RegAlloc_IndexesManySameValueCopyPairs` covers nine unique pairs and a repeated lookup after indexing; all twelve static Micro task checksums matched and task-owned listings stayed unchanged. |

Rejected experiment: storing `upperRegValues` directly in `SanitizerFlatMap`
passed DevMode C++, safety, sanity and a 69-stage compiler campaign, but grew
every `SanitizerState` by 16 bytes even when the map was empty. Without evidence
about map occupancy, the added copy work is not justified by fewer node
allocations; the map remains sparse.

At this checkpoint DevMode passed 1,715 C++ tests. The broad compiler suite
passed 69/69 stages before the final three insertion-driven table-growth edits;
the latest targeted native run passed all 3 stages, including its two owning
error suites. A later full compiler run first passed 8/69 stages and reported
one `safety` failure on `cwe416_use_after_free.swg`; rerunning that safety
command in its workspace passed all 165 tests. A fresh full compiler campaign
then passed 69/69 stages, including C++, safety, sanity, native and workspace
stages. After reverting the flat-map experiment, the rebuilt retained tree also
passed all 69 compiler stages, before the latest allocator changes. After the
loop residency and liveness table changes, DevMode passed 1,715 C++ tests, the
full native suite (3/3 stages) and the full compiler campaign (69/69 stages).
After adding live-bit loop-carried marking, the rebuilt compiler again passed
69/69 stages. The subsequent loop-header fusion passed the C++ suite (1,715
tests), all three native stages, and the full compiler campaign (69/69 stages).
The later preload live-bit walk passed the C++ suite, all three native stages,
the full compiler campaign (69/69 stages), and the twelve-task static Micro
comparison with identical checksums. Listing differences included reordered
duplicate `AtomicValue` clone bodies and synthetic `__run_expr` addresses; all
task-owned function listings were unchanged, and a same-binary control
reproduced the runtime/synthetic variations. The subsequent back-edge cache
passed the full compiler campaign too (69/69 stages, including 1,832 C++ tests
and native), with all twelve checksums matching and every task-owned listing
unchanged. The retained changes reduce repeated scans, size comparisons,
table growth checks, and temporary header storage by construction. Their net
speed and memory effects remain for the dedicated benchmark campaign to
measure. Indexing repeated copy-coalescing pairs, with a test covering nine
unique pairs and a repeated lookup after indexing, preserves all twelve static
Micro task checksums and task-owned listings; the full 69-stage compiler
campaign passed with 1,833 C++ tests and native validation.
