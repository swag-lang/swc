# SIMD Backlog

Tracks missing `#simd` capabilities and optimizations in `bin/runtime` and `bin/std`. Each
capability entry owns the matching API, compiler, tests, and reference updates. Each consumer keeps
a scalar fallback, verifies parity at boundaries and tails, and compares a Release benchmark.

The supported machine baseline is x86-64-v3. Intrinsic spelling changes also update the language
reference and VSCode grammar. Current consumers include PCM conversion, H.264 decoding, YCbCr
conversion, image codecs, text/crypto routines, Pixel spans, and SDF samples.

### cpu.simd.035 — Keep H.264 pixel kernels in the narrowest profitable lane shape

- Evidence: H.264 kernels widen byte samples to 16-bit lanes even where the operation has a byte-lane form in the SIMD API and backend. This halves the samples processed per vector; the luma six-tap filter already fuses loads with widening, so rewriting it may trade instructions for register pressure.
- Next: profile the current decode lane, optimize the largest remaining pixel kernel, and compare emitted instructions and lane samples on the same fixture. Revisit the luma six-tap byte path only if it reduces `interpolateLuma` cost without adding spills.
- Done when: prediction, residual, reconstruction, and deblocking stay byte-exact and fit the measured pixel budget on the maintained fixture; delete the entry if profiling shows no viable improvement.

### cpu.simd.012 — Packed code generation misses idiomatic hardware forms

- Intent: complete dynamic lane insertion and extraction and prove the remaining 64-bit lane constructions.
  Immediate lane shuffles, horizontal reductions and SAD already lower through dedicated
  operations. Under `backend.math.fma` (on in `release`), a post-RA peephole contracts eligible
  scalar and packed product accumulations when the product is otherwise dead in every lane;
  packed contraction also requires `backend.math.noNaN`. Explicit scalar and vector `Swag.mulAdd`
  preserve separate multiply and add rounding, including when contraction is enabled.
- Evidence: a constant lane read of a register-resident vector never touches the frame. A 32- or
  64-bit lane is a `movd`/`movq`, through one `pshufd` past lane zero; an 8- or 16-bit lane slides
  down by bytes (`psrldq`) and leaves through the same move, extended from its own width. A
  constant lane written into a vector local is one `vpinsrb`/`vpinsrw`/`vpinsrd` where it was a
  sixteen-byte spill, a narrow store and a wide reload stalled behind it.
  `bin/unittests/native/simd/lanes.swg` covers signed and unsigned narrow reads and all four
  insertion widths, including `vpinsrq` when a whole stored vector is updated. A trial that also
  built vectors from two qword stores changed H.264 output; those stores can form slices and other
  scalar aggregates, so that broader rewrite is not retained without a stronger proof. Every
  dynamic index still goes through the frame: `v[i]` spills the vector and reads `[rsp + i * 4]`,
  `v[i] = x` spills, stores the lane and reloads sixteen bytes.
- Next: isolate the two-qword aggregate failure and prove its alias and lifetime conditions;
  lower a dynamic lane read through a byte shuffle with a computed control where that beats the
  spill, preserving the explicit `mulAdd` rounding contract.
- Done when: encoder tests and `PrintMicro` show each idiom on a representative standard-module
  kernel and end-to-end benchmarks show no regression on the fallback target.
- Related: cpu.simd.010.

### cpu.simd.008 — Packed memory access has no alignment or cache policy

- Next: add aligned load/store assertions or hints, broadcast loads, and non-temporal stores.
  `Swag.prefetch` already hints a read into every cache level (`prefetcht0`), never faults and is
  a no-op where a target has no such instruction; a locality or write-intent variant belongs here
  once a consumer measures a need for it.
- Done when: alignment violations are diagnosed or guarded as declared, large copy/fill and
  image-row benchmarks establish thresholds for streaming access, and ordinary unaligned access
  remains the default portable operation.
- Related: cpu.simd.001, cpu.simd.025, cpu.simd.032.

### cpu.simd.014 — Loop vectorization cannot form reductions or masked tails

- Evidence: the registered vectorizer is basic-block SLP (`Pass.SlpVectorize`).
  `Pass.LoopUnroll` recognizes only a straight-line, fixed-bound indexed 32-bit XOR
  reduction (groups of four, or two packed loads with independent accumulators for bounds
  of at least 128 divisible by eight). There is no general loop-reduction vectorizer and no
  runtime-versioned alias/tail pipeline.
- Next: add loop vectorization that recognizes associative reductions, versions
  alias/alignment checks, and generates masked or peeled tails using the explicit SIMD
  operation set.
- Done when: sum/min/max/bitwise reductions and an unknown-length byte loop vectorize under
  the supported target policy with scalar-equivalent results and profitable cost decisions.
- Related: cpu.simd.006, cpu.simd.015.

### cpu.simd.028 — Remaining PNG sample conversion needs a current profile

- Evidence: packed bit expansion, encoder filter/scoring kernels, decoder Up/Average/Paeth
  and Sub for 1/2/3/4/6/8-byte pixels exist (`defilterSubRow` in `decode/png/filter.swg`);
  `image.png.test.swg` compares Sub against scalar recurrence across strides 1 through 8.
  Gray and palette conversion have thresholded packed-word paths. Native 16-bit samples
  without transparency keys are byte-swapped eight at a time, and grayscale keys
  are compared eight at a time; RGB keys are compared two pixels at a time. Earlier rejections of other packed
  Sub and gray shuffles predate cross-module SIMD inlining and do not settle the current cost.
- Next: profile current decoding by filter and bit depth, then compare the packed 16-bit
  sample and transparency-key paths against their scalar forms in the same process. Keep Inflate's
  share separate from image conversion so a microkernel gain has an end-to-end
  interpretation.
- Done when: remaining paths have a measured decision, odd/Adam7 tails and malformed rows
  retain bounds protection, and every retained kernel improves representative decoding.
- Related: cpu.simd.006, cpu.simd.007, cpu.simd.010.

### cpu.simd.024 — Irregular H.264 directional intra prediction still needs a measured packed strategy

- Evidence: `intra.swg` already packs the 16x16 simple stores and plane predictor, selected
  8x8 directional rows, and several chroma stores. Irregular 4x4/8x8 predictors and chroma-plane
  arithmetic retain scalar paths; earlier gather/table and narrow-store prototypes were neutral
  or slower and must be remeasured against the current inlined wrappers.
- Next: profile the remaining directional modes, reduce representative edge layouts, and retain
  packing only when it improves their share of complete decoding.
- Done when: conformance streams remain byte-exact and the remaining directional modes each
  have a measured decision, with a retained packed kernel improving the staged reconstruction
  profile.
- Related: cpu.simd.006, std.video.001.

### cpu.simd.007 — Gather supports one shape; scatter, compress and expand are absent

- Evidence: `Swag.vecGather` / `Math.Simd.gather` support only `s32` lanes with `u32x4`
  indices, lowered to AVX2 `vpgatherdd`. Scatter, compress and expand have no surface. The
  earlier gather timings were taken while the SIMD wrappers were still cross-module calls,
  so they do not establish the operation's cost. They are not evidence behind the
  gather-driven rejections in cpu.simd.029 and cpu.simd.023 either.
- Next: time the inlined `vpgatherdd` against scalar lane loads on a hot-LUT
  microbenchmark and in one consumer, then specify bounds and aliasing semantics for
  indexed loads/stores and mask compaction/expansion, with a cost model allowed to pick
  scalar lane operations.
- Done when: bounds and aliasing semantics are explicit, AVX2 gather and AVX-512 scatter/
  compress/expand are encoded, and the fallback never performs an invalid masked access.
- Related: cpu.simd.003, cpu.simd.028, cpu.simd.031, cpu.simd.034.

### cpu.simd.006 — Vector tails require scalar cleanup

- Next: add masked load/store and partial load/store operations with an explicit valid-lane mask,
  defined non-faulting behavior, and efficient baseline lowering when native masks are unavailable.
  `Core.Math.Simd` also ships `storeLow4` and `storeLow8` with no load counterpart, so 4x4 and 8x8 block kernels need padded storage for a full load or explicit scalar partial
  loads. A masked or partial API must make those preconditions explicit.
- Done when: arbitrary byte counts can be processed without reading or writing outside the
  slice, sanitizer-style guard-page tests cover both ends, and AVX-512 uses native masks.
- Related: cpu.simd.003, cpu.simd.015, cpu.simd.024, cpu.simd.025.

### cpu.simd.003 — 512-bit vectors and AVX-512 masks have no representation

- Next: add 64-byte `#simd` shapes, ZMM register allocation, and explicit predicate-mask values
  for AVX-512 targets without making AVX-512 a baseline requirement.
- Done when: arithmetic, comparison, masked load/store, calls, spills, constants, reflection,
  and cross-module use work behind feature gating, with the x86-64-v3 baseline selected on
  supported machines that lack the optional feature.
- Related: cpu.simd.001, cpu.simd.002, cpu.simd.006, cpu.simd.007.

### cpu.simd.001 — Optional SIMD beyond the baseline has no shared dispatch contract

- Evidence: the supported compiler/runtime baseline is x86-64-v3 and startup rejects older
  hosts; there is no lower-ISA build mode. Standard modules still have no common contract for
  optional features beyond that baseline.
- Next: add authoritative optional-feature queries and function multiversioning so a module can
  select a baseline or richer implementation without duplicating dispatch. A lower-ISA product
  target would require a separate explicit baseline decision.
- Done when: dispatch is cached, testable with a forced feature ceiling, works in JIT and native
  builds, and one runtime or codec kernel selects a measured optional-feature variant while retaining its
  baseline implementation.
- Related: cpu.simd.002, cpu.simd.003.

### cpu.simd.009 — AES round and key instructions have no typed surface

- Evidence: `Swag.vecCarrylessMul` and the four `Math.Simd.clmul...` wrappers already expose
  carry-less multiplication; `Hash.Crc32.foldClmul` consumes them and the x64 encoder has a byte
  test. AES round/key instructions have no equivalent typed API.
- Next: expose AES round/key operations with explicit availability and known-answer tests.
- Done when: feature gating prevents illegal instructions, known-answer tests cover operands
  and lane ordering, and portable fallbacks or explicit availability checks are part of the API.
- Related: cpu.simd.001.

### cpu.simd.018 — The Argon2 permutation remains scalar

- Evidence: Argon2id compression is scalar; independent lanes already use `parallel for`.
  Earlier packed attempts lost. These ran while the SIMD wrappers were still cross-module
  calls:
  - `U64x2` block XOR was 3.2% slower.
  - Paired BlaMka with a `u32 x u32 -> u64` low-half product (`pmuludq`) was 72% or more
    slower, because lane regrouping and state materialization erased the arithmetic gain.
- Next: retry only with a lowering that keeps the eight-word state in registers across both
  G halves and regroups 64-bit lanes from two sources without scalar extraction, or with a
  wider layout that amortizes the regrouping. Measure with the fixed-worker
  [lane-scaling benchmark](../bench/argon2/README.md).
- Done when: published vectors pass for all supported parameters and profile benchmarks
  isolate the packed kernel gain from independent-lane parallelism.

### cpu.simd.011 — Vector rounding and transcendental families remain incomplete

- Evidence: vector sqrt, floor, ceil, trunc, abs, min/max, mul-add, sign, copysign, saturate and
  lerp already have public wrappers in `math/simd.swg`.
- Next: add vector `round`, reciprocal/reciprocal-square-root policy, exp, log, pow, and the
  trigonometric family with documented accuracy tiers instead of treating absent machine
  instructions as a permanent reason to keep callers scalar.
- Done when: error bounds, exceptional values, determinism policy, and scalar/vector parity are
  tested, and benchmarks justify the chosen polynomial/table implementations.
- Related: cpu.simd.027, cpu.simd.033, cpu.simd.034.

### cpu.simd.015 — UTF-8 validation still lacks a profitable packed fast path

- Next: improve `isValid` beyond its current 8-byte scalar ASCII scan; a direct U8x16 bitmask
  path measured 20.76 to 20.42 GiB/s and was rejected.
- Done when: malformed boundaries and arbitrary tails match the scalar implementation and an
  ASCII-heavy benchmark improves rather than only replacing the load width.
- Related: cpu.simd.006, cpu.simd.014.

### cpu.simd.019 — Blake2b compression remains scalar

- Evidence: pairing two G functions while packing and extracting scalar state at every
  half-round was 5.19x slower over 64 MiB. That measurement predates current inlining and
  the current allocator.
- Next: prototype paired G functions with persistent vector state and cheap 64-bit lane
  permutation (native rotates or shift/or), or independent messages per lane, and measure
  against the scalar kernel.
- Done when: incremental, keyed, and boundary-length vectors match and compression
  throughput improves without changing digest output.

### cpu.simd.025 — Half-size and gradient paths still have unoptimized scalar work

- Evidence: the legacy RGB/BGR half-size path calls `visitPixels`; other formats already use
  parallel row loops. The two-color legacy gradient computes one row and copies it, while the
  four-corner and logical-pixel paths still process pixels individually. Fill already copies rows.
- Next: compare packed byte-color half-size rows and the remaining gradient work against
  their scalar paths, and a packed source-over kernel against its row-wise scalar implementation.
- Done when: supported pixel formats, alpha preservation, odd widths, stride, overlap, and tails
  match existing behavior and each retained kernel beats callback dispatch.
- Related: cpu.simd.004, cpu.simd.006, cpu.simd.010.

### cpu.simd.031 — Remaining palette lookups need a profitable packed strategy

- Evidence: BMP/TGA 16-bit expansion, TGA row reversal and RLE spans, RGB/BGR channel shuffles,
  GIF fixed quantization and PNG packed-word palette tables already have bulk implementations.
  Palette lookup still has no general gather/shuffle strategy that beats those direct tables.
- Evidence: a 16-entry SSSE3 PNG table shuffle lost (2.97x RGB, 1.83x RGBA) while SIMD
  wrappers were still cross-module calls; PNG's packed-u32 lookup beat the gather
  prototype. Neither result settles every palette size or target.
- Next: profile GIF palette expansion and remaining indexed layouts before selecting gather or
  shuffle, preserve the existing small-image setup thresholds, and compare against the current
  packed-word tables rather than an older per-channel loop.
- Done when: each remaining indexed path has a measured dispatch decision and covers palette
  size, transparency and tails without invalid reads or changes to decoded pixels.
- Related: cpu.simd.007.

### cpu.simd.032 — CPU span packing stops before translucent blending and complex shading

- Evidence: `rendercpu.swg` already clears packed spans, evaluates four edge samples, and writes
  full covered constant-color BGRA groups with channel masks. Its translucent alpha path keeps
  scalar float rounding, and gradient, MSDF and general texture shading retain per-pixel work.
- Next: extend profitable horizontal spans to those remaining cases, specializing by program,
  blending and format rather than adding branches to one universal loop.
- Done when: clip and layer boundaries remain exact, byte/golden parity or a deliberately
  specified numeric tolerance protects rounding, and stage and application benchmarks justify
  each retained path. Gather-dependent sampling needs its own measured decision.
- Related: cpu.simd.004, cpu.simd.007, cpu.simd.011, cpu.simd.016.

### cpu.simd.033 — TrueType raster and MSDF kernels remain scalar

- Evidence: ordinary SDF already evaluates two F64 sample positions through
  `closestEdgeDistances` and `insideMask`; MSDF and analytic raster coverage remain separate scalar
  implementations.
- Next: vectorize analytic coverage conversion and process multiple sample points in MSDF
  distance evaluation, using vector math and gathers only where edge traversal remains profitable.
- Done when: glyph goldens stay within a declared coverage/distance tolerance and raster and
  MSDF are benchmarked separately across small and large glyphs.
- Related: cpu.simd.007, cpu.simd.011.

### cpu.simd.034 — PDF packed samples and mask composition remain scalar

- Evidence: default 8-bit gray expansion and CMYK conversion already use packed shuffles in
  `decode.image.swg`; the remaining paths still use sample extraction and per-pixel composition.
- Progress: 8-bit soft masks with identity decode copy their samples directly; inverted masks
  subtract sixteen samples at a time and handle the tail scalarly. PDF tests compare all 256
  coverage values against the original scalar conversion and cover SIMD block boundaries.
- Next: vectorize non-default decode arrays, packed and 16-bit samples, color-key comparison,
  mask scaling, and alpha composition; use gather for indexed spaces only when profitable.
- Done when: PDF image fixtures preserve pixels across remaining bit depths, masks, decode
  arrays, and indexed spaces, with separate conversion benchmarks.
- Related: cpu.simd.004, cpu.simd.007, cpu.simd.011.

### cpu.simd.023 — H.264 strong chroma deblocking remains scalar vertically

- Evidence: weak luma/chroma in both orientations, strong luma in both orientations and
  strong horizontal chroma are packed in `h264/deblock.swg`. `filterChromaStrongVertical`
  still filters two-line scalar segments through `filterChroma`. A transposed-tile
  vertical strong-chroma kernel, built the way `filterLumaVertical` is, was slower than
  the scalar segments on the Release microkernel. A later direct two-row SIMD prototype
  avoided the tile but added unconditional stack traffic and saved-register work on weak
  and zero-strength segments; isolating the helper still spilled values across its call.
- Next: find a vertical strong-chroma layout cheaper than the rejected transpose, and
  confirm the retained packed deblocking kernels in a complete 1080p decode profile.
- Done when: decoded frames remain byte-exact, a profitable strong vertical chroma kernel is
  retained or ruled out with an end-to-end profile, and the 1080p profile confirms the
  other gains.
- Related: cpu.simd.010, std.video.001.

### cpu.simd.002 — 256-bit vectors are not expressible

- Next: extend the type constructor to 32-byte geometry (`#simd [32] u8`, `#simd [8] f32`) gated
  on AVX2, with YMM registers, 32-byte spills/constants/alignment, operators, intrinsics, arguments,
  returns, type information, cross-module exports, and matching `Math.Simd` aliases.
- Done when: every supported 32-byte shape compiles and runs, crosses a module boundary, and
  128-bit code generation remains byte-identical when the wider path is not selected.
- Related: cpu.simd.001, cpu.simd.012.

### cpu.simd.004 — Packed numeric lane conversion is incomplete

- Next: complete signed and unsigned integer-to-float, the float-to-integer directions beyond
  the existing four-lane `f32` to `s32` truncation, and widening/narrowing numeric conversions
  distinct from bit reinterpretation and saturating pack.
- Cost of the gap: the JPEG encoder converts colour with packed 16.16 arithmetic but its forward
  transform reads floats, and with no `s32` to `f32` lane conversion the samples have to land in a
  `s16` staging array that the transform then converts one lane at a time.
- Done when: every legal 128-bit conversion has specified overflow/NaN behavior, constant and
  runtime coverage, idiomatic hardware lowering, and wider equivalents where the target supports
  them.
- Related: cpu.simd.027, cpu.simd.029, cpu.simd.032.

### cpu.simd.005 — Packed integer division and modulo have no portable lowering

- Next: define integer lane division/remainder semantics and implement constant-divisor strength
  reduction plus a profitable target-independent sequence or explicit fallback, instead of treating
  the absence of one machine instruction as a permanent operator restriction.
- Done when: signed/unsigned lanes, zero divisors, `Min / -1`, constant and variable divisors,
  constant folding, and runtime execution have one documented contract and the cost model declines
  transformations that would lose to scalar code.
- Related: cpu.simd.017, cpu.simd.025, cpu.simd.027.

### cpu.simd.010 — Dot products have no VNNI form

- Next: select the VNNI dot-product instructions where the host has them. Unsigned and signed
  byte SAD (`psadbw`), the 16-bit pairwise product (`pmaddwd`) and the unsigned/signed byte
  product (`pmaddubsw`) are the baseline forms and are already selected.
- Done when: a VNNI accumulation is chosen on a host that reports the feature, the baseline
  sequence still runs everywhere else, and both answer the same on the differential tests.
- Related: cpu.simd.001, cpu.simd.012, cpu.simd.019, cpu.simd.026, cpu.simd.029, cpu.simd.030.

### cpu.simd.016 — Vector4 and Pixel.Color do not use their native packed shape

- Next: implement component arithmetic, min/max, abs, floor/ceil, lerp, clamp, dot/length support,
  and reusable color arithmetic through `F32x4`/packed bytes without changing floating semantics;
  do not wrap the current scalar operators directly, which measured 321 to 637 ms in a Release
  array-arithmetic benchmark because the backend already vectorizes their contiguous form better.
- Done when: public math/color tests cover NaN, signed zero, normalization thresholds, rounding,
  and aliasing, and renderer/filter consumers measure a gain rather than only fewer source lines.
- Related: cpu.simd.004, cpu.simd.011, cpu.simd.032.

### cpu.simd.017 — NumericArray cannot specialize legal packed geometries

- Next: specialize generic equality, arithmetic, fill, copy, and mul-add when the instantiated
  element/count/operator combination has supported packed semantics.
- Done when: specialization is compile-time selected, unsupported shapes remain scalar, and
  generated-code tests prove no hidden conversion or temporary array.
- Related: cpu.simd.002, cpu.simd.004.

### cpu.simd.020 — Poly1305 remains scalar

- Next: implement a packed limb strategy or several-message kernel, selected only where it beats
  the current scalar carry chain.
- Done when: differential vectors cover every block-tail length, carry/reduction boundaries are
  exact, and authenticated-encryption throughput improves end to end.

### cpu.simd.021 — SHA-1, SHA-256, and MD5 have no multi-buffer kernels

- Next: add batch APIs or internal batching that process independent message blocks across lanes,
  instead of attempting to vectorize one recurrence-dependent stream.
- Done when: one- through lane-width batches preserve streaming/finalization semantics, fall
  back for a single stream, and improve aggregate hashing throughput.

### cpu.simd.026 — Convolution, resize, smart-crop, and Haar kernels remain scalar

- Next: vectorize interior convolution, horizontal/vertical resampling, integral-image box output,
  Sobel/normalization maps, and contiguous Haar passes while keeping borders and unfavorable gathers
  scalar.
- Done when: golden images remain within the declared numeric tolerance and representative
  large-image workloads show per-stage gains.
- Related: cpu.simd.007, cpu.simd.010.

### cpu.simd.027 — LUT and transcendental image filters have no packed path

- Next: use gathered tables or vector math to accelerate gamma, contrast, fade, colorize, HSL, and
  noise kernels without weakening their output contract merely to fit today's instruction set.
- Done when: each filter declares exact or bounded-error parity, uses the profitable gather/math
  path under feature dispatch, and retains a scalar fallback.
- Related: cpu.simd.004, cpu.simd.007, cpu.simd.011.

### cpu.simd.029 — The JPEG forward transform and quantization remain scalar

- Evidence: the JPEG decoder and the encoder's colour conversion (`loadFromRGB` in
  `encode/jpg/dct.swg`) are packed. The encoder's float AAN forward transform and the
  quantization that follows it are scalar and now dominate encoding. Their samples go
  through an `s16` staging array because no packed `s32` to `f32` lane conversion exists
  (cpu.simd.004).
- Next: decide whether byte-exactness with today's encoded output must be kept. Lane-by-lane
  float order can still change the last bit under multiply-add contraction, and an integer
  transform changes the bytes outright. Then profile the encoder stages before writing the
  kernel.
- Done when: fixtures preserve accepted pixel tolerances, coefficient extremes are covered,
  and encode throughput improves in an interleaved A/B on a quiet machine.
- Related: cpu.simd.004, cpu.simd.010.

### cpu.simd.030 — WebP reconstruction and transforms remain mostly scalar

- Next: vectorize VP8 inverse transforms, predictors, deblocking, YUV conversion, alpha filters,
  and lossless subtract-green/cross-color/predictor transforms.
- Done when: lossy and lossless fixture pixels remain identical where specified, predictor and
  boundary modes are exhaustive, and stage benchmarks show the retained gains.
- Related: cpu.simd.006, cpu.simd.010.
