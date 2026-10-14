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
- Related: cpu.simd.012, std.core.031

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
