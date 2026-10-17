# Structural compilation savings, 2026-10-17

This prompt-4 pass starts at `46c33a053c` on `perf/prompt4-20261017` in an external
worktree. Planned speed work uses that worktree's DevMode compiler, with six workers.
The reproduced SmallVector lifetime defect also requires the Release compiler
under the shared protocol's defect-repair exception.
`SWC_BUILD_NUM` remains 1173. The existing compilation reports guided selection
of Micro analysis work; no timing, profiling, or benchmark campaign was run.

| Retained change | Compiler work removed | Equivalence argument |
| --- | --- | --- |
| Precompute record-store byte effects (`082309ef7`) | Repeated operand reads, width/mask construction, and immediate-byte scans during record dataflow sweeps; map nodes for reads | Each store has a fixed defined-byte mask and zero-byte mask. Applying those masks produces the same outgoing state. Instructions remain unchanged throughout the analysis. |
| Save record states only for partial stores (`9f8be1e9f`) | State-map lookups and insertions for reads and whole-word writes | Only partial stores consult the saved state when rewriting. The complete access validation and dataflow remain in place. |
| Intersect forward dominators by instruction order | RPO-rank stores for reachable instructions and repeated rank-array reads during intersections | Every edge in this path points forward, so instruction indices have the same ordering as the previously stored ranks. The existing SSA helper now serves both analyses; cyclic graphs retain their previous algorithm. |
| Solve forward-only record states in one sweep (`edf51be1b`) | A second full instruction-and-edge walk that only confirms convergence | Every predecessor of an instruction has already been processed. Graphs with backward edges keep the existing fixed-point loop and iteration limit. A C++ test checks that repeated field stores in a loop retain their byte-clearing operation. |
| Solve forward-only sanitizer liveness in one reverse sweep | Repeating the chain and live-bit matrix walks to confirm unchanged sets | Chain states are numbered in instruction order, so every successor is final before its predecessor is visited. Graphs with backward edges retain their convergence loop. |
| Visit only marked operand-width positions | Tests of unrelated union operands in register allocation and frame compaction | Removing the lowest set mask bit visits the same width operands in the same ascending order. Fixed-width vector opcodes keep their existing early return. |
| Advance the type-info DFS dependency cursor | Rechecking the completed dependency prefix after each descent, plus a separate node-based stack-membership set | The cursor visits dependencies in the same order. Membership and the cursor fit existing entry padding, checked statically; scope cleanup clears membership before a semantic pause releases cache ownership, so a resumed walk starts each unfinished entry from its first dependency. |
| Keep numeric-promotion rows in one allocation | Allocating each of the 16 rows separately, constructing a temporary row vector, and loading a row pointer for every promotion | Each row has the same compile-time width as the builtin numeric list, protected by a static assertion. All cells retain the same computation and row/column indices. The vector control block has the same size. |
| Skip impossible frame-base candidate probes | Looking up physical or floating-point bases and preferred registers in a table containing only virtual integer registers | The existing validity predicates become candidate-kind predicates. The table contents, iteration order, and selection rule are unchanged. |
| Avoid unread byte-swap provenance initialization and copies | Clearing arrays that every successful trace overwrites, copying those arrays before overwriting them again, and materializing a root result used only for immediate comparison | Successful traces still fill all 64 positions; failed traces are never read. Leaf metadata, bit-combination order, near-miss rejection, and emitted swaps are unchanged. |
| Omit the unqualified type-info self-dependency | Appending and subsequently ignoring the current type when it has no qualifiers | The existing qualifier branch appends a dependency only when normalization is needed. Qualified types keep the same dependency and traversal position. |
| Initialize blocked-call flags only with their final target value | Zero-filling the flag array immediately before assigning every entry | Names and graph rows are appended together. Every target flag is assigned before the edge walk adds caller flags; one owned array replaces the single-use vector without widening its storage. |
| Queue incomplete return summaries only on their state transition | Reading and writing queue-membership bytes during completeness propagation | A summary changes from complete to incomplete once. The transition itself prevents duplicate queue entries; the later growing-mask fixpoint retains its membership array and existing queue order. |
| Materialize completeness dependencies only when propagation is needed | Prefix summation, a second dependency walk, and the reverse-edge and cursor allocations when no dependency is missing; a separate seed scan in every case | Missing dependencies seed the same caller-order queue during the existing count walk. Without a seed, completeness cannot fall; with one, the same reverse edges and queue propagate it as before. Temporary storage is released before the mask phase. |
| Write converged upper-half facts directly into their final slots | A per-instruction input-state allocation, its initialization, and a final full copy in the cyclic path | Every instruction starts queued and writes its input fact on each visit. Queries are enabled only after convergence; outgoing facts, requeues and visit order are unchanged. The existing final buffer already has the required slot extent. |
| Share one enum-value lowering buffer within its metadata build | All but the first temporary byte allocation for the values of one enum | The underlying layout has one fixed size. Each value still starts with zero bytes and is fully materialized before the next reset, preserving omitted elements, padding and relocations. Capacity remains that one layout's size. |
| Keep large inline-binding visited sets in a flat key table | Per-node hash allocations and linked-node probing after the first 16 visited nodes | The small path and pending-node order are unchanged. Membership uses the same 32-bit reference identity; a static assertion bounds the optional control object's size. The flat slots replace MSVC's two-iterator buckets and linked reference nodes. |
| Construct AST visitor frames with their final node reference | The second initialization of every newly pushed frame | Member defaults now describe the complete initial state, and emplacement supplies the node reference directly. Restarts assign that same initial state. Object inspection confirms removal of the caller's repeated stores, with one emplacement specialization and unchanged frame fields. |
| Compute each span chunk's layout once | A second header decode and helper call when reading a chunk, repeated alignment when a write fits its current page, and division in the reader's alignment operation | The pointer and count share the same decoded header and aligned offset. The writer recomputes only after moving to a fresh page. Reader alignment is already constrained to a nonzero power of two, so masking gives the same rounded offset. Publication, bounds checks, element counts and storage layout are unchanged. |
| Initialize primitive semantic-view fields only during computation | Constructor stores immediately repeated by `computeInner`, plus an invalid node reference immediately replaced by the resolved reference | The sole constructor always reaches `computeInner`, which initializes every field before its first read or early return. Recomputations retain the same complete reset. Wrapper members and the object layout are unchanged; object inspection confirms removal of the primitive constructor stores. |
| Initialize record input states only on first reach | Filling every instruction's record state before its reached bit permits a read | The entry gets an explicit empty state. First arrival assigns both byte masks before any later read; successor merging and access validation already guard every other read with reachability. The trivial state has no implicit initialization, protected by a static assertion; value-initialized map entries retain their zero defaults. |
| Read SIMD byte tables through a byte span | Copying each 16-byte index table into a second local array | `std::as_bytes` exposes the same unsigned-byte representation. Materialization copies it synchronously into constant storage; type selection, payload hashing and emitted instructions use the same bytes and retain their order. |
| Mark only named aggregate slots | A byte store for every preceding positional child while resolving an aggregate child | The positional cursor only advances. Its consumed slots are never read again; named bindings retain marks because they may occupy a future slot. Child visitation, identifier lookup and slot choices are unchanged. |
| Align raw span writes with a mask | Runtime remainder operations in chunked and contiguous span alignment | Raw writers accept zero or a supported power of two. A zero mask preserves the zero convention; otherwise unsigned masking rounds to the identical offset. Header placement, payload, page selection and publication are unchanged. |
| Return Tarjan low links from the recursive walk | The low-link array allocation, its initial fill and per-edge element loads and stores | Each low link is consumed only by its own activation and its parent immediately after recursion. Discovery indices, stack membership, SCC popping and graph visitation retain their order. The DevMode object reserves the same 72 bytes per recursive call; the graph object loses one vector. |
| Traverse attribute spans by chunks | Repeated span setup, header reads and prefix-chunk walks for each attribute | A borrowed AST span exposes the existing ordered chunks without copying references or allocating. Meta-function discovery keeps its first-match exit; semantic attribute validation preserves its first-error exit. Existing AST span helpers share the same shard decoding. |
| Check multiply-to-shift eligibility once | A repeated operand-width check, power-of-two check and integer-logarithm scan after checking CPU flags | The sole caller already rejects every ineligible nontrivial immediate before the flags walk. Zero and one keep their existing reductions; the remaining case emits the same shift and shift amount. Width-boundary and live-flag C++ cases protect both decisions. |
| Walk static-switch cases by chunks | Repeated span setup, header reads and prefix walks during case lookup and semantic child collection | Searches retain their first matching case. Child collection keeps the selector, all case values, all bodies and the case-label nodes in their original separate phases, without a new buffer. A C++ case checks that flattened order including a default section. |
| Construct a reserved forward assignment directly | A capacity comparison for every assigned element | The forward range supplies its complete distance before reservation. Direct construction retains the same values, order, size publication and capacity policy; input iterators keep their incremental growth path. |
| Traverse switch selections and duplicate checks by chunks | Per-case and per-value span setup, header reads and prefix walks | Semantic selection still visits every value and retains the first matching body and first default; code generation keeps its first-match return. Duplicate checks retain their range exclusion, order and first diagnostic. No new buffer or lookup table is introduced. |
| Trust the allocator's private dense virtual-register table | Three repeated register-kind checks and sentinel/bounds checks for every scored virtual occurrence | Both insertion sites require virtual registers, and every scored use and definition was indexed before arrays were sized. The interval fallback does not mutate those lists. Occurrence multiplicity, scores, traversal and allocation choices are unchanged; object inspection confirms removal of both scored-loop bounds sequences. |
| Borrow closing-delimiter recovery lists | Constructing and destroying a temporary SmallVector for each closing delimiter, including successful matches | Every caller supplies an empty list or a literal list whose lifetime covers the call. Only a missing closer constructs the same working recovery vector, preserving token order, fallback tokens and diagnostics. Object inspection confirms the removed destructor call in expression parsing. |
| Keep fresh attribute records at their allocated zero defaults | Resetting attribute type pointers, parameter-slice pointers and inline Any values after reserveSpan already zeroed them | Both the paged and large-block allocation paths zero the entire fresh span. These private helpers have only that fresh-array call chain; absent types, parameters and null values retain identical empty fields. Object inspection confirms the removed Any zero store with the same stack reservation. |
| Decode single-node spans once | A second span setup, another header-size read and the indexed lookup loop for a one-element query | The writer guarantees nonempty chunks for a nonempty span. The existing one-element assertion remains; empty/invalid spans retain the invalid result when assertions are disabled. The page-growth regression checks the query, and the DevMode object has fewer calls and a smaller body and stack frame. |
| Trust masked signed-remainder divisor widths | Rechecking the width and power-of-two predicate and computing a logarithm solely to confirm the width | The divisor has already been masked to the accepted 32/64-bit width. A remaining nonzero power of two necessarily has a shift below that width. New C++ cases cover the highest bit and discarded high stored bits; the object loses the redundant logarithm loop with the same stack reservation. |
| Check signed-remainder eligibility before flag analysis | A suffix walk for candidates already excluded by width, immediate, divisor or register kind | The same cheap eligibility guard now precedes the same dead-flags requirement inside the private fold. Rewriting and fallback decisions remain identical. The original shared dispatch is retained; object inspection shows a smaller body with the same frame. A C++ matrix covers division/remainder, divisors 3/8, live/dead flags and deferred/immediate expansion. |
| Compute byte-array padding once | A remainder/division operation after each padding byte | The initial remainder determines the exact number of existing pushBack operations. Their order, allocation sequence and capacities are unchanged, including general non-power-of-two alignments. An iterative oracle covers reserved and growing buffers; object inspection confirms one initial division and the same total stack reservation. |
| Keep chunk iteration setup minimal | Constructing a complete iterator for each end comparison, its comparison call, and begin-state stores immediately overwritten | An empty sentinel tests the same invalid header reference. The begin iterator receives its final count, geometry and first chunk directly. Iterator/view fields, publication, page order and payloads are unchanged. Default/empty/single/multi-page cases cover all comparison forms; object inspection confirms removed AST end/comparison calls and smaller caller/begin frames. |

The retained changes preserve traversal order, promotion choices, virtual-register
assignment and instruction rewriting. The dominator oracle checks reachability
with a node removed, including loops and disconnected roots. Other regression
cases cover record-byte facts, deferred type-info work, AST pauses and restarts,
semantic-view recomputation, span alignment and page growth, and recursive
call-graph components.

Validation used the checkout-local DevMode compiler and six workers. Every
retained build and completed validation below exited zero; fresh machine-load
admission preceded each command. Each changed compiler used isolated temporary
caches while `SWC_BUILD_NUM` stayed 1173. The default C++ suite excludes the 60
filesystem cases requiring `--dev-full`.

| Validated checkpoint | C++ tests | Additional DevMode checks |
| --- | ---: | --- |
| 3 | 1,419 | Native record case and 299 optimizer tests |
| 6 | 1,421 | Full native: 3,888; full JIT: 1,539; sanity: 85 |
| 7 | 1,421 | Native type-info: 57; JIT reflection: 16 |
| 8 | 1,423 | Three arithmetic semantic sources plus runtime; native countdown case |
| 11 | 1,423 | Full native: 3,889; full JIT: 1,539 |
| 12 | 1,423 | Native relaxed automatic-inlining case |
| 14 | 1,423 | Sanity: 85 |
| 15 | 1,424 | Native dword-join case |
| 16 | 1,424 | Full native: 3,889; full JIT: 1,539; native enum type-info: 2 |
| 17 | 1,424 | New large inline-binding case; four local-function semantic error sources |
| 18 | 1,424 | Full JIT: 1,539 |
| 19 | 1,425 | JIT reflection: 16 |
| 22 | 1,426 | Full native: 3,890; full JIT: 1,539; native SIMD: 51; full semantic suites: 295 normal and 347 expected-error inputs, including runtime |
| 24 | 1,427 | Native positional aggregate case; named-member semantic source; sanity: 85 |
| 25 | 1,428 | New direct/mutual-recursion and incoming-wrapper assertions |
| 26 | 1,429 | Two normal attribute sources and eight expected-error attribute sources, plus runtime |
| 28 | 1,432 | Full native: 3,891; full JIT: 1,539; full semantic suites: 295 normal and 347 expected-error inputs, including runtime |
| 30 | 1,446 | Native `static_control.swg`: 1; semantic `switch` selection: 35 normal and 38 expected-error inputs, including runtime |
| 31 | 1,446 | Native optimizer selection: 302 |
| 32 | 1,446 | Full parser suites: 50 normal and 80 expected-error inputs, including runtime |
| 33 | 1,446 | Native `typeinfo_attribute` selection: 7; JIT `typeinfo_attribute_param.swg`: 1 |
| 34 | 1,446 | Full native: 3,891; full JIT: 1,539 |
| 35 | 1,447 | Native optimizer selection: 302 |
| 36 | 1,448 | Native optimizer selection: 302 |
| 37 | 1,449 | Native optimizer selection: 302 |
| 38 | 1,450 | Full native: 3,891; full JIT: 1,539 |
| 39 | 1,454 | Native `separated_float_products.swg`: 1, with the DevMode compiler and `release` program configuration |

Full native runs include the expected idle, pending and hardware recovery probes.
Semantic suites check source and compile-time assertions without executing
`#test` bodies. Focused semantic selections with no matching error source were
not counted as error coverage.

Representative commands, with additional suite/file selections as listed above:

```text
MSBuild.exe swc.sln /t:Build /m:6 /p:Configuration=DevMode /p:Platform=x64 /p:SwcCompileJobs=6 /nologo /v:minimal
bin\swc.dm.exe unittest --num-cores 6 --verbose-unittest
bin\swc.dm.exe --num-cores 6 tools\unittests.swgs dm native -bc devmode --num-cores 6 --rebuild
```

An initial JIT `compiler` file filter omitted the required allocator-helper source;
the corrected full JIT run passed. The initial Tarjan regression fixture omitted
four Swag statement separators; it was corrected before retention and now checks
parsing errors before its graph assertions. Formatting and `git diff --check`
passed for retained changes. No benchmark was run; Release-compiler validation is
limited to the SmallVector lifetime repair below.

Checkpoint 28 includes the prompt-2 immutable-parameter loop-read change imported
at `205ac08ff3`. SmallVector checks also include the later immutable-field-address
propagation imported at `a21d518c77`.
Checkpoint 30 additionally exercises the memory-flags and TLS-context changes
imported at `b5cba4d47a`.
Checkpoint 35 includes the composite address-scale legalization and encoder case
imported at `ab03d9dbce`.
Checkpoint 39 includes the reloaded-factor FMA and sibling-copy forwarding changes
imported at `e2b7ff1f54`; its native program configuration enables FMA contraction.

A new SmallVector regression first exposed a leaked live prefix when copy
construction failed. The repair cleans partial construction and raw allocations,
keeps contiguous live elements after interrupted insertion or erasure, preserves
borrowed element arguments through growth, and reports fallible inline moves
accurately through C++ traits. Copy operations require copyable elements, so
standard containers can relocate vectors of move-only elements. The inline
storage, object fields and capacity policy are unchanged. These correctness
changes are not claimed as compilation-speed gains.

The checkpoint-29 DevMode C++ suite passes 1,445 tests, including twelve SmallVector
regressions for inline and heap storage, aliasing, interrupted constructors,
assignments and iterator traversal, and move-only elements. Both compiler builds
pass with the same six-worker bound. DevMode also passes the full native suite
(3,891 tests) and JIT suite (1,539 tests). The Release compiler passes 302 native
optimizer tests in the `devmode` program configuration:

```text
MSBuild.exe swc.sln /t:Build /m:6 /p:Configuration=Release /p:Platform=x64 /p:SwcCompileJobs=6 /nologo /v:minimal
bin\swc.exe --num-cores 6 tools\unittests.swgs native -bc devmode --file-filter optimizer --num-cores 6 --rebuild
```

Checkpoint 39 repairs a separate SmallVector compatibility defect: the borrowed-fill
probe called an element's overloaded unary `&`. A deleted operator reproduced a
compilation error before the change. `std::addressof` now obtains the actual object
address; two regressions cover deleted and misleading operators, including a fill
borrowed across growth. This changes no storage or lifetime algorithm and is not
claimed as a speed gain. Its DevMode C++ suite passes 1,454 tests.

The compilation-time targets remain unverified. This is not a claim that the speed
campaign has exhausted every possible structural saving.
Worklist visitation changes were left aside because changed early-exit priority
would require measurement to establish a saving.
An additional register-kind predicate on every definition was also left aside:
only refining the already-required base and preferred-register predicates avoids
an extra test on valid candidate definitions.
Packing entry-escape bytes into frame ranges was discarded: eager state initialization
and strided writes would require measurement to establish a CPU saving.
Lazy default-value insertion was discarded: object inspection showed an additional large insertion specialization, leaving a code-footprint tradeoff for measurement.
Reusing unique dense-index lists for access scores was discarded because the original use/definition lists intentionally retain repeated occurrences.
Splitting the signed-operation dispatch was discarded because of generated stack/code growth; the retained eligibility guard keeps the original shared dispatch.
Processing the first low-bit worklist item outside its vector was discarded because its generated stack grew.
Batching integer-byte appends was discarded because some generated frames grew; only the padding-count change was retained.
