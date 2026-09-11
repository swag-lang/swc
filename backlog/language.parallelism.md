# Native Parallelism and Concurrency

This domain owns the native concurrency model: structured tasks, checked memory access, parallel
computation, suspension, cancellation, and the runtime contract that connects them. It covers
both simultaneous CPU execution and concurrent operations that mostly wait.

The first stage has shipped: `parallel for` is a language statement, and `bin/runtime` owns the
worker pool, tasks, groups, locks, conditions, and atomics that every module and application now
uses. What remains here is the part that is still design plus implementation. Shipped behavior is
documented in the language reference and in the runtime sources, not here.

All new Swag types of this concurrency system belong to `bin/runtime`. Library algorithms and
consumer migration stay in [std.core.md](std.core.md), general memory-safety prerequisites in
[compiler.safety.md](compiler.safety.md), and operating-system adapters in
[platform.portability.md](platform.portability.md).

## Vocabulary

| Term | Meaning in this domain |
| --- | --- |
| Task | A logical computation owned by a group or supervisor, with one eventual terminal outcome. |
| Group | An owner that limits child lifetime, propagates policy, and joins accepted work before releasing its resources. |
| Operation | An awaitable action, such as a receive or I/O request; it need not allocate another task. |
| Executor | The authority that schedules accepted continuations under a placement and affinity contract. |
| Region | Storage and aliases connected by ownership/access relationships that the compiler must track. |
| Isolation domain | An authority that controls access to mutable state; it is not necessarily a dedicated physical thread. |
| Cancellation | A request to stop, whose acknowledgement and cleanup occur before actual completion. |
| Data race | Conflicting unsynchronized accesses to the same memory, with at least one write. |
| Logical race | An incorrect result caused by operation ordering, even when all memory accesses are synchronized. |

## Entries

### language.parallelism.010 — Nothing detects a data race while the program runs

- Recorded: 2026-09-08 20:14
- Updated: 2026-09-11 22:31 — Name the current guarded configuration accurately.
- Evidence: .005 states that a capture list is written rather than proved, and names the two cases
  that still compile: two partitions writing the same element, and a captured pointer whose
  pointee is mutated elsewhere. Neither is caught at run time either. The `devmode` configuration
  checks allocation lifetime and bounds, and the sanity pass reasons inside one function's flow,
  but no configuration records happens-before edges between threads. A race in a partitioned loop
  therefore surfaces as an occasional wrong pixel or an intermittent crash somewhere unrelated,
  which is the shape of several intermittent defects already recorded in this repository.
- Next: choose the instrument before writing it. Only a checker that knows the runtime's own
  synchronization points -- lock, unlock, atomic operation, submission, completion, join, and
  partition boundary -- can see the edges this runtime creates, so the shadow state belongs
  beside the scheduler rather than in a foreign tool. Scope it to one build configuration with a
  stated slowdown budget, start from the accesses the compiler already instruments for bounds and
  lifetime, and decide what it does with a foreign call, which is opaque to it for the same reason
  it is opaque to compiler.safety.007.
- Complete when: a test writing one element from two partitions fails deterministically in that
  configuration, naming both accesses and the edge that is missing between them, and a correct
  partitioned loop reports nothing.
- Elsewhere: Go ships `-race`, C++ and Rust use ThreadSanitizer, and Rust adds `loom` for
  exhaustive interleavings of a small structure. A language that claims checked memory access
  without a dynamic detector claims it only as far as its static analysis reaches.
- Related: language.parallelism.005, language.parallelism.007, compiler.safety.007,
  compiler.safety.014

### language.parallelism.009 — Cancellation stops at one group and has no deadline

- Recorded: 2026-09-08 20:14
- Updated: 2026-09-10 20:06 — Distinguish cancellable blocking waits from async suspension.
- Evidence: `Swag.TaskGroup.cancel` raises one flag that only the children of that group can read,
  and only through a captured reference to the group. A child that opens a group of its own gets
  a fresh flag, so the outer request never reaches the grandchildren. `Swag.Task` carries no
  cancellation state at all, `parallel for` carries none, and no task, group or loop carries a
  deadline: a program that wants to stop after a duration polls a clock it wrote itself. The
  request is also invisible to every wait. `Swag.Condition.waitFor` expires on its own timeout
  without consulting it, and `Swag.Semaphore.acquire` and `Swag.Barrier.arrive` cannot be woken
  by it.
- Next: decide where the state lives before adding to it -- ambient state the runtime propagates
  into every child, or a value each spawn is handed explicitly. Then propagate it through nested
  groups, give `parallel for` and `Swag.Task` a way to read it, and make a deadline one more
  source of the same request rather than a second mechanism. State the boundary at the waiting
  primitives instead of implying it: today `acquire` has no cancellation input or wake path.
  A cancellation-aware blocking wait can return early without async suspension; define its
  wake registration, permit-consumption race, and cleanup independently of .002.
- Complete when: cancelling an outer group is observed by a grandchild, a deadline produces the
  same observable request, and a cancelled tree joins with every borrowed resource still valid.
- Elsewhere: Swift propagates cancellation to every child task and exposes it as task-local
  state; Kotlin cancels a `Job` together with its children; Java's `StructuredTaskScope` and
  .NET's linked `CancellationTokenSource` both build the tree explicitly. All four are
  cooperative, and none of them stops at one level.
- Related: language.parallelism.001, language.parallelism.002, language.parallelism.003

### language.parallelism.011 — No channel abstraction

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-10 19:32 — Move the runtime channel contract from the Core integration domain.
- Historical provenance: moved from retired std.core.026.
- Evidence: no typed channel defines transfer, capacity, close, cancellation, and selection
  together. A producer and a consumer that need one build it from `Swag.Mutex` and
  `Swag.Condition` by hand, which is what the Swag Scope video queue does.
- Next: define the bounded, rendezvous, and one-shot forms in `bin/runtime`, with their endpoint,
  selection, and rejected-message types. Settle endpoint clone and drop behavior, draining after
  close, ownership of a moved message rejected before acceptance, and the single commit point of a
  selection before adding any Core convenience function.
- Complete when: focused channel and selection tests cover backpressure, closure, cancellation,
  simultaneous readiness, and withdrawal without a lost message or a duplicate consumption.
- Related: language.parallelism.002, std.core.025

### language.parallelism.001 — The shipped model, and the promises it does not yet make

- Recorded: 2026-09-06 07:51
- Updated: 2026-09-10 18:33 — Refresh remaining workload, application and foundational-entry claims.
- Where it stands: `parallel for |captures| name in range` is a statement of the language, lowered
  to a runtime range call, with fallible variants under `try`, `catch` and `expect`.
  `bin/runtime` owns the worker pool, `Swag.Task`,
  `Swag.TaskGroup`, `Swag.Mutex`, `Swag.RWLock`, `Swag.Condition`, `Swag.Semaphore`,
  `Swag.Barrier`, `Swag.AtomicValue` and `Swag.AtomicFlag`. One process has one pool, resolved
  through a process anchor so an executable and every shared library it loads share it. `Core.Jobs`
  is gone and every consumer -- pixel, truetype, video, gui, the four applications, the examples
  and the scripts -- goes through the runtime.
- What the model does not yet promise: race freedom. The capture list is written, not proved
  (.005); a partition can fail but cannot state disjointness (.004); there is one executor and
  no affinity (.003); nothing suspends and a task carries no typed result (.002). A program can
  still write a data race through a capture, and the compiler accepts it.
- Next: the four foundational entries (.002 through .005) remain, in dependency order:
  suspension and typed results, then executors, then partition proofs, then checked captures.
  Keep this entry as the place that states the whole contract, and let each of them own its part.
  Do not advertise race freedom in the reference or in the runtime documentation until .005 holds.
- Complete when: those four foundational entries are closed and the language reference states one contract for
  ownership, suspension, cancellation, failure and memory access that the compiler enforces.
- Related: std.core.025, language.parallelism.011, std.core.028, compiler.safety.005, compiler.safety.006,
  compiler.safety.007, compiler.safety.014, runtime.allocator.004, platform.portability.035.

#### Progress and memory-model boundaries that already apply

These hold for the shipped model and constrain every entry in this domain.

| Construction | Progression boundary |
| --- | --- |
| Finite independent kernels and descendant-only fork/join | Completes with one worker if the sequential computations terminate and the executor services ready work. A `parallel for` and a joined `Swag.TaskGroup` are in this class. |
| Ranked locks | Prevent acquisition cycles only while all acquisitions obey the declared order. Nothing declares one yet. |
| Explicit task graph | Reject cycles when constructing or extending the dependency graph; other waits in node bodies need their own contract. |
| General channels, promises, actors, leases | Safe memory access does not prove the communication protocol terminates. |
| Foreign waits and external systems | Require explicit backend contracts; no universal deadline or deadlock guarantee. |

Concurrent conflicting non-atomic access is invalid. Atomics do not create multi-location
transactions, and an atomic pointer algorithm still needs a valid reclamation protocol and a
lifetime proof. Default atomics are sequentially consistent; acquire/release/relaxed orders remain
expert operations that do not inherit that claim, and none are exposed yet.

A joining thread can claim the queued task it is waiting for, and that task can join its own
children in turn. It does not execute unrelated ready tasks: a guard held across a join must
not be reentered by an unrelated callback. With no worker, submission executes synchronously.
An explicit `Swag.drainWork` still runs arbitrary accepted work and needs a context that permits
that reentrancy. Joining a task that itself needs a held lock can still deadlock; targeted helping
does not prove a task dependency graph or lock ordering correct.

A join briefly polls a running child, then parks on the process scheduler's completion condition.
A parked observer first publishes the address of the node it waits for, and a completion consults
that registry instead of the node it has just released: an owner can already have reused or freed
its node, so nothing reads it once Done is published. A completion therefore wakes observers only
for a node somebody waits for, and every woken observer still rechecks its own state. A process
with more parked observers than registry slots falls back to waking all of them, which is correct
and unselective. Parking reduces waiting CPU use but still occupies the calling thread and any
worker that called the join. It is not the stackless suspension or executor capacity release required by .002 and .003.

The scheduler's artifact-local cache publishes its pointer atomically after serialized first use.
The worker count is also atomic, while roster growth stays under the pool mutex; callers can
submit and inspect the pool while other callers increase its size. Runtime shutdown still assumes
its users have quiesced: atomic publication is not an admission or cancellation protocol for late
submissions during teardown.

Native `parallel for` now keeps bounded atomic cost hints keyed by the generated body's entry
address. An unknown body samples one actual iteration before starting workers; later calls use
the estimated work per partition and periodically refresh it. Empty and single-iteration ranges
need no pool. An already started pool with fewer than two workers skips profiling entirely;
the observation starts no execution resource, and later calls see concurrent pool growth.
Partition storage lives in a separate, non-inlined dispatch function, so serial and empty calls
do not reserve the full worker array or probe its stack pages. The dispatch function keeps one
runner per chosen worker and joins every accepted runner before releasing that storage.
Runners claim disjoint blocks through an atomic
cursor; the whole range uses at most eight times as many blocks as runners, and the measured
grain still sets their minimum size. The caller reserves its first block before publication and
participates in the remaining claims. Each successful claim clamps its end before addition, even
when the exclusive range end is `U64.Max`. An unusually expensive individual iteration or block
can still dominate completion; blocks are not preempted or split after a claim.
Hints retain no captured storage, and concurrent observations only affect placement.
The fixed table probes at most four slots and never replaces an owner. If none accepts the body,
the current call still samples its own cost, without caching it. Variable costs,
preemption and stale observations can still choose an inefficient schedule; this is not a time
bound or a proof that parallel execution will help. Resize, Argon2 and ChaCha20 no longer carry
separate small-work thresholds. The pixel-filter and Argon2 benchmarks measure both cheap ranges
and expensive four-iteration ranges against one-worker controls.
CPU rasterization now exposes sixteen-row blocks instead of one band per worker, so the runtime
can distribute localized overdraw. Triangle order stays fixed within each pixel, with exclusive
ownership of its color, stencil and overlap scratch rows until the join. The renderer retains its
pixel-area threshold and whole-range serial path to amortize repeated triangle setup; its small
draw path returns before querying or starting the pool. `bench/rasterbalance` compares complete
one-worker and four-worker images, including uniform and localized-overdraw controls.

#### Workloads still to be answered

These remaining workloads are acceptance cases for the entries in this domain.

| Workload | Desired expression | Adversarial case to settle | Evidence required |
| --- | --- | --- | --- |
| Bounded streaming pipeline | Transferred buffers and finite-capacity channels. | Consumer stops while producer is blocked; one stage fails after a partial transfer. | Every buffer and rejected message has an owner; failure closes and drains the pipeline under its stated policy. |
| Recursive CPU work | Nested structured tasks or parallel partitions. | One worker and an exhausted task-lifetime quota. | No hidden quota wait cycle, bounded bookkeeping, and equivalent completed results. |
| Dependency graph | Typed nodes with explicit result edges. | A dynamic edge introduces a cycle, or one node awaits an unrelated external event. | Cycle rejection for graph edges; no false claim that arbitrary node bodies are deadlock-free. |
| Foreign blocking operation | A task scheduled on the blocking or dedicated executor. | The operation ignores cancellation or synchronously calls back into the host. | Borrowed resources survive; callback and runtime attachment stay valid; no unsupported timeout bound is promised. |
| Lock-free shared structure | Typed atomics with a reclamation domain. | ABA, a stalled reader, and reclamation during shutdown. | Storage lifetime is justified separately from atomic ordering; the unchecked implementation boundary is explicit. |
| Latency-sensitive audio | Dedicated execution, preallocated memory, no-allocation and no-wait contracts. | A device callback that must never allocate or block. | The contract is checked rather than documented; no hard real-time guarantee is claimed on a general-purpose operating system. |

For each case, record the source size, annotations, explicit clones, unchecked escapes,
allocations, and runtime costs the preferred path needs. A short keyword example is not evidence
of simplicity when every useful helper needs an unchecked contract.

#### Validation that every entry here inherits

- Semantic tests accept safe transfers and partitions and reject hidden aliases, cross-module
  global writes, escaped borrows, incompatible callable effects, and wrong-executor destruction.
  A guarantee that only a warning or a devmode guard enforces is not the guarantee.
- A runtime-only consumer declares and uses the concurrency types without importing Core, and a
  sequential program starts no execution resource it never asked for.
- Native and JIT lifecycle tests cover every exit after capture, including failed admission before
  capture, a failing later capture after an earlier move, and serial fallback after partial
  dispatch.
- A controlled scheduler and a fake backend enumerate cancellation before publication, during
  registration, at commit, after completion, and during cleanup, together with simultaneous
  completions, withdrawn channel operations, producer abandonment, and late native callbacks.
- Runtime tests distinguish one worker from several, nested fork/join, quota exhaustion, pool
  shutdown, and a stalled foreign call. Soundness is not inferred from stress testing.
- Consumer evidence comes from a real pixel operation, a real GUI background lifecycle, and a real
  native-affinity operation. Measure creation and join cost, memory per live task, queue
  contention, cancellation latency under stated cooperation assumptions, serial thresholds, and
  throughput against what the code did before.
- Every implemented syntax change updates the language reference, the editor grammar, the
  formatter and the relevant diagnostics together. Compiler-source changes increment
  `SWC_BUILD_NUM`; serialized effect summaries and runtime ABI changes invalidate incompatible
  cached artifacts.

### language.parallelism.006 — One locked ready stack, so fine-grained work does not scale

- Recorded: 2026-09-08 20:14
- Updated: 2026-09-08 21:10 — the benchmark exists, the completion path is fixed, and what remains
  is the ready stack itself
- Evidence: `bench/scheduler` prices one submission at six grains, concurrent submission with and
  without a task group's own storage, a nested region against its flat equivalent, and one
  completion beside parked observers, at 1, 2, 4, 8 and every worker. Its README states the
  alternating-worktree protocol these numbers need on this machine, where two runs of one binary
  differed by a factor of three while another agent was building.
- Evidence: completion was the largest cost and is gone. A finished unit used to wake every parked
  observer in the process, so 20,000 short tasks beside 22 parked observers took 646 ms against
  3.6 ms unobserved. Each parked observer now publishes the node address it waits for, and a
  completion wakes only for a node someone waits for: the same stream costs 4.1 ms and is flat in
  the number of observers, with a measured ratio of 0.01 at 22 observers and 0.35 at one.
  Fine-grained fork/join follows from the same cause, because a joining thread that parks is an
  observer: 1.4 to 3 times faster below eight workers. A group also holds its first four children
  itself and fills the page each further block already reserved, which is 27% off a group's spawn
  at one worker while the plain-task control stays where it was.
- Evidence: what remains is the ready stack. Every `submitWork` takes one process-wide mutex to
  push and every `popWork` takes it to claim. Fork/join over 64-element leaves costs 115 ms on 22
  workers against 13.7 ms on one, and spawn throughput falls from 2.1 to 0.5 children per
  microsecond over the same range. Every candidate ratio returns to one at 22 workers. The
  machine's three classes of core are part of that number, and nothing in the pool knows they
  exist.
- Settled here: the worker cap stays at 64, because a parallel range reserves one runner per worker
  in its dispatch frame, so the cap is also the stack every parallel section touches; raising it
  means moving that storage off the stack first. Nesting stays supported and unrestricted, because
  one process has one pool and an inner region therefore cannot multiply execution resources; it
  measured within a fifth of the flat range that does the same work.
- Next: shard the ready list so that a submission and a claim do not serialize on one lock -- one
  list per shard with its own lock, the shard chosen from the node's own address so a targeted
  claim still finds it in constant time, and an idle worker scanning the other shards. Keep it only
  against the benchmark's alternating protocol on a quiet machine, and settle in the same change
  whether a worker should spin before parking and whether the pool should know which class of core
  it was placed on.
- Complete when: fork/join over 64-element leaves stops getting slower as workers are added, and
  spawn throughput stops falling between one worker and every worker.
- Elsewhere: Rayon, Intel TBB, Java's `ForkJoinPool`, .NET's thread pool and the Go runtime all
  give each worker its own deque and steal from the others, which is what makes recursive fork/join
  cheap.
- Related: language.parallelism.001, language.parallelism.003, language.parallelism.005

### language.parallelism.005 — Captures do not prove task lifetime or race freedom

- Recorded: 2026-09-07 15:52
- Updated: 2026-09-08 21:10 — the group case that demonstrated the linked-storage gap is now rejected
- Evidence: borrow analysis follows named and initialized captures, including addresses, field
  references, slices, aggregates and deferred call-result summaries. It rejects the tested local
  borrows returned in a closure or stored in a task from an outer lexical scope. Local destructor
  ordering also matters: a task declared before its captured source joins after that source is
  destroyed. Borrow merges retain the shortest local lifetime across captures, fields and flow
  alternatives. The unexecuted regression cases are in
  `bin/unittests/sanity/borrow_escape_drop_order.swg`. This does not
  establish race freedom: two partitions writing the same element and a captured pointer whose
  pointee is mutated elsewhere still compile.
- Remaining lifetime gap: `store(task: *Swag.Task)` can declare a local and submit a closure
  borrowing it into the caller's task. This is accepted even for `func|&local|()`, independently
  of initialized captures. `intoArgumentOutlivesStored` deliberately exempts destinations reached
  through a caller parameter to allow transient borrowed state. A local source has no caller
  parameter origin, so the deferred summary cannot move this check to the caller. The unexecuted
  `storeTaskParameterGap` case in `bin/unittests/sanity/borrow_escape_capture.swg` keeps the gap
  visible without running a dangling task.
- Linked-storage gap: the group no longer demonstrates it. `Swag.TaskGroup` holds its first
  children itself, so `reserveChild` can return a pointer into the group, `spawn` feeds a
  stores-into-group summary, and `groupBeforeCapture` in
  `bin/unittests/sanity/borrow_escape_drop_order.swg` is rejected with its expected diagnostic.
  The rule itself did not change: only block pointers carry owned payload, because treating every
  `*T` as owned would confuse parent and callback back-references with ownership, so a child
  reached solely through `blocks: *GroupBlock?` is still invisible to the ownership analysis.
  Find or build another case before extending the rule to linked storage.
- Both `Swag.Task.opDrop` and `Swag.TaskGroup.opDrop` join their work, including on early return
  and failure. An owner can still release a borrowed field in its own destructor before the
  implicit destruction of its task field; it must join before releasing that storage.
- Next: follow owned linked storage through accessors, with both an owned child and a non-owned
  parent pointer as regression cases. Distinguish a borrow retained past a helper's return from
  transient borrowed state before removing the caller-parameter exemption. Cover both a retained task closure and a helper that
  clears temporary state before returning. Then infer transferable (`Send`) and shared-readable
  (`Sync`) properties from fields, allocation, copy, move and destruction effects, and require
  them at captures. `NoCopy` does not imply `Send`, `const` does not imply deep immutability, and
  an atomic reference count does not synchronize its pointee. Raw pointers, opaque owners, native
  handles and foreign calls need a stated contract rather than automatic acceptance.
- Complete when: a rejected capture names the concrete alias, allocator, destructor or executor
  constraint and points at a valid partition or ownership alternative; semantic tests reject
  hidden aliases, escaped borrows and cross-module global writes without optional analysis.
  Until then the capture list states intent rather than proving race freedom.
- Related: compiler.safety.005, compiler.safety.006, compiler.safety.007, compiler.safety.014,
  language.parallelism.001.

### language.parallelism.008 — A parallel loop cannot combine per-partition results

- Recorded: 2026-09-08 20:14
- Evidence: every partition of a `parallel for` receives the same captures. A loop that computes
  one value -- a sum, a maximum, a count, a first match, an accumulated bounding box -- cannot
  say that each partition needs its own accumulator and that the accumulators combine at the
  join. Consumers write one of two workarounds: an atomic on the shared destination, which
  serializes the loop's hot line and, with `AtomicValue.store` lowered to a locked exchange,
  pays a full barrier per iteration; or an array indexed by a partition number the language does
  not expose, which forces the body to know the partitioning it is explicitly told not to depend
  on.
- Evidence: the general escape, one accumulator per thread, is also expensive. `tls` lowers a
  thread-local global to a runtime call per access, measured at 4 ns against 1 ns for a plain
  global read (runtime.allocator.002), and the per-thread block is released at thread exit
  without running `opDrop`, so it can only hold a plain value.
- Next: design the combining form as part of the statement, stating the identity, the
  per-partition storage and the combining operation together, and combining at the join rather
  than in the body. Settle whether the operation must be associative and commutative or only
  associative -- a floating-point sum is neither -- and say what result the program is entitled
  to when it is not. Decide whether the form is a clause of `parallel for` or a value the
  statement produces.
- Complete when: a parallel sum, a parallel maximum and a parallel bounding box are written
  without an atomic on the hot line and without indexing a partition, and a single-worker run of
  the same source produces the same value the loop promises.
- Elsewhere: OpenMP has `reduction(+:x)` and user-declared reducers; Rayon, .NET PLINQ and Java
  streams reduce through the iterator; Chapel writes `+ reduce`. All of them treat reduction as
  the second data-parallel primitive after the map, not as a library afterthought.
- Related: language.parallelism.001, language.parallelism.004, std.core.025

### language.parallelism.007 — The memory model is a design note, and only sequential consistency exists

- Recorded: 2026-09-08 20:14
- Evidence: what a program may assume about ordering is written in this file and in scattered
  documentation comments, not in the language reference. `Swag.AtomicValue` exposes `load`,
  `store`, `exchange`, `compareExchange` and the arithmetic and bitwise forms, all lowered to
  the sequentially consistent `Swag.atom*` intrinsics; `store` is a locked exchange. No acquire,
  release or relaxed order is reachable and no fence exists. Nothing states the happens-before
  edges a program may rely on either: lock release to lock acquisition, submission to body
  start, body end to observed completion, `parallel for` entry to its join, atomic store to
  atomic load.
- Evidence: the absence costs on both sides. A reference count, a publication flag or a work
  cursor pays a full barrier where an acquire or a relaxed increment is what the algorithm
  needs; and a consumer reasoning about a lock-free structure has nothing normative to reason
  against, which is the same gap `compiler.safety.014` names for the safe subset.
- Next: write the model first, as a reference page: which operations create edges, what a data
  race is, and what an invalid program is entitled to. Then expose the orders on the atomic
  operations, keeping the sequentially consistent form as the default and documenting the weaker
  ones as expert operations that do not inherit the default's claim. Decide in the same change
  whether Swag keeps the C++ family of orders or a smaller set, and whether atomic storage may
  ever be reached by an ordinary access.
- Complete when: the reference states one memory model, both the native backend and JIT execution
  respect it, and one lock-free consumer uses a weaker order with a stated justification.
- Elsewhere: Java and Go publish memory models as part of the language definition; C++11 and Rust
  share one order family; Swift and C# state theirs against their runtime. None of them leaves
  the model in a design note.
- Related: language.parallelism.001, compiler.safety.014, std.core.031

### language.parallelism.004 — Partitions cannot prove disjointness

- Recorded: 2026-09-07 15:52
- Updated: 2026-09-08 13:54 — narrow the remaining work to checked partition views
- Evidence: `try/catch/expect parallel for` now carries failures across the join, but there is
  still no way to express an exclusive view of part of a container. Consumers index captured
  buffers, including H.264 reconstruction, and the compiler proves nothing about those indices.
- Next: add exclusive row, tile, chunk, stride, split and zip views with bounds and overlap
  contracts, and a checked partition constructor for the cases static proof cannot reach. That
  validation is semantic input checking, not a release-disabled guard. Read-only source halos
  beside disjoint destination tiles must be expressible, because stencils and image transforms
  need them. Preserve the fallible loop's join and partial-effect contract while adding views.
- Complete when: a partitioned image operation needs no manual indexing into a captured buffer,
  overlapping mutable views are rejected, and success still means every index ran exactly once.
- Related: std.pixel.md, language.parallelism.001.

### language.parallelism.003 — One executor, one placement

- Recorded: 2026-09-07 15:52
- Updated: 2026-09-07 17:26 — a barrier among pooled tasks deadlocks, which is the sharpest
  evidence that the pool is the wrong owner for anything that waits for another task
- Evidence: a `Swag.Barrier` with four participants, entered by four `Swag.TaskGroup` children,
  hangs. The pool decides how many children run at once; a participant then waits for one the
  pool has not started, and the waiting participants occupy the workers that would start it.
  Under compile-time execution, where the count is zero, the first child blocks the only thread.
  The same reasoning applies to `Swag.Semaphore.acquire` and `Swag.Condition.wait`: a waiting
  thread runs no ready work, so what it waits for must already be running. The three
  documentation comments now say so, and the suite test uses one participant.
- Evidence: `Swag.setWorkerCount` sizes one general pool and `Swag.startWorkers` starts it. There is
  no main/UI executor, no blocking executor, no dedicated-thread executor, and no way to require
  that a value is created, used and destroyed on one thread. Consumers that need thread affinity
  still own a `Core.Threading.Thread` of their own -- the video frame threads, the audio device,
  and the GUI event loop -- so the process runs the runtime pool beside private threads instead of
  one scheduler.
- Next: define the executor contract before adding a second executor: affinity, accepted operation
  kinds, completion ownership, and what happens when submission fails or shutdown starts. Then add
  the main/UI, blocking and dedicated-thread executors and the affinity restriction that makes a
  native handle's use and destruction stay on its thread, including during cancellation and
  shutdown. A bounded blocking executor does not promise progress for mutually dependent foreign
  calls; document and test that boundary.
- Complete when: a thread-affine resource is created, used and destroyed on its required executor
  under a shutdown that races its last callback, and the UI executor keeps servicing completion
  and destruction while it drains.
- Related: platform.portability.035, std.audio.md, std.video.md.

### language.parallelism.002 — No suspension, and no typed task result

- Recorded: 2026-09-07 15:52
- Evidence: [Swag.Task](../bin/runtime/task.swg) runs an infallible closure and reports only that it
  finished. A consumer that produces a value writes it into captured storage and reads it after
  the join, which is what `Viewer.BackgroundLoad` and `Gui.PdfView` do; a consumer that fails
  stores the error beside the value. Nothing suspends: a task that waits occupies its worker for
  the whole wait, so `Swag.workerCount` also bounds how many operations can be in flight.
- Next: settle the suspension gates before implementing. Fix the `async`/`await` grammar, the
  effect in the callable type, stackless frame ownership, stable frame addresses, and the async
  boundary for both native and JIT execution. Decide whether cancellability is a separate control
  effect or an outcome carried by `fail`, and what `try`, a catch-all, `defer #fail` and
  `defer #nofail` observe. Then give the runtime a typed `Task'T` whose result is owned and
  consumed once, with failure and cancellation as terminal outcomes beside success.
- Complete when: a `Task'T` transfers its result or its failure to exactly one observer, an
  awaiting task releases its worker, and native and JIT lifecycle tests cover every exit after
  capture: immediate completion, a suspended frame, a cancelled waiter whose child still owns a
  loan, and destruction exactly once.
- Elsewhere: [Swift structured concurrency](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0304-structured-concurrency.md)
  scopes child-task lifetime; [Go's memory model](https://go.dev/ref/mem) makes synchronization and
  happens-before part of the language contract. These are references for separate decisions, not a
  proposal to import one language's complete model.
- Related: std.core.025, std.core.028, language.parallelism.001.
