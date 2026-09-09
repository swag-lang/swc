# Compiler Backlog

This backlog covers the compiler front end, back end, workspace build engine, and editor-facing compiler services. Documentation, formatting, and language-design work have their own domain files. Only unfinished work belongs here; completed investigations and implementations remain discoverable through Git history.

Items are ordered from the most recently updated down. Every completion condition is intended to be testable. Measurements below are a dated baseline, not permanent product claims.

As of 2026-09-04, excluding the vendored `src/Support/Memory/mimalloc` tree, `src/` contains 266,719 physical lines in 685 `.cpp` and `.h` files. `src/Compiler/Sema` accounts for 85,710 lines in 154 files. The compiler diagnostic catalog contains 561 ids carrying 643 message variants, and `swc format --dump-config` exposes 133 options. Recompute these figures when using them to prioritize work.

### compiler.core.032 — Repeated module builds publish different borrow summaries

- Recorded: 2026-09-07 10:43
- Updated: 2026-09-09 07:06 — the instability decides whether a real borrow escape is reported:
  three rebuilds out of four missed one
- Found while: checking public-export equivalence during the standard-module compilation campaign.
- Evidence: four complete `core` rebuilds with the same frozen Release 0.1.390 binary, identical
  tracked sources, `devmode`, and six workers alternated between publishing and omitting
  `BorrowSummary(0, 0, 0, 0, 1, 0)` on both `Core.Math.Curve.addKey` overloads. The foreign symbol
  names stayed identical. Both A and B in the recorded control refer to the same executable and
  SHA-256; one of four warm rebuild snapshots omitted the attributes. This predates the campaign's
  compiler changes. [Raw control data](../bench/results/compilation/20260907/api-baseline-repeats.json)
  includes the full foreign-attribute lines and commands.
- Evidence (2026-09-09, six workers, devmode, `swc tools/std.swgs dm test core --rebuild`): the
  same tracked sources and the same compiler binary produced seven
  `borrowed data from local variable 'buffer' escapes through a stored call argument` errors in
  one rebuild and none in the three that followed it, with no edit in between. The sites were
  `core`'s own tests, `tests/serialization/tagbin_itfarray.test.swg:142` among them, on a
  `ConcatBuffer` passed to `encoder.writeAll`. `fdf901acc` then outlived those encoders by the
  buffers they borrow, in exactly those three files, which settles what the runs disagreed about:
  the diagnostics were right and three rebuilds out of four failed to produce them. So the
  instability is not a cosmetic difference in an exported attribute. It decides whether a real
  escape is reported at all, and a suite that passes says nothing about the run that follows.
- Observation: `ModuleApiExport.Generate.cpp::collectMissingFunctionAttributes` serializes the
  summary masks. `Symbol.Function.h` says body sema and the final summary fixpoint grow those
  masks. The ordering or publication defect has not yet been isolated.
- Next: reproduce from the failing side rather than the exported one, because it is cheaper: loop
  a `core` rebuild until the borrow errors appear, then compare that run's published summaries
  against a passing run's. Trace summary completion and API emission through the final
  `SemaEscape::reportDeferredChecks` fixpoint from that difference, and reduce it to a
  provider/consumer regression.
- Complete when: repeated parallel provider rebuilds publish identical summaries, a consumer
  consistently observes the corresponding invalidation contract, and a hundred consecutive `core`
  rebuilds compile.
### compiler.core.036 — A misplaced 'mtd impl' is accepted and silently overrides nothing

- Recorded: 2026-09-08 22:35
- Found while: writing the timer handler of Swag Prism, which never ran. The three
  `mtd impl` overrides of `MainWindow` sat in its plain `impl MainWindow` block instead of an
  `impl IWnd for MainWindow` one. Nothing was reported, and the window waited forever on a
  compilation whose result it could no longer collect.
- Evidence: an isolated module with `interface ISpeak { mtd speak()->s32 }`, a `Base` that
  implements it returning 1, and a `Derived` embedding it through `using base: Base` and
  declaring `mtd impl speak()->s32 => 2` inside a plain `impl Derived`. It compiles with no
  diagnostic. `let itf: ISpeak = &d; itf.speak()` returns 1, so the marked method overrode
  nothing; `d.speak()` returns 2, so it is a plain method that only a direct call reaches. In
  the same block, `mtd impl notAnInterfaceMethodAnywhere()->s32 => 3` — a name belonging to no
  interface in the program — also compiles silently.
- Why this costs so much: the two blocks look the same in a diff and read the same at a glance,
  the mistake compiles clean, every direct call still works, and only virtual dispatch differs.
  What it produces is not a wrong answer but an interface method that is never called, which
  surfaces far from its cause — a window that stops responding, a state that is never persisted,
  a language switch that changes nothing.
- Next: decide which of the two readings `mtd impl` in a plain `impl` block should take. Either
  it names an interface the type already implements and installs the override, which is what the
  author meant in every case seen so far, or it is rejected. Either way, `mtd impl` naming a
  method that belongs to no interface the type implements must be an error, and that check is
  the smaller half: the name is already resolved when the marker is seen.

### compiler.core.035 — Bound native test recovery with outstanding borrowed tasks

- Recorded: 2026-09-08 09:08
- Found while: testing targeted scheduler joins in
  [task_wait.swg](../bin/unittests/native/runtime/task_wait.swg).
- Evidence: with the original scheduler, an assertion inside the callback of a helper holding
  every worker on a condition abandoned the helper before its deferred gate release. The next
  test waited indefinitely for those workers, and the native test process had to be stopped.
  Moving assertions after the helper had released and joined its workers reported the two
  expected failures and terminated in 80 ms.
- Source lead: `__hostTestResume` in [os_windows.swg](../bin/runtime/os_windows.swg) restores
  the saved test context without unwinding the failed frames. Their cleanup does not run, and
  pending tasks can retain borrowed captures into abandoned stack storage.
- Next: define a bounded recovery contract for native test panics with outstanding tasks, such
  as process isolation or terminating the affected test process. Draining callbacks that borrow
  abandoned frames is not a safe recovery strategy.
- Complete when: a failing native test with pending borrowed work produces a bounded failure
  without hanging subsequent tests, shutdown, or running callbacks against abandoned storage.

### compiler.core.031 — Reject silent semantic failure before reporting success

- Recorded: 2026-09-06 21:14
- Updated: 2026-09-08 07:27 — fixed constant address lowering; the driver-level failure guard remains
- Historical evidence: taking the address of immutable GUID locals made `Integration.run` fail
  to produce machine code, while the corresponding script reported success with `0 mains`.
  A standalone `let bytes: [2] u8 = [17, 29]; let ptr = &bytes` reproduced the same silent loss
  inside a `#test`, without Win32 or imports.
- Resolved source cause: unary constant folding returned `Result::Error` without a diagnostic
  for address and dereference operators. Build 0.1.403 lets them reach their storage semantics
  and materializes aligned constant storage with native pointer relocations and stable addresses.
  [The native regression](../bin/unittests/native/operators/address_constant_storage.swg) covers
  captured arrays and structures, scalar addresses, embedded pointers and repeated address use.
  The reduced script now executes `1 main`, and the previously missing ChaCha20 test runs.
- Remaining gap: these source regressions protect the unary path, but the command boundary has
  no explicit protection against another semantic job returning an unreported error. The original
  failure showed that checking only the successfully registered mains or tests can report success
  after an enclosing function disappears.
- Next: propagate failed semantic jobs to command status even when no source diagnostic was
  emitted; test the driver boundary with an injected diagnostic-free failure and a declared main.
- Complete when: that failure returns a nonzero exit status with an actionable report, and a
  declared main or selected test cannot silently disappear from a successful run.

### compiler.core.034 — 'orelse' loses a strict interface alias when removing nullability

- Recorded: 2026-09-07 21:16
- Found during prompt 7 while testing nullable interface presence.
- Evidence: with `interface IValue { mtd value()->u32 }` and
  `#[Swag.Strict] alias Handle = IValue`, the function
  `func choose(value: Handle?, fallback: Handle)->Handle { return value orelse fallback }`
  reports `cannot cast from 'Handle' to 'IValue'` on `fallback`. The reduced standalone source
  fails under checkout-local `swc.dm.exe sema --file <source> --num-cores 6`, build 0.1.399.
  Ordinary nullable-interface coalescing works; strict-alias boolean presence and equality also work.
- Source lead: `resolveNullCoalescingResultType` in
  [Sema.Conditional.cpp](../src/Compiler/Sema/Ast/Sema.Conditional.cpp) unwraps the alias before
  removing `Nullable`, and only restores the alias when the concrete type did not change.
  Existing `strictHandleFallback` coverage keeps the fallback nullable, so that concrete type
  stays unchanged and does not exercise this narrowing case.
- Next: specify how nullability changes preserve a strict alias, then cover nullable-to-required
  coalescing for pointer and interface aliases, both branch outcomes, constants, and result types.
  Check that any accepted implicit conversion changes only nullability, not the alias identity.
- Complete when: these coalescing expressions retain the intended strict type and compile/run with
  standalone sema and native regressions, or a deliberate restriction has a precise diagnostic.

### compiler.core.033 — A closure cannot capture the parameter of the macro it is written in

- Recorded: 2026-09-07 16:02
- Found while: moving `Pixel.Image.visitPixels` and `visitVectorBytes` off `Core.Jobs` and onto a
  closure passed to `Swag.parallelRange`.
- Evidence: inside a `#[Swag.Macro]` function, `func|pixelUserData|(...)` on a parameter of that
  macro reports `closure does not capture outer variable 'pixelUserData'` at every expansion, while
  the same capture of an ordinary local of the macro body is accepted. The macro's parameters are
  bound at the call site rather than materialized as locals, and the capture path looks for a
  local. Binding the parameter to a local first -- `let opaque = pixelUserData` -- and capturing
  that local compiles and runs, which is what both macros now do.
- Next: decide whether a macro parameter is capturable at all. It is a caller expression bound by
  name, so capturing it by value means capturing the bound value, and capturing it by address means
  taking the address of the caller's own storage. Both are answerable; neither is answered today,
  and the diagnostic describes a missing capture rather than the real restriction.
- Complete when: either the capture is accepted with a stated meaning, or the diagnostic says that
  a macro parameter is bound at the call site and names the local-binding workaround.
- Related: language.parallelism.001

### compiler.core.024 — A JIT '#test' can silently compute a wrong value in a release run

- Recorded: 2026-08-22 21:23
- Updated: 2026-09-06 18:42 — rechecked the complete native suite with both compilers; the historical failure did not recur
- Area: compiler
- Found while: validating the `x86-64-v3` baseline change with
  `swc tools/unittests.swgs dm native -bc release`, on the first run after a `SWC_BUILD_NUM` bump
  had invalidated every cache.
- Observation: `bin/unittests/native/casts/autocast_pointer_receiver.swg:35` reported
  `assertion does not hold: AutoCastStorage.lo == 16` from the JIT `#test` at line 31, which writes
  a file-scope struct through a pointer receiver. Nothing faulted: the global simply did not hold
  what the call had written. This widens the class compiler.core.021 and compiler.core.022 describe -- both of those
  manifest as a hardware exception, so a run that survives is trusted; here a run survived and the
  data was wrong, which no `#test` outside this one would have noticed.
- Evidence: the failure reproduced twice in a row -- once in the full suite, once with
  `--file-filter autocast_pointer_receiver` -- then never again. The same filtered command passed
  5/5, the full suite passed, and a full cold-cache `--rebuild` of the same suite passed 2_919/2_919.
  Stashing the change and running the same filtered test on the pre-change `bin/swc.exe` also
  passed, so the two failures sit on the changed tree and the eight successes sit on the same
  changed tree; the discriminator is not the diff. Both failures were on caches invalidated by the
  version bump, which is the one condition the eight green runs did not share.
- Historical follow-up (2026-08-24): the same assertion then fired on every complete
  `swc tools/unittests.swgs native -bc release` run while the filtered command passed. Both
  warm-cache runs and an untouched Release compiler showed that pattern, making the rest of the
  compiled suite the strongest observed discriminator at that time.
- Current verification (2026-09-06, compiler 0.1.390): the complete 3_018-test native suite
  passes its JIT tests and generated executable with the DevMode compiler in both target
  configurations, and with the Release compiler in `release`. The formerly deterministic
  full-suite failure did not recur; these green runs do not identify its historical cause.
- Next step: preserve the compiler identity, cache state and full input set if the failure
  recurs. Reduce that failing state by halving the rest of the `native` directory while keeping
  `casts/autocast_pointer_receiver.swg`, until the smallest set that still fails is known. Then
  compare dumps of `setRange` and the `#test` body from that set and from the filtered one before
  changing allocator behavior or global-segment publication.

### compiler.core.005 — Compiler memory has no attributed, enforced budget

- Recorded: 2026-08-06 20:18
- Updated: 2026-09-06 16:06 — git: Integrate master fixes before merging sanitizer memory changes

**Evidence (2026-09-05, Release `swc.exe`, `--num-cores 6`, peak working set).** Before: core devmode rebuild 731 MB, core release rebuild 638 MB, hello 73 MB, bench tasks 74-83 MB. After finished jobs release their Sema and CodeGen state, 64 KiB arena blocks, and the api-export index dropped after export: 517 MB, 360 MB, 60 MB, 58-66 MB, with wall time at 0.86x, 0.95x, 1.0x, 0.97x (order-alternated A/B). Attribution by mimalloc statistics and a throwaway sampling probe on the DevMode core rebuild: the largest block still resident at peak is the static sanitizer's flow state (`SanitizerState` copies, ~150 MiB of ~100-byte map nodes, 17M allocations per core rebuild), then paged AST/payload/type stores (~110 MiB), per-thread arenas (~95 MiB, dominated by 2 KB `SymbolFunction` and 1.3 KB `SemaInlinePayload`), the CodeGen objects of sleeping codegen jobs (~23 MiB), and link-time archive buffers (~23 MiB). The compile-time runtime allocator is not a factor.

**Intent.** Use external profiling and the compiler.core.004 workloads to reduce retained AST, semantic, Micro, and temporary state, then turn the agreed memory targets into regression checks.

**Current investigation (2026-09-06).** The isolated candidate `717ec4db6` stores flow state only at chain heads and omits Unknown stack values and default register facts. The changes are merged into `master` at the owner's request; repeated low-load A/B time and working-set validation remains pending, and loaded observations are not proof of unchanged compile time. External native-stack heap sampling on the core devmode rebuild observes 57.7 MiB of live requested sanitizer memory before and 35.8 MiB after, with mixed semantic/symbol arenas at 50.5/50.7 MiB. Unknown values account for about 74.5% of sampled baseline stack-map node bytes and none in the candidate snapshot. These are sampled live allocation estimates, not a complete resident-set split: proximity pages and retained freed allocator pages remain partly unattributed. Finished CodeGen jobs already release Sema/CodeGen state, and emitted functions already release their Micro builder. The four full baseline/candidate compiler campaigns stopped at the same pre-existing GUI5 failure, later fixed separately in `7f00d9f26`; their later smoke stages remain unrun. The [campaign report](../bench/results/memory/20260906/README.md) keeps raw samples, profiling coverage limits, validation and the reduced failure.

**Next.** Finish repeated order-alternated measurements for every campaign workload on a quiet host to validate the performance of the merged changes. Then extend external accounting to proximity allocations and allocator-retained pages so the remaining AST, types, symbols, constants and Micro footprint is attributable before choosing the next lifetime change. Revisit dense sanitizer storage only if that trace still makes it the leading retained block: the earlier sorted flat-array attempt raised CPU time by 60%, so any replacement must avoid sorted-insert shifts. Shrinking `SymbolFunction` and releasing file text/tokens remain leads, not measured wins.

**Complete when.**

- A full core DevMode build peaks below 250 MiB and a hello-world build below 40 MiB on the campaign host.
- Every campaign workload stays within twice the best comparable compiled-language implementation measured by the same harness, or records a reviewed exception.
- Thresholds, host normalization, and variance policy are stored with the campaign.
- External profiling attributes the remaining peak well enough that a regression report names the responsible subsystem.

**Related:** compiler.core.004, compiler.core.007.

### compiler.core.004 — The benchmark campaign has no regression threshold on the edit-build loop

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-06 15:21 — git: Refresh module compilation profiles and measurement caveats

**Evidence.** Since 2026-09-05 the campaign measures the edit-build loop beside the seven tasks: `core_rebuild`, `core_noop`, `core_touch`, `hello_build`, `doc_std` and `format_tree` (`bench/toolchains.py`, `make_compiler_workloads`), each recorded with wall time, every sample and peak memory, corrected by the campaign's compilation context and indexed against the first clean campaign that measured it (`history.py`, `index_loop`). `bench/compile.py` answers the round-by-round A/B between two compilers. On 2026-09-05, Release 0.1.366, six worker cores, medians of five on a quiet machine: `core_rebuild` 3 485 ms, `core_noop` 334 ms, `core_touch` 3 214 ms, `format_tree` 5.6 s at one busy core, `doc_std` 142 s and 3.3 GiB peak, the standard-library publish pass included. No recorded campaign carries these workloads yet: the four records of protocol 2 predate them.

**Intent.** Record enough clean campaigns to know the resolution of each workload, then make the campaign report a regression instead of only plotting it.

**Measurement caveat (2026-09-06).** The original benchmark memory field is process-tree peak
committed memory. The instrument now records the timed process's peak working set separately;
older samples have no resident-memory value and must not be used to set that threshold. Memory
is not normalized by timing context. Formatter source mirrors now preserve `.swc-format` and
the maintenance tool's complete input selection; the remaining input-opening bias is tracked
in repo.tooling.007. Establish the baseline band using these corrected inputs and explicit
compiler-worker counts.

**Complete when.**

- At least five clean baseline campaigns establish the resolution band of every edit-build workload, as the null indices already do for the tasks.
- The campaign reports a workload that moved past its band without silently rewriting the baseline.
- Release and DevMode are measured where their behavior differs, and the report says which one a number belongs to.

**Related:** compiler.core.002, compiler.core.005, compiler.core.007.

### compiler.core.011 — The editor has no semantic definition navigation

- Recorded: 2026-08-09 20:16
- Updated: 2026-09-06 07:51 — git: prompt 6

**Evidence.** The VSCode extension registers build, rebuild, and format tasks. It registers no
definition provider and does not consume resolved compiler symbols.

**Intent.** Resolve the symbol referenced at a source position and return its canonical declaration location, including declarations in dependencies represented by persisted interfaces.

**Complete when.**

- Navigation covers locals, parameters, members, overloads after resolution, generics, aliases, generated declarations with an available source origin, and imported symbols.
- Ambiguous or unresolved positions return no misleading location.
- Paths and ranges are valid for open snapshots and on-disk dependency sources.
- Protocol tests cover same-file, cross-file, cross-module, overload, and no-result cases.

**Related:** compiler.core.001, compiler.core.008, compiler.core.012.

### compiler.core.022 — A JIT '#test' can call through a function slot that was never patched

- Recorded: 2026-08-12 18:01
- Updated: 2026-09-06 07:51 — git: prompt 6
- Area: compiler
- Found while: the 2026-08-12 sanification pass, looping the apps workspace in debug. This is the
  strongest reproduction so far of the intermittent Swag Vault JIT failures the pass set out to track.
- Observation: in `swc.dm test -w bin/apps -bc debug --rebuild`, six Swag Vault `#test` functions
  in `mainwindow.test.swg` (109, 133, 163, 363, 384, 494) die on the same hardware exception:
  execution lands at `rip=0x0000000080019060` (memory state FREE, "jit offset: unresolved"), which
  is a jump through a function-pointer slot holding a value no live code owns. The failure hits
  roughly two runs out of three at the first iteration, always with that same rip, and an A/B
  build bisected it as independent of the concurrent matcher fix added the same day. Swag Capture's
  151 tests pass in the same runs; the release and fast-debug legs of the same workspace pass far
  more often.
- Evidence: the run reports `state: Run JIT`, `__test_14` at `mainwindow.test.swg:109:1`,
  `0xC0000005` at `0x0000000080019060`, `memory: state=FREE`. The constant-side patcher leaves a
  slot untouched when its relocation carries `allowUnresolvedFunction` and the target is not ready
  (`shouldLeaveOptionalFunctionRelocationUnresolved`, [JIT.cpp](../src/Backend/JIT/JIT.cpp)), and
  the `LazyGenericBodyRunning` case explicitly defers; nothing re-patches such a slot when the
  target becomes ready afterward, so a test that reaches one through an interface table or stored
  callback jumps into the placeholder bytes. The rip being identical across six tests and several
  runs says the slot content is deterministic, not heap garbage.
- Next step: retry the apps JIT suite with the checkout-local DevMode compiler in the supported
  `devmode` and `release` target configurations, with `--rebuild` and `--num-cores 6`; the `debug`
  command above is historical. On recurrence, dump the pointed-to
  slot: identify which constant allocation contains `0x80019060` at patch time and which symbol its
  relocation names. Decide between re-running the constant patcher when a deferred target publishes
  its JIT address, and refusing to defer relocations that are reachable from an interface table.

### compiler.core.030 — Every executable lowers the runtime's functions again

- Recorded: 2026-09-05 22:13
- Updated: 2026-09-05 22:30 — git: Merge master into compile-speed

**Evidence.** Profiled on 2026-09-05 (Release 0.1.367 with a PDB, six worker cores, a user-mode sampling profiler): a hello world build spends 38 % of its thread samples in `CodeGenJob::exec`, 31 % of them in `MicroPassManager::run`, against 8 to 11 % in semantic analysis. The stage log says why — `tuned 172 functions`, `forged 320 functions`, for a four-line program: the runtime's own functions are lowered and optimized again for every executable, at the `release` preset's `O2`. `swc sema` on an empty file shows the same shape at 19 %: the prelude's `const __buildCfg = #run Swag.compiler().getBuildCfg()![]` (bin/runtime/core.swg) JIT-lowers about a hundred runtime functions so that the build configuration, which the compiler already holds in C++, can be read back through compile-time execution. On a quiet machine the same run measured `swc help` at 34 ms, the prelude's syntax at 35 ms, its sema at 165 ms and the hello world build at 197 ms (0.1.369, six cores); the campaign's `hello_build` target is 50 ms.

**Intent.** Keep the runtime's lowered code between builds — per compiler build, configuration and architecture, like the module setup cache keeps a setup — and give the prelude its build configuration as a compiler-materialized constant instead of a JIT run.

**Complete when.**

- A build whose sources contain no compile-time execution lowers nothing of the runtime and runs no JIT code.
- The cached runtime code is invalidated by the compiler build, the runtime sources, the configuration and the target, and a workspace test proves a fresh and a reused runtime produce identical executables.
- `hello_build` in the compiler.core.004 campaign reads under 50 ms on the campaign host.

**Related:** compiler.core.001, compiler.core.004, compiler.core.006, compiler.optimization.029.

### compiler.core.006 — Every process rebuilds the prelude state

- Recorded: 2026-08-06 20:18
- Updated: 2026-09-05 22:13 — git: Take the fixed costs a profile named out of every short command

**Evidence.** On 2026-09-05 (Release 0.1.369, six worker cores, quiet machine): `swc help` 34 ms, `swc syntax` on an empty file 35 ms, `swc sema` on the same 165 ms. The prelude is 14 files and 32 948 tokens; its semantic pass, including the JIT run compiler.core.030 describes, is what separates the last two numbers, and every module setup used to pay it once more until the setup cache of 0.1.367 kept the result.

**Intent.** Serialize and reuse the prelude through the same module-interface mechanism as ordinary dependencies, rather than maintaining a special prelude cache.

**Complete when.**

- A warm hello-world build and a warm script launch load the prelude interface without lexing, parsing, or semantically rebuilding the prelude.
- Prelude source, compiler version, target, and relevant configuration changes invalidate the interface.
- Fresh and reused prelude paths produce identical diagnostics and artifacts.
- The compiler.core.004 campaign demonstrates the reduced fixed startup floor.

**Related:** compiler.core.001, compiler.core.004, compiler.core.016.

### compiler.core.002 — Front-end invalidation is module-wide

- Recorded: 2026-08-06 20:18
- Updated: 2026-09-05 22:11 — git: Measure the edit-build loop in the benchmark campaign

**Intent.** Persist lexical, parsed, and semantic state per source file. Cache keys must include the source content, relevant build configuration, and fingerprints of imported public symbols actually observed by the file.

**Complete when.**

- Editing a private body reanalyzes only the changed file and its semantic dependents.
- Changing a public signature invalidates every consumer that observed it.
- Adding, removing, or renaming a file, changing relevant configuration, and changing compiler versions invalidate the correct state.
- The compiler.core.004 `core_touch` workload lands far below `core_rebuild`, which today it does not: one saved file rebuilds every file of the module.
- Clean and incremental workspace builds are covered by equivalent-result tests.

**Related:** compiler.core.001, compiler.core.004, compiler.core.003, compiler.core.016.

### compiler.core.001 — Dependencies cross the module boundary as regenerated source

- Recorded: 2026-08-06 20:18
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

**Intent.** Replace generated dependency API source with a versioned binary module interface. The interface must preserve exported symbols, types, constants, attributes, ABI information, and any bodies or metadata required by downstream optimization, while allowing lazy lookup by symbol.

**Complete when.**

- Workspace imports no longer add generated API `.swg` files to the lexer and parser.
- `--export-api-dir` still emits a human-readable `.swg` representation for inspection and tooling.
- Cache invalidation covers compiler version, build configuration, public declarations, exported constants, ABI-relevant attributes, and serialized inlinable bodies.
- Workspace tests prove that fresh and reused interfaces produce identical diagnostics and artifacts.

**Related:** compiler.core.002, compiler.core.006, compiler.core.008, compiler.core.011.

### compiler.core.003 — Code-generation invalidation is module-wide

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

**Intent.** Cache code generation at function granularity. A reusable artifact must be keyed by the function's semantic fingerprint plus the reachable ABI and inlinable-body dependencies that can affect its generated code.

**Complete when.**

- A body-only edit regenerates the changed function and any function whose generated code depends on it, while unrelated functions are reused.
- Reuse works for JIT and native builds, including debug and unwind metadata.
- A deterministic test compares clean and warm native images, manifests, and observable behavior.
- Cache entries reject compiler, target, configuration, ABI, and relevant optimization changes.

**Related:** compiler.core.001, compiler.core.002, compiler.core.004.

### compiler.core.007 — Workspace front ends and code generation run serially

- Recorded: 2026-08-09 20:16
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

**Evidence.** The workspace computes dependency order, but module front-end and code-generation work is still consumed serially. The current depth-one pipeline can overlap one background link with compilation of the next module; it does not schedule independent ready modules concurrently.

**Intent.** Schedule ready modules concurrently on the dependency DAG through a shared worker pool with explicit memory and CPU limits.

**Complete when.**

- Independent sibling modules overlap front-end and code-generation work, while consumers wait for the required interface or link artifact.
- Compiler and linker work share a bounded concurrency policy and do not oversubscribe the host.
- Logs, manifests, diagnostics, and emitted artifacts remain deterministic.
- The concurrency cap accounts for the memory measurements and budget from compiler.core.005.
- Workspace tests cover a diamond graph, concurrent failures, cancellation, and deterministic repeated builds.

**Related:** compiler.core.004, compiler.core.005.

### compiler.core.008 — There is no persistent language-server process

- Recorded: 2026-08-09 20:16
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

**Intent.** Add a compiler-hosted LSP transport and session layer: initialization and shutdown, workspace discovery, document open/change/close notifications, versioned snapshots, request cancellation, and orderly teardown. Requests must call compiler-library services instead of launching a compiler process per operation.

**Complete when.**

- A standard LSP client can open a workspace, edit unsaved buffers, cancel obsolete requests, and shut down cleanly.
- Responses are computed from the requested document version and stale work cannot publish newer state.
- The session reuses persisted compiler state from compiler.core.001 and compiler.core.002 when available.
- Protocol integration tests run independently of the VSCode extension.

**Related:** compiler.core.001, compiler.core.002, compiler.core.010, compiler.core.011, compiler.core.013, compiler.core.014, compiler.core.009, compiler.core.012.

### compiler.core.009 — Open documents have no incremental diagnostics

- Recorded: 2026-08-09 20:16
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

**Intent.** Publish parser and semantic diagnostics for the accepted version of every open document, including affected dependents, without requiring a workspace build.

**Complete when.**

- Opening a file with an error publishes diagnostics, correcting it clears them, and closing it restores the on-disk view.
- A stale analysis job never overwrites diagnostics for a newer document version.
- Diagnostic identifiers, severity, primary and related locations, source snippets, and normalized paths survive the protocol conversion.
- A multi-file protocol test covers an edit that introduces and then repairs a dependent-file error.

**Related:** compiler.core.002, compiler.core.008.

### compiler.core.010 — The editor has no semantic completion service

- Recorded: 2026-08-09 20:16
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

**Intent.** Provide completion candidates from the semantic snapshot at a source position, including local scope, members, visible imports, generic parameters, and applicable language constructs.

**Complete when.**

- Completion operates on unsaved, syntactically incomplete buffers and honors shadowing and visibility.
- Items include stable kind, insertion text, signature/detail, and documentation fields where available.
- Results are deterministic and cancellable, and a stale request cannot populate a newer buffer.
- Protocol tests cover local, member, import, generic, incomplete-expression, and inaccessible-symbol cases.

**Related:** compiler.core.008, compiler.core.011, compiler.core.013.

### compiler.core.012 — The editor cannot find semantic references

- Recorded: 2026-08-09 20:16
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

**Intent.** Enumerate references to the resolved declaration at a source position across the workspace, distinguishing declarations from uses and excluding textually identical but semantically different symbols.

**Complete when.**

- Results cover locals, members, overloads, generics, aliases, and cross-module references.
- The request supports including or excluding the declaration and uses versioned open-document snapshots.
- Shadowed names, comments, strings, and unrelated overloads do not appear.
- Results are deterministic, deduplicated, cancellable, and covered by same-file and cross-module protocol tests.

**Related:** compiler.core.008, compiler.core.011, compiler.core.014.

### compiler.core.013 — The editor has no semantic hover service

- Recorded: 2026-08-09 20:16
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

**Intent.** Render concise semantic information for the resolved entity at a source position: declaration signature, inferred type or constant value, ownership and relevant attributes, and public documentation.

**Complete when.**

- Hover covers values, types, functions and selected overloads, generic parameters, fields, aliases, and literals with inferred types.
- Output uses stable Markdown escaping and does not expose internal compiler-only names.
- Unknown or ambiguous positions return no misleading result.
- Protocol tests cover imported documentation, inferred values, overload resolution, and no-result cases.

**Related:** compiler.core.008, compiler.core.010, compiler.core.011.

### compiler.core.014 — The editor cannot rename a symbol semantically

- Recorded: 2026-08-09 20:16
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

**Intent.** Validate a requested identifier at a resolved declaration, reuse the semantic reference set, and produce a versioned workspace edit without changing unrelated text.

**Complete when.**

- Prepare-rename rejects keywords, compiler-generated or immutable declarations, ambiguous positions, and names that would create a known collision.
- Rename covers declarations and references across open and on-disk workspace files while preserving comments and strings.
- Edits are sorted, non-overlapping, versioned where required, and rejected when snapshots become stale.
- Protocol tests cover shadowing, members, overloads, aliases, cross-module use, collision, and cancellation.

**Related:** compiler.core.008, compiler.core.012.

### compiler.core.016 — Tool scripts recompile on every invocation

- Recorded: 2026-08-09 20:16
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

**Intent.** Persist compiled script artifacts using a dependency-complete key over loaded source files, imported public interfaces, compiler version, target, and relevant build configuration.

**Complete when.**

- A second unchanged invocation skips script lexing, parsing, semantic analysis, and code generation before launching the cached artifact.
- Changes in the main script, `#load` inputs, imported public APIs, compiler version, target, or relevant configuration invalidate the artifact.
- Cached and fresh paths preserve diagnostics, forwarded arguments, environment handling, output, and exit code.
- Tests cover direct source changes, transitive loads, imports, configuration changes, corrupt entries, and concurrent cache population.

**Related:** compiler.core.001, compiler.core.002, compiler.core.006, platform.portability.080.

### compiler.core.019 — An ambiguous `.member` still reads "not published yet" as "not there"

- Recorded: 2026-08-06 20:18
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity
- Area: compiler
- Found while: fixing the same race for the unambiguous case, which was making `Swag Capture` fail to
  compile with 18 to 26 errors per attempt, a different set every run
- Observation: `probeAutoMemberCandidates` looks every candidate up with `noWaitOnEmpty`, because
  with several candidates it must step over the ones that legitimately lack the name. An empty
  result therefore means both "this scope has no such member" and "this scope has not published it
  yet", and the two are indistinguishable. With exactly one candidate the lookup now waits, like
  the qualified spelling of the same access; with more than one it still decides immediately and
  reports `sema_err_cannot_compute_auto_scope`.
- Evidence: a member minted by a `#[Swag.Mixin]` inside one `impl` block of a type arrives when
  that block's body runs, and a struct is marked sema-completed once its `impl` blocks are
  *registered* — `decPendingImplRegistrations` fires before the body
  ([Sema.Impl.cpp:157-166](../src/Compiler/Sema/Ast/Sema.Impl.cpp#L157-L166)) — so a lookup on a
  "complete" type can still miss members. Every Swag Capture failure was that shape:
  `struct 'ActionQuickStyle' has no field 'Reset'` for a `Reset` that `newCmdId("Reset")` mints in
  a neighbouring `impl` block. The single-candidate half is fixed; a `with` block or a method
  carrying binding vars puts more than one candidate in scope and reopens it.
- Next step: reproduce it deliberately before changing anything — a type whose id is minted by a
  mixin, used as `.Id` inside a `with` block over an unrelated value, in a module big enough to
  spread the jobs. Then decide whether the multi-candidate path can park too: waiting on each
  candidate in turn is wrong (one of them is expected to lack the name), so the wait has to be
  "no candidate can still grow", which needs a scope-settled predicate the compiler does not have.
  A cheaper answer may be to park only while at least one candidate type has an `impl` block whose
  body has not run.

### compiler.core.020 — Concurrent type generation can corrupt declared-method traversal

- Recorded: 2026-08-10 12:35
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity
- Area: compiler
- Found while: rerunning `tools/tests.swgs dm --all-cfg` after an unrelated intermittent
  semantic-completion assertion had passed on immediate focused rerun.
- Observation: a later multi-configuration pass ended with a mimalloc corrupted-free-list report
  and a hardware exception while type generation traversed a struct's declared methods. The same
  compiler and sources had completed the full Release campaign immediately beforehand, and the
  equality suites had already passed in all three build configurations, so the failure appears
  scheduling-dependent rather than tied to one deterministic source construct.
- Evidence: mimalloc reported a corrupted 32-byte free-list entry. The stack ran through
  `appendImplFunctions` and `SymbolStruct::declaredMethods` in `Symbol.Struct.cpp`,
  `findGeneratedImplicitMethod`, `findGeneratedLifecycleWrapper`, `initStruct`,
  `TypeGen::processTypeInfo`, and then function-candidate implicit-conversion probing. The isolated
  command is `swc tools/tests.swgs dm --all-cfg`; it failed only in a downstream standard-library
  leg after lexer, parser, sema, JIT, safety, sanity, native, and workspace suites had passed in all
  three configurations.
- Next step: re-evaluate on the next occurrence only. The 2026-08-12 sanification pass eliminated
  three writers able to corrupt or misread memory underneath a stack like this one: a struct
  layout republished through transient zero and partially accumulated sizes on every post-node
  resume (`SymbolStruct::computeLayout`, now computed into locals and published once, atomically);
  imported native modules keeping `Swag.processInfos().args` slices into a destroyed compiler instance's
  storage (`ensureProcessInfosRunArgs`, now interning into process-lifetime storage); and the call
  matcher reading the signature type of a selected candidate before that type was published
  (`Match::resolveFunctionCandidates`, which now parks until the winner is typed — caught live as
  a `typeRef.isValid()` assertion under `finalizeAutoEnumArgs` while building the generated `ogl`
  wrappers, one run in ~20; in Release that read returned an out-of-bounds `TypeInfo`). A mimalloc
  report now appends the reporting thread's stack (`Allocator.cpp`), so a recurrence names its
  culprit directly; if one does recur, persist the failing module and stress parallel type
  generation as originally planned.

### compiler.core.021 — A dangling reference into a destroyed compiler instance has no deterministic detector

- Recorded: 2026-08-12 18:01
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity
- Area: compiler
- Found while: tracking an intermittent JIT '#test' failure in `swc test -w bin/apps -m swagcapture
  --rebuild`, which turned out to be imported native modules (core.dll and siblings, loaded once
  per process) keeping `Swag.processInfos().args` slices into the run-argument storage of a dependency-build
  compiler instance that had already been destroyed. That defect is fixed by interning the handed
  storage for the lifetime of the process, but the *class* — long-lived imported modules holding a
  pointer into per-instance state — was only caught because a heap block happened to be reused with
  bytes that failed an assertion inside `Path.extension`, in the Release compiler binary only,
  roughly once per run.
- Observation: nothing makes such a stale reference fail deterministically, so a suite regression
  cannot be written that reliably turns red without the fix: the dead storage usually still holds
  its old bytes, and every read through it then looks healthy. The DevMode binary never tripped at
  all because its allocator reused the freed block differently.
- Evidence: pre-fix, iteration 1 of every `swc test -w bin/apps -m swagcapture --rebuild` loop on the
  Release binary failed in `library.test.swg` (the one test that funnels `Env.executablePath()`
  into a validated path API), while the same command on the DevMode binary passed 10/10; post-fix
  the Release loop passed 8/8. A probe comparing the live instance against what JIT code reads
  showed five compiler instances writing five run-argument storages in one process, the test
  instance healthy, and the imported module reading a sixth, dead one.
- Next step: poison the global segments and other instance-owned storage handed across the JIT
  boundary when a `CompilerInstance` is destroyed, under `SWC_DEV_MODE` — a stale cross-instance
  reference then reads the poison pattern instead of plausible stale bytes, which makes this whole
  class reproduce on the first run. Then add a `bin/unittests/workspace` case that rebuilds a
  dependency and asserts `Env.executablePath()` is a valid, existing path from the tested module.

### compiler.core.023 — DevMode assigns a semantic payload to the same slice node twice

- Recorded: 2026-08-19 10:05
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity
- Area: compiler
- Found while: building the shared `bin/apps` workspace after integrating Swag Scope's viewers.
- Observation: at 0.1.166, two consecutive runs of a freshly built `swc.dm.exe` asserted
  while semantically checking the unchanged `tools/src/backlog.swg`; the Release compiler checked
  the same tool. At 0.1.167 the reduced witness and the original commands no longer reproduce,
  without a change known to target payload ownership, so this is now an unresolved
  scheduling-dependent lead rather than a deterministic defect.
- Evidence: two consecutive `bin/swc.dm.exe tools/apps.swgs dm build swagscope` runs assert
  in `NodePayload::setSemaPayload` at `NodePayload.cpp:806` because
  `shard->semaPayloads` already contains the node. Both name the `start` reference inside
  `line[start until line.count]` at `tools/src/backlog.swg:172`, under the `#code` body passed
  to `Utf8.visitRunes`. The defect has not yet been reduced because the tool combines a slice of a
  `string`, a captured mutable index, and macro-generated traversal; removing one without first
  identifying the second semantic visit would risk recording the wrong mechanism. A second,
  macro-free witness was found while optimizing `Latin1.trim`: passing
  `bytes[first until bytes.count]` directly to `lastNonSpace` triggers the same assertion on
  `first`, while binding that slice to a local before the call compiles. This removes macro
  expansion from the minimum mechanism and leaves a slice expression used as a call argument.
  At 0.1.167, the macro-free witness — a standalone `#test` passing
  `bytes[first until bytes.count]` straight into a `const [..] u8` parameter — compiles and
  runs, every `tools/*.swgs` invocation checks `backlog.swg` without asserting, and two
  consecutive `bin/swc.dm.exe tools/apps.swgs dm build swagscope` runs are green. Nothing
  in that release targeted payload ownership, so the double visit is more likely scheduling
  dependent rather than resolved.
- Next step: re-evaluate on the next occurrence. Persist the failing module when one happens and
  capture both `setSemaPayload` calls for the slice node before changing payload ownership; a
  reduction that does not fail on demand cannot be turned into a `bin/unittests/sema` case.

### compiler.core.027 — A run-time loaded shared library cannot share the host's runtime

- Recorded: 2026-08-30 12:06
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity
- Area: compiler
- Found while: making an executable link its dependencies' code in by default, so it ships as one
  file (`bin/unittests/workspace/modules/standalone_exe`).
- Observation: an executable links its whole import closure in, which gives the process one copy of
  each module and one runtime state. A shared library it loads at run time through
  `Core.NativeLibrary.load` was built against the shared libraries instead, so it brings a second
  `core` with it: two allocators, two runtime contexts, and memory that cannot cross between them.
  Nothing the compiler sees says the load will happen — the library is named by a path the program
  computes while it runs.
- Evidence: `runtime_context_dynamic_consumer` faulted with `0xC0000005` after its `#test` passed,
  at shutdown, once its `core` import resolved to the archive. Pinning that import with
  `link: "shared-library"` — which the all-or-nothing rule then propagates to the whole closure —
  makes it pass again, and is now what the module states.
- Next: decide whether a loaded module can adopt its host's runtime instead. The
  `__swc_rt_stage` hook already hands an imported module the host's TLS slot and context, and
  `NativeLibrary.load` could call it the same way; that leaves the loaded module's own `core.dll`
  allocator as the remaining split, so the question is whether the hook can also install the host's
  allocator. Until then the rule is the pin, and it is documented on the reference's dependency
  page.
- Complete when: either a loaded shared library provably shares the host's allocator and context in
  a workspace test that links its dependencies in, or the backlog records why it cannot and the
  compiler diagnoses the combination it can see.

---

## Deliberately out of scope

- **An LLVM back end.** The native and Micro back ends are the supported architecture. Reconsider only if a concrete platform or optimization requirement cannot be met within them.
- **A second language front end.** The compiler architecture is optimized for Swag; a second parser and semantic model would dilute the persisted-state and tooling work above.
- **A package registry inside the compiler backlog.** Path and workspace dependencies remain compiler responsibilities. Registry identity, trust, lockfiles, acquisition, and publishing need a separate product backlog once their scope and owner are defined.

Frontend, semantic analysis, and code generation defects: something observed in `swc` itself, with
a reproduction and a next investigation step. Optimization passes and generated-code performance
are [compiler.optimization.md](compiler.optimization.md); the borrow, lifetime and sanity analyses
are [compiler.safety.md](compiler.safety.md); the `doc` and `format` commands have their own files,
[compiler.command.doc.md](compiler.command.doc.md) and [compiler.command.format.md](compiler.command.format.md).
