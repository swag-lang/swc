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

### language.parallelism.005 — Captures do not prove task lifetime or race freedom

- Recorded: 2026-09-07 15:52
- Updated: 2026-09-08 19:12 — distinguish destructor ordering from caller-owned and linked-storage lifetime gaps
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
- Linked-storage gap: `TaskGroup.spawn` stores the closure into a child reached through
  `reserveChild`, but `blocks: *GroupBlock?` is a single-object pointer. The ownership analysis
  deliberately treats only block pointers as owned payload carriers; treating every `*T` as
  owned would confuse parent and callback back-references with ownership. The child's storage
  therefore does not feed a stores-into-group summary, so `groupBeforeCaptureGap` in the same
  regression file remains accepted. It is never executed. Track the allocation's attachment to
  the group and its release before extending the ownership rule to linked storage.
- Both `Swag.Task.opDrop` and `Swag.TaskGroup.opDrop` join their work, including on early return
  and failure. An owner can still release a borrowed field in its own destructor before the
  implicit destruction of its task field; it must join before releasing that storage.
- Next: follow owned linked storage through accessors, with both an owned child and a non-owned
  parent pointer as regression cases. Distinguish a borrow retained past a helper's return from transient borrowed state before
  removing the caller-parameter exemption. Cover both a retained task closure and a helper that
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

### language.parallelism.001 — The shipped model, and the promises it does not yet make

- Recorded: 2026-09-06 07:51
- Updated: 2026-09-08 17:52 — distinguish parked task joins from asynchronous suspension
- Where it stands: `parallel for |captures| name in range` is a statement of the language, lowered
  to a runtime range call, with fallible variants under `try`, `catch` and `expect`.
  `bin/runtime` owns the worker pool, `Swag.Task`,
  `Swag.TaskGroup`, `Swag.Mutex`, `Swag.RWLock`, `Swag.Condition`, `Swag.Semaphore`,
  `Swag.Barrier`, `Swag.AtomicValue` and `Swag.AtomicFlag`. One process has one pool, resolved
  through a process anchor so an executable and every shared library it loads share it. `Core.Jobs`
  is gone and every consumer -- pixel, truetype, video, gui, the three applications, the examples
  and the scripts -- goes through the runtime.
- What the model does not yet promise: race freedom. The capture list is written, not proved
  (.005); a partition can fail but cannot state disjointness (.004); there is one executor and
  no affinity (.003); nothing suspends and a task carries no typed result (.002). A program can
  still write a data race through a capture, and the compiler accepts it.
- Next: the other four entries are the remaining work, in the order they unblock each other:
  suspension and typed results, then executors, then partition proofs, then checked captures.
  Keep this entry as the place that states the whole contract, and let each of them own its part.
  Do not advertise race freedom in the reference or in the runtime documentation until .005 holds.
- Complete when: the four entries are closed and the language reference states one contract for
  ownership, suspension, cancellation, failure and memory access that the compiler enforces.
- Related: std.core.025, std.core.026, std.core.028, compiler.safety.005, compiler.safety.006,
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
Registration and completion coordinate through the scheduler mutex, and completion never reads
the node after publishing Done: an observer can already have reused or released it. Every
registered observer rechecks its own node after a wake, including when an unrelated task finishes.
This reduces waiting CPU use but still occupies the calling thread and any worker that called the
join. It is not the stackless suspension or executor capacity release required by .002 and .003.

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

The first three rows shipped. The rest are the acceptance cases the entries above must satisfy.

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
