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

Every optimized consumer keeps a scalar or narrower fallback, proves byte-for-byte or numerically
specified parity at boundaries and tails, and records a release benchmark against that fallback.
Every capability entry also owns its declarations in `bin/runtime/api.swg`, the public
`Core.Math.Simd` family, constant folding, diagnostics, encoder tests, native/JIT tests, and the
language reference. An implementation that introduces or changes an intrinsic spelling also owns
the lexer token and editor grammar update required for a surface-syntax change.
The current production baseline consists of the public wrapper in
`bin/std/modules/core/src/math/simd.swg`, the PCM conversion kernels in `audio/src/codec/pcm.swg`,
and the H.264 interpolation and YCbCr conversion kernels in `video/src/decode/h264/inter.swg` and
`frame.swg`. H.264 RBSP unescaping now copies escape-free 16-byte blocks directly: over 512 MiB
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

## Tier A — Target selection, widths, and calling boundaries

### cpu.simd.001 — Standard modules cannot dispatch SIMD by host capability

- Intent: add one authoritative CPU-feature query and function-multiversioning mechanism so a
  distributed standard module can select scalar/SSE2, AVX2, and later AVX-512 implementations
  without executing an unsupported instruction or duplicating ad-hoc dispatch in every module.
- Complete when: dispatch is cached, testable with a forced feature ceiling, works in JIT and native
  builds, and one runtime or codec kernel ships scalar, 128-bit, and 256-bit variants through it.
- Related: cpu.simd.002, cpu.simd.003.

### cpu.simd.002 — 256-bit vectors are not expressible

- Intent: extend the type constructor to 32-byte geometry (`#simd [32] u8`, `#simd [8] f32`) gated
  on AVX2, with YMM registers, 32-byte spills/constants/alignment, operators, intrinsics, arguments,
  returns, type information, cross-module exports, and matching `Math.Simd` aliases.
- Complete when: every supported 32-byte shape compiles and runs, crosses a module boundary, and
  128-bit code generation remains byte-identical when the wider path is not selected.
- Related: cpu.simd.001, cpu.simd.012.

### cpu.simd.003 — 512-bit vectors and AVX-512 masks have no representation

- Intent: add 64-byte `#simd` shapes, ZMM register allocation, and explicit predicate-mask values
  for AVX-512 targets without making AVX-512 a baseline requirement.
- Complete when: arithmetic, comparison, masked load/store, calls, spills, constants, reflection,
  and cross-module use work behind feature gating, with AVX2 and SSE2 fallbacks still selected on
  machines that lack the feature.
- Related: cpu.simd.001, cpu.simd.002, cpu.simd.006, cpu.simd.007.


## Tier A — Missing packed operations

### cpu.simd.004 — Packed numeric lane conversion is incomplete

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

- Intent: define integer lane division/remainder semantics and implement constant-divisor strength
  reduction plus a profitable target-independent sequence or explicit fallback, instead of treating
  the absence of one machine instruction as a permanent operator restriction.
- Complete when: signed/unsigned lanes, zero divisors, `Min / -1`, constant and variable divisors,
  constant folding, and runtime execution have one documented contract and the cost model declines
  transformations that would lose to scalar code.
- Related: cpu.simd.017, cpu.simd.025, cpu.simd.027.

### cpu.simd.006 — Vector tails require scalar cleanup

- Intent: add masked load/store and partial load/store operations with an explicit valid-lane mask,
  defined non-faulting behavior, and efficient SSE2/AVX2 fallback lowering.
  `Core.Math.Simd` also ships `storeLow4` and `storeLow8` with no load counterpart, so every 4x4 and
  8x8 block kernel either over-reads sixteen bytes or routes four and eight bytes through a scalar
  splat.
- Complete when: arbitrary byte counts can be processed without reading or writing outside the
  slice, sanitizer-style guard-page tests cover both ends, and AVX-512 uses native masks.
- Related: cpu.simd.003, cpu.simd.015, cpu.simd.024, cpu.simd.025.

### cpu.simd.007 — Gather, scatter, compress, and expand are unavailable

- Intent: add indexed lane loads/stores and mask-based compaction/expansion, with target gating and
  a cost model that is allowed to choose scalar lane operations when hardware gather is slower.
  The JPEG-driven `s32x4` gather is now available with an AVX2 `vpgatherdd` lowering and a portable
  four-load fallback. Over 64 million hot-LUT reads, the fallback measured 9,952 to 13,646 us
  (1.37x slower than scalar) and AVX2 measured 11,804 to 15,360 us (1.30x slower), so consumers
  still need an end-to-end win from the vector work surrounding the lookup.
  Both of those numbers were taken inside the call window described in the introduction, with the
  gather itself lowered as a call, so the cost of the operation is not established. Re-measure it
  before concluding anything about gather, and before reading the gather-driven rejections of
  cpu.simd.029 and cpu.simd.023 as evidence against it.
- Complete when: bounds and aliasing semantics are explicit, AVX2 gather and AVX-512 scatter/
  compress/expand are encoded, and the fallback never performs an invalid masked access.
- Related: cpu.simd.003, cpu.simd.028, cpu.simd.031, cpu.simd.034.

### cpu.simd.008 — Packed memory access has no alignment or cache policy

- Intent: add aligned load/store assertions or hints, broadcast loads, non-temporal stores, and
  prefetch controls with semantics that remain safe when a target ignores the hint.
- Complete when: alignment violations are diagnosed or guarded as declared, large copy/fill and
  image-row benchmarks establish thresholds for streaming access, and ordinary unaligned access
  remains the default portable operation.
- Related: cpu.simd.001, cpu.simd.025, cpu.simd.032.

### cpu.simd.009 — Polynomial and cryptographic instructions have no typed surface

- Intent: expose carry-less multiplication and, separately gated, AES round/key instructions as
  typed packed operations rather than opaque inline machine code.
- Complete when: feature gating prevents illegal instructions, known-answer tests cover operands
  and lane ordering, and portable fallbacks or explicit availability checks are part of the API.
- Related: cpu.simd.022.

### cpu.simd.010 — Dot products have no VNNI form

- Intent: select the VNNI dot-product instructions where the host has them. Unsigned and signed
  byte SAD (`psadbw`), the 16-bit pairwise product (`pmaddwd`) and the unsigned/signed byte
  product (`pmaddubsw`) are the baseline forms and are already selected.
- Complete when: a VNNI accumulation is chosen on a host that reports the feature, the baseline
  sequence still runs everywhere else, and both answer the same on the differential tests.
- Related: cpu.simd.001, cpu.simd.012, cpu.simd.019, cpu.simd.026, cpu.simd.029, cpu.simd.030.

### cpu.simd.011 — Core has no vector math implementation

- Intent: implement vector `round`, reciprocal/reciprocal-square-root policy, exp, log, pow, and the
  trigonometric family with documented accuracy tiers instead of treating absent machine
  instructions as a permanent reason to keep callers scalar.
- Complete when: error bounds, exceptional values, determinism policy, and scalar/vector parity are
  tested, and benchmarks justify the chosen polynomial/table implementations.
- Related: cpu.simd.027, cpu.simd.033, cpu.simd.034.

## Tier B — Backend quality and automatic vectorization

### cpu.simd.012 — Packed code generation misses idiomatic hardware forms

- Intent: select immediate shuffles, fused multiply-add, horizontal forms, SAD, and direct lane
  insert instead of generic sequences. Landed 2026-08-22: `Swag.vecselect` is one `vpblendvb` (the
  mask's byte sign bits carry a whole-lane compare mask exactly), and a constant 32- or 64-bit
  lane read of a register-resident vector is a `movd`/`movq` — lane zero directly, another lane
  through one `pshufd` — instead of a spill and a reload, which is what `storeLow4`/`storeLow8`
  and every transposed store compile to. Narrow lanes and dynamic indices still take the spill.
- Complete when: encoder tests and `PrintMicro` show each idiom on a representative standard-module
  kernel and end-to-end benchmarks show no regression on the fallback target.
- Related: cpu.simd.010.

### cpu.simd.013 — Unrolling does not expose constant-index SIMD packs

- Intent: fold induction-derived addresses to constant offsets after unrolling and rerun the
  combining needed for SLP to recognize adjacent loads and stores.
- Complete when: the ChaCha key-stream XOR and a neutral array kernel become packed after unrolling,
  with no code-size-only unroll when vectorization does not follow.
- Related: compiler.optimization.002.

### cpu.simd.014 — Loop vectorization cannot form reductions or masked tails

- Intent: teach the loop vectorizer to recognize associative reductions, version alias/alignment
  checks, and generate masked or peeled tails using the explicit SIMD operation set.
- Complete when: sum/min/max/bitwise reductions and an unknown-length byte loop vectorize under the
  configured feature ceiling with scalar-equivalent results and profitable cost decisions.
- Related: cpu.simd.006, cpu.simd.015.

## Tier B — Runtime and Core bulk primitives

### cpu.simd.015 — UTF-8 validation still lacks a profitable packed fast path

- Intent: improve `isValid` beyond its current unrolled scalar ASCII scan; a direct U8x16 bitmask
  path measured 20.76 to 20.42 GiB/s and was rejected.
- Complete when: malformed boundaries and arbitrary tails match the scalar implementation and an
  ASCII-heavy benchmark improves rather than only replacing the load width.
- Related: cpu.simd.006, cpu.simd.014.

### cpu.simd.016 — Vector4 and Pixel.Color do not use their native packed shape

- Intent: implement component arithmetic, min/max, abs, floor/ceil, lerp, clamp, dot/length support,
  and reusable color arithmetic through `F32x4`/packed bytes without changing floating semantics;
  do not wrap the current scalar operators directly, which measured 321 to 637 ms in a Release
  array-arithmetic benchmark because the backend already vectorizes their contiguous form better.
- Complete when: public math/color tests cover NaN, signed zero, normalization thresholds, rounding,
  and aliasing, and renderer/filter consumers measure a gain rather than only fewer source lines.
- Related: cpu.simd.004, cpu.simd.011, cpu.simd.032.

### cpu.simd.017 — NumericArray cannot specialize legal packed geometries

- Intent: specialize generic equality, arithmetic, fill, copy, and mul-add when the instantiated
  element/count/operator combination has supported packed semantics.
- Complete when: specialization is compile-time selected, unsupported shapes remain scalar, and
  generated-code tests prove no hidden conversion or temporary array.
- Related: cpu.simd.002, cpu.simd.004.

## Tier B — Cryptography and checksums

### cpu.simd.018 — The Argon2 permutation remains scalar

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
- Related: std.core.009 in [std.core.md](std.core.md).

### cpu.simd.019 — Blake2b compression remains scalar

- Intent: run paired G functions and message/state permutations in packed 64-bit lanes, using native
  rotates or defined shift/or lowering.
- Complete when: incremental, keyed, and boundary-length vectors match and compression throughput
  improves without changing digest output.
- Evidence: pairing two G functions while packing and extracting scalar state at every half-round
  measured 273,397 to 1,419,077 microseconds over 64 MiB (5.19x slower) and was rejected. A viable
  kernel needs persistent vector state with cheap lane permutation, or independent messages per lane.

### cpu.simd.020 — Poly1305 remains scalar

- Intent: implement a packed limb strategy or several-message kernel, selected only where it beats
  the current scalar carry chain.
- Complete when: differential vectors cover every block-tail length, carry/reduction boundaries are
  exact, and authenticated-encryption throughput improves end to end.

### cpu.simd.021 — SHA-1, SHA-256, and MD5 have no multi-buffer kernels

- Intent: add batch APIs or internal batching that process independent message blocks across lanes,
  instead of attempting to vectorize one recurrence-dependent stream.
- Complete when: one- through lane-width batches preserve streaming/finalization semantics, fall
  back for a single stream, and improve aggregate hashing throughput.

### cpu.simd.022 — CRC32 cannot use polynomial folding

- Intent: add a carry-less-multiply folding implementation with feature dispatch and retain the
  table implementation as the portable fallback.
- Complete when: incremental CRC values match for every alignment and tail and large-buffer
  throughput improves on supported machines without illegal-instruction risk.
- Related: cpu.simd.001, cpu.simd.009.

## Tier B — Audio and video codecs

### cpu.simd.023 — H.264 strong chroma deblocking remains scalar vertically

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
- Related: cpu.simd.010, app.scope.video.014 in [app.scope.video.md](app.scope.video.md).

### cpu.simd.024 — H.264 dequantization and irregular directional intra prediction remain scalar

- Intent: profile dequantization and the remaining gather- or shuffle-heavy directional modes.
  Residual addition is already part of the packed inverse transforms. The 16x16 vertical,
  horizontal, and DC stores now run 2.12x to 3.20x faster, and the filtered 8x8 vertical
  store runs 1.43x faster; narrower dynamic-splat attempts regressed and were discarded. Replacing
  the 4x4 and 8x8 dequantization zero loops with two and eight vector stores regressed 30,000 High
  Profile decodes from 7,877,846 to 8,032,948 us (1.02x slower), so the scalar loops remain.
  All three discarded results — the 1.02x zero loops, the narrower dynamic splats, and the
  flat-add four-pixel rows recorded as neutral within 0.5% in `std.video.md` — sit inside the
  call window and within its margin, which makes them the cheapest re-measures in this file.
  The 16x16 plane predictor now forms four S32x4 column groups per row and improves 2 million
  Release calls from 516,278 to 435,013 us (1.19x). Chroma DC writes its four quadrants as packed
  rows (53,978 to 39,165 us, 1.38x), while horizontal and vertical broadcast or copy eight samples
  per row (27,627 to 12,637 us, 2.19x; 27,228 to 12,983 us, 2.10x). The analogous eight-wide
  chroma plane arithmetic regressed from 101,197 to 142,369 us (1.41x slower) and remains scalar.
  Three contiguous 8x8 directional modes now reuse packed rows: down-left evaluates two S32x4
  filter groups per row (200,071 to 140,476 us, 1.42x), vertical-left selects its two-tap or
  three-tap packed filter (175,817 to 145,094 us, 1.21x), and horizontal-up computes its 22-value
  edge sequence once before copying eight windows (307,700 to 110,525 us, 2.78x). Two million
  native Release calls were used. Equivalent 4x4 packing was neutral for down-left and 1.14x to
  1.41x slower for the other two modes. Packing only the simple 4x4/8x8 stores also regressed or
  stayed within 1%, while 8x8 down-right and horizontal-down lookup tables were 2.24x and 2.69x
  slower; those paths remain scalar.
- Complete when: conformance streams remain byte-exact and each retained kernel improves the staged
  reconstruction profile.
- Related: cpu.simd.006.

## Tier C — Pixel processing and image codecs

### cpu.simd.025 — Half-size and simple gradients still dispatch one callback per pixel

- Intent: add row/chunk kernels for half-size and simple gradients, and assess a packed
  source-over kernel beyond its row-wise scalar implementation. Fill already copies complete rows;
  the other original candidates now have measured chunk or row kernels.
- Complete when: supported pixel formats, alpha preservation, odd widths, stride, overlap, and tails
  match existing behavior and each retained kernel beats callback dispatch.
- Related: cpu.simd.004, cpu.simd.006, cpu.simd.010.

### cpu.simd.026 — Convolution, resize, smart-crop, and Haar kernels remain scalar

- Intent: vectorize interior convolution, horizontal/vertical resampling, integral-image box output,
  Sobel/normalization maps, and contiguous Haar passes while keeping borders and unfavorable gathers
  scalar.
- Complete when: golden images remain within the declared numeric tolerance and representative
  large-image workloads show per-stage gains.
- Related: cpu.simd.007, cpu.simd.010.

### cpu.simd.027 — LUT and transcendental image filters have no packed path

- Intent: use gathered tables or vector math to accelerate gamma, contrast, fade, colorize, HSL, and
  noise kernels without weakening their output contract merely to fit today's instruction set.
- Complete when: each filter declares exact or bounded-error parity, uses the profitable gather/math
  path under feature dispatch, and retains a scalar fallback.
- Related: cpu.simd.004, cpu.simd.007, cpu.simd.011.

### cpu.simd.028 — PNG packed samples, filters, and color conversion remain scalar

- Intent: complete non-paletted color conversion and decoder Sub for byte strides 1/3/6.
  Decode and encode `Up` now process 64 bytes per iteration (1.59x and 1.27x), exact RGB/RGBA
  16-to-8 reduction processes eight samples per iteration (1.27x), and 4-bit expansion processes
  32 samples per iteration (1.34x). The 1-bit and 2-bit paths now expand 16 samples per iteration
  (1.27x and 1.46x). Measurements cover 512 MiB in Release. The packed rewrites also fixed the
  scalar 2-bit and 4-bit 2/3-sample tails writing a complete group past the row. Encoder `None`
  and `Up` scoring now reduce 16 bytes per iteration (2.70x and 1.92x). Explicit four- and
  sixteen-pixel shuffle layouts for grayscale RGB/RGBA conversion regressed native Release by
  54-76% and were rejected. Opaque grayscale-to-RGB now uses bounded overlapping `u32` stores
  above 4,096 pixels: its 16 Mi-pixel kernel improves from 17,551 to 9,849 us (1.78x), and ten
  complete 2048x2048 decodes improve from 509,191 to 408,989 us (1.25x). Transparent and alpha
  variants now write prepacked RGBA words above 512 and 256 pixels. Their 16 Mi-pixel kernels
  improve from 26,647 to 8,582 us (3.10x) and from 13,109 to 10,571 us (1.24x); five complete
  2048x2048 decodes improve from 371,154 to 292,555 us (1.27x) and from 416,515 to 357,417 us
  (1.17x), respectively. True-color `tRNS` expansion now shuffles four RGB pixels into RGBA and
  compares their packed colors in parallel above 4,096 pixels. Its 16 Mi-pixel kernel improves
  from 17,092 to 15,748 us (1.09x), and five complete 2048x2048 decodes improve from 314,387 to
  296,702 us (1.06x); the 32x32 fixture remains on the scalar path. A scalar packed-`u32` rewrite
  regressed the same kernel from 17,681 to 24,856 us (1.41x slower) and was rejected.
  Encoder `Sub` generation processes 64 bytes per iteration (1.69x), while its score reuses the
  packed independent-byte reducer after the first pixel (1.59x). Encoder `Average` uses exact
  downward-rounded packed averages for row generation (2.25x) and scoring (1.63x). Encoder Paeth
  evaluates eight S16 lanes per half-vector for row generation (3.24x) and scoring (3.55x).
  Decoder `Sub` uses packed prefix scans for 2/4/8-byte pixels (1.33x/1.44x/1.67x); the four-shuffle
  one-byte scan regressed 18-27% and was rejected. Three- and six-byte carry-shuffle prototypes
  also regressed 256 MiB in native Release from 226,957 to 276,945 us (1.22x slower) and from
  222,110 to 236,188 us (1.06x slower), so those layouts remain scalar.
  Those rejections and the grayscale shuffle layouts all date from inside the call window, and the
  three-byte stride they leave scalar is the commonest PNG pixel layout. PNG is also the one place
  where the window biased the other way: the encoder Paeth figures were measured against a scalar
  `filterPaeth` calling `Math.abs` three times per byte, against roughly a quarter of a call per
  byte on the packed side, so 3.24x and 3.55x are inflated.
  Decoder `Average` and `Paeth` now widen one whole pixel to a lane per byte and carry the left
  pixel in a register, the shape libpng's SSE2 kernels use; a pixel is at most eight bytes wide at
  any depth, so one kernel covers every stride from two upward. Timed against the scalar form in
  the same process over 441 rows of a 2,640-byte scanline, Paeth improves from 5,999 to 3,690 us
  (1.63x) and Average from 1,265 to 1,204 us (1.05x) — Average was already cheap enough that the
  packed form only pays for the load and store. The rewrite also bounds both by the row: the
  scalar prefix wrote `bytesPerPixel` bytes without checking the row length, which overran a
  narrow Adam7 pass whose stride is shorter than one pixel.
  Note the ceiling before spending: a decode is about two-thirds Inflate, so a 2x filter or
  conversion kernel shows as a few percent end to end.
- Complete when: the PNG fixture corpus is byte/pixel identical, malformed inputs remain rejected,
  every filter and bit depth covers odd tails, and encode/decode throughput improves.
- Related: cpu.simd.006, cpu.simd.007, cpu.simd.010.

### cpu.simd.029 — The JPEG forward transform and quantization remain scalar

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

- Intent: vectorize VP8 inverse transforms, predictors, deblocking, YUV conversion, alpha filters,
  and lossless subtract-green/cross-color/predictor transforms.
- Complete when: lossy and lossless fixture pixels remain identical where specified, predictor and
  boundary modes are exhaustive, and stage benchmarks show the retained gains.
- Related: cpu.simd.006, cpu.simd.010.

### cpu.simd.031 — Packed and indexed pixel formats lack gather/shuffle kernels

- Intent: complete GIF/PNG palette expansion, fixed quantization, and 24/32-bit channel packing
  using shuffle or gather according to the active target. BMP's default BGR555 path now expands
  16 pixels per iteration through exact 5-bit lookup tables and BGR shuffles (4.23x over 512 MiB
  in Release); the common BGR565 bitfield layout reuses that packing with exact 6-bit integer
  expansion and improves from 1,541,725 to 288,495 us over 256 MiB in native Release (5.34x).
  Other contiguous 16-bit masks with one to eight bits per RGB channel use a shared exact
  multiply/shift normalizer; BGR444 improves from 1,551,093 to 237,259 us over 256 MiB in native
  Release (6.54x). Wider and non-contiguous channel masks retain the scalar fallback. Raw
  non-right-origin TGA15 rows reuse the same exact 5-bit kernel (1.59x). TGA16 adds
  alpha and packs BGRA through the new low/high interleave operations (1.97x overall; 1.12x over
  the shuffle-only prototype). A 16-entry SSSE3 shuffle prototype for low-bit PNG palettes was
  rejected: over 512 MiB in native Release, RGB regressed from 109,065 to 324,334 us (2.97x
  slower) and RGBA from 143,141 to 262,360 us (1.83x slower). The indexed SIMD gather now exists,
  but PNG RGBA expansion measured faster with a prepacked `u32` table: over 16 Mi pixels, portable
  Release improved from 30,113 to 16,662 us (1.81x) and AVX2 from 35,784 to 17,311 us (2.07x),
  while gather reached only 27,310 and 33,441 us. A 512-pixel dispatch threshold keeps table setup
  out of tiny images; 10,000 complete 34x24 decodes improved from 327,233 to 218,321 us (1.50x).
  RGB palette expansion uses bounded overlapping `u32` stores above the same threshold, leaving
  its final pixel to exact three-byte stores. Over 16 Mi pixels it improves from 34,475 to 12,643
  us (2.73x); ten complete 2048x2048 decodes improve from 435,350 to 428,298 us (1.02x) because
  Inflate dominates that fixture. GIF's fixed RGB/BGR/RGBA/BGRA quantizer now
  processes four pixels per iteration with exact packed division by 255. Over 256 MiB of 32-bit
  output in native Release, opaque conversion improves from 3,919,498 to 830,869 us (4.72x) and
  transparent conversion from 3,718,998 to 1,167,242 us (3.19x); over 64 MiB of 24-bit output,
  opaque conversion improves from 3,763,685 to 281,324 us (13.38x). Shared RGB/BGR row shuffles
  now feed uncompressed TGA and BMP encoding through contiguous appends instead of per-channel
  buffer writes. Over 64 MiB in native Release, TGA RGB improves from 435,321 to 56,059 us
  (7.77x) and RGBA from 434,613 to 55,755 us (7.80x); BMP RGB improves from 391,184 to 53,262 us
  (7.34x) and RGBA from 421,889 to 54,080 us (7.80x). TGA RLE literal packets now append
  blue-first spans directly and shuffle red-first spans into a fixed scratch block. Over 64 MiB
  in native Release, BGR improves from 459,142 to 98,627 us (4.66x), RGB from 494,237 to
  123,278 us (4.01x), BGRA from 355,013 to 80,932 us (4.39x), and RGBA from 460,670 to
  103,347 us (4.46x). Four-pixel run detection is retained for 32-bit TGA RLE: over 64 MiB
  of uniform input, BGRA improves from 61,720 to 23,549 us (2.62x) and RGBA from 56,684 to
  26,544 us (2.14x). The 24-bit prototype was rejected after improving BGR only from 61,260
  to 60,605 us (1.01x) and RGB from 62,595 to 57,510 us (1.09x). Right-origin TGA15/16 rows
  reverse 16 packed pixels per iteration; over 256 MiB in native Release, TGA15 improves from
  1,657,107 to 364,168 us (4.55x) and TGA16 from 1,750,620 to 306,748 us (5.71x). Raw TGA24/32
  now dispatches left-origin rows to the runtime SIMD copy and right-origin rows to shared packed
  reversal kernels. Over 128 MiB in native Release, TGA24 improves from 733,271 to 6,348 us
  (115.51x) on left-origin rows and from 715,535 to 56,519 us (12.66x) on right-origin rows;
  TGA32 improves from 570,873 to 7,186 us (79.44x) and from 526,046 to 55,211 us (9.53x),
  respectively. True-color TGA RLE now splits packets at row boundaries and reuses SIMD copy,
  reversal, and packed-pixel fill kernels. Over 64 MiB in native Release, repeated TGA24 improves
  from 328,404 to 11,858 us (27.69x) on left-origin rows and from 344,228 to 12,501 us (27.54x)
  on right-origin rows; raw packets improve from 303,191 to 8,428 us (35.97x) and from 307,714
  to 33,097 us (9.30x). Repeated TGA32 improves from 229,474 to 14,081 us (16.30x) and from
  231,657 to 15,492 us (14.95x); raw packets improve from 233,690 to 7,706 us (30.33x) and
  from 236,496 to 33,536 us (7.05x).
  The 16-entry SSSE3 palette prototype was also rejected inside the call window, but its margin is
  wide and the prepacked `u32` table already beats it on the same fixtures, so it has the weakest
  claim on a re-measure in this file.
- Complete when: every format variant, palette size, transparency case, row padding, and tail matches
  scalar decoding/encoding and the dispatcher avoids gather where it loses.
- Related: cpu.simd.007.

### cpu.simd.032 — The CPU renderer has no packed span pipeline

- Intent: process four or more horizontal pixels per iteration for clear, alpha blend, solid and
  gradient shading, MSDF coverage, and profitable texture paths, with specialized kernels instead
  of one branch-heavy universal loop.
- Complete when: command-stream goldens remain stable, clip and layer boundaries are exact, simple
  spans improve first, and gather-dependent sampling is enabled only by measurement.
- Related: cpu.simd.004, cpu.simd.007, cpu.simd.011, cpu.simd.016.

## Tier C — Text, fonts, and PDF

### cpu.simd.033 — TrueType raster and MSDF kernels remain scalar

- Intent: vectorize analytic coverage conversion and process multiple sample points in MSDF
  distance evaluation, using vector math and gathers only where edge traversal remains profitable.
- Complete when: glyph goldens stay within a declared coverage/distance tolerance and raster and
  MSDF are benchmarked separately across small and large glyphs.
- Related: cpu.simd.007, cpu.simd.011.

### cpu.simd.034 — PDF packed samples and mask composition remain scalar

- Intent: vectorize non-default decode arrays, packed and 16-bit samples, color-key comparison,
  mask scaling, and alpha composition; use gather for indexed spaces only when profitable.
- Complete when: PDF image fixtures preserve pixels across remaining bit depths, masks, decode
  arrays, and indexed spaces, with separate conversion benchmarks.
- Related: cpu.simd.004, cpu.simd.007, cpu.simd.011.
