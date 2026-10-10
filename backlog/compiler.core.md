# Compiler Backlog

This backlog covers the compiler front end, back end, and workspace build engine. Documentation, formatting, and language-design work have their own domain files. Only unfinished work belongs here; completed investigations and implementations remain discoverable through Git history.

Items are ordered from the most recently updated down. Every completion condition is intended to be testable. Measurements below are a dated baseline, not permanent product claims.

As of 2026-09-04, excluding the vendored `src/Support/Memory/mimalloc` tree, `src/` contains 266,719 physical lines in 685 `.cpp` and `.h` files. `src/Compiler/Sema` accounts for 85,710 lines in 154 files. The compiler diagnostic catalog contains 561 ids carrying 643 message variants, and `swc format --dump-config` exposes 133 options. Recompute these figures when using them to prioritize work.

### compiler.core.082 — Hot-path node containers that need more than a container swap

- Recorded: 2026-10-09 12:37
- Updated: 2026-10-10 15:44 — Retain only the remaining order and table-lifetime constraints.
- Evidence: flat tables now replace node-based containers across sema, code generation, optimization, sanitization, linking, and native dependency walks. Per-run side tables are lazy, and type interning builds TypeInfo only for new types. Native listings and linked sections remain identical. A CallArgMapping reuse needs proof that attempted and selected generic functions agree; TypeGen's deep stackSet may be cheaper than scanning.
- Remaining: order-preserving replacements for sanitizer sparse facts, mem2reg slots, SLP locations and entry values, web loads, LICM hoistSet, and native dependency rejections. A worker-kept FlatKeyMap also clears at the largest size seen, not the current function's size.
- Next: replace one ordered map with an output-equivalent flat map, or benchmark a kept-table clear against rebuilding a fresh table.
- Complete when: each remaining table is replaced with identical output and its owning tests pass, or its added design cost is shown not worthwhile.
- Related: compiler.core.060.

### compiler.core.074 — Repeated native rebuilds still vary in data layout

- Recorded: 2026-10-01 17:08
- Updated: 2026-10-10 15:44 — Narrow the remaining variation to empty-string placement and parallel global layout.
- Evidence: normalized code, unwind data, debug data, exports, and imports are stable across repeated builds. A single-core lz77 build still shifts .rdata and relocations when an empty reflected type name points to an earlier shared string in one build and its own allocation in another. Global .data and .bss offsets also vary because sema assigns them concurrently.
- Next: assign global layout at emission from a stable module, file, and declaration key while preserving JIT addresses; then compare normalized unwind records again.
- Complete when: repeated builds have stable normalized code, data layout, and unwind records, with the native regression suite green.

### compiler.core.060 — A compile-time call still pays per-call plumbing its call graph does not need

- Recorded: 2026-09-30 08:32
- Updated: 2026-10-10 15:44 — Summarize the remaining walks and their invalidation constraints.
- Evidence: compile-time calls still repeat four walks: relocation patching traverses constant closures per function; JIT preparation rebuilds call order before and after sema; runtime type hashing reconstructs scoped names already cached by symbols; and escape summaries rescan pending edges plus guarded return summaries. Patch walks now keep relocations inline.
- Constraints: patched function addresses can move from work to patch addresses; JIT order also depends on ignored functions and macro attributes; scoped-name caching requires immutable scope chains; escape summaries must preserve guarded proofs and late completion.
- Next: measure these costs on a gui Release rebuild and change only a bounded walk with a repeatable gain.
- Complete when: each walk is removed with compile-time execution and safety coverage, or measured and retained as not worth its risk.
- Related: compiler.core.030.

### compiler.core.003 — Code-generation invalidation is module-wide

- Recorded: 2026-08-09 11:30
- Updated: 2026-10-10 15:44 — Condense the implemented cache layers and remaining invalidation work.
- Current cache layers: workspace manifests reuse unchanged modules; interface-compatible dynamic dependency edits republish the DLL without rebuilding consumers; static dependency edits can relink persisted consumer objects; and non-debug executables reuse large relocation-free function members, including unwind data. Cache writes are atomic and best-effort; missing, changed, or malformed artifacts fall back to ordinary compilation. Imported native code run at compile time remains an invalidation boundary.
- Next: admit relocation-bearing functions by fingerprinting referenced symbols, constant payloads, ABI, and inlinable bodies. Add debug records only when source identities and line mappings are deterministic; keep an adaptive threshold so cache work costs less than the code generation it saves.
- Performance gate: compare clean, no-op, private-body, static-dependency, and public-API edits with compiler.core.004; clean builds must stay within the established noise band.
- Complete when: safe native and JIT builds reuse body-only edits with correct dependency invalidation, fresh and cached artifacts are identical, and the campaign shows a repeatable gain without a clean-build regression.
- Related: compiler.core.001, compiler.core.002, compiler.core.004, compiler.core.030.

### compiler.core.030 — Every executable lowers the runtime's functions again

- Recorded: 2026-09-05 22:13
- Updated: 2026-10-10 15:43 — Keep the current runtime-closure cost and discard superseded profiles.
- Evidence: executables now lower only functions reached from their roots, but the reachable runtime closure is still lowered for every executable. The function cache in compiler.core.003 excludes functions with code relocations, which covers most of that closure. The earlier JIT cost was removed from native builds; historical timings no longer describe the current compiler.
- Next: measure the runtime functions and time in a current hello-world Release rebuild, then compare relocation-aware function reuse with a runtime-code cache keyed by compiler build, configuration, architecture, and runtime inputs.
- Complete when: fresh and reused runtime code produce identical artifacts, all relevant inputs invalidate the cache, and the current edit-build campaign shows a repeatable gain.
- Related: compiler.core.001, compiler.core.003, compiler.core.004, compiler.core.006, compiler.optimization.029.

### compiler.core.039 — One module analysis resolves four and a half million substitutions

- Recorded: 2026-09-09 17:44
- Updated: 2026-10-10 15:43 — Retain the unresolved repeated-query question and current structural savings.
- Evidence: an imported-module analysis once resolved 4.55 million substitute chains, averaging two links. Passing already-read payload state through comparison lowering and metadata merging removed redundant queries without changing substitution rules; the attempted call-site shortcut showed no reliable timing gain and was reverted. A combined type-and-constant view is unsafe because flow narrowing can suppress a null constant.
- Next: attribute current resolutions to repeated questions within one pass versus callers rebuilding views they already hold; retain a change only with equivalent analysis results and a paired timing on an imported-module workload.
- Complete when: the remaining query cost is attributed and either reduced with a repeatable gain or shown not worth additional state.
- Related: compiler.core.001, compiler.core.038.

### compiler.core.005 — Compiler memory has no attributed, enforced budget

- Recorded: 2026-08-06 20:18
- Updated: 2026-10-10 15:43 — Keep the current memory attribution and discard superseded snapshots.
- Evidence: September 29 Release measurements reduced a six-worker Core DevMode rebuild from 579 to 389 MB with a 0.87x wall-time ratio, and hello build from 112 to 78 MB. The remaining committed-memory gap grows with worker count while live allocation stays near 16 to 17 MiB, chiefly from per-thread Micro scratch and semantic-analysis high-water marks. Earlier snapshots predate page, sanitizer-state, symbol-map, and job-lifetime reductions.
- Next: reduce and attribute per-worker retained scratch without reducing parallelism; share JIT code pages when patching no longer requires page-sized allocations.
- Complete when: Core and hello builds stay below 250 MB and 40 MB on the campaign host, workloads remain within twice the best comparable implementation or record a reviewed exception, and campaign thresholds and variance are explicit.
- Related: compiler.core.004, compiler.core.007, runtime.allocator.017.

### compiler.core.081 — An imported generic method once lost its own parameter

- Recorded: 2026-10-09 02:07
- Evidence: at 2026-10-08 23:56 the first `tools/help.swgs dm` after the formatting commit
  33f2aa0f3 stopped in the `brand.swgs` dependency build (gdi32, ogl, truetype, then pixel, all
  rebuilt against a just-republished core API) with `unknown symbol 'arr'` at
  `bin/std/.output/core/shared-library/devmode/x86_64/array.swg:135`, inside
  `Array.opSet(arr: const [..] T) where Reflection.canCopy(T)`, noted "while checking generic
  struct 'Array' with T = u8" from `core.swg:1410` (`ICodec.encode`). The generated file was
  intact and the parameter is declared on the line above; the next run passed unchanged.
- Reduction attempts, all green: 40 pixel-only rebuilds; 40 rebuilds of the same four modules
  in one process; 60 `--randomize` seeds of that build; 30 two-process rounds (core rebuilt, then
  its dependents); 12 replays of the exact core-then-`brand.swgs` sequence in the checkout. API
  reads are captured under the publication lock, and the editor extension only runs `sema`, so
  a torn file from a concurrent writer is unlikely: the race looks internal to sema of a
  generic method instantiated from an imported API while several modules share it.
- Next: when it reappears, keep the failing process's full log and rerun that exact command
  under `--randomize --seed` sweeps; instrument parameter registration versus body lookup
  for generic instance methods with a `where` clause (DevMode assertion that a body lookup
  never runs before the instance's parameter scope is populated).
- Complete when: the ordering is proved safe by construction or the race is reproduced and
  fixed with a regression case in the `workspace` suite.

### compiler.core.080 — Published generic bodies call omitted helper declarations

- Recorded: 2026-10-08 16:26
- Updated: 2026-10-08 20:01 — Confirm the same publication boundary for the XML reader before and after its numeric refactoring.
- Evidence: a forced DevMode import at `94dcc8f39`, with six workers, successfully rebuilt
  Core and then rejected `Hash.hash32` for a `#[Swag.DynCast]` struct with an `s32` field:
  `unknown symbol 'hashDynamicStorage'`. The span points to that call in generated `core.swg`.
  Both published `hash32` and `hash64` bodies contain the call, but the generated API has no
  declaration of the private helper from `crypto/hash64.swg`. The failure is at the import
  boundary: the eight `tests/collections/dynamicstorage.test.swg` tests pass inside Core.
- Reproduction: put the following script outside the checkout and run it with the checkout-local
  `bin/swc.dm.exe --num-cores 6 --rebuild <absolute-script-path>`:

  ```swag
  #import("core", location: "swag@std")
  using Core
  #[Swag.DynCast]
  struct DynamicKey { value: s32 = 17 }
  #main
  {
      var left: DynamicKey
      var right: DynamicKey
      Swag.assert(Hash.hash32(left) == Hash.hash32(right))
      Swag.assert(Hash.hash64(left) == Hash.hash64(right))
  }
  ```

- Additional evidence: an external script importing Core and calling
  `Serialization.Read.Xml.readNative'f32()` fails with `struct 'Xml' has no field 'zapBlanks'`
  in generated `core.swg`. The same forced rebuild with the XML source from before `6ba358e2c`
  fails at the same call; this is not introduced by its numeric-dispatch refactoring. Nine XML
  and resource tests, including every numeric width, pass inside Core. The missing helper is
  `internal` here, so checking only private free functions does not cover the boundary. The
  import diagnostic also describes the missing method as a field and lists only data members.
- XML reproduction: import Core in an external script, create a `Serialization.Read.Xml`,
  call `expect reader.startRead("1.5")`, then `discard expect reader.readNative'f32()`.
- Scope: this is an absent declaration, not the intermittent missing or duplicated local bindings
  in compiler.core.047. The nongeneric implicit-body export check from `d34b178c2` does not cover
  unresolved dependencies in an unmaterialized generic body.
- Next: reduce the published generic/private-helper dependency to an isolated provider and
  importer, then define how its reachable implementation is published or diagnosed at export.
  Preserve Core's dynamic-identity-independent hash contract; do not make a raw implementation
  helper public merely to silence the importer. Verify each hash width and the XML reader
  separately; include internal receiver methods in the dependency inventory.
- Complete when: a consumer importing the generated Core API hashes equal standalone and base-view
  dynamic values consistently with both hash widths, and a publication regression protects the
  dependency boundary without relying only on tests compiled inside the provider. Imported
  generic XML numeric and textual reads must also resolve their implementation dependencies.

### compiler.core.079 — Tuple values never drop the owning fields they hold

- Recorded: 2026-10-07 20:33
- Found while: fixing the ownership of values an implicit `opSet` builds inside literal fields.
- Evidence: a struct-literal type (a tuple) has no lifecycle: `resolveEffectiveLifecycleFunction`
  and `tryBuildLifecycleActionRec` in `CodeGen.cpp` only answer for structs and arrays, so
  `functionHasImplicitDrops` and `registerImplicitDrop` see nothing to drop in a tuple local.
  With a field type that counts its `opDrop` calls, `let t = {owned: cast(Owned, name())}`
  adopts the value with `opPostMove` and never drops it (one set, zero drops), and
  `let t = {owned: mk()}` with `mk()->Owned` moves the call result into the tuple while the
  call temporary is dropped at the end of the statement, so the tuple keeps a released value.
  Every owning type held in a tuple local, such as `Core.String`, leaks or dangles the same way.
- Next: decide whether a tuple owns its fields like a struct (field-wise drop, post-copy and
  post-move derived from the field types) or rejects owning field types; then implement that
  rule in the lifecycle resolution and cover both producers above in the `native` suite.
- Complete when: a tuple local holding an owning field drops it exactly once at scope end, or
  the declaration is rejected with a diagnostic, and the two reproducers above are suite tests.

### compiler.core.047 — Imported generic bodies intermittently lose or duplicate bindings

- Recorded: 2026-09-16 09:28
- Updated: 2026-10-07 12:09 — a forced documentation rebuild lost an imported method parameter.
- Found while: validating the dynamic type-pattern migration with DevMode 0.1.675 and six workers.
- Evidence: `bin/swc.dm.exe --num-cores 6 tools/scripts.swgs dm smoke --num-cores 6`
  ran `2048.swgs`, then stopped while checking `asciiart.swgs`. The generated core API's
  `hashtable.swg:521` reported that local `mask` was already defined; the previous-definition
  note pointed to the same declaration. The specialization was
  `HashTable(string, ConcatBufferPosition)`, requested by generated `core.swg:5311`.
  Application tests and example builds were running concurrently in the same checkout.
- Reduction status: an immediate isolated `tools/scripts.swgs dm smoke asciiart` rerun with
  the same compiler, sources, cache, and six workers passed. A complete rerun of all 21
  script smokes also passed. The cause and any relationship
  to the type-pattern change are unestablished; no concurrency fix is included in that migration.
- Further evidence: on 2026-10-07, `tools/help.swgs dm --num-cores 6` with the cast-call
  compiler stopped during the forced standard-library rebuild: generated `array.swg:134`
  reported unknown symbol `arr` inside `Array(u8).opSet(arr: const [..] T)`, while checking
  the Pixel dependency. The parameter declaration remained present in the published source.
  A direct doc retry passed, as did a complete forced tool rerun; a separate forced doc run
  with baseline `ca107d2a9` and its compiler also passed. No other command in this checkout
  was compiling when the first failure occurred. These observations do not establish a cause
  or a relationship to the cast syntax change or the earlier duplicate-local report.
- Next: replay the cached script import alongside module builds, capture generic-instance
  ownership, parameter-scope restoration, and semantic restarts around the affected bindings,
  and compare with the parent
  compiler before attributing the failure to parsing, publication, or scheduling.
- Complete when: a bounded reproducer identifies the duplicate visitation or publication,
  the root cause is fixed, and the script passes repeated parallel imports with six workers.

### compiler.core.078 — Reduce a suspected nested-owner release false positive

- Recorded: 2026-10-07 10:42
- Evidence: an experimental Windows OpenGL/DirectComposition context stored a separately
  allocated composition object in `OglContext.composition`. `NativeRenderOgl.dropContext(rc:
  OglContext)` deleted that field; its caller then deleted the separately allocated `OglContext`
  carrier. The compiler reported that the carrier had already been freed. Embedding the
  composition state removed the report, but changed the ownership shape and did not explain it.
- Boundary: this was observed in the discarded composition prototype, not in the retained
  layered presenter. It is a suspected false positive, not an established alias-analysis defect;
  no standalone suite reproducer has yet been obtained.
- Next: reduce a heap-allocated carrier with a separately allocated field, a by-value cleanup
  callee, and the subsequent carrier delete to the safety suite. Check whether the inferred
  release summary confuses a field's pointee with its enclosing allocation before changing it.
- Complete when: a standalone regression explains the diagnostic as valid or protects the
  corrected ownership summary without GUI or graphics dependencies.

### compiler.core.064 — A compiler-held dependency DLL blocks child rebuilds

- Recorded: 2026-09-30 15:28
- Updated: 2026-10-07 08:02 — forced documentation rebuilds reproduce the loaded-DLL conflict.
- Evidence: a serial native Swag Prism test with the DevMode compiler and program configuration
  `release` loads `bin/std/.output/core/shared-library/release/x86_64/core.dll` in its parent
  compiler. The test's child compiler requests `build --build-cfg release --optim-level 0` for a
  temporary Core importer and tries to republish that DLL. The write fails with access denied;
  the diagnostic identifies the parent `swc.dm.exe` as its owner. Six workers and serial execution
  reproduce it. Running a script concurrently can hold the same source artifact and expose the
  same failure, but concurrency between campaigns is not required.
- Further evidence: after the non-null success-contract migration, both
  `swc.dm.exe --num-cores 6 tools/help.swgs dm --num-cores 6` and a standalone
  `swc.dm.exe doc --workspace bin/std --doc-output-dir bin/help --rebuild --num-cores 6`
  fail after publishing Core: a second write to the devmode `core.dll` reports that
  a compiler process still owns it. The direct command reproduces this without the
  tool-script wrapper or another main-checkout compilation. Include this same-command
  documentation path in the dependency-lifetime investigation.
- Boundary: scripts use immutable dependency-cache copies, and external workspace dependencies
  are mirrored into `.dep`; workspace-local dependencies can still be loaded from their mutable
  `.output` directories. `ExternalModuleManager` retains loaded libraries for the process.
  Prism's retired probe helper exposed this by forwarding snippet optimization levels to all
  dependencies; its current `BuildArtifact` path sets the level on the snippet's module instead.
- Next: reduce the parent compile-time DLL call followed by a child's forced dependency rebuild
  to a workspace-suite fixture. Audit shared-library resolution during dependency builds and
  separate compiler-loaded library lifetime from the mutable publication path, while preserving
  native linking, publication, cache invalidation, and runtime-instance ownership.
- Complete when: the fixture rebuilds the dependency while its parent compiler remains alive,
  with both compiler executables, and workspace reuse and publication checks still pass.

### compiler.core.020 — Concurrent type generation can corrupt declared-method traversal

- Recorded: 2026-08-10 12:35
- Updated: 2026-10-06 20:59 — Added a completion condition to the dormant corruption watch.
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
- Current validation (2026-09-14): 100 Release 0.1.571 rebuilds of `core` completed with
  byte-identical sets of 24 published API files. Another 20 Release and 20 DevMode rebuilds
  of `ogl` completed without a crash. The current declared-method traversal copies impl and
  interface lists under shared locks, and `SymbolMap::getAllSymbols` snapshots each map under
  its corresponding lock. This session also fixed mutable attribute snapshots and lifecycle
  pointer publication, with regression tests. These results establish non-recurrence under
  those workloads; they do not identify the writer that caused the original free-list damage.
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
  report now appends the reporting thread's stack (`Allocator.cpp`), so a recurrence preserves its
  detection stack; if one does recur, persist the failing module and stress parallel type
  generation as originally planned.
- Complete when: a recurrence is attributed through its captured stack and fixed with a
  regression, or a parallel type-generation stress run over the whole standard library under both
  compiler executables stays clean and the lead is retired.

### compiler.core.021 — JIT code leaks one thread-local index per compiler instance

- Recorded: 2026-08-12 18:01
- Updated: 2026-10-06 16:12 — Destroyed instances are now poisoned and release their fiber-local slots; thread-local indexes remain.
- Area: compiler, JIT runtime hosting
- Found while: tracking an intermittent JIT '#test' failure in `swc test -w bin/apps -m swagcapture
  --rebuild`: imported native modules kept `Swag.processInfos().args` slices into the storage of a
  destroyed dependency-build instance. That storage is interned for the process since.
- Done (2026-10-06): a DevMode `~CompilerInstance` fills its global zero, initialized and compiler
  segments with `0xCD`, so a stale reference into a destroyed instance reads the pattern instead
  of plausible old bytes. The first thing it caught was `retireAllocatorThreadHeap`, the cleanup
  callback the JIT-compiled runtime allocator registers through `FlsAlloc`: Windows ran it at
  thread exit, after the instance was gone, and it read `Swag.g_AllocatorThreadHeapTlsId` from the
  dead segment (`import_core_without_using.swgs` exited with a failure code after reporting
  `clean`). JIT calls to `FlsAlloc` and `FlsFree` now resolve to host wrappers that record each
  slot and its callback, and an instance frees the slots whose callback is its own JIT code before
  it is destroyed; `FlsFree` runs the callbacks while their code and data are still valid.
- What remains: JIT code also takes plain thread-local indexes through `TlsAlloc` (the allocator's
  fast heap slot, for example). They have no callback, so nothing reads them after the instance
  dies, but each instance that ran its allocator keeps one index allocated for the rest of the
  process, and Windows has 1,088 of them.
- Next: count the indexes a long workspace run (`tools/std.swgs dm test`) leaves allocated, and if
  the count grows with the number of instances, record the `TlsAlloc` indexes per instance the
  same way and free them at destruction.
- Complete when: a process that creates and destroys many compiler instances keeps a bounded
  number of thread-local indexes, with the workspace suite green under the poisoning.

### compiler.core.053 — Confirm that a linked PDB keeps one definition per structure

- Recorded: 2026-09-17 08:42
- Updated: 2026-10-06 14:55 — One type table no longer repeats a record; a linked program remains to be measured.
- Area: compiler/backend, `DebugInfoCodeView` type table, integrated PDB writer
- Evidence: `swc tools/apps.swgs dm build swagscope --debug` (build 847) wrote a 12.2 MB PDB
  whose TPI stream held 38,154 records, 5,178 of them `LF_STRUCTURE`, with `Surface` defined 28
  times, `interface` 26, `Wnd` 24 and `Application` 22.
- Done (2026-10-06): `TypeTableBuilder` now hash-conses every record it emits, so a record
  identical to an earlier one returns the earlier index, and a pointer to a structure names its
  forward declaration, as MSVC does, so a structure's records no longer depend on whether its
  definition was complete when they were emitted. On a 60-structure probe compiled with
  `--debug`, the TPI stream went from 1,253 to 913 records (procedures 296 to 200, argument
  lists 296 to 154), `interface` from five structure records to one and `string` from four to
  one; each structure keeps one forward declaration and one definition. The `DebugInfo_*` and
  `Pdb_*` tests pass.
- What remains: `LinkDebugMerger` already keeps one copy of each record once remapped, so the
  copies archive members brought came from records that differed only by which index a pointer
  named. With pointers now naming forward declarations those records should coincide, but no
  linked `--debug` program with debug archives has been measured yet.
- Next: build swagscope with `--debug` before and after this change and compare the PDB size,
  the TPI record count and the number of `LF_STRUCTURE` records per name.
- Complete when: every structure has one definition per distinct layout in a linked PDB, the
  `DebugInfo_*` and `Pdb_*` tests pass, and the swagscope `--debug` PDB shrinks accordingly.

### compiler.core.046 — A `!` buried in a `Swag.assert` argument proves a path the guard may not check

- Recorded: 2026-09-15 12:47
- Updated: 2026-10-06 09:49 — Measured what recording nothing from an assertion argument would touch.
- Found while: the same change, on `bin/unittests/sanity/self_borrow_move.swg`.
- Evidence: `Swag.assert(target.cursor![] == 13)` records the non-null proof for the rest of the
  block, but `Swag.Safety(.Assert, false)` and the `release` preset drop the whole assertion,
  including the `!` inside its argument. The proof survives compilation; the runtime guard does
  not. `Swag.assert(p != null)` has the same property and the reference documents it as the
  precondition form, which is why it reads as deliberate there; a `!` inside an argument does not
  read as a precondition at all.
- Cost: no unsoundness in `release`, where every guard is already off. In `devmode` with an
  explicit safety override, a path can be used unguarded because of an assertion that was
  compiled out.
- Blast radius (2026-10-06): recording nothing from inside a `Swag.assert` argument is a
  one-line change to `notNullRunsUnconditionally` (an `AstIntrinsicCallExpr` parent with
  `IntrinsicAssert` returns false). `bin/` holds 89 assertions with a postfix `!` in an
  argument, most of them in application and module tests, so any code after them that relies on
  the proof would stop compiling; that needs every `bin/` test source compiled before it lands.
  Recording the proof only where `Assert` safety is on would make the same source compile in one
  configuration and not in another, which is worse.
- Next: decide whether a proof recorded inside an argument of a removable intrinsic should be
  kept. Either record nothing from inside a `Swag.assert` argument and compile every `bin/` test
  source, or state the rule in `bin/reference/modules/language/src/004_007_pointers.swg` next to
  the existing `Swag.assert` paragraph.
- Complete when: the chosen rule is implemented or documented, with a case showing what
  `Swag.Safety(.Assert, false)` does to the proof.

### compiler.core.072 — Link preparation resolves and places the native image on one thread

- Recorded: 2026-10-01 14:25
- Updated: 2026-10-06 09:49 — Description sections are now built in parallel; placement and resolution remain serial.
- Evidence: `PELinker::prepareImageLinkParallel` loads archives and builds the symbol table as
  jobs. On 2026-10-01, probed phases in a 16-worker DevMode `gui` rebuild gave image lowering
  about 0.6 s and resolution 0.2 s of wall time over the five native modules. Since 2026-10-06,
  `buildNativeImage` builds each object description's text bytes, code relocations and unwind
  sections as an indexed parallel loop, then places them in description order on the driver; an
  in-process comparison against the sequential order produced identical sections, relocations
  and symbols for `core`, `ogl`, `truetype`, `pixel`, `gui` and `gui2`. A module has only six
  descriptions, so that loop is at most six-way. Placement (`placeNativeSection`, the symbol and
  relocation tables), `resolveSymbols`, `appendSymbolTable`, and `finishImage` are still serial.
- Next: measure `link prepare` in a 16-worker `gui` rebuild with `--dev-sched-stats` and decide
  whether the remaining serial time justifies splitting descriptions further or resolving
  archive members in parallel.
- Complete when: `link prepare` no longer shows as serial time in the scheduler report, with the
  linker and PDB C++ tests, the native suite, and a linked consumer green under both executables.
- Related: compiler.core.069

### compiler.core.075 — Aligned node references collapse semantic metadata partitions

- Recorded: 2026-10-03 16:28
- Evidence: `NodePayload` selects each of its 16 shards with `nodeRef.get() % 16`.
  The reference contains an AST byte offset aligned to at least eight bytes, so only
  two shards can receive payload storage or side-table entries. Readers of a sparse
  side table also lose most of the intended empty-shard early exits.
- Experiment: replacing all 22 selectors with `Math::hash(nodeRef.get()) % 16`
  passed concurrent publication/readback coverage, both JIT suites, and semantic
  tests; all 116 benchmark functions retained identical normalized pre-emit code.
  Five paired six-worker Release rebuilds increased peak committed memory by a
  median 17% on `core` and 3% on `gui`. Wall-time medians moved by +3% and -6%,
  respectively, on a machine with substantial background-load variation. A quieter
  single-worker pair also made `core` about 6% slower. The change was not retained:
  distributing every file's small payloads over more 16 KiB pages has a definite
  cost, without a sufficiently clear overall compilation-time win.
- Next: separate sparse side-table distribution from payload-page allocation, or
  reduce initial storage without reducing the supported contiguous symbol-list
  size. Compare one-worker and parallel rebuilds on both modules under stable load.
- Complete when: the partitioning improvement has concurrent read/write coverage
  and a measured compilation-time benefit with its memory cost explicitly bounded.

### compiler.core.073 — A dependent module waits for its dependency's whole link before starting

- Recorded: 2026-10-01 14:25
- Evidence: `CompilerInstance::runWorkspace` keeps one deferred link in flight, but joins it before
  compiling any module that depends on the linked one. The `std` chain is nearly linear
  (`core` → `ogl`/`truetype` → `pixel` → `gui`), so most links become a wait: in 16-worker DevMode
  `gui` rebuilds, `--dev-sched-stats` charges 2.8–4.8% of worker time to the
  `workspace link wait` phase, nearly all of it starvation while the single `NativeLink` job
  (0.4–1.2 s per module) runs.
- Next: list what a dependent actually needs from its dependency before code generation (the
  module API and setup files, the DLL only for compile-time calls into it) and join the link at
  the first use that needs the binary instead of before the module starts.
- Complete when: a dependent's semantic analysis overlaps its dependency's link in a `gui`
  rebuild, with the workspace suite and `std` tests green under both compiler executables.
- Related: compiler.core.069, compiler.core.007

### compiler.core.071 — WebP's macroblock reconstruction takes seconds to generate and holds back `pixel`

- Recorded: 2026-10-01 13:08
- Updated: 2026-10-01 13:40 — traced to inlining and unrolling; code generation now starts the largest functions first
- Evidence: in 16-worker DevMode `gui` rebuilds, the longest code-generation job is one WebP
  function, `Pixel.Webp.decodeLossy` or `Pixel.Webp.vp8Reconstruct` depending on the run, 3–8 s in
  one slice. The `pixel` module's first code-generation round lasts exactly that long: the round is
  bounded by one job, not by when it starts. Per-pass timing on `decodeLossy` (DevMode, six
  workers) spreads about 4 s over the whole pipeline — register allocation 0.8–0.9 s in one run,
  branch-simplify 0.7 s, instcombine 0.5 s, const-fold 0.5 s, copy-elim 0.4 s, most pre-RA passes
  running eight or nine times — so no single pass misbehaves; the function is simply enormous.
  `vp8ReconstructMacroblock` runs two 4×4 loops that call `vp8Predict4` and `vp8InverseDct4`;
  single-call auto-inlining (`K_AUTO_INLINE_LAST_CALL_COST`, 4 096 tokens per callee, no cap on
  the caller's growth) folds the whole chain into its caller, and unrolling then repeats it sixteen
  times. Code generation now enqueues functions largest first, estimated from their own size plus
  what semantic analysis inlined into them, which removes late starts but not this length.
- Next: bound the growth a caller may receive from last-call auto-inlining and from unrolling
  loops whose bodies contain inlined calls, then compare WebP decoding speed and `pixel` build time
  before and after with the benchmark harness.
- Complete when: no single function's code generation in `bin/std` takes more than a tenth of its
  module's wall time at 16 workers, without a measurable loss in WebP decoding speed.
- Related: compiler.core.069

### compiler.core.069 — Measure where a module build loses its workers beyond six cores

- Recorded: 2026-10-01 07:35
- Updated: 2026-10-01 13:40 — break the losses down by driver phase
- Evidence: `--dev-sched-stats` (DevMode compiler) splits worker time into running jobs, serial
  phases (no job running), scheduler lock waits, and starvation (jobs run elsewhere, nothing is
  ready), and reports per job kind its work, its longest slice with what it worked on, and the
  starvation charged to it. `std.swgs dm build gui --rebuild`, 2026-10-01, DevMode compiler:
  - 6 workers, loaded machine: 70 s, 81% running, 11% serial, 0.3% lock, 7.5% starved.
  - 16 workers: 26–54 s depending on load, 58–66% running, 13–16% serial, 0.5–0.9% lock,
    20–25% starved. CodeGen alone causes 10–12% starvation: `Pixel.Webp.decodeLossy` is one job
    of 6.6–8.2 s. Sema's longest slice is 1–2.6 s; the five native links cost 4% together.
  - Barrier rounds no longer matter: 65 rounds moved about 500 sleepers, against 78 000–91 000
    dependency wakes.
- Per phase (the report now charges serial and starved time to driver phases): a quiet 16-worker
  run (26 s) loses 7.4% of worker time starved in semantic analysis, 7.0% starved and 2.2% serial
  in code generation, 3.3% serial and 2.4% starved in the rest of the native backend (collecting
  functions and dependencies before and after code generation), 3.2% starved waiting for deferred
  links, and 1.3% serial in module API export. Code generation runs two or three dependency
  rounds per module; only the first costs anything.
- Next: find what the backend does serially around code generation (`NativeBackendBuilder::prepare`
  and `rebuildFunctionInfos`) and what the semantic tail waits on (its longest job is 1.5–4 s);
  each becomes its own entry once named.
- Complete when: each share above has an owning entry.
- Related: compiler.core.071, compiler.core.072, compiler.core.073, compiler.core.065, compiler.core.068, compiler.core.007

### compiler.core.068 — The job scheduler serializes every transition on one mutex

- Recorded: 2026-10-01 07:35
- Updated: 2026-10-01 13:08 — measured: lock waits cost under 1% of worker time at 16 workers
- Evidence: `JobManager` keeps one `mtx_` for the three ready deques, the client counters, the
  waiter map, and the worker list. Jobs are fine-grained (one per top-level declaration, one per
  function in code generation) and every enqueue, dequeue, park, and wake takes that lock.
  `growWorkersForLoadLocked` still creates threads while holding it. The queue is a global FIFO:
  a resumed job lands on any worker with a cold cache. The default worker count is
  `hardware_concurrency()`, which on a hybrid CPU includes efficiency cores and SMT siblings, so
  critical-path jobs can run on the slowest cores.
- Measured: `--dev-sched-stats` on a 16-worker DevMode `gui` rebuild charges 0.5–0.9% of worker
  time to waiting for this lock (compiler.core.069). It is not the ceiling today; revisit when
  starvation and serial phases shrink.
- Next: prototype per-worker deques with stealing behind the same `JobManager` interface, keeping
  the waiter map and client counters under their own lock, and spawn workers outside it.
- Complete when: a std module build at 16 workers spends no measurable time waiting on the
  scheduler lock (VTune or ETW contention view), with the scheduler unit tests and both compiler
  executables green.
- Related: compiler.core.069

### compiler.core.065 — Remaining barrier rounds still drain the whole module

- Recorded: 2026-10-01 07:35
- Updated: 2026-10-01 09:53 — add paused lazy bodies as a barrier source
- Evidence: `SemaWaitIdentifier` and `SemaWaitImplRegistrations` now park on the name and are
  woken by symbol-map insertion and by the last impl registration; `SemaWaitTypeCompleted` parks
  on its blocking symbol and is woken by `setSemaCompleted`. Those producers have no flag to
  recheck at registration, so a publication racing the park still waits for the `wakeAll` in
  `Sema::waitDone`; so do `SemaWaitCompilerDefined`, a type completed by its concrete layout after
  `setSemaCompleted`, and a name made visible by a new `using` rather than an insertion. That
  barrier first drains the client: the tail of each wave runs on a few workers, then the driver
  does serial work before the next one. Any symbol transition still sets `changed_`, so most
  rounds end in a full `wakeAll`. The same barrier separates the declaration pass from the full
  pass and closes native code generation (`scheduleCodeGen`). A paused lazy function body is
  normally resumed by the job that paused it; when that job does not come back to it, its other
  callers stay parked on `SemaCompleted` until `hasPausedLazyBodyWait` wakes them in a barrier
  round so one can adopt the run. How often that fallback fires is unknown.
- Next: count rounds and re-parked sleepers per wait kind (compiler.core.069) on a std module, then
  give the dominant remaining kind a recheckable publication (a per-name generation counter for
  identifier waits closes the park race) so it no longer needs the barrier.
- Complete when: a std module build needs no barrier round to resolve forward identifier and
  type-completion dependencies, with the sema suite, the C++ scheduler tests, and std release
  green under both compiler executables.
- Related: compiler.core.069, compiler.core.007

### compiler.core.063 — Reduce the PDF spill-slot regression to a standalone language test

- Recorded: 2026-09-30 11:15
- Updated: 2026-09-30 14:18 — retain only the standalone regression coverage still missing
- Evidence: `sinkFrameStoreIntoBranchTarget` compared raw stack displacements across outgoing-call
  stack adjustments. In `Pdf.parseContent`, a store at `[rsp + 0x1AA8]` under an eight-byte
  adjustment belonged to the slot later read at `[rsp + 0x1AA0]`. The pass mistook it for another
  loop's store at the first displacement and erased it. Comparing entry-relative addresses fixes
  the three PDF failures; all eleven selected corpus/stroke tests pass in release JIT and native
  execution. `PostRAPeephole_SpillStoreSinkingTracksStackDepth` fails before the fix and covers both
  distinct slots with equal displacements and one slot with different displacements.
- Remaining boundary: that regression is a C++ Micro test, not a standalone source under
  `bin/unittests`. Extracting the parser and dash loop into a Core-only script passes even without
  the fix. Forty-eight standalone two-loop variants, varying call arity from one to twelve and
  live accumulator pressure, also pass without it. Those reductions change register allocation
  and no longer place the two loops' spills at the conflicting adjusted displacements; retaining
  the full GUI decoder would violate the standalone suite boundary.
- Next: reduce the interacting loops and their register pressure while checking the pre-fix
  post-allocation instruction stream, then keep a native suite case that fails without the fix.
- Complete when: `bin/unittests/native` reproduces this stack-depth aliasing independently of GUI,
  alongside the existing C++ regression and PDF consumer tests.

### compiler.core.061 — Type-info graph publication uses one serialization domain

- Recorded: 2026-09-30 08:34
- Updated: 2026-09-30 13:48 — narrow the remaining boundary to canonical graph ownership
- Evidence: `ConstantManager::makeTypeInfo` deliberately sends all reflected types to constant
  shard zero, so shared dependencies have one canonical runtime identity. `TypeGen::makeTypeInfo`
  retains exclusive ownership of that segment across `processTypeInfo` and back-reference
  publication. Contention now records the exact storage and owner generation, and every ownership
  release wakes its registered jobs, including semantic pauses. Independent reflection roots still
  cannot generate their metadata concurrently. This is a static concurrency boundary, not an
  attribution of a measured fraction of cold-build time.
- Safety boundary: hashing roots into separate stores would duplicate common dependencies and
  break pointer identity. Publishing an entry before all required payloads and back references
  are ready would expose partial recursive metadata.
- Next: separate canonical graph registration from payload generation, identify independently
  publishable components, and define ownership and completion for recursive components before
  shortening or dividing the exclusive section. Preserve one address per reflected type.
- Complete when: independent components can progress on different workers, mutually recursive
  graphs publish no partial data, and identity, interface, and reflection tests pass under
  repeated parallel cold compilation.
- Related: compiler.core.020, compiler.core.007.

### compiler.core.007 — Workspace front ends and code generation run serially

- Recorded: 2026-08-09 20:16
- Updated: 2026-09-30 07:58 — Located the shared state that must be isolated before scheduling module front ends concurrently.

**Evidence.** The workspace computes dependency order, but module front-end and code-generation work is still consumed serially. The current depth-one pipeline can overlap one background link with compilation of the next module; it does not schedule independent ready modules concurrently.

**Architecture audit (2026-09-30).** `CompilerInstance::runWorkspace` still calls
`runWorkspaceModule` synchronously for each item in `buildOrder`; only one
`WorkspaceModuleLink` can remain in flight. Increasing `--num-cores` therefore cannot overlap
two independent module front ends. `Logger::ScopedStagesDetailed` and `Logger::ScopedStageMute`
change shared logger state, and command metrics live in the process-wide `Stats` singleton.
Dispatching the existing module loop as worker jobs would also let its blocking
`waitAll(clientId)` calls exhaust the same worker pool they need to finish.

**Next.** Give each in-flight module its own log/metric scope and drive module stages from a
coordinator that never blocks a compiler worker on its own pool. Preserve the lifetime of each
compiler through artifact publication and linking, then admit independent ready modules within
the shared memory budget.

**Intent.** Schedule ready modules concurrently on the dependency DAG through a shared worker pool with explicit memory and CPU limits.

**Complete when.**

- Independent sibling modules overlap front-end and code-generation work, while consumers wait for the required interface or link artifact.
- Compiler and linker work share a bounded concurrency policy and do not oversubscribe the host.
- Logs, manifests, diagnostics, and emitted artifacts remain deterministic.
- The concurrency cap accounts for the memory measurements and budget from compiler.core.005.
- Workspace tests cover a diamond graph, concurrent failures, cancellation, and deterministic repeated builds.

**Related:** compiler.core.004, compiler.core.005.

### compiler.core.057 — The lazy-body completion race has no deterministic regression

- Recorded: 2026-09-24 14:07
- Updated: 2026-09-29 14:26 — Root cause fixed; only the regression seam remains.
- Area: compiler/semantic analysis, lazy bodies of generic-instance, imported and runtime functions.
- Evidence: `Core.HashTable.find` (`hashtable.swg:594`, `.tryFind(key)`) intermittently reached
  `resolveSelectedCallFunction` with no bound function symbol, once in a six-worker
  `std/core --rebuild` comparison on 2026-09-24 and once in
  `tools/std.swgs dm test core -bc release` on 2026-09-29. The declaration walk that hands a
  body to the lazy runner could still complete the function in `AstFunctionDecl::semaPostNode`:
  it read `LazyBodyRunning` twice, and a runner starting between the two reads made the walk
  publish the function and schedule its code generation while the runner was still resolving
  the body. `semaPostNode` now leaves a delegated body to its runner. A temporary 3 ms delay
  between the two reads made one core release test report six premature completions
  (`Core.Array.grow`, `Swag.panic`, `Core.HashTable.tablePtr`, `__ftoa`) and stop on a missing
  identifier symbol in code generation; with the fix, three delayed runs and ten undelayed runs
  passed with none.
- Why no suite test: the failure needs another task to start the lazy run inside a window of a
  few instructions in the declaration walk. No suite source or C++ test can place a thread there.
- Next: add a DevMode scheduling-stress option that delays the declaration walk's post-node
  when its function has a lazy body, and run `tools/std.swgs dm test core -bc release` with it
  from the `cpp` or `workspace` campaign. Check whether `compiler.core.047` (a generic local
  defined twice in `HashTable`) reproduces under the same stress before attributing it here.
- Complete when: a repeatable test fails without the post-node ownership check and passes with it.

### compiler.core.052 — Isolate a transient null-capture diagnosis in a macro binding

- Recorded: 2026-09-16 19:54
- Area: compiler/codegen, captured variables, static sanity
- Evidence: a Release `swc.exe` 728 full native test (`-bc release --num-cores 6`)
  diagnosed twelve null dereferences at `total += seed` in
  `bin/unittests/native/inline/binding_visit_growth.swg`. The source is already a
  permanent regression test and is unchanged during this investigation.
- Reduction: standalone builds 712 and 714 passed; build 718 failed using the
  original session output/work roots, then passed with new output/work roots.
  An identical source copied outside the checkout passed with the same 718 binary.
  Build 730 with temporary pre-sanity tracing passed. Tracing was removed; integrated
  build 731 passes all 3,277 native tests and the expected-failure recovery probes.
  These observations do not distinguish cache/work-directory state from scheduling
  or another input. They do not prove that a particular optimization introduced or
  fixed the failure. The diagnostic is emitted before the micro optimization loops.
- Evidence artifact: [generated-code session](../bench/results/generated-code/20260916/README.md).
- Next: repeat the unchanged standalone source with controlled work directories and
  six workers, preserve the failing pre-sanity capture lowering, and distinguish
  cache reuse from shared code-generation state when cloning the macro's closure.
- Complete when: a stable reproducer identifies the cause, the correction passes
  that reproducer repeatedly, and the full native suite remains green.

### compiler.core.045 — A conditionally evaluated `!` cannot record the proof it makes

- Recorded: 2026-09-15 12:47
- Found while: making the postfix `!` prove its own path so a second one on that path is
  rejected (`sema_err_notnull_already_proven`).
- Evidence: a proof is recorded by mutating live frames in place, because pushing a frame with
  an ancestor-anchored pop from the middle of a statement breaks the LIFO discipline of the
  deferred pops. The right operand of `and`/`or`, a branch of `?:`, the fallback of `orelse` and
  the tail of a `?.` chain are each evaluated on a decision taken to their left, and none of them
  carries a frame of its own: `AstLogicalExpr::semaPostNodeChild` pushes one only when the left
  side yielded facts, and the other three push none. A fact recorded inside one would therefore
  outlive the region that justifies it, so `notNullRunsUnconditionally` in
  `Sema.Function.Flow.cpp` refuses to record anything there.
- Cost: `p!` written in those positions teaches the compiler nothing, so a later `!` on the same
  path is not reported and its runtime guard is still emitted. Measured on the 2026-09-15 sweep:
  246 assertions were removed across `bin/`, and the paths left untouched are dominated by
  sibling `case` bodies (which are correctly out of scope) and by these conditional operands.
- Next: give each conditionally evaluated operand its own frame unconditionally — the `and`/`or`
  right side whatever the left side yielded, both branches of `?:`, the `orelse` fallback, and
  the `?.` chain tail — then drop the `notNullRunsUnconditionally` guard and let the frame pop
  scope the fact. Measure sema time on `bin/std` before and after: this adds a frame push per
  logical expression.
- Complete when: `p!` in an `and` right side proves the path for the rest of that operand and
  for nothing beyond it, with a JIT case for each of the four forms in
  `bin/unittests/jit/flow/nullable_narrow.swg` and the negative controls in
  `bin/unittests/errors/sema/sema_err_notnull_already_proven.swg` still passing.

### compiler.core.038 — Measure the remaining semantic frame construction cost

- Recorded: 2026-09-09 15:04
- Updated: 2026-09-14 06:24 — narrowed the investigation after conditional frame copies and compact safety state landed
- Historical evidence: Release 0.1.425 pushed 41,573 frames for a 22,800-line file and
  259,030 for a snippet importing `core`; `SemaFrame` then occupied 1,376 bytes. Removing
  one copy at 42 push sites was tried and reverted after three paired runs measured
  100.0%, 102.6%, and 103.8% of baseline processor time. The earlier attribute-list shrink
  had removed non-trivial string-vector construction and destruction, not just copy bytes.
  Those counts and sizes describe that build, not the current implementation.
- Current evidence: `Sema::preNode` now copies a frame only when a node introduces syntax,
  compiler-evaluation, or generated-top-level context, directly into the scoped destination.
  `AttributeList` now summarizes sanity and runtime-safety overrides with masks instead of
  copying override histories (`ab595100b`, `55a30fbbf`). `SemaFrame` still owns non-trivial
  collections for namespaces, bindings, iteration borrows, hidden symbols, and narrowing
  facts, and `AttributeList::attributes` still stores attribute instances. The
  [September 13 report](../bench/results/compilation/20260913-sema-codegen/README.md)
  records the implemented reductions and their validation; it does not establish how much
  these remaining members cost or attribute a timing gain to this entry alone.
- Next: remeasure frame-push counts, populated-member frequency, and constructor/destructor
  samples on the current compiler for both original workload shapes. Only select a member
  for deferred storage or a call site for reuse if that measurement shows a material cost;
  the reverted copy-only experiment is not evidence that the current cost is zero.
- Complete when: current measurements either identify a bounded, worthwhile change with a
  reproducible A/B comparison, or show that the residual cost does not justify further work.
- Related: compiler.core.001, compiler.core.005, compiler.core.006.

### compiler.core.004 — The benchmark campaign has no regression threshold on the edit-build loop

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-10 19:43 — Account for the September 6 campaign that already records edit-build workloads.

**Evidence.** Since 2026-09-05 the campaign measures the edit-build loop beside the seven tasks: `core_rebuild`, `core_noop`, `core_touch`, `hello_build`, `doc_std` and `format_tree` (`bench/toolchains.py`, `make_compiler_workloads` and `make_hello_builds`), each recorded with wall time, every sample and peak memory, corrected by the campaign's compilation context and indexed against the first clean campaign that measured it (`history.py`, `index_loop`). `bench/compile.py` answers the round-by-round A/B between two compilers. On 2026-09-05, Release 0.1.366, six worker cores, medians of five on a quiet machine: `core_rebuild` 3 485 ms, `core_noop` 334 ms, `core_touch` 3 214 ms, `format_tree` 5.6 s at one busy core, `doc_std` 142 s and 3.3 GiB peak, the standard-library publish pass included. The four August protocol-2 records predate these workloads. The later
[20260906-143159 record](../bench/results/20260906-143159.json) contains all five `loop`
workloads and the separate hello-world build result. One such record does not establish the
five-campaign baseline band required below.

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

### compiler.core.006 — Every process rebuilds the prelude state

- Recorded: 2026-08-06 20:18
- Updated: 2026-09-09 12:34 — remeasured on 0.1.422 against the Swag Prism edit loop

**Evidence.** On 2026-09-05 (Release 0.1.369, six worker cores, quiet machine): `swc help` 34 ms, `swc syntax` on an empty file 35 ms, `swc sema` on the same 165 ms. The prelude is 14 files and 32 948 tokens; its semantic pass, including the JIT run compiler.core.030 describes, is what separates the last two numbers, and every module setup used to pay it once more until the setup cache of 0.1.367 kept the result.

**Evidence (2026-09-09, Release 0.1.422, twelve workers).** Measured against the Swag Prism edit loop, which compiles one snippet per keystroke: a snippet module that imports nothing takes 116 ms, of which 16 ms is process start and 48 ms is lowering the runtime (compiler.core.030). The remaining 52 ms is this entry — the prelude analyzed again for a snippet that never changes it.

**Intent.** Serialize and reuse the prelude through the same module-interface mechanism as ordinary dependencies, rather than maintaining a special prelude cache.

**Complete when.**

- A warm hello-world build and a warm script launch load the prelude interface without lexing, parsing, or semantically rebuilding the prelude.
- Prelude source, compiler version, target, and relevant configuration changes invalidate the interface.
- Fresh and reused prelude paths produce identical diagnostics and artifacts.
- The compiler.core.004 campaign demonstrates the reduced fixed startup floor.

**Related:** compiler.core.001, compiler.core.004, compiler.core.016.

### compiler.core.001 — Dependencies cross the module boundary as regenerated source

- Recorded: 2026-08-06 20:18
- Updated: 2026-09-09 12:21 — measured what the regenerated API costs an interactive consumer

**Evidence.** Swag Prism compiles one snippet per keystroke through a `swc build`, and on 2026-09-09 (Release 0.1.421, quiet machine, minimum of nine interleaved runs) that compilation cost 294 ms of which the user's code was 1 ms: a five-line snippet took 400 ms and a 1 400-line one 421 ms. The fixed cost decomposes into 17 ms of process start, 32 ms for the runtime prelude, 14 ms for the module setup, 60 ms to lower and link the runtime, and **172 ms to lex, parse, and analyze `core`'s generated API again** — 32 files and 115 000 tokens, on every keystroke. The heavier viewers pay the same cost scaled by their dependency: `pixel` 248 000 tokens and 672 ms, `gui` 365 000 tokens and 986 ms. A binary module interface is what removes that term; nothing else in the budget is large enough to reach a realtime edit loop.

**Intent.** Replace generated dependency API source with a versioned binary module interface. The interface must preserve exported symbols, types, constants, attributes, ABI information, and any bodies or metadata required by downstream optimization, while allowing lazy lookup by symbol.

**Complete when.**

- Workspace imports no longer add generated API `.swg` files to the lexer and parser.
- `--export-api-dir` still emits a human-readable `.swg` representation for inspection and tooling.
- Cache invalidation covers compiler version, build configuration, public declarations, exported constants, ABI-relevant attributes, and serialized inlinable bodies.
- Workspace tests prove that fresh and reused interfaces produce identical diagnostics and artifacts.
- One snippet compilation that imports `core` no longer spends its time in the front end of that import.

**Related:** compiler.core.002, compiler.core.006, compiler.language.service.001, compiler.language.service.003, compiler.core.030.

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
