# Static micro-pass batch 22: Compact membership and shared analysis data

Build 552, source commit `35241cdef`.
All checks passed with exit code 0:

- [DevMode build 552](batch22-build.log), MSBuild `/m:6 /p:SwcCompileJobs=6`.
- [C++ suite](batch22-cpp.log): 766 passed, including three added tests and one extended oracle.
- [Native devmode](batch22-native-devmode.log): 3,131 passed; generated executable passed.
- [Native release](batch22-native-release.log): 3,131 passed; generated executable passed.

SSA instruction-slot ordinals had become membership checks after reaching-definition
queries moved to the rename index. A byte mask now records that membership, replacing
four-byte entries. It still describes the build snapshot: an erased anchor remains
queryable until rebuilding. The existing erase/recycle test now checks that intermediate
state explicitly. The instruction-to-block map is also overwritten before every reader,
so rebuilds retain its size and avoid filling the old entries before assigning them.
Existing physical-only and changing-CFG rebuild tests cover the early-return boundaries.

Register allocation uses the predecessor rows already owned by its CFG snapshot, removing
one container per instruction, a second copy of all edges and the reverse-edge construction
walk. CFG construction records the same source order and bounded targets as the removed
walk. The borrowed rows have exactly the lifetime already required by RA's instruction and
successor queries through rewriting: storage changes do not rebuild this CFG during RA.
The next run clears the view before touching it. An added test compares reused and fresh
allocators across different graph sizes and loops, with interval allocation enabled and
disabled, destroying each builder between runs. No scheduling or lifetime window changed;
the DevMode compiler supplies the required assertions and backend validation.

SLP constructs the canonical packed-load tuple by permuting the four load IDs already
interned by the scan. Contiguous distinct offsets establish each lane, so four value
constructions and interning lookups disappear without changing IDs, shuffle controls,
load order or budgets. A new test checks an initially permuted leaf through both direct
loads and arithmetic memory operands, including exact offsets and shuffle control.

Store-to-load forwarding rejects incompatible base/offset/width/source before comparing
relocation identity. It also reuses the load's initial claim check: a failed forward has
no claim side effects, while a successful forward is excluded from producer caching.
The new oracle checks prior claims and exact first-producer selection. Existing relocation
and alias tests remain in the C++ suite.

All four families received independent review. Validation uses the checkout-local DevMode
compiler and six workers under the user's load-admission waiver. Both native configurations
cover guarded backend behavior and Release vectorization. `git diff --check` passed.
No backlog metadata changed, benchmark executed, or timing comparison run.
