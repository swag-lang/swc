# Compiler Backlog

This backlog covers the compiler front end, back end, and workspace build engine. Documentation, formatting, and language-design work have their own domain files. Only unfinished work belongs here; completed investigations and implementations remain discoverable through Git history.

Entries stay in one flat list. Keep only measurements that affect the next action; refresh them before relying on them.


### compiler.core.082 — Hot-path node containers that need more than a container swap

  and listing-order slots; the other order-sensitive maps and the kept-table clear remain.
- Evidence: the October 9 prompt-4 pass replaced the node-based containers that sat on hot paths
  and could be swapped for flat ones with identical results (sema visited sets, impl snapshots,
  escape state, code generation node and variable payloads, value numbering, loop rotation and
  unrolling labels, stack offsets, sanitizer counts, inline binding uses, linker tables, the JIT
  address cache, the sanitizer register and stack facts, branch-simplify label and register
  counts, the per-function call and relocation sets, loop-invariant code motion's relocation
  chains, lifecycle type walks, switch case tables). It also stopped building tables most
  objects never fill (struct and enum impl guards, node payload side tables, generic instance
  indices, move-elision facts), formats the `where` instantiation text only when a constraint
  fails, sorts a function's symbols for unused captures only when it has a capture, and takes
  sema scopes from a per-Sema arena whose slots are never reused, because an inline payload keeps
  the address of the scope it was expanded from. Optimizer listings of `bin/unittests/native`
  compare equal before and after, in devmode and release. The sanitizer facts did not need an
  ordered replacement: every pass over them keeps or drops each entry on its own.
- Not worth the change: rebuilding the winner's `CallArgMapping` in `resolveFunctionCandidates`
  is one pass over the arguments into inline vectors, and reusing an attempt's mapping would have
  to prove that the attempted function and the selected one (possibly a generic instance) agree.
  `TypeGen::processTypeInfo` keeps its `stackSet`: the stack it mirrors can be deep, so a scan of
  it is not provably cheaper than the set.
- October 10: `TypeManager` interns array and aggregate types from their parts with the same
  hash, placement and equality, building a `TypeInfo` only for a new type; a compile-time run's
  buffers live in its pending entry (one allocation instead of two); flat tables replaced the
  per-run node containers of mem2reg, constant folding's constant addresses, loop-invariant use
  counts, register allocation and stack normalization label depths, the post-allocation peephole
  backtracks, SLP's definition scan (now shared by both lane widths) and register values, loop
  load forwarding, the native dependency closure, branch simplification's diamond label counts
  and referenced labels (`FlatKey64Set`, 64-bit keys) and implied-branch label uses,
  induction-variable use and definition counts, mem2reg's address registers and access lookup,
  definition summaries shared by loop-invariant code motion and SLP, loop-invariant code motion's
  per-loop sets, dead-code float counts, web renaming's sets, the sanitizer's escaped locals, the
  native function-info lookup and the module API dependency walk. Location sort keys convert a
  file's path once and the sort compares file parts and token numbers without building keys.
  Loop scans start and stop at a natural loop's body span. Pre-emit listings of eight bench tasks
  in devmode and release compare equal before and after, and single-core executables and
  `core.dll` keep identical code, unwind, debug, export and import sections.
- October 10: loop-invariant code motion replaces its node-based `hoistSet` and temporary `keep`
  set with `FlatKeySet` membership plus slots retained in listing order; emitted clones remain
  sorted by slot. The DevMode C++ suite passes all 1,420 tests.
- These remain, each needing a design change:
  - Node maps whose iteration order reaches the output: the sanitizer's sparse fact maps
    (`movedFrom`, `aliasPtrSlots`, ...), mem2reg's `slots`, SLP's `locations` and
    `entryValues`, web renaming's `loads`, and the native dependency walk's `rejected`. Each needs
    an order-preserving replacement.
  - A worker-kept `FlatKeyMap` clears its whole table, so a rebuild costs the largest function the
    worker has seen rather than the current one. Bounding it (stamped slots, or a list of the
    occupied ones) trades a per-insert cost for the clear; that tradeoff needs the benchmark
    campaign.
- Next: design an order-preserving flat map for the sanitizer's sparse facts, then audit the
  other listed node maps against their output ordering requirements.
- Done when: each item is replaced with identical output and its owning suites green, or
  recorded here as not worth the change it needs.
- Related: compiler.core.060.

### compiler.core.074 — Repeated native rebuilds choose different prologues

- Evidence: two consecutive full `native -bc release --rebuild` suite runs with the same
  Release compiler (build 1173, prompt-4 working revision based on `656356844`) both pass
  3,545 tests, but `dumpbin /unwindinfo` reports 6,713 and 6,712 function records. Comparing
  records without addresses finds eleven changed groups, including one removed leaf record,
  different saved registers, and stack allocations changing from `0x700` to `0xAF0`.
  Both commands cap the outer script and inner compiler at six workers and use isolated
  temporary caches. No compiler rebuild occurs between them.
- Scope: this was observed while removing the redundant sort in `X64UnwindWindows::buildInfo`.
  That routine serializes already generated prologue operations; the record differences also
  occur between runs of the same changed binary. This does not establish when the variation
  was introduced, nor whether its cause is semantic ordering, automatic inlining, or allocation.
- October 3: three causes found and fixed. A by-value aggregate argument that folds to a
  constant (`#curlocation` in every `Swag.panic` call) had its call-argument storage detached
  by the folding cast and registered again on every sema rerun, each copy keeping a frame
  slot: `allocatorCorruptedFreeList` in the runtime got a 0x40 to 0x130-byte frame from one
  build of the same benchmark to the next. `.rdata` was laid out by constant shard and
  creation offset, which follow job scheduling; it now follows the order the code reaches
  each constant. And a source-location constant chose its shard from the function's address
  and the source view's load index, so two locations in one file shared their file-name
  string in some builds and not in others, shifting the whole section; the shard now comes
  from the file and function names. Over five pairs each of `sort`, `wordfreq` and `nbody`
  builds, the code (ignoring addresses), `.pdata` and `.xdata` no longer vary, and `.rdata`
  differed in one pair only, by 41 bytes, next to a `.data` difference.
- October 9: two consecutive `std.swgs build core -bc release --rebuild --num-cores 1` runs of the
  same Release compiler (prompt-4 branch at `f3a0c10b3`) give `core.dll` files whose `.text`,
  `.pdata`, `.xdata`, `.swagdbg`, `.edata` and `.data` sections are byte-identical, while `.rdata`
  is 259,583 against 259,543 bytes (103,866 differing bytes from offset `0xb60`, the shifted
  addresses of data-only references) and `.reloc` differs accordingly. Six-core rebuilds also
  change the file size by 512 bytes. The code itself is stable; one `.rdata` allocation still
  changes size or order between runs, even without parallel workers.
- October 10: single-core builds of the same bench task by the same Release compiler still
  differ in `.rdata` and `.reloc` alone, in about one build of two. In `lz77` the difference is
  one empty-string payload: a reflected type value's empty name points into an allocation reached
  early in one build, and into its own one-byte allocation emitted just before
  `"[..] Swag.TypeValue"` in the other, shifting every later string by one byte. Type-info
  strings come from shard 0's `DataSegment::addString`, which deduplicates per segment; which
  allocation first holds `""` follows the order type infos are generated.
- What still varies: the offsets of globals in `.data` and `.bss`. They are assigned while
  sema runs in parallel, so the addresses that code and relocations use differ from one
  build to the next (48 to 5,800 bytes per pair).
- Next: give globals a layout decided at emission from a stable key (module, file, declaration
  order) instead of first-come offsets, keeping the JIT's addresses valid; then repeat the
  unwind record comparison to see whether another prologue cause remains.
- Done when: the source of the different prologues is explained and corrected at its
  owning boundary, with stable normalized output and the affected native tests green.

### compiler.core.060 — A compile-time call still pays per-call plumbing its call graph does not need

- Area: compiler/JIT, compile-time execution, compilation time
- Evidence: the remaining repeated work is visible in the current call paths:
  - `patchConstantFunctionRelocationsRec` walks the whole constant closure of each constant a
    patched function names, once per function, taking the allocation lock and the relocation lock
    for every allocation it visits (each allocation's relocations are copied into an inline list
    since October 10). The semantic walk over the same graph remembers an allocation per
    relocation version; this one remembers nothing between functions. A patchable target is the
    function's patch address once it has one and its work address before, so a slot patched early
    can later receive a different address: a memo across functions must keep re-patching or prove
    the address no longer moves.
  - `prepareJitFunction` builds the JIT order once before waiting for sema and again after, only
    to compare sizes. The order follows the call graph and the native init targets, which both
    carry a version; reusing the first order when neither moved needs every other input of the
    walk (ignored functions, macro attributes) to move one of them too.
  - `TypeRuntimeHash::canonicalScopedNameHash` rebuilds a symbol's full scoped name for every
    runtime hash that meets it, while `Symbol::scopedNameHash` caches the same value. Using the
    cache needs proof that no symbol's scope chain changes after its hash is first taken;
    otherwise a reflected type's identity could differ between modules.
  - `SemaEscape::propagateCompletedFreesSummaries` runs twice per prepared compile-time call. Its
    memo keys on the count of semantically completed symbols, which moves while sema runs. The
    unguarded path retains applied forwardings and appends only new edges, but each new signature
    still scans the pending edges; an edge whose callee never frees its parameter stays pending.
    The guarded path also reconstructs its closure-local return-summary table. A worklist keyed by
    callee could revisit an edge only when its callee's mask or either end's completion changes.
- Next: measure these remaining walks on a `gui` release rebuild. Before remembering patched
  allocations across functions, preserve deferred-function registration and the `Pause` path;
  a memo must account for both. Preserve the guarded return proofs and late completion when
  replacing the release scan with a worklist.
- Done when: each item is either removed with compile-time execution and safety tests, or
  recorded as measured and not worth its risk.
- Related: compiler.core.030.

### compiler.core.081 — An imported generic method once lost its own parameter

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
- Done when: the ordering is proved safe by construction or the race is reproduced and
  fixed with a regression case in the `workspace` suite.

### compiler.core.080 — Published generic bodies call omitted helper declarations

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
- Done when: a consumer importing the generated Core API hashes equal standalone and base-view
  dynamic values consistently with both hash widths, and a publication regression protects the
  dependency boundary without relying only on tests compiled inside the provider. Imported
  generic XML numeric and textual reads must also resolve their implementation dependencies.

### compiler.core.047 — Imported generic bodies intermittently lose or duplicate bindings

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
- Done when: a bounded reproducer identifies the duplicate visitation or publication,
  the root cause is fixed, and the script passes repeated parallel imports with six workers.

### compiler.core.078 — Reduce a suspected nested-owner release false positive

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
- Done when: a standalone regression explains the diagnostic as valid or protects the
  corrected ownership summary without GUI or graphics dependencies.

### compiler.core.064 — A compiler-held dependency DLL blocks child rebuilds

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
- Done when: the fixture rebuilds the dependency while its parent compiler remains alive,
  with both compiler executables, and workspace reuse and publication checks still pass.

### compiler.core.030 — Reuse lowered runtime code across executables

- Evidence: executable lowering starts from reachable roots, but runtime functions reached through relocations are lowered for every executable. The existing function cache skips functions with code relocations.
- Next: profile a current `hello_build`, identify the runtime functions repeatedly lowered, and determine whether their relocations can be represented in a reusable artifact keyed by compiler build, runtime sources, configuration, and target.
- Done when: a fresh and reused runtime artifact produce identical executables and the cache invalidates on every relevant input change; delete the entry if no safe reusable subset remains.
- Related: compiler.core.003, compiler.core.004, compiler.core.006.
### compiler.core.039 — Avoid repeated substitute-chain resolution during semantic analysis

- Evidence: comparison lowering and payload metadata merging already reuse resolved values. Other high-frequency `SemaNodeView` callers may still resolve the same substitute chain repeatedly.
- Next: profile a current module analysis that imports `core`, attribute repeated resolutions to callers, then choose call-site reuse or memoization only where the profile shows meaningful duplicate work.
- Done when: a measured duplicate-resolution cost is removed without changing narrowing or constant semantics, or current profiling shows no worthwhile target and the entry is deleted.
- Related: compiler.core.001, compiler.core.038.
### compiler.core.020 — Concurrent type generation can corrupt declared-method traversal

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
- Done when: a recurrence is attributed through its captured stack and fixed with a
  regression, or a parallel type-generation stress run over the whole standard library under both
  compiler executables stays clean and the lead is retired.

### compiler.core.021 — JIT code leaks one thread-local index per compiler instance

- Area: compiler, JIT runtime hosting
- Found while: tracking an intermittent JIT '#test' failure in `swc test -w bin/apps -m swagcapture
  --rebuild`: imported native modules kept `Swag.processInfos().args` slices into the storage of a
  destroyed dependency-build instance. That storage is interned for the process since.
- What remains: JIT code also takes plain thread-local indexes through `TlsAlloc` (the allocator's
  fast heap slot, for example). They have no callback, so nothing reads them after the instance
  dies, but each instance that ran its allocator keeps one index allocated for the rest of the
  process, and Windows has 1,088 of them.
- Next: count the indexes a long workspace run (`tools/std.swgs dm test`) leaves allocated, and if
  the count grows with the number of instances, record the `TlsAlloc` indexes per instance the
  same way and free them at destruction.
- Done when: a process that creates and destroys many compiler instances keeps a bounded
  number of thread-local indexes, with the workspace suite green under the poisoning.

### compiler.core.053 — Confirm that a linked PDB keeps one definition per structure

- Area: compiler/backend, `DebugInfoCodeView` type table, integrated PDB writer
- Evidence: `swc tools/apps.swgs dm build swagscope --debug` (build 847) wrote a 12.2 MB PDB
  whose TPI stream held 38,154 records, 5,178 of them `LF_STRUCTURE`, with `Surface` defined 28
  times, `interface` 26, `Wnd` 24 and `Application` 22.
- What remains: `LinkDebugMerger` already keeps one copy of each record once remapped, so the
  copies archive members brought came from records that differed only by which index a pointer
  named. With pointers now naming forward declarations those records should coincide, but no
  linked `--debug` program with debug archives has been measured yet.
- Next: build swagscope with `--debug` before and after this change and compare the PDB size,
  the TPI record count and the number of `LF_STRUCTURE` records per name.
- Done when: every structure has one definition per distinct layout in a linked PDB, the
  `DebugInfo_*` and `Pdb_*` tests pass, and the swagscope `--debug` PDB shrinks accordingly.

### compiler.core.046 — A `!` buried in a `Swag.assert` argument proves a path the guard may not check

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
- Done when: the chosen rule is implemented or documented, with a case showing what
  `Swag.Safety(.Assert, false)` does to the proof.

### compiler.core.072 — Link preparation resolves and places the native image on one thread

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
- Done when: `link prepare` no longer shows as serial time in the scheduler report, with the
  linker and PDB C++ tests, the native suite, and a linked consumer green under both executables.
- Related: compiler.core.069

### compiler.core.075 — Aligned node references collapse semantic metadata partitions

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
- Done when: the partitioning improvement has concurrent read/write coverage
  and a measured compilation-time benefit with its memory cost explicitly bounded.

### compiler.core.073 — A dependent module waits for its dependency's whole link before starting

- Evidence: `CompilerInstance::runWorkspace` keeps one deferred link in flight, but joins it before
  compiling any module that depends on the linked one. The `std` chain is nearly linear
  (`core` → `ogl`/`truetype` → `pixel` → `gui`), so most links become a wait: in 16-worker DevMode
  `gui` rebuilds, `--dev-sched-stats` charges 2.8–4.8% of worker time to the
  `workspace link wait` phase, nearly all of it starvation while the single `NativeLink` job
  (0.4–1.2 s per module) runs.
- Next: list what a dependent actually needs from its dependency before code generation (the
  module API and setup files, the DLL only for compile-time calls into it) and join the link at
  the first use that needs the binary instead of before the module starts.
- Done when: a dependent's semantic analysis overlaps its dependency's link in a `gui`
  rebuild, with the workspace suite and `std` tests green under both compiler executables.
- Related: compiler.core.069, compiler.core.007

### compiler.core.071 — WebP's macroblock reconstruction takes seconds to generate and holds back `pixel`

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
- Done when: no single function's code generation in `bin/std` takes more than a tenth of its
  module's wall time at 16 workers, without a measurable loss in WebP decoding speed.
- Related: compiler.core.069

### compiler.core.069 — Measure where a module build loses its workers beyond six cores

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
- Done when: each share above has an owning entry.
- Related: compiler.core.071, compiler.core.072, compiler.core.073, compiler.core.065, compiler.core.068, compiler.core.007

### compiler.core.068 — The job scheduler serializes every transition on one mutex

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
- Done when: a std module build at 16 workers spends no measurable time waiting on the
  scheduler lock (VTune or ETW contention view), with the scheduler unit tests and both compiler
  executables green.
- Related: compiler.core.069

### compiler.core.065 — Remaining barrier rounds still drain the whole module

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
- Done when: a std module build needs no barrier round to resolve forward identifier and
  type-completion dependencies, with the sema suite, the C++ scheduler tests, and std release
  green under both compiler executables.
- Related: compiler.core.069, compiler.core.007

### compiler.core.063 — Reduce the PDF spill-slot regression to a standalone language test

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
- Done when: `bin/unittests/native` reproduces this stack-depth aliasing independently of GUI,
  alongside the existing C++ regression and PDF consumer tests.

### compiler.core.061 — Type-info graph publication uses one serialization domain

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
- Done when: independent components can progress on different workers, mutually recursive
  graphs publish no partial data, and identity, interface, and reflection tests pass under
  repeated parallel cold compilation.
- Related: compiler.core.020, compiler.core.007.

### compiler.core.007 — Workspace front ends and code generation run serially


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

**Done when.**

- Independent sibling modules overlap front-end and code-generation work, while consumers wait for the required interface or link artifact.
- Compiler and linker work share a bounded concurrency policy and do not oversubscribe the host.
- Logs, manifests, diagnostics, and emitted artifacts remain deterministic.
- The concurrency cap accounts for the memory measurements and budget from compiler.core.005.
- Workspace tests cover a diamond graph, concurrent failures, cancellation, and deterministic repeated builds.

**Related:** compiler.core.004, compiler.core.005.

### compiler.core.005 — Set and enforce a compiler memory budget

- Evidence: parallel compiler jobs retain high-water allocations across semantic analysis, code generation, and the Micro pipeline. The current peak and largest retained owners need a fresh measurement.
- Next: measure peak memory for a six-worker `core` DevMode rebuild and a representative hello build, then attribute the largest retained allocations before selecting one reduction.
- Done when: the campaign publishes host-normalized memory limits, every selected workload stays within them, and a regression report names the responsible subsystem.
- Related: compiler.core.004, compiler.core.007, runtime.allocator.017.
### compiler.core.057 — The lazy-body completion race has no deterministic regression

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
- Done when: a repeatable test fails without the post-node ownership check and passes with it.

### compiler.core.003 — Code-generation invalidation is module-wide


**Current boundary.** Workspace manifests keep a completed module when its own inputs and the
dependency API generations it consumed are unchanged. The default build keeps an executable image
when only an interface-compatible dynamically linked implementation changed; the fresh DLL is
republished before a run. It also persists one deterministic COFF object containing a non-debug
executable's module-owned code and data. When only a static native dependency generation changes,
the workspace reloads that object, resolves the fresh archives, and writes a new PE without running
the consumer's front end or code generation. Imported native code executed at compile time remains
a strict invalidation boundary. Cache publication is atomic and best-effort, and a missing or
modified object falls back to a normal compilation.

The next cache layer now fingerprints raw per-function microcode before optimization. For a
non-debug executable, an unchanged function with at least 64 micro-instructions and no
code relocation reuses its COFF archive member, including unwind metadata, and skips the micro
passes and encoder. The cache remains one archive plus a compact index rather than one persistent
file per function. Entries carry the compiler build and backend configuration identity; malformed,
missing, renamed, or fingerprint-mismatched entries fall back to ordinary emission. The workspace
regression changes one large leaf while observing another reported as reused, then verifies that
`--rebuild` bypasses the cache.

**Evidence for the next layer.** The first function slice deliberately excludes calls, referenced
constants, debug information, and small functions: those need a canonical dependency fingerprint
or cost more to serialize than they save. `NativeObjFileWriter` already serializes one function per
archive member, and the integrated linker resolves those members lazily, so broader coverage should
extend the fingerprint and admission policy rather than create another storage format.

Do not content-hash the source tree in a separate warm-build pass. Reuse the manifest's read
boundaries for the cheap eligibility decision; when content fingerprints are later needed, compute
them while bytes are already being read. Do not write capsules for non-native outputs or failed
builds, and allow the write to be skipped below a measured code-generation cost threshold. Record
cache decision time, bytes read/written, and saved code-generation/link time so a hit that costs
more than it saves is visible.

**Next — broaden function-level code generation.** Admit functions with relocations by fingerprinting
their referenced symbol identities, constant payloads, reachable ABI, and inlinable bodies. Add
debug records only after their source identity and line mapping are deterministic. Measure an
adaptive size/cost threshold so small functions never pay more hashing and archive work than their
micro passes cost. Front-end state and binary module interfaces remain compiler.core.002 and
compiler.core.001 respectively; this entry consumes their semantic fingerprints rather than
inventing a second dependency graph.

**Performance gate.** Compare clean, no-op, private-body edit, static-dependency edit, and public-API
edit workloads with compiler.core.004. A clean build may not regress outside the established noise
band, a no-op cache decision must stay cheaper than launching code generation, and cache writes may
not extend the reported critical path. `--rebuild` remains the clean-build oracle while every safe
cache is part of the normal DevMode and Release paths.

**Done when.**

- A static-dependency implementation edit relinks a consumer without re-running its front end or
  code generation. Done for non-debug executable build/run/smoke commands.
- A body-only edit regenerates the changed function and any function whose generated code depends
  on it, while unrelated functions are reused. Done for sufficiently large relocation-free leaf
  functions in non-debug executables.
- Reuse works for native and JIT builds, including debug and unwind metadata.
- Clean and warm builds produce byte-identical deterministic cache entries and observably identical
  programs, and reject compiler, target, configuration, ABI, API, and optimization changes.
- The compiler.core.004 edit-build workloads demonstrate a material win with no measurable clean
  build regression.

**Related:** compiler.core.001, compiler.core.002, compiler.core.004, compiler.core.030.

### compiler.core.052 — Isolate a transient null-capture diagnosis in a macro binding

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
- Done when: a stable reproducer identifies the cause, the correction passes
  that reproducer repeatedly, and the full native suite remains green.

### compiler.core.051 — Isolate a silent CodeGen failure observed in a discarded JIT prototype

- Found while: comparing Release compilation of `bin/std` with six pinned performance workers.
- Evidence: an unmerged build-710 prototype based on `277804c1c` returned exit 5 on the third
  candidate rebuild of `swc.exe build -w bin/std -m gui -bc release --num-cores 6 --rebuild`.
  Seven dependency modules completed; gui stopped with
  `internal compiler error: job 'CodeGen' returned an error without a diagnostic`.
- Scope: the prototype transferred the existing shared JIT-order lock to its reader and reused
  local dependency/completion vectors. It was discarded. The same gui command passed once in
  DevMode; three further runs with unchanged Release build 702 passed. Neither a production
  regression nor a causal connection to either prototype change has been established.
- Evidence location: `bench/results/compilation/20260916-bin-release/README.md` and its sample
  CSV retain the command context, compiler hashes and failed run. The session's external
  `jit-order-lock-buffers-710.patch` and `jit-order-control` compilers retain the exact prototype.
- Next: capture the function, waited symbol and failing return path at `abortCodeGen`, replay
  candidate and baseline, and isolate lock transfer from vector reuse before reviving either
  optimization. Do not classify this as compiler.core.047 without a matching generic-local witness.
- Done when: a bounded reproducer identifies the responsible path, or evidence confines the
  failure to an invalid discarded prototype; remove this entry once that question is settled.

### compiler.core.038 — Measure the remaining semantic frame construction cost

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
- Done when: current measurements either identify a bounded, worthwhile change with a
  reproducible A/B comparison, or show that the residual cost does not justify further work.
- Related: compiler.core.001, compiler.core.005, compiler.core.006.

### compiler.core.041 — Reduce parallel dependency registration to a workspace-suite witness

- Evidence: the 2026-09-11 workspace build stopped inside `std::set::insert` reached from
  `semaCompilerInclude`. `NativeArtifact_ConcurrentCompilerInputsKeepEveryDependency` now forces
  six simultaneous writers and checks all included files, loaded files, and deduplicated imports;
  registration and snapshots share a mutex. That C++ boundary is covered, but the language suites
  cannot yet force the failing interleaving. A reduction with 256 independent source files and
  16,384 `#include` expressions over 256 byte fixtures passed both standalone semantic analysis
  and a workspace build with the unfixed Release 0.1.477 compiler; its manifest retained every
  fixture. Keeping that reduction as a regression would not distinguish the defect.
- Next: find a bounded source-level ordering or a workspace-test scheduling hook that exposes
  missing or corrupted dependency registration without depending on a large GUI module build.
  Keep the existing C++ concurrency test as the precise internal guard.
- Done when: a `bin/unittests/workspace` case fails with unsynchronized registration, passes
  with synchronized registration under both compiler executables with six workers, and verifies
  dependency retention and subsequent invalidation without an intermittent timeout as its oracle.

### compiler.core.004 — The benchmark campaign has no regression threshold on the edit-build loop


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

**Done when.**

- At least five clean baseline campaigns establish the resolution band of every edit-build workload, as the null indices already do for the tasks.
- The campaign reports a workload that moved past its band without silently rewriting the baseline.
- Release and DevMode are measured where their behavior differs, and the report says which one a number belongs to.

**Related:** compiler.core.002, compiler.core.005, compiler.core.007.

### compiler.core.006 — Reuse analyzed prelude state

- Evidence: each fresh compiler process analyzes the unchanged runtime prelude before compiling a module or script.
- Next: serialize the prelude through the ordinary module-interface mechanism and include source, compiler, target, and relevant configuration in its cache key.
- Done when: warm module builds and script launches skip prelude lexing, parsing, and semantic analysis, while fresh and reused paths produce identical diagnostics and artifacts.
- Related: compiler.core.001, compiler.core.004, compiler.core.016.
### compiler.core.001 — Replace generated dependency source with a reusable module interface

- Evidence: every workspace import currently adds generated API source to the dependent compiler front end, repeating lexing, parsing, and semantic analysis for unchanged dependencies.
- Next: define a versioned binary interface that preserves exported symbols, types, constants, attributes, ABI data, and bodies needed by downstream optimization; keep readable `.swg` export for inspection.
- Done when: workspace imports no longer parse generated API source, cache invalidation covers every exported input, and fresh and reused interfaces produce identical diagnostics and artifacts.
- Related: compiler.core.002, compiler.core.006, compiler.language.service.001, compiler.language.service.003, compiler.core.030.
### compiler.core.002 — Front-end invalidation is module-wide


**Intent.** Persist lexical, parsed, and semantic state per source file. Cache keys must include the source content, relevant build configuration, and fingerprints of imported public symbols actually observed by the file.

**Done when.**

- Editing a private body reanalyzes only the changed file and its semantic dependents.
- Changing a public signature invalidates every consumer that observed it.
- Adding, removing, or renaming a file, changing relevant configuration, and changing compiler versions invalidate the correct state.
- The compiler.core.004 `core_touch` workload lands far below `core_rebuild`, which today it does not: one saved file rebuilds every file of the module.
- Clean and incremental workspace builds are covered by equivalent-result tests.

**Related:** compiler.core.001, compiler.core.004, compiler.core.003, compiler.core.016.

### compiler.core.016 — Tool scripts recompile on every invocation


**Intent.** Persist compiled script artifacts using a dependency-complete key over loaded source files, imported public interfaces, compiler version, target, and relevant build configuration.

**Done when.**

- A second unchanged invocation skips script lexing, parsing, semantic analysis, and code generation before launching the cached artifact.
- Changes in the main script, `#load` inputs, imported public APIs, compiler version, target, or relevant configuration invalidate the artifact.
- Cached and fresh paths preserve diagnostics, forwarded arguments, environment handling, output, and exit code.
- Tests cover direct source changes, transitive loads, imports, configuration changes, corrupt entries, and concurrent cache population.

**Related:** compiler.core.001, compiler.core.002, compiler.core.006, platform.portability.080.

### compiler.core.027 — A run-time loaded shared library cannot share the host's runtime

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
- Done when: either a loaded shared library provably shares the host's allocator and context in
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
