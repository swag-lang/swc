# Runtime API Backlog

This backlog covers the public surface of [bin/runtime](../bin/runtime): the `Swag` namespace,
its constants, the per-thread `Swag.Context`, the allocator interface, and the intrinsic
spellings the lexer resolves under `Swag.`. The allocator implementation has its own file,
[runtime.allocator.md](runtime.allocator.md); the concurrency contract is in
[language.parallelism.md](language.parallelism.md). [README.md](README.md) has the whole layout.

The runtime is about 11.7k lines of Swag in 22 files. That size is comparable to Odin's
`base:runtime` and to Jai's preload and runtime support, and far below Go or Swift. These
entries do not ask to shrink it. They ask that its public surface follow one admission rule,
one naming rule, and the meaning other languages give the same names.

Several entries rename a public name or a lexer token. Follow
[reflect-swag-syntax-changes](../.agents/skills/reflect-swag-syntax-changes/SKILL.md) for any
`Swag.` intrinsic spelling, and
[design-swag-bin-modules](../.agents/skills/design-swag-bin-modules/SKILL.md) for every public
declaration. `src/Backend/Runtime*.h` mirrors part of `api.swg` field by field; keep both sides
in sync in the same change.

### runtime.api.002 — `F32.Min` is the smallest positive value, unlike every other `Min`

- Evidence: in [api.swg](../bin/runtime/api.swg) `Swag.S8.Min` through `Swag.S64.Min` are the
  most negative values, while `Swag.F32.Min = 1.17549435e-38` and `Swag.F64.Min = 2.2250738e-308`
  are the smallest positive normal values (C's `FLT_MIN`). Rust's `f32::MIN`, C#'s
  `float.MinValue` and Go's `-math.MaxFloat32` idiom all mean the most negative finite value.
  The same name meaning two things inside one family is a trap; the Core vector constants
  already carry a warning comment about it (`Vector2.Min`: "not the most negative value").
- Evidence: the deliberate uses of the smallest normal are
  [parse.swg:326](../bin/std/modules/core/src/text/parse.swg#L326) and its test
  [parse.test.swg:59](../bin/std/modules/core/src/tests/text/parse.test.swg#L59), plus the
  `Math.Vector2/3/4.Min` constants and their tests in `vector.test.swg`. `F64.Min` has no use.
- Proposed contract: for every numeric type, `Min` and `Max` are the ends of the finite
  representable range, so `F32.Min == -F32.Max`. The smallest positive normal value is
  `F32.MinNormal` / `F64.MinNormal`. Keep `Inf`, `NegInf`, `NaN`, `MantBits`, `ExpBits` and
  `Bias` unchanged (`Bias` follows Go's `float64info` convention used by `decimal.swg`).
- Next: add `MinNormal`, move the parse code and test to it, decide whether
  `Math.VectorN.Min` follows `F32.Min` (recommended: yes, and drop the warning comment), and
  flip `F32.Min` / `F64.Min` in the same commit after grepping every remaining `F32.Min` and
  `F64.Min` in `bin/`, `tools/` and `bin/reference`. A silent meaning change cannot be split
  across commits.
- Done when: `Swag.F32.Min == -Swag.F32.Max` and `Swag.F64.Min == -Swag.F64.Max`, `MinNormal`
  exists and is documented, no maximum accumulator in `bin/` starts from a positive constant,
  and the Core, GUI and Pixel tests pass.

### runtime.api.003 — `Swag.Context` is 7 KB per thread and caps error nesting at 32

- Evidence: measured with `#sizeof` in a `.swgs` probe, `Swag.Context` is 7,064 bytes.
  `errors: [32] ErrorValue` takes 4,608 of them (65%), because each 144-byte `ErrorValue`
  embeds a whole 88-byte `ScratchAllocator` (`pushErrorAllocator`). `traces: [32]
  SourceCodeLocation` takes 1,536, `panicStack: [64] *void` 512, and the two scratch allocators
  176. Odin's context is about a hundred bytes; Jai's is a few hundred.
- Evidence: every worker ([scheduler.swg:58](../bin/runtime/scheduler.swg#L58)), every executor
  ([executor.swg:59](../bin/runtime/executor.swg#L59)), every `Core.Thread`
  ([thread.swg:29](../bin/std/modules/core/src/thread/thread.swg#L29)), every `Core.Timer`
  ([timer.swg:21](../bin/std/modules/core/src/time/timer.swg#L21)) and the XAudio2 thread own a
  full context by value. `System.pushContext(cxt: Swag.Context, ...)`
  ([system.swg:6](../bin/std/modules/core/src/system/system.swg#L6)) takes it by value, so the
  ordinary "copy the current context, change the allocator, push it" pattern moves 7 KB of
  stack per use.
- Evidence: the error stack is a fixed `[32] ErrorValue`. Each active `catch`/`expect` holds
  one frame for its body, so a recursion that calls itself under `catch` stops with a panic once
  the frames in use reach 31 (`__pushErr`, pinned by `native/runtime/error_nesting.swg`). Nothing
  in the language reference states the limit.
- Evidence: `user0`..`user3: u64` are four untyped slots. Their only users in `bin/` are
  `core/src/tests/system/context.test.swg`, which uses `user0` as a marker.
- Next: decide the layout from the four costs above, in this order. (1) Keep the error frame
  stack small: store in `ErrorValue` only what `__popErr` restores (block, used, capacity), not
  a whole `ScratchAllocator`, and measure the new `#sizeof`. (2) Either grow the error stack on
  demand (the frames could live in the wrapper's own stack frame, which already owns an
  `ErrorCapture`) or state its depth in the reference next to `catch`.
  (3) Make `pushContext` take `const *Swag.Context` (or a by-reference parameter) and
  migrate its callers. (4) Replace `user0..3` by one `userData: *void?` plus one `userTag: u64`,
  or remove them if no consumer wants them. Keep the fields marked "must stay first" and the
  C++ mirror in [RuntimeContext.h](../src/Backend/RuntimeContext.h) in sync.
- Done when: `#sizeof(Swag.Context)` is recorded in a test, the error stack no longer embeds a
  scratch allocator per frame, the nesting limit is either gone or documented and tested, and
  `pushContext` no longer copies a context.
- Related: runtime.api.007, language.parallelism.001

### runtime.api.004 — The `Swag` namespace has no admission rule, and the build API lives in it

- Evidence: [api.swg](../bin/runtime/api.swg) (1,909 lines) serves five audiences in one
  namespace: the language vocabulary (`AttrUsage`, `Inline`, `Macro`, `Foreign`, `Safety`...),
  reflection (`TypeInfo*`, `TypeValue`, `Attribute`), runtime services (`Context`,
  `IAllocator`, `ScratchAllocator`, errors), build scripts and the compiler interface
  (`BuildCfg`, `BuildCfgBackend*`, `BuildCfgGenDoc`, `BuildCfgDocTheme`, `BuildCfgWarnings`,
  `CompilerCommand`, `CompilerMessage*`, `ICompiler`), and the intrinsic declarations. A program
  that never builds anything still has `Swag.BuildCfgDocTheme` beside `Swag.Context`.
- Evidence: concurrency is split between `Swag` (`Task`, `TaskGroup`, `Mutex`, `RWLock`,
  `Condition`, `Semaphore`, `Barrier`, `AtomicValue`) and `Core` (`Thread`, `Sync.Event`,
  `Sync.Mutex`, `Sync.RWLock`, `Atomic`). The runtime half is there because `parallel for`
  lowers into the scheduler; no written rule says so, so the next addition has nothing to
  follow.
- Evidence: 20 files in `bin/` and `tools/` name `BuildCfg` or `buildCfg`; `ICompiler` and
  `CompilerMessage` have three users outside `api.swg` (the reference page
  `015_004_compiler_interface.swg` and two unit tests). The C++ side looks these types up by
  name through the mirrors in `src/Backend/Runtime*.h`.
- Proposed rule: a declaration belongs to `Swag` when the compiler knows it by contract (it
  emits calls to it, lowers syntax to it, mirrors its layout, or reads it back at compile time)
  or when the process must have exactly one of it (allocator, scheduler, context). Everything
  else belongs to a module. Build and compiler API belong to a nested namespace
  (`Swag.Build`), not to the root.
- Next: write the rule in the runtime documentation page of `bin/reference`. Split `api.swg`
  into files by audience (`attributes.swg`, `reflection.swg`, `context.swg`, `build.swg`,
  `intrinsics.swg`) without renaming anything, and update the `api.swg` paths quoted in
  `src/Backend/Runtime*.h`, `SemaSpecOp.h` and `CompilerInstance.cpp`. Then move the build and
  compiler declarations under `Swag.Build`, dropping the now redundant `BuildCfg` prefix of
  nested types (`Swag.Build.Backend`, `Swag.Build.DocTheme`...), and migrate the 20 files.
- Done when: the rule is published, `api.swg` is split by audience, the build and compiler
  declarations are out of the `Swag` root, and every remaining `Swag` declaration satisfies the
  rule or has its own entry.
- Related: std.core.031, std.core.035, language.parallelism.001

### runtime.api.005 — Intrinsic spellings follow three conventions and leak x86 mnemonics

- Evidence: the `Swag.` intrinsics declared in
  [Tokens.Def.inc](../src/Compiler/Lexer/Tokens.Def.inc) use three casings at once.
  camelCase: `getContext`, `setContext`, `stringCmp`, `typeCmp`, `kindOf`, `makeSlice`,
  `makeAny`, `tableOf`, `byteSwap`, `bitCountTz`, `bitCountLz`, `bitCountNz`, `postMove`,
  `postCopy`, `safetyPanic`. Run-together lowercase: `muladd`, `atomadd`, `atomand`, `atomor`,
  `atomxor`, `atomxchg`, `atomcmpxchg`, `atomget`, and the 31 `vec*` intrinsics
  (`vecreduceadd`, `vecinterleavelo`, `vecwidenhi`...). C names: `memcpy`, `memmove`, `memset`,
  `memcmp`. A reader cannot predict `Swag.mulAdd` from `Swag.byteSwap`, and `Core.Math.mulAdd`
  wraps `Swag.muladd` with the other casing.
- Evidence: several vector intrinsics are named after x86 instructions rather than after what
  they compute: `vecmaddubs` (`pmaddubsw`), `vecmadd` (`pmaddwd`), `vecpackus` / `vecpackss`
  (`packuswb` / `packsswb`), `vecsad` (`psadbw`), `vecclmul` (`pclmulqdq`), `vecavgr` (`pavgb`),
  `vecmulhi`, `vectruncs32`. An ARM64 port keeps the names but loses their meaning.
- Evidence: migration size in tracked sources: 607 `Swag.vec*` uses in 28 files, 187
  `Swag.atom*`, 72 `Swag.bitCountNz`, 22 `Swag.muladd`. Core already wraps most of them
  (`Core.Atomic`, `Core.Math`, `Simd`), so most consumers do not name the intrinsic directly.
- Proposed rule: camelCase for every intrinsic, like the rest of the language; keep the four
  C memory names as the single documented exception. Atomics become `atomicAdd`, `atomicAnd`,
  `atomicOr`, `atomicXor`, `atomicExchange`, `atomicCompareExchange`, `atomicLoad`; vectors
  become `vecSplat`, `vecReduceAdd`, `vecInterleaveLo`... ; `muladd` becomes `mulAdd`.
  ISA-named vector intrinsics get semantic names chosen with cpu.simd's owner, for example
  `vecDotU8S8Pairs` (maddubs), `vecDotS16Pairs` (madd), `vecNarrowSatU` / `vecNarrowSatS`
  (packus/packss), `vecSumAbsDiff` (sad), `vecCarrylessMul` (clmul), `vecAvgRound` (avgr),
  `vecMulHigh` (mulhi).
- Next: write the full old-to-new table in this entry and get it approved before touching the
  lexer. Then rename the tokens, the declarations in `api.swg`, the reference, the VSCode
  grammar and every consumer in one change per family (atomics, vectors, scalars), with no
  compatibility aliases, as the reflect-swag-syntax-changes skill requires.
- Done when: every `Swag.` intrinsic except `memcpy`, `memmove`, `memset` and `memcmp` is
  camelCase, no vector intrinsic is named after an x86 instruction, and the reference and
  VSCode grammar list the new spellings only.
- Related: runtime.api.006, cpu.simd.012, std.core.031

### runtime.api.006 — Opaque and unidiomatic public names in the runtime

- Evidence, one name each:
  - `Swag.gvtd()` / `Swag.Gvtd` ("global variables to drop"): a four-letter acronym in the
    public API, documented as "Returns the global variables the runtime drops when the process
    exits". Four uses in `bin/`; the C++ side uses the name about 80 times.
  - `Swag.processInfos()` / `Swag.ProcessInfos`: "info" is uncountable in English; the idiom is
    `processInfo` / `ProcessInfo`. 17 uses in `bin/`, about 60 in `src/`.
  - `Swag.bitCountNz`: "number of non-zero bits" is a population count; `bitCountTz` and
    `bitCountLz` are trailing and leading zero counts, so `Nz` reads as their sibling while
    meaning something different. 72 uses.
  - `Swag.TypeCmpFlags.UnScoped`: `Unscoped` is one word. Three uses.
  - `Swag.TypeCmpFlags` and `Swag.typeCmp` abbreviate "compare" while `Swag.stringCmp` does too
    but `memcmp` follows C; decide once and apply it to both functions and the flags.
- Next: pick the new names in this entry (proposed: `globalsToDrop` / `GlobalToDrop`,
  `processInfo` / `ProcessInfo`, `bitCountOnes` or `popCount`, `Unscoped`), then rename each in
  its own commit together with its lexer token, its C++ mirror, the reference and its
  consumers. Apply the casing rule of runtime.api.005 to the result.
- Done when: none of the names listed above remains in `bin/`, `src/`, the reference or the
  VSCode grammar.
- Related: runtime.api.005

### runtime.api.007 — `IAllocator` forces debug operations on every allocator, and `ScratchAllocator` publishes its bookkeeping

- Evidence: [IAllocator](../bin/runtime/api.swg#L574) has five mandatory methods. Of the nine
  implementations in `bin/`, five write both `mtd impl freeAll(...) {}` and
  `mtd impl assertAllocated(...) {}` as empty bodies (`core/src/memory/alloc.swg`,
  `core/src/tests/memory/alloc.test.swg` twice, `swagcapture/src/tests/library.test.swg`,
  `unittests/workspace/.../memory.test.swg`); two more only delegate or assert false. An empty `assertAllocated` silently
  accepts any address, which is the opposite of an assertion.
  [CompilerInstance.cpp:657](../src/Main/CompilerInstance.cpp#L657) relies on the slot order.
- Evidence: [ScratchAllocator](../bin/runtime/api.swg#L593) makes `capacity`, `used`,
  `maxUsed`, `firstLeak`, `totalLeak` and `maxLeak` public and writable. Outside the runtime,
  only `core/src/tests/time/timer.test.swg` (reads `firstLeak`) and the native runtime unit
  tests read them. `releaseOwner` and `releaseHook` are internal but sit in the same struct and
  in every `ErrorValue` (runtime.api.003).
- Next: make `freeAll` and `assertAllocated` optional at the interface level: either give
  `IAllocator` default implementations if the language supports them, or replace both by one
  `capabilities()` query plus the two operations on a separate optional interface. Decide what
  a missing `assertAllocated` means (no check, explicitly reported) and document it. Then make
  the `ScratchAllocator` statistics read-only through methods (`used()`, `peakUsed()`,
  `leakStats()`), keep the fields internal, and migrate the timer test and the runtime unit
  tests.
- Done when: an allocator that only allocates, reallocates and frees implements three
  methods, no implementation in `bin/` contains an empty `assertAllocated`, and no code outside
  the runtime writes a `ScratchAllocator` field.
- Related: runtime.api.003, runtime.allocator.002

### runtime.api.008 — The runtime has one target, and its public enums say so

- Evidence: `Swag.TargetArch` has the single member `X86_64` and the runtime's only host leaf is
  [os.win32.swg](../bin/runtime/os.win32.swg) (745 lines). `CallConv.WindowsX64` is a public
  member of a portable enum. The portability work itself is tracked in
  [platform.portability.md](platform.portability.md); this entry only covers what the public
  runtime surface must look like once a second target exists.
- Next: list every public runtime declaration whose name or members encode Windows or x86-64
  (`TargetArch`, `TargetOs`, `CallConv`, the `Swag.vec*` ISA names of runtime.api.005, the
  `SystemError.errorID` meaning), and state for each whether it stays as an enumerated target
  or moves behind a neutral name, so the first port does not have to rename public API.
- Done when: that list exists in this entry with a decision per declaration, and every
  decision that renames something has its own entry or has landed.
- Related: platform.portability.035, runtime.api.005
