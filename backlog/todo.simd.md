# SIMD Roadmap

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

## Tier A — Target selection, widths, and calling boundaries

### T-509 — Standard modules cannot dispatch SIMD by host capability

- Intent: add one authoritative CPU-feature query and function-multiversioning mechanism so a
  distributed standard module can select scalar/SSE2, AVX2, and later AVX-512 implementations
  without executing an unsupported instruction or duplicating ad-hoc dispatch in every module.
- Complete when: dispatch is cached, testable with a forced feature ceiling, works in JIT and native
  builds, and one runtime or codec kernel ships scalar, 128-bit, and 256-bit variants through it.
- Related: T-506, T-510.

### T-506 — 256-bit vectors are not expressible

- Intent: extend the type constructor to 32-byte geometry (`#simd [32] u8`, `#simd [8] f32`) gated
  on AVX2, with YMM registers, 32-byte spills/constants/alignment, operators, intrinsics, arguments,
  returns, type information, cross-module exports, and matching `Math.Simd` aliases.
- Complete when: every supported 32-byte shape compiles and runs, crosses a module boundary, and
  128-bit code generation remains byte-identical when the wider path is not selected.
- Related: T-509, T-505, T-507.

### T-510 — 512-bit vectors and AVX-512 masks have no representation

- Intent: add 64-byte `#simd` shapes, ZMM register allocation, and explicit predicate-mask values
  for AVX-512 targets without making AVX-512 a baseline requirement.
- Complete when: arithmetic, comparison, masked load/store, calls, spills, constants, reflection,
  and cross-module use work behind feature gating, with AVX2 and SSE2 fallbacks still selected on
  machines that lack the feature.
- Related: T-509, T-506, T-516, T-517.

### T-505 — A `#simd` argument cannot occupy a stack slot

- Intent: define stack/home-slot passing for packed arguments beyond the register lanes and apply
  it consistently to caller lowering, callee prologues, the JIT bridge, and pure-call folding.
- Complete when: fifth-and-later packed arguments work in JIT and native code for every supported
  vector width and the existing `ABICall` and `SemaJIT` guards disappear.
- Related: T-506, T-510, T-522.

### T-522 — Foreign vector ABIs are unavailable

- Intent: support explicitly selected platform vector ABIs for foreign declarations where the ABI
  is stable, while continuing to reject an ambiguous bare C-vector contract.
- Complete when: supported Windows x64 vector parameters and returns interoperate with a C/C++
  fixture, unsupported conventions fail semantically, and the contract is documented per target.
- Related: T-505, T-506.

## Tier A — Missing packed operations

### T-511 — Packed numeric lane conversion is incomplete

- Intent: complete signed and unsigned integer-to-float, the float-to-integer directions beyond
  the existing four-lane `f32` to `s32` truncation, and widening/narrowing numeric conversions
  distinct from bit reinterpretation and saturating pack.
- Complete when: every legal 128-bit conversion has specified overflow/NaN behavior, constant and
  runtime coverage, idiomatic hardware lowering, and wider equivalents where the target supports
  them.
- Related: T-547, T-549, T-552, T-555.

### T-512 — Rotates and several packed shifts are missing

- Intent: provide lane rotates plus portable lowerings for byte shifts, 64-bit arithmetic right
  shift, and other useful shift shapes that lack a single baseline instruction.
- Complete when: constant and variable counts have scalar-equivalent masking semantics, use native
  instructions when available, and otherwise lower to bounded shift/or or widen/pack sequences.
- Related: T-251, T-536, T-538.

### T-513 — Packed integer multiplication is incomplete

- Intent: add low and widening products for 8-, 16-, 32-, and 64-bit signed and unsigned lanes,
  including decomposed baseline lowerings where no one-instruction form exists.
- Complete when: low and high halves are unambiguous, all shapes have differential tests against
  scalar arithmetic, and AVX2/AVX-512 forms are selected where profitable.
- Related: T-251, T-250, T-536.

### T-556 — Packed integer division and modulo have no portable lowering

- Intent: define integer lane division/remainder semantics and implement constant-divisor strength
  reduction plus a profitable target-independent sequence or explicit fallback, instead of treating
  the absence of one machine instruction as a permanent operator restriction.
- Complete when: signed/unsigned lanes, zero divisors, `Min / -1`, constant and variable divisors,
  constant folding, and runtime execution have one documented contract and the cost model declines
  transformations that would lose to scalar code.
- Related: T-535, T-545, T-547.

### T-557 — Elementary packed min, max, abs, and sign operations are incomplete

- Intent: complete 64-bit integer min/max, 64-bit signed abs, floating abs/copysign, clamp, and
  related elementary lane operations through native forms or compare/select/bitwise lowerings.
- Complete when: every numeric lane shape has explicit NaN, signed-zero, and minimum-integer
  behavior, with constant/runtime parity and no spill-based implementation.
- Related: T-507, T-534, T-546, T-552.

### T-514 — Shuffle, zip, transpose, and two-source permutation are incomplete

- Intent: add immediate lane permutation, zip/unzip, byte align/extract, and two-source table
  permutation rather than forcing every transpose through spills or byte masks. Low/high
  interleave now exists for `u8x16` and `u16x8`; extend it only when another lane shape has a
  measured application.
- Complete when: constant patterns select immediate hardware forms, dynamic patterns retain a
  defined fallback, and 4x4/8x8 transpose helpers require no scalar lane extraction.
- Related: T-507, T-542, T-549, T-550, T-551.

### T-515 — Horizontal reductions are not first-class

- Intent: add sum, min, max, bitwise-and/or/xor, and count reductions with widening variants so
  callers do not open-code shuffle ladders.
- Complete when: integer and floating reductions document order, overflow, NaN, and signed-zero
  behavior and lower without memory round-trips.
- Related: T-520, T-531, T-534, T-536, T-546.

### T-516 — Vector tails require scalar cleanup

- Intent: add masked load/store and partial load/store operations with an explicit valid-lane mask,
  defined non-faulting behavior, and efficient SSE2/AVX2 fallback lowering.
- Complete when: arbitrary byte counts can be processed without reading or writing outside the
  slice, sanitizer-style guard-page tests cover both ends, and AVX-512 uses native masks.
- Related: T-510, T-531, T-545.

### T-517 — Gather, scatter, compress, and expand are unavailable

- Intent: add indexed lane loads/stores and mask-based compaction/expansion, with target gating and
  a cost model that is allowed to choose scalar lane operations when hardware gather is slower.
  The JPEG-driven `s32x4` gather is now available with an AVX2 `vpgatherdd` lowering and a portable
  four-load fallback. Over 64 million hot-LUT reads, the fallback measured 9,952 to 13,646 us
  (1.37x slower than scalar) and AVX2 measured 11,804 to 15,360 us (1.30x slower), so consumers
  still need an end-to-end win from the vector work surrounding the lookup.
- Complete when: bounds and aliasing semantics are explicit, AVX2 gather and AVX-512 scatter/
  compress/expand are encoded, and the fallback never performs an invalid masked access.
- Related: T-510, T-548, T-551, T-554.

### T-558 — Packed memory access has no alignment or cache policy

- Intent: add aligned load/store assertions or hints, broadcast loads, non-temporal stores, and
  prefetch controls with semantics that remain safe when a target ignores the hint.
- Complete when: alignment violations are diagnosed or guarded as declared, large copy/fill and
  image-row benchmarks establish thresholds for streaming access, and ordinary unaligned access
  remains the default portable operation.
- Related: T-509, T-545, T-552.

### T-518 — Packed bit counting and bit scans are unavailable

- Intent: add popcount, leading/trailing-zero count, byte swap, and bit reverse over integer lanes,
  using native target features or correct SIMD/SWAR lowerings.
- Complete when: zero-lane behavior matches scalar intrinsics, constant folding agrees with runtime,
  and UTF/hash consumers no longer reduce masks one scalar lane at a time.
- Related: T-531, T-538, T-539.

### T-519 — Polynomial and cryptographic instructions have no typed surface

- Intent: expose carry-less multiplication and, separately gated, AES round/key instructions as
  typed packed operations rather than opaque inline machine code.
- Complete when: feature gating prevents illegal instructions, known-answer tests cover operands
  and lane ordering, and portable fallbacks or explicit availability checks are part of the API.
- Related: T-539.

### T-520 — Dot products and sums of absolute differences are missing

- Intent: add unsigned and signed SAD plus common byte/word dot-product forms with declared widening
  and accumulation widths.
- Complete when: the backend selects `psadbw`, `pmadd*`, VNNI forms when available, and scalar
  differential tests cover saturation and overflow boundaries.
- Related: T-507, T-536, T-546, T-549, T-550.

### T-521 — Core has no vector math implementation

- Intent: implement vector `round`, reciprocal/reciprocal-square-root policy, exp, log, pow, and the
  trigonometric family with documented accuracy tiers instead of treating absent machine
  instructions as a permanent reason to keep callers scalar.
- Complete when: error bounds, exceptional values, determinism policy, and scalar/vector parity are
  tested, and benchmarks justify the chosen polynomial/table implementations.
- Related: T-547, T-553, T-554.

### T-508 — Unary plus rejects packed vectors

- Intent: make unary `+` the identity for every numeric `#simd` shape, matching packed unary minus
  and scalar arithmetic.
- Complete when: sema, native execution, compile-time execution, the language reference, and the
  operator suite agree on the accepted form.
- Related: F-167, retired when this finding became a todo.

## Tier B — Backend quality and automatic vectorization

### T-507 — Packed code generation misses idiomatic hardware forms

- Intent: select immediate shuffles, blends, fused multiply-add, horizontal forms, SAD, and direct
  lane extract/insert instead of generic sequences and spill-slot lane access.
- Complete when: encoder tests and `PrintMicro` show each idiom on a representative standard-module
  kernel and end-to-end benchmarks show no regression on the fallback target.
- Related: T-514, T-515, T-520.

### T-523 — Unrolling does not expose constant-index SIMD packs

- Intent: fold induction-derived addresses to constant offsets after unrolling and rerun the
  combining needed for SLP to recognize adjacent loads and stores.
- Complete when: the ChaCha key-stream XOR and a neutral array kernel become packed after unrolling,
  with no code-size-only unroll when vectorization does not follow.
- Related: F-034.

### T-524 — Loop vectorization cannot form reductions or masked tails

- Intent: teach the loop vectorizer to recognize associative reductions, version alias/alignment
  checks, and generate masked or peeled tails using the explicit SIMD operation set.
- Complete when: sum/min/max/bitwise reductions and an unknown-length byte loop vectorize under the
  configured feature ceiling with scalar-equivalent results and profitable cost decisions.
- Related: T-515, T-516, T-531.

## Tier B — Runtime and Core bulk primitives

### T-531 — UTF-8 validation still lacks a profitable packed fast path

- Intent: improve `isValid` beyond its current unrolled scalar ASCII scan; a direct U8x16 bitmask
  path measured 20.76 to 20.42 GiB/s and was rejected.
- Complete when: malformed boundaries and arbitrary tails match the scalar implementation and an
  ASCII-heavy benchmark improves rather than only replacing the load width.
- Related: T-515, T-516, T-518, T-524.

### T-534 — Vector4 and Pixel.Color do not use their native packed shape

- Intent: implement component arithmetic, min/max, abs, floor/ceil, lerp, clamp, dot/length support,
  and reusable color arithmetic through `F32x4`/packed bytes without changing floating semantics;
  do not wrap the current scalar operators directly, which measured 321 to 637 ms in a Release
  array-arithmetic benchmark because the backend already vectorizes their contiguous form better.
- Complete when: public math/color tests cover NaN, signed zero, normalization thresholds, rounding,
  and aliasing, and renderer/filter consumers measure a gain rather than only fewer source lines.
- Related: T-511, T-515, T-521, T-552.

### T-535 — NumericArray cannot specialize legal packed geometries

- Intent: specialize generic equality, arithmetic, fill, copy, and mul-add when the instantiated
  element/count/operator combination has supported packed semantics.
- Complete when: specialization is compile-time selected, unsupported shapes remain scalar, and
  generated-code tests prove no hidden conversion or temporary array.
- Related: T-506, T-511, T-513, T-515.

## Tier B — Cryptography and checksums

### T-251 — The Argon2 permutation remains scalar

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
- Related: T-252 in `todo.vaultdrive.md`, T-512, T-513, T-515.

### T-536 — Blake2b compression remains scalar

- Intent: run paired G functions and message/state permutations in packed 64-bit lanes, using native
  rotates or defined shift/or lowering.
- Complete when: incremental, keyed, and boundary-length vectors match and compression throughput
  improves without changing digest output.
- Evidence: pairing two G functions while packing and extracting scalar state at every half-round
  measured 273,397 to 1,419,077 microseconds over 64 MiB (5.19x slower) and was rejected. A viable
  kernel needs persistent vector state with cheap lane permutation, or independent messages per lane.
- Related: T-512, T-513, T-514.

### T-250 — Poly1305 remains scalar

- Intent: implement a packed limb strategy or several-message kernel, selected only where it beats
  the current scalar carry chain.
- Complete when: differential vectors cover every block-tail length, carry/reduction boundaries are
  exact, and authenticated-encryption throughput improves end to end.
- Related: T-513, T-515.

### T-538 — SHA-1, SHA-256, and MD5 have no multi-buffer kernels

- Intent: add batch APIs or internal batching that process independent message blocks across lanes,
  instead of attempting to vectorize one recurrence-dependent stream.
- Complete when: one- through lane-width batches preserve streaming/finalization semantics, fall
  back for a single stream, and improve aggregate hashing throughput.
- Related: T-512, T-514, T-518.

### T-539 — CRC32 cannot use polynomial folding

- Intent: add a carry-less-multiply folding implementation with feature dispatch and retain the
  table implementation as the portable fallback.
- Complete when: incremental CRC values match for every alignment and tail and large-buffer
  throughput improves on supported machines without illegal-instruction risk.
- Related: T-509, T-518, T-519.

## Tier B — Audio and video codecs

### T-541 — H.264 vertical and strong deblocking remain scalar

- Intent: complete the packed luma and chroma edge filters with strong filtering and a transpose
  strategy for vertical edges. The weak horizontal paths now process 16 luma or 8 chroma samples
  per call; release microkernels improved by 2.66x and 2.05x respectively, byte-exact across the
  fixture corpus and exhaustive strength combinations. A byte-exact 8x8-transpose prototype for
  weak vertical luma regressed the deblocking stage from 189,600 to 243,128 us (1.28x slower), and
  a mixed weak/strong horizontal prototype regressed 2,000,000 calls from 142,362 to 333,897 us
  (2.35x slower); both were discarded.
- Complete when: decoded frames remain byte-exact, strong and vertical paths are packed, and the
  existing 1080p profile shows an end-to-end gain.
- Related: T-514, T-520, T-420 in `todo.video.md`.

### T-542 — H.264 inverse transforms remain scalar

- Intent: vectorize `addIdct4x4`, `addDc4x4`, `hadamard4x4`, and `addIdct8x8` with packed
  transposes and saturating output. Direct packed-column and packed-residual prototypes were
  byte-exact but slower than the scalar kernels and were discarded; a profitable transpose or
  combined transform/reconstruction strategy is still needed.
- Complete when: coefficient extremes and conformance streams remain byte-exact and transform time
  decreases in the video profile.
- Related: T-514, T-520, T-541.

### T-544 — H.264 reconstruction and directional intra prediction remain scalar

- Intent: vectorize dequantization, residual addition, and the DC/horizontal/vertical/plane intra
  predictors; keep shuffle-heavy directional modes only when profiling supports them. The 16x16
  vertical, horizontal, and DC stores now run 2.12x to 3.20x faster, and the filtered 8x8 vertical
  store runs 1.43x faster; narrower dynamic-splat attempts regressed and were discarded.
- Complete when: conformance streams remain byte-exact and each retained kernel improves the staged
  reconstruction profile.
- Related: T-513, T-514, T-516, T-542.

## Tier C — Pixel processing and image codecs

### T-545 — Half-size and simple gradients still dispatch one callback per pixel

- Intent: add row/chunk kernels for half-size and simple gradients, and assess a packed
  source-over kernel beyond its row-wise scalar implementation. Fill already copies complete rows;
  the other original candidates now have measured chunk or row kernels.
- Complete when: supported pixel formats, alpha preservation, odd widths, stride, overlap, and tails
  match existing behavior and each retained kernel beats callback dispatch.
- Related: T-511, T-514, T-516, T-520.

### T-546 — Convolution, resize, smart-crop, and Haar kernels remain scalar

- Intent: vectorize interior convolution, horizontal/vertical resampling, integral-image box output,
  Sobel/normalization maps, and contiguous Haar passes while keeping borders and unfavorable gathers
  scalar.
- Complete when: golden images remain within the declared numeric tolerance and representative
  large-image workloads show per-stage gains.
- Related: T-515, T-517, T-520.

### T-547 — LUT and transcendental image filters have no packed path

- Intent: use gathered tables or vector math to accelerate gamma, contrast, fade, colorize, HSL, and
  noise kernels without weakening their output contract merely to fit today's instruction set.
- Complete when: each filter declares exact or bounded-error parity, uses the profitable gather/math
  path under feature dispatch, and retains a scalar fallback.
- Related: T-511, T-517, T-521.

### T-548 — PNG packed samples, filters, and color conversion remain scalar

- Intent: complete non-paletted color conversion, decoder Sub for byte strides 1/3/6, and decoder
  Average/Paeth with prefix-scan strategies where left dependencies require them.
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
  (1.17x), respectively.
  Encoder `Sub` generation processes 64 bytes per iteration (1.69x), while its score reuses the
  packed independent-byte reducer after the first pixel (1.59x). Encoder `Average` uses exact
  downward-rounded packed averages for row generation (2.25x) and scoring (1.63x). Encoder Paeth
  evaluates eight S16 lanes per half-vector for row generation (3.24x) and scoring (3.55x).
  Decoder `Sub` uses packed prefix scans for 2/4/8-byte pixels (1.33x/1.44x/1.67x); the four-shuffle
  one-byte scan regressed 18-27% and was rejected. Three- and six-byte carry-shuffle prototypes
  also regressed 256 MiB in native Release from 226,957 to 276,945 us (1.22x slower) and from
  222,110 to 236,188 us (1.06x slower), so those layouts remain scalar.
- Complete when: the PNG fixture corpus is byte/pixel identical, malformed inputs remain rejected,
  every filter and bit depth covers odd tails, and encode/decode throughput improves.
- Related: T-514, T-516, T-517, T-520.

### T-549 — JPEG DCT, IDCT, quantization, and color conversion remain scalar

- Intent: vectorize RGB/YCbCr conversion, chroma upsampling, 8x8 FDCT/IDCT, and quantization with
  explicit rounding semantics. A six-shuffle prototype for the eight-pixel direct-RGB planar pack
  regressed 192 MiB in native Release from 62,379 to 224,940 us (3.61x slower), so it was discarded.
  The common H2V2 YCbCr path was then tried with the new `s32x4` gather, amortizing four chroma
  lookups over sixteen output pixels. Forty 1024x768 decodes regressed from 682,359 to 752,853 us
  on the portable target (1.10x slower) and from 612,948 to 791,885 us with AVX2 (1.29x slower).
  Recomputing the LUT coefficients as packed fixed-point arithmetic regressed portable decoding
  to 2,362,812 us (3.46x slower), and replacing the eight contiguous IDCT DC stores by one SIMD
  splat/store regressed a 32 MiB microkernel from 5,650 to 5,760 us (1.02x slower). A byte-exact
  second IDCT pass that kept four columns packed through the complete `s32` butterfly regressed the
  measured transform stage from 80,085 to 132,055 us (1.65x slower). A block-level DC fast path
  applied to 32.6% of the H2V2 fixture but still regressed paired median IDCT time by 10.9% and
  end-to-end decode by 1.8%, because its seven-row zero test ran on every block. All prototypes
  were discarded; JPEG now needs a lower-shuffle combined conversion/packing layout, narrower IDCT
  arithmetic, or cheaper backend packed multiply/narrow sequences rather than isolated SIMD work.
- Complete when: baseline and progressive fixtures preserve accepted pixel tolerances, coefficient
  extremes are covered, and encode/decode stages improve independently.
- Related: T-511, T-514, T-520.

### T-550 — WebP reconstruction and transforms remain mostly scalar

- Intent: vectorize VP8 inverse transforms, predictors, deblocking, YUV conversion, alpha filters,
  and lossless subtract-green/cross-color/predictor transforms.
- Complete when: lossy and lossless fixture pixels remain identical where specified, predictor and
  boundary modes are exhaustive, and stage benchmarks show the retained gains.
- Related: T-513, T-514, T-516, T-520.

### T-551 — Packed and indexed pixel formats lack gather/shuffle kernels

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
- Complete when: every format variant, palette size, transparency case, row padding, and tail matches
  scalar decoding/encoding and the dispatcher avoids gather where it loses.
- Related: T-514, T-517.

### T-552 — The CPU renderer has no packed span pipeline

- Intent: process four or more horizontal pixels per iteration for clear, alpha blend, solid and
  gradient shading, MSDF coverage, and profitable texture paths, with specialized kernels instead
  of one branch-heavy universal loop.
- Complete when: command-stream goldens remain stable, clip and layer boundaries are exact, simple
  spans improve first, and gather-dependent sampling is enabled only by measurement.
- Related: T-511, T-517, T-521, T-534.

## Tier C — Text, fonts, and PDF

### T-553 — TrueType raster and MSDF kernels remain scalar

- Intent: vectorize analytic coverage conversion and process multiple sample points in MSDF
  distance evaluation, using vector math and gathers only where edge traversal remains profitable.
- Complete when: glyph goldens stay within a declared coverage/distance tolerance and raster and
  MSDF are benchmarked separately across small and large glyphs.
- Related: T-517, T-521.

### T-554 — PDF packed samples and mask composition remain scalar

- Intent: vectorize non-default decode arrays, packed and 16-bit samples, color-key comparison,
  mask scaling, and alpha composition; use gather for indexed spaces only when profitable.
- Complete when: PDF image fixtures preserve pixels across remaining bit depths, masks, decode
  arrays, and indexed spaces, with separate conversion benchmarks.
- Related: T-511, T-517, T-521.

### T-555 — BMP conversion and bounded UTF-16 terminator search remain scalar

- Intent: add packed BMP conversion beyond the existing ASCII fast paths, accelerate endian-aware
  UTF-16/32 decoding, and provide a length-bounded terminator search so SIMD loads remain inside
  caller-owned storage. Fall back before surrogates or invalid sequences.
- Complete when: malformed sequences, endian variants, bounded terminators, destination limits,
  and tails match scalar behavior and BMP-heavy conversions improve.
- Related: T-511, T-514, T-516.
