# SIMD Backlog

This file is the cross-cutting roadmap for explicit `#simd`, the compiler and backend support that
makes it useful, and the `bin/runtime` and `bin/std` kernels that should consume it. Applications,
examples, tests, raw native bindings, and GPU shader work are outside this roadmap.

The roadmap is deliberately not bounded by today's 128-bit operation set. A scalar kernel is not
declared unsuitable merely because the current surface lacks a conversion, reduction, gather,
rotation, polynomial operation, mask, or wider register. Missing platform capability is tracked
first; the consuming optimization names it through `Related:`. Portable semantics must remain
available where the operation can be lowered efficiently on every supported target, while
target-specific forms require compile-time gating or safe runtime dispatch.

The supported machine baseline is x86-64-v3, as stated in the repository README; scalar or
narrower kernels below are algorithmic alternatives, not a promise to run on an older ISA.
Every optimized consumer keeps a scalar or narrower fallback, proves byte-for-byte or numerically
specified parity at boundaries and tails, and records a release benchmark against that fallback.
Every capability entry also owns its declarations in `bin/runtime/api.swg`, the public
`Core.Math.Simd` family, constant folding, diagnostics, encoder tests, native/JIT tests, and the
language reference. An implementation that introduces or changes an intrinsic spelling also owns
the lexer token and editor grammar update required for a surface-syntax change.
The production baseline includes the public wrapper in
`bin/std/modules/core/src/math/simd.swg`, the PCM conversion kernels in `audio/src/codec/pcm/pcm.swg`,
and H.264 interpolation and YCbCr conversion kernels in `video/src/decode/h264/inter.swg` and
`frame.swg`. Other consumers include crypto/UTF conversion, Pixel codecs and selected CPU spans,
and paired SDF samples. Historical measurements below are not a fresh baseline for the current
compiler. H.264 RBSP unescaping copies escape-free 16-byte blocks directly: over 512 MiB
in native Release it improves from 1,910,646 to 528,998 us (3.61x), and the complete 3,000-frame
MP4/H.264 decode improves from 911,676 to 698,308 us (1.31x); the work below is still outstanding.

Every packed measurement recorded between 2026-08-20 07:58 and 2026-08-21 21:55 was taken while
most of `Core.Math.Simd` cost a call into `core.dll`. The wrapper was created at the start of that
window, `video` adopted it at 13:17 the same day and `pixel` at 20:13, and the window closes with
the two commits that let an inline callee inline across a module boundary: `#global export` on
`simd.swg` and `integer.swg` at 21:18, then the module-API exporter publishing the body of every
public `#[Inline]` function at 21:55, which also reached `float.swg` and `bits.swg`. What was a
call: `load`, `store`, `splat`, `shuffle`, `select`, `widenLow`, `widenHigh`, `packUnsigned`,
`packSigned`, `interleaveLow`, `interleaveHigh`, `average`, `mulAddPairs`, `gather`, `bitmask`, the
vector form of `Math.abs`, and the concrete integer and float `Math.min`, `Math.max` and
`Math.abs`. What was not, and never has been: the operators on `#simd` — arithmetic, bitwise,
shift, comparison — and every generic function, `Math.clamp` and the vector forms of `Math.min`
and `Math.max` among them, because a generic root always publishes its source. An arithmetic-bound
kernel was therefore unaffected while a data-movement-bound one paid one call per operation, and
the scalar kernels those prototypes were measured against usually paid none: the H.264 and JPEG
sample paths use in-module branchless helpers instead of the `Math` family. So the bias usually
understates the packed side, and where it does not — PNG Paeth scoring, cpu.simd.028 — it inflates it
instead. It applies to the accepted kernels as much as to the discarded ones: every number dated
inside that window has to be re-baselined before it is trusted, and the entries below name their
own. Work dated before the window used the raw `Swag.vec*` intrinsics directly and is unaffected.

### cpu.simd.024 — Irregular H.264 directional intra prediction still needs a measured packed strategy

- Recorded: 2026-08-20 08:56
- Updated: 2026-09-10 21:00 — removed reconstruction dequantization after its entropy-decoder fusion
- Evidence: `intra.swg` already packs the 16x16 simple stores and plane predictor, selected
  8x8 directional rows, and several chroma stores. Irregular 4x4/8x8 predictors and chroma-plane
  arithmetic retain scalar paths; earlier gather/table and narrow-store prototypes were neutral
  or slower and must be remeasured against the current inlined wrappers.
- Evidence: `cb35b2db8` moved AC scaling and raster placement into the CABAC/CAVLC residual
  decoders. The reconstruction `dequant4x4`/`dequant8x8` passes and their clears no longer exist;
  their former zero-store experiment is not an outstanding optimization.
- Next: profile the remaining directional modes, reduce representative edge layouts, and retain
  packing only when it improves their share of complete decoding.
- Complete when: conformance streams remain byte-exact and the remaining directional modes each
  have a measured decision, with a retained packed kernel improving the staged reconstruction
  profile.
- Related: cpu.simd.006, std.video.001.

### cpu.simd.014 — Loop vectorization cannot form reductions or masked tails

- Recorded: 2026-08-20 08:56
- Updated: 2026-09-10 20:49 — distinguished the existing SLP pass from the proposed loop vectorizer
- Evidence: the registered pass is basic-block SLP (`Pass.SlpVectorize`), with no general
  loop-reduction vectorizer or runtime-versioned alias/tail pipeline.
- Intent: add loop vectorization that recognizes associative reductions, versions alias/alignment
  checks, and generate masked or peeled tails using the explicit SIMD operation set.
- Complete when: sum/min/max/bitwise reductions and an unknown-length byte loop vectorize under the
  supported target policy with scalar-equivalent results and profitable cost decisions.
- Related: cpu.simd.006, cpu.simd.015.

### cpu.simd.013 — Unrolling does not expose constant-index SIMD packs

- Recorded: 2026-08-20 08:56
- Updated: 2026-09-10 20:49 — removed the already explicit-packed ChaCha path as the outstanding reproducer
- Evidence: ChaCha already uses explicit packed XOR in `chacha20XorFour`; it is no longer
  evidence that automatic packing must still be added there. `Pass.LoopUnroll` and
  `Pass.SlpVectorize` remain separate passes, and the remaining lead needs a scalar-source fixture.
- Intent: fold induction-derived addresses to constant offsets after unrolling and rerun the
  combining needed for SLP to recognize adjacent loads and stores.
- Complete when: reduced scalar-source array and codec kernels become packed after unrolling
  because induction-derived addresses are combined, with no code-size-only unroll when vectorization
  does not follow.
- Related: compiler.optimization.002.

### cpu.simd.007 — Gather supports one shape; scatter, compress and expand are absent

- Recorded: 2026-08-20 08:56
- Updated: 2026-09-10 20:47 — distinguished current direct gather lowering from the historical fallback
- Intent: add indexed lane loads/stores and mask-based compaction/expansion, with target gating and
  a cost model that is allowed to choose scalar lane operations when hardware gather is slower.
  The JPEG-driven `s32x4` gather is now available with an AVX2 `vpgatherdd` lowering; the current code generator emits it
  directly. The historical four-load fallback is not a selectable current target. Over 64 million
  hot-LUT reads, that fallback measured 9,952 to 13,646 us
  (1.37x slower than scalar) and AVX2 measured 11,804 to 15,360 us (1.30x slower), so consumers
  still need an end-to-end win from the vector work surrounding the lookup.
  Both of those numbers were taken inside the call window described in the introduction, with the
  gather itself lowered as a call, so the cost of the operation is not established. Re-measure it
  before concluding anything about gather, and before reading the gather-driven rejections of
  cpu.simd.029 and cpu.simd.023 as evidence against it.
- Complete when: bounds and aliasing semantics are explicit, AVX2 gather and AVX-512 scatter/
  compress/expand are encoded, and the fallback never performs an invalid masked access.
- Related: cpu.simd.003, cpu.simd.028, cpu.simd.031, cpu.simd.034.

### cpu.simd.006 — Vector tails require scalar cleanup

- Recorded: 2026-08-20 08:56
- Updated: 2026-09-10 20:47 — kept partial access independent of an unsupported SSE2 target
- Intent: add masked load/store and partial load/store operations with an explicit valid-lane mask,
  defined non-faulting behavior, and efficient baseline lowering when native masks are unavailable.
  `Core.Math.Simd` also ships `storeLow4` and `storeLow8` with no load counterpart, so 4x4 and 8x8 block kernels need padded storage for a full load or explicit scalar partial
  loads. A masked or partial API must make those preconditions explicit.
- Complete when: arbitrary byte counts can be processed without reading or writing outside the
  slice, sanitizer-style guard-page tests cover both ends, and AVX-512 uses native masks.
- Related: cpu.simd.003, cpu.simd.015, cpu.simd.024, cpu.simd.025.

### cpu.simd.003 — 512-bit vectors and AVX-512 masks have no representation

- Recorded: 2026-08-20 08:56
- Updated: 2026-09-10 20:47 — removed the obsolete lower-ISA fallback assumption
- Intent: add 64-byte `#simd` shapes, ZMM register allocation, and explicit predicate-mask values
  for AVX-512 targets without making AVX-512 a baseline requirement.
- Complete when: arithmetic, comparison, masked load/store, calls, spills, constants, reflection,
  and cross-module use work behind feature gating, with the x86-64-v3 baseline selected on
  supported machines that lack the optional feature.
- Related: cpu.simd.001, cpu.simd.002, cpu.simd.006, cpu.simd.007.

### cpu.simd.001 — Optional SIMD beyond the baseline has no shared dispatch contract

- Recorded: 2026-08-20 08:56
- Updated: 2026-09-10 20:47 — aligned optional-feature dispatch with the current x86-64-v3 minimum
- Evidence: the supported compiler/runtime baseline is x86-64-v3 and startup rejects older
  hosts; there is no lower-ISA build mode. Standard modules still have no common contract for
  optional features beyond that baseline.
- Intent: add authoritative optional-feature queries and function multiversioning so a module can
  select a baseline or richer implementation without duplicating dispatch. A lower-ISA product
  target would require a separate explicit baseline decision.
- Complete when: dispatch is cached, testable with a forced feature ceiling, works in JIT and native
  builds, and one runtime or codec kernel selects a measured optional-feature variant while retaining its
  baseline implementation.
- Related: cpu.simd.002, cpu.simd.003.

### cpu.simd.009 — AES round and key instructions have no typed surface

- Recorded: 2026-08-20 08:56
- Updated: 2026-09-10 20:47 — removed the shipped carry-less multiplication surface from the remaining AES work
- Evidence: `Swag.vecclmul` and the four `Math.Simd.clmul...` wrappers already expose
  carry-less multiplication; `Hash.Crc32.foldClmul` consumes them and the x64 encoder has a byte
  test. AES round/key instructions have no equivalent typed API.
- Intent: expose AES round/key operations with explicit availability and known-answer tests.
- Complete when: feature gating prevents illegal instructions, known-answer tests cover operands
  and lane ordering, and portable fallbacks or explicit availability checks are part of the API.
- Related: cpu.simd.001.

### cpu.simd.018 — The Argon2 permutation remains scalar

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-08 06:30 — added the native lane-scaling baseline for future packed-kernel comparisons
- Intent: vectorize block XOR, BlaMka compression, row/column permutation, and final reduction while
  retaining Argon2id's exact memory-index and synchronization semantics.
- Evidence (2026-08-20): on eight Argon2id derivations at 4 MiB, three passes, and four lanes, the
  scalar Release kernel measured 104,661 us. Explicit `U64x2` block XOR measured 107,969 us (3.2%
  slower) and was reverted. A trial `u32 x u32 -> u64` low-half product lowered directly to
  `pmuludq` made paired BlaMka exact, but the best eight-vector row/column layout measured 180,000
  us (72% slower); a sixteen-vector layout measured 190,313 us. The intrinsic, API, and kernel were
  all reverted because the lane regrouping and state materialization erased the paired arithmetic
  gain. Revisit only with a lowering that keeps the eight-word state in registers across both G
  halves and performs the two-source 64-bit lane regroup without scalar extraction, or with a
  wider layout that amortizes that regrouping; the low-half multiply alone is not a useful feature.
- Complete when: published vectors pass for all supported parameters and profile benchmarks isolate
  the packed kernel gain from independent-lane parallelism.
- Baseline: independent lanes now use native `parallel for`. The focused
  [lane-scaling benchmark](../bench/argon2/README.md) holds the scalar compression kernel fixed
  and compares one with four workers at 64 and 256 MiB. Keep that worker count fixed when
  measuring a future packed kernel.

### cpu.simd.011 — Vector rounding and transcendental families remain incomplete

- Recorded: 2026-08-20 08:56
- Updated: 2026-09-06 07:51 — git: prompt 6
- Evidence: vector sqrt, floor, ceil, trunc, abs, min/max, mul-add, sign, copysign, saturate and
  lerp already have public wrappers in `math/simd.swg`.
- Intent: add vector `round`, reciprocal/reciprocal-square-root policy, exp, log, pow, and the
  trigonometric family with documented accuracy tiers instead of treating absent machine
  instructions as a permanent reason to keep callers scalar.
- Complete when: error bounds, exceptional values, determinism policy, and scalar/vector parity are
  tested, and benchmarks justify the chosen polynomial/table implementations.
- Related: cpu.simd.027, cpu.simd.033, cpu.simd.034.

### cpu.simd.012 — Packed code generation misses idiomatic hardware forms

- Recorded: 2026-08-19 19:26
- Updated: 2026-09-06 07:51 — git: prompt 6
- Intent: complete direct narrow/dynamic lane insertion and extraction and evaluate fused
  multiply-add with an explicit rounding contract. Immediate lane shuffles, horizontal reductions
  and SAD already lower through dedicated operations; vector `mulAdd` currently emits a multiply
  followed by an add, so replacing it with FMA must not silently change its rounding semantics. Landed 2026-08-22: `Swag.vecselect` is one `vpblendvb` (the
  mask's byte sign bits carry a whole-lane compare mask exactly), and a constant 32- or 64-bit
  lane read of a register-resident vector is a `movd`/`movq` — lane zero directly, another lane
  through one `pshufd` — instead of a spill and a reload, which is what `storeLow4`/`storeLow8`
  and every transposed store compile to. Narrow lanes and dynamic indices still take the spill.
- Complete when: encoder tests and `PrintMicro` show each idiom on a representative standard-module
  kernel and end-to-end benchmarks show no regression on the fallback target.
- Related: cpu.simd.010.

### cpu.simd.015 — UTF-8 validation still lacks a profitable packed fast path

- Recorded: 2026-08-20 08:56
- Updated: 2026-09-06 07:51 — git: prompt 6
- Intent: improve `isValid` beyond its current 8-byte scalar ASCII scan; a direct U8x16 bitmask
  path measured 20.76 to 20.42 GiB/s and was rejected.
- Complete when: malformed boundaries and arbitrary tails match the scalar implementation and an
  ASCII-heavy benchmark improves rather than only replacing the load width.
- Related: cpu.simd.006, cpu.simd.014.

### cpu.simd.019 — Blake2b compression remains scalar

- Recorded: 2026-08-20 08:56
- Updated: 2026-09-06 07:51 — git: prompt 6
- Intent: run paired G functions and message/state permutations in packed 64-bit lanes, using native
  rotates or defined shift/or lowering.
- Complete when: incremental, keyed, and boundary-length vectors match and compression throughput
  improves without changing digest output.
- Evidence: pairing two G functions while packing and extracting scalar state at every half-round
  measured 273,397 to 1,419,077 microseconds over 64 MiB (5.19x slower) and was rejected. Those historical numbers predate the current allocator and need rechecking. A viable
  kernel needs persistent vector state with cheap lane permutation, or independent messages per lane.

### cpu.simd.025 — Half-size and gradient paths still have unoptimized scalar work

- Recorded: 2026-08-20 08:56
- Updated: 2026-09-06 07:51 — git: prompt 6
- Evidence: the legacy RGB/BGR half-size path calls `visitPixels`; other formats already use
  parallel row loops. The two-color legacy gradient computes one row and copies it, while the
  four-corner and logical-pixel paths still process pixels individually. Fill already copies rows.
- Intent: measure row/chunk replacements for the remaining half-size and gradient work and a
  packed source-over kernel beyond its row-wise scalar implementation.
- Complete when: supported pixel formats, alpha preservation, odd widths, stride, overlap, and tails
  match existing behavior and each retained kernel beats callback dispatch.
- Related: cpu.simd.004, cpu.simd.006, cpu.simd.010.

### cpu.simd.028 — PNG Sub strides and remaining sample conversion need a current profile

- Recorded: 2026-08-20 08:56
- Updated: 2026-09-06 07:51 — git: prompt 6
- Evidence: packed bit expansion, encoder filter/scoring kernels, decoder Up/Average/Paeth and
  Sub for 2/4/8-byte pixels already exist. Gray and palette conversion also have thresholded
  packed-word paths. `convert16` still converts samples and transparency keys individually; Sub
  strides 1/3/6 retain scalar recurrence paths.
- Historical experiments: packed Sub prototypes for strides 1/3/6 and gray byte shuffles lost
  during the 2026-08-20/21 cross-module wrapper-call window. The encoder Paeth speedup from that
  window was also biased because the scalar form called `Math.abs`. These measurements cannot
  settle the current inlined kernels' cost.
- Next: profile current decoding by filter and bit depth, then remeasure the remaining Sub
  layouts and 16-bit conversion against their scalar forms in the same process. Keep Inflate's
  share separate from image conversion so a microkernel gain has an end-to-end interpretation.
- Complete when: remaining paths have a measured decision, odd/Adam7 tails and malformed rows
  retain bounds protection, and every retained kernel improves representative decoding.
- Related: cpu.simd.006, cpu.simd.007, cpu.simd.010.

### cpu.simd.031 — Remaining palette lookups need a profitable packed strategy

- Recorded: 2026-08-20 08:56
- Updated: 2026-09-06 07:51 — git: prompt 6
- Evidence: BMP/TGA 16-bit expansion, TGA row reversal and RLE spans, RGB/BGR channel shuffles,
  GIF fixed quantization and PNG packed-word palette tables already have bulk implementations.
  Palette lookup still has no general gather/shuffle strategy that beats those direct tables.
- Historical experiments: a 16-entry SSSE3 PNG table shuffle lost by 2.97x for RGB and 1.83x for
  RGBA during the wrapper-call window. PNG's current packed-u32 lookup beat the gather prototype;
  neither result proves that every palette size or new target should make the same choice.
- Next: profile GIF palette expansion and remaining indexed layouts before selecting gather or
  shuffle, preserve the existing small-image setup thresholds, and compare against the current
  packed-word tables rather than an older per-channel loop.
- Complete when: each remaining indexed path has a measured dispatch decision and covers palette
  size, transparency and tails without invalid reads or changes to decoded pixels.
- Related: cpu.simd.007.

### cpu.simd.032 — CPU span packing stops before translucent blending and complex shading

- Recorded: 2026-08-20 08:56
- Updated: 2026-09-06 07:51 — git: prompt 6
- Evidence: `rendercpu.swg` already clears packed spans, evaluates four edge samples, and writes
  full covered constant-color BGRA groups with channel masks. Its translucent alpha path keeps
  scalar float rounding, and gradient, MSDF and general texture shading retain per-pixel work.
- Intent: extend profitable horizontal spans to those remaining cases, specializing by program,
  blending and format rather than adding branches to one universal loop.
- Complete when: clip and layer boundaries remain exact, byte/golden parity or a deliberately
  specified numeric tolerance protects rounding, and stage and application benchmarks justify
  each retained path. Gather-dependent sampling needs its own measured decision.
- Related: cpu.simd.004, cpu.simd.007, cpu.simd.011, cpu.simd.016.

### cpu.simd.033 — TrueType raster and MSDF kernels remain scalar

- Recorded: 2026-08-20 08:56
- Updated: 2026-09-06 07:51 — git: prompt 6
- Evidence: ordinary SDF already evaluates two F64 sample positions through
  `closestEdgeDistances` and `insideMask`; MSDF and analytic raster coverage remain separate scalar
  implementations.
- Intent: vectorize analytic coverage conversion and process multiple sample points in MSDF
  distance evaluation, using vector math and gathers only where edge traversal remains profitable.
- Complete when: glyph goldens stay within a declared coverage/distance tolerance and raster and
  MSDF are benchmarked separately across small and large glyphs.
- Related: cpu.simd.007, cpu.simd.011.

### cpu.simd.034 — PDF packed samples and mask composition remain scalar

- Recorded: 2026-08-20 08:56
- Updated: 2026-09-06 07:51 — git: prompt 6
- Evidence: default 8-bit gray expansion and CMYK conversion already use packed shuffles in
  `decode.image.swg`; the remaining paths still use sample extraction and per-pixel composition.
- Intent: vectorize non-default decode arrays, packed and 16-bit samples, color-key comparison,
  mask scaling, and alpha composition; use gather for indexed spaces only when profitable.
- Complete when: PDF image fixtures preserve pixels across remaining bit depths, masks, decode
  arrays, and indexed spaces, with separate conversion benchmarks.
- Related: cpu.simd.004, cpu.simd.007, cpu.simd.011.

### cpu.simd.023 — H.264 strong chroma deblocking remains scalar vertically

- Recorded: 2026-08-20 08:56
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules
- Intent: find a profitable vertical strong-chroma layout and confirm the retained strong luma
  and horizontal chroma kernels in a complete decode profile. The weak paths are done: horizontal
  since 2026-08-20 (16 luma or 8 chroma samples per call, 2.66x and
  2.05x on release microkernels), vertical since 2026-08-22 — `filterLumaWeakVertical` and
  `filterChromaWeakVertical` transpose the sixteen (eight) lines through a tile with the
  interleave tree (32 interleaves for luma), run the horizontal kernel on the tile, and transpose
  the four (two) changed rows back with lane-extraction stores. Exhaustive differential test
  against the scalar per-line filters (16 seeds, 5 `indexA`, every strength combination) and the
  whole fixture corpus stay byte-exact. Measured once `Core.Math.Simd` inlined across modules and
  the lane reads stopped spilling: on a generated 1080p High/CABAC clip of 120 frames the complete
  release decode went from a 5,061 ms to a 4,953 ms mean (2.1%) over six alternated runs, a 60-frame
  Main clip from 2,518 to 2,513 ms — the earlier transpose prototypes had been measured with every
  wrapper a call into `core.dll`, which is what made them lose. Strong luma now filters sixteen
  horizontal lanes at once and reuses the same transposed tile for vertical edges; strong chroma
  filters eight horizontal lanes. Exhaustive scalar differential tests cover all 625 mixed
  strength combinations, five threshold indices and sixteen sample patterns in both orientations.
  Native Release microkernels improved 2 million calls by 3.39x for horizontal luma (369,302 to
  109,023 us), 2.22x for horizontal chroma (88,951 to 40,089 us), and 1.66x for vertical luma
  (372,715 to 224,832 us). The analogous chroma transpose regressed from 91,347 to 97,450 us
  (1.07x slower) and was rejected, so strong vertical chroma retains its scalar two-line segments.
- Complete when: decoded frames remain byte-exact, a profitable strong vertical chroma kernel is
  retained or ruled out with an end-to-end profile, and the 1080p profile confirms the other gains.
- Related: cpu.simd.010, std.video.001 in [std.video.md](std.video.md).

### cpu.simd.002 — 256-bit vectors are not expressible

- Recorded: 2026-08-19 19:26
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity
- Intent: extend the type constructor to 32-byte geometry (`#simd [32] u8`, `#simd [8] f32`) gated
  on AVX2, with YMM registers, 32-byte spills/constants/alignment, operators, intrinsics, arguments,
  returns, type information, cross-module exports, and matching `Math.Simd` aliases.
- Complete when: every supported 32-byte shape compiles and runs, crosses a module boundary, and
  128-bit code generation remains byte-identical when the wider path is not selected.
- Related: cpu.simd.001, cpu.simd.012.

### cpu.simd.004 — Packed numeric lane conversion is incomplete

- Recorded: 2026-08-20 08:56
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity
- Intent: complete signed and unsigned integer-to-float, the float-to-integer directions beyond
  the existing four-lane `f32` to `s32` truncation, and widening/narrowing numeric conversions
  distinct from bit reinterpretation and saturating pack.
- Cost of the gap: the JPEG encoder converts colour with packed 16.16 arithmetic but its forward
  transform reads floats, and with no `s32` to `f32` lane conversion the samples have to land in a
  `s16` staging array that the transform then converts one lane at a time.
- Complete when: every legal 128-bit conversion has specified overflow/NaN behavior, constant and
  runtime coverage, idiomatic hardware lowering, and wider equivalents where the target supports
  them.
- Related: cpu.simd.027, cpu.simd.029, cpu.simd.032.

### cpu.simd.005 — Packed integer division and modulo have no portable lowering

- Recorded: 2026-08-20 08:56
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity
- Intent: define integer lane division/remainder semantics and implement constant-divisor strength
  reduction plus a profitable target-independent sequence or explicit fallback, instead of treating
  the absence of one machine instruction as a permanent operator restriction.
- Complete when: signed/unsigned lanes, zero divisors, `Min / -1`, constant and variable divisors,
  constant folding, and runtime execution have one documented contract and the cost model declines
  transformations that would lose to scalar code.
- Related: cpu.simd.017, cpu.simd.025, cpu.simd.027.

### cpu.simd.008 — Packed memory access has no alignment or cache policy

- Recorded: 2026-08-20 08:56
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity
- Intent: add aligned load/store assertions or hints, broadcast loads, non-temporal stores, and
  prefetch controls with semantics that remain safe when a target ignores the hint.
- Complete when: alignment violations are diagnosed or guarded as declared, large copy/fill and
  image-row benchmarks establish thresholds for streaming access, and ordinary unaligned access
  remains the default portable operation.
- Related: cpu.simd.001, cpu.simd.025, cpu.simd.032.

### cpu.simd.010 — Dot products have no VNNI form

- Recorded: 2026-08-20 08:56
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity
- Intent: select the VNNI dot-product instructions where the host has them. Unsigned and signed
  byte SAD (`psadbw`), the 16-bit pairwise product (`pmaddwd`) and the unsigned/signed byte
  product (`pmaddubsw`) are the baseline forms and are already selected.
- Complete when: a VNNI accumulation is chosen on a host that reports the feature, the baseline
  sequence still runs everywhere else, and both answer the same on the differential tests.
- Related: cpu.simd.001, cpu.simd.012, cpu.simd.019, cpu.simd.026, cpu.simd.029, cpu.simd.030.

### cpu.simd.016 — Vector4 and Pixel.Color do not use their native packed shape

- Recorded: 2026-08-20 08:56
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity
- Intent: implement component arithmetic, min/max, abs, floor/ceil, lerp, clamp, dot/length support,
  and reusable color arithmetic through `F32x4`/packed bytes without changing floating semantics;
  do not wrap the current scalar operators directly, which measured 321 to 637 ms in a Release
  array-arithmetic benchmark because the backend already vectorizes their contiguous form better.
- Complete when: public math/color tests cover NaN, signed zero, normalization thresholds, rounding,
  and aliasing, and renderer/filter consumers measure a gain rather than only fewer source lines.
- Related: cpu.simd.004, cpu.simd.011, cpu.simd.032.

### cpu.simd.017 — NumericArray cannot specialize legal packed geometries

- Recorded: 2026-08-20 08:56
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity
- Intent: specialize generic equality, arithmetic, fill, copy, and mul-add when the instantiated
  element/count/operator combination has supported packed semantics.
- Complete when: specialization is compile-time selected, unsupported shapes remain scalar, and
  generated-code tests prove no hidden conversion or temporary array.
- Related: cpu.simd.002, cpu.simd.004.

### cpu.simd.020 — Poly1305 remains scalar

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity
- Intent: implement a packed limb strategy or several-message kernel, selected only where it beats
  the current scalar carry chain.
- Complete when: differential vectors cover every block-tail length, carry/reduction boundaries are
  exact, and authenticated-encryption throughput improves end to end.

### cpu.simd.021 — SHA-1, SHA-256, and MD5 have no multi-buffer kernels

- Recorded: 2026-08-20 08:56
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity
- Intent: add batch APIs or internal batching that process independent message blocks across lanes,
  instead of attempting to vectorize one recurrence-dependent stream.
- Complete when: one- through lane-width batches preserve streaming/finalization semantics, fall
  back for a single stream, and improve aggregate hashing throughput.

### cpu.simd.026 — Convolution, resize, smart-crop, and Haar kernels remain scalar

- Recorded: 2026-08-20 08:56
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity
- Intent: vectorize interior convolution, horizontal/vertical resampling, integral-image box output,
  Sobel/normalization maps, and contiguous Haar passes while keeping borders and unfavorable gathers
  scalar.
- Complete when: golden images remain within the declared numeric tolerance and representative
  large-image workloads show per-stage gains.
- Related: cpu.simd.007, cpu.simd.010.

### cpu.simd.027 — LUT and transcendental image filters have no packed path

- Recorded: 2026-08-20 08:56
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity
- Intent: use gathered tables or vector math to accelerate gamma, contrast, fade, colorize, HSL, and
  noise kernels without weakening their output contract merely to fit today's instruction set.
- Complete when: each filter declares exact or bounded-error parity, uses the profitable gather/math
  path under feature dispatch, and retains a scalar fallback.
- Related: cpu.simd.004, cpu.simd.007, cpu.simd.011.

### cpu.simd.029 — The JPEG forward transform and quantization remain scalar

- Recorded: 2026-08-20 08:56
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity
- State: the decoder is packed. Colour conversion of every layout, the direct-RGB interleave and
  the inverse transform all run on vectors, and the encoder converts colour packed as well. All of
  it is byte-exact with the scalar form it replaced, checked by hashing decoded pixels and encoded
  bytes of the 4:4:4, 4:2:2, 4:2:0, grayscale, progressive and large fixtures against a worktree at
  pristine master. Interleaved A/B in native Release: decode 1.15x to 1.38x, encode 1.37x to 1.76x.
- Intent: pack the forward transform and the quantization that follows it, which is where the
  encoder now spends most of its time.
- Problem to settle first: the forward transform is the float AAN one, and its samples reach it
  through a `s16` staging array only because no packed `s32` to `f32` lane conversion exists
  (cpu.simd.004). Packing it therefore means either keeping the float operation order lane by lane —
  where the optimizer is free to contract a multiply and an add and change the last bit — or
  moving to an integer transform, which changes the encoded bytes outright. Decide whether
  byte-exactness with today's output is a property to keep before writing the kernel.
- What the decoder work showed, since the prototypes recorded here before had concluded the
  opposite: measure end to end, never inside the call window, and profile the stages first. One
  1024x768 4:2:0 decode split as 2.3 ms entropy, 3.0 ms inverse transform, 2.5 ms conversion, which
  is what made those two the ones worth packing. Recomputing the conversion coefficients as packed
  fixed point — rejected here before as 3.46x slower — is exactly what the shipped conversion
  does; what cost that prototype its time was the gather beside it, not the arithmetic. The inverse
  transform keeps `s16` lanes through a multiply-add decomposition of the same integer transform
  instead of widening to `s32` columns, which is the narrower arithmetic this entry asked for, and
  a whole-block DC shortcut is worth 16% on a smooth fixture where a per-line one had regressed.
- Complete when: fixtures preserve accepted pixel tolerances, coefficient extremes are covered, and
  encode throughput improves in an interleaved A/B on a quiet machine.
- Related: cpu.simd.004, cpu.simd.010.

### cpu.simd.030 — WebP reconstruction and transforms remain mostly scalar

- Recorded: 2026-08-20 08:56
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity
- Intent: vectorize VP8 inverse transforms, predictors, deblocking, YUV conversion, alpha filters,
  and lossless subtract-green/cross-color/predictor transforms.
- Complete when: lossy and lossless fixture pixels remain identical where specified, predictor and
  boundary modes are exhaustive, and stage benchmarks show the retained gains.
- Related: cpu.simd.006, cpu.simd.010.
