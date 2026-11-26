# Core Backlog

This backlog covers `std/core`, measured against the standard libraries it competes with:
the Go standard library, the .NET base class library, Rust's `std` plus its de-facto crates, the
Python standard library, and Zig's `std`.

Compiler issues belong in [compiler.frontend.md](compiler.frontend.md), [compiler.build.md](compiler.build.md),
[compiler.codegen.md](compiler.codegen.md), or [compiler.optimization.md](compiler.optimization.md). Language changes belong in
[language.design.md](language.design.md). This file keeps the evidence, investigations, and intended outcomes
owned by `bin/std/modules/core` together. [README.md](README.md) has the whole layout.


Read [design-swag-bin-modules](../.agents/skills/design-swag-bin-modules/SKILL.md) before
acting on an entry that proposes a boundary change. This file keeps the evidence and intended
outcomes owned by `core` together.

## Entries

### std.core.018 — Rebaseline and reduce Deflate match-search cost

- Evidence: match search dominates `Compress.Deflate` level 6 on filtered PNG data, which also
  sets the cost of `TagBin` and future containers. Level 6 walks up to 132 candidates per
  position for matches three to six bytes long, while level 1 compresses the same input about 4x
  faster for about 5% more bytes. The two untried levers are zlib's `nice_match` (stop the chain
  once a match is long enough, 128 at level 6) and tuning the lazy-match rule inherited from
  miniz. Both change which matches are chosen, so each must report compressed size beside time.
  Older timings predate a compiler spill fix, so they are not a baseline. Any remaining backend
  cause belongs in [compiler.optimization.md](compiler.optimization.md).
- Next: remeasure the current compiler and match finder on the same PNG and `.scc` corpus,
  then compare each search-policy change against that recorded baseline.
- Done when: level 6 on the PNG and `.scc` fixtures is at least 1.5x faster than that
  baseline with no more than 1% growth in compressed size, and every `core` compression test
  still round-trips.
- Related: std.core.021, std.core.022

### std.core.010 — No AES implementation

- Evidence: `Crypto.Aes` now implements AES-128/192/256 blocks with a constant-operation-path
  software substitution and FIPS 197 tests. `Math.Simd` has no AES-round intrinsic, so AES-NI
  dispatch is not available; the software path is slower than a hardware backend. AES-GCM now
  parallelizes independent CTR batches for large records. `core/src/crypto`
  also has Adler-32, CRC-32, CRC-64, MD5, SHA-1, SHA-224, SHA-256, SHA-384, SHA-512,
  SHA-512/224, SHA-512/256, SHA-3, SHAKE,
  HMAC-SHA-224/256/384/512, HMAC-SHA-3, KMAC128/256 and KMACXOF,
  AES-CMAC,
  HKDF-SHA-224, HKDF-SHA-256, HKDF-SHA-384, HKDF-SHA-512, PBKDF2-HMAC-SHA-224/256/384/512, BLAKE2b,
  BLAKE2s, BLAKE3, X25519, P-256 ECDH and ECDSA-SHA-256, Ed25519, AES-GCM, Argon2id, ChaCha20,
  Poly1305, ChaCha20-Poly1305, XChaCha20-Poly1305, AES-CTR, AES-CCM, AES-XTS, AES-SIV,
  AES-KW/KWP, scrypt,
  RSA-OAEP-SHA-256, RSA-PSS-SHA-256, and several non-cryptographic hashes.
- Next: add an AES-round backend that can safely select AES-NI after runtime feature detection,
  retain the constant-operation-path software fallback, and measure both paths. Add separately
  numbered modes only when their contracts are chosen.
- Done when: AES-128, AES-192, and AES-256 block operations match published vectors in
  hardware and fallback paths, the fallback has a documented constant-time contract, and cipher
  modes retain separate backlog IDs.
- Related: std.net.005

### std.core.021 — No gzip container support

- Next: add the gzip container over the existing deflate/inflate and zlib support, including
  headers, trailers, checksums, and concatenated members.
- Done when: gzip reading and writing validate headers, trailers, checksums, and concatenated
  members over existing Deflate, with round-trip, truncation, and corruption tests.
- Related: std.core.022, std.core.023

### std.core.023 — No TAR container support

- Next: add streaming TAR reading and writing, with the supported metadata and extension
  variants stated.
- Done when: a streaming TAR reader and writer round-trip regular files, directories, and the
  declared metadata and extension variants, while malformed sizes and unsafe paths fail under
  explicit limits.
- Related: std.core.021

### std.core.024 — Time zones

- Evidence: `time` handles UTC and local. There is no IANA zone database, no historical
  offsets, and no DST rules for an arbitrary zone, so any application that schedules or displays
  times across regions is stuck at the boundary.
- Next: choose the zone-data source (platform database or embedded tzdata) and add a zone type
  that converts UTC to and from civil time for a named zone.
- Done when: a named IANA zone converts UTC and local civil times using historical offsets and
  daylight-saving rules, and tests cover transitions, ambiguous times, missing times, and
  unknown zones.

### std.core.019 — Unambiguous regular-expression captures replay the search

- Evidence: `src/text/regexp` finds the matching span with its automata, then uses the
  iterative backtracking engine for short-span capture recovery, with the Pike VM handling
  longer spans or exhausted backtracking budgets. Capture extraction therefore walks the
  pattern a second time.
- Next: identify patterns whose capture transitions are unambiguous and prototype capture
  extraction during one forward pass. Keep the bounded fallback for patterns outside that subset.
- Done when: the capture corpus returns identical groups and spans, ambiguous patterns retain
  the existing fallback, and interleaved measurements show the cost of the second walk removed.
- Related: std.core.020, std.core.030

### std.core.032 — The recovered inflate rewrite fails a real-document golden

- Evidence: the rewrite, with a refill of its own for the careful path's length/distance group,
  is preserved in commit `643900899`; `bin/std` keeps master's inflate. The rewrite decoded the
  native InDesign fixture `publicdomain.indd` (removed from Swag Scope with its viewer; still in the
  history of `bin/apps/modules/swagscope/src/tests/datas/`) to an image the golden rejected, and the
  mismatch has not been attributed to specific decoded bytes. No synthetic Deflate stream from the
  repository's own compressor reaches the careful path with a drained bit buffer, so that file is
  what exercises the real shape.
- Next: decode the document's streams with both decoders and compare the output, rather than
  rendered images, so the divergence is a byte offset instead of a pixel. Only then decide
  whether the rewrite is repairable, and measure what it buys over master's inflate.
- Done when: the rewrite decodes every stream byte-for-byte as master's inflate does, a `core`
  test fails without the careful path's refill, and a measurement says what the rewrite buys;
  or the rewrite is abandoned and this entry deleted.

### std.core.022 — No reusable ZIP reader and writer


- Evidence: Core exposes no ZIP container API. Swag Scope already owns a bounded reader in
  `bin/apps/modules/swagscope/src/viewers/archive/zip.swg`, including ZIP64 directory metadata, stored/Deflate
  extraction, CRC checks, and a 250,000-entry limit.
- Next: review and extract that reader into a reusable container boundary, migrate Scope to it,
  and add the missing writer with explicit supported formats and resource limits.
- Done when: owning round-trip and malformed-container tests cover the shared reader/writer
  and Scope uses that contract without a private ZIP parser.

- Related: std.core.021

### std.core.031 — Two atomic families, one of them Core's

- Evidence: `Core.Atomic` (`thread/atomic.swg`) is a namespace of `#[Swag.Inline]` wrappers
  over the `Swag.atom*` intrinsics, with about 220 uses in 26 files under `bin/`.
  `Swag.AtomicValue'T` (`bin/runtime/atomic.swg`) owns atomic storage and exposes the same
  operations as methods. The concurrency contract says one owner for each concurrency type
  family; there are two, and the runtime one is named `AtomicValue` because `Atomic` is already
  taken by the Core namespace in every file that writes `using Threading`.
- Next: decide which one the language keeps. Storage that only its own operations reach is the
  stronger contract, since it makes "no ordinary access beside an atomic one" checkable, so the
  likely answer is the runtime type, with `Core.Atomic` migrating to it and the runtime type
  taking the name `Atomic` once the namespace is gone. Count the call sites that atomically
  access a field of a larger structure, because those need the field itself to become an
  `AtomicValue` rather than a wrapper call on its address.
- Done when: one atomic family remains, its name is not a workaround, and no consumer reaches
  atomic storage through an ordinary pointer.
- Related: language.parallelism.001, language.parallelism.015

### std.core.025 — A dependency graph of tasks is written by hand

- Evidence: the runtime joins a group whose children can fail (the first error asks the others to
  stop), and waits for all or any of several typed tasks (`Swag.whenAll`, `Swag.whenAny`);
  H.264 reconstruction bands use such a group. What remains hand-made is a dependency between
  tasks: HEVC wavefront rows each wait for the row above to be two coding tree blocks ahead,
  through an array of `Sync.Event`s, a progress array and a shared failure flag. Nothing bounds
  how many children a group runs at once either.
- Next: decide whether a row that waits on its neighbour's progress is a task-graph edge, with
  cycle rejection, or a progress counter a task can wait on without occupying its worker; settle
  it against the dependency-graph workload in language.parallelism.001.
- Done when: HEVC wavefront decoding has no hand-made event array or failure flag, and its
  speed is measured against what it does today.
- Related: language.parallelism.002, language.parallelism.011, std.core.028

### std.core.028 — No asynchronous I/O contract

- Evidence: there is no shared asynchronous I/O contract for completion, cancellation, borrowed
  buffers, or scheduler integration.
- Next: implement awaitable I/O against language.parallelism.002's completion and task-lifetime rules,
  using runtime-owned operation, completion, and cancellation types. Keep the common operation
  contract independent of its first socket or file backend. Model
  immediate completion, failed registration, cancellation racing completion, partial transfer,
  late callbacks, and shutdown. A stop request or expired deadline is not native completion.
- Done when: a fake backend and one real backend demonstrate exactly one terminal completion
  and retain buffers, request records, and callbacks until the backend is finished with them;
  owning I/O consumers use the common runtime without private task or cancellation machinery.
- Related: language.parallelism.002, std.core.025, std.net.004

### std.core.030 — Compiling a regular expression makes many separate allocations

- Evidence: after byte-set accounting and lazy automaton construction, the remaining cost of
  compiling a small pattern is suspected to be allocation count, but it has not been isolated
  from parsing and program construction in a current profile.
- Next: count allocations and bytes per compiled pattern, then test whether co-locating the
  immutable program data improves compilation without retaining unused automata or excess memory.
- Done when: that attribution is reproducible and the allocation design is either improved
  with equal matching behavior or retained for a measured reason.
- Related: std.core.019

### std.core.020 — Unicode scripts and most derived properties are missing

- Intent: `\p{...}` should name the scripts and the common derived properties, not only the
  handful of general categories the Unicode tables in `core` happen to carry.
- Where it stands: `\p{L}`, `\p{Ll}`, `\p{Lu}`, `\p{Lt}`, `\p{N}`, `\p{Nd}`, `\p{S}`,
  `\p{Sm}` and `\p{Z}` work, negated by `\P`. `\p{Greek}`, `\p{Han}`, `\p{Alphabetic}` and
  the rest fail to compile; `White_Space` is already supported. The engine itself needs nothing new: a property is a set of scalar
  intervals, and the compiler already turns any such set into a UTF-8 automaton.
- Next: the interval tables. `Unicode` ships general-category tables ported from Go;
  scripts would be another table of the same shape, generated the same way, and the property
  lookup in `RuneClass.unicodeProperty` is one more `switch` arm per table.
- Done when: the script names of UAX #24 resolve, a test matches text in two scripts, and the
  tables are generated rather than hand-written.
- Related: std.core.019
### std.core.036 — Move the regex program and syntax nodes to tagged unions after measuring

- Evidence: `Regex.Inst` ([program.swg](../bin/std/modules/core/src/text/regexp/program.swg))
  shares `next` across kinds and keeps `lo`, `hi`, `assertion`, `alt` and `slot` meaningful for one
  kind each; `Regex.Node` and `Regex.Prefilter` are wide structs commented form by form. They sit
  on the hot paths of every regex engine.
- Next: prototype `Inst` as `next` beside a union tagged by `InstKind`, compare the generated
  loops in the existing regex engine on representative search inputs. Check instruction
  counts and data layout before migrating.
- Done when: the regex types state their forms as tagged unions and paired measurements
  preserve search performance, or the measurement rejects the change and this entry is
  removed.
- Related: language.design.055.

### std.core.037 — Format.toString ignores arguments its format does not use

- Evidence: `Format.append` asserts when a placeholder has no value but silently ignores unused
  values. `Format.checkFormat` is not called and counts every non-escaped percent sign as a separate
  value, which would reject supported indexed or repeated placeholders such as
  `%{#0} and %{#0} again`. The formatter already supports zero-padded fields: `"%{04}"` with `7`
  writes `"0007"` in its functional test.
- Next: define argument-use rules for sequential, indexed, reordered, and repeated placeholders,
  then validate literal formats at compile time and dynamic formats with an assertion without
  rejecting supported indexed reuse.
- Done when: mismatched placeholder and value use is reported, indexed and repeated references
  remain valid, and tests cover both format paths.

### std.core.038 — TagBin stores an enum by its rank, which ties stored data to declaration order

- Evidence: `serialization/helpers.swg` identifies an enum by its underlying type and writes its
  value, which for an ordinary enum is the rank of its case. Inserting, reordering or removing a
  case changes the meaning of every stored value: Swag Capture had to put
  `LibraryContentFilter.Animations` last instead of where the filter menu shows it, and
  `EditorLanguage` warns that "the order is the stored one". Application states, capture documents
  (`CaptureMedia`, `CaptureSourceKind`, `FormSubKind`) and options all store enums this way.
- Next: give TagBin a policy for enums: write a stable identity of the case, such as a CRC of its
  name (overridable by an attribute for a renamed case), read it back to the matching case, and
  keep reading the value written by earlier versions; `#[Swag.EnumFlags]` and enums with explicit
  values that are a wire format (`TagBin` flags) keep their value.
- Done when: inserting or reordering cases of a stored enum reads earlier files back to the same
  cases, a renamed case can keep its identity, and unknown identities are reported rather than
  mapped to a wrong case, with tests at the serializer boundary.

### std.core.041 — Make file transfer roles and replacement explicit

- Evidence: [`File.move` and `File.duplicate`](../bin/std/modules/core/src/filesystem/file.swg)
  take two strings in destination-first order and replace an existing destination. Swapping
  paths still type-checks. `duplicate` reads the source and writes directly to the destination.
- Next: define explicit source and destination roles and an explicit replacement policy.
  Specify same-file and cross-filesystem behavior, and how copying publishes a complete
  replacement. Migrate callers by the role each argument already plays. Evaluate a request
  record with named, required fields if the language keeps named arguments optional.
- Done when: callers express both roles and the collision policy. Tests on Linux and Windows
  cover refusing to replace an existing or concurrently created destination, preserving the
  old destination on a failed replacement copy, same-file calls, and cross-filesystem moves.
- Related: language.design.044, compiler.query.003.

---

### std.core.042 — Packed numeric lane conversion is incomplete

- Next: complete signed and unsigned integer-to-float, the float-to-integer directions beyond
  the existing four-lane `f32` to `s32` truncation, and widening/narrowing numeric conversions
  distinct from bit reinterpretation and saturating pack.
- Cost of the gap: the JPEG encoder converts colour with packed 16.16 arithmetic but its forward
  transform reads floats, and with no `s32` to `f32` lane conversion the samples have to land in a
  `s16` staging array that the transform then converts one lane at a time.
- Done when: every legal 128-bit conversion has specified overflow/NaN behavior, constant and
  runtime coverage, idiomatic hardware lowering, and wider equivalents where the target supports
  them.
- Related: std.pixel.042, std.pixel.image.054, std.pixel.043.

### std.core.043 — Vector tails require scalar cleanup

- Next: add masked load/store and partial load/store operations with an explicit valid-lane mask,
  defined non-faulting behavior, and efficient baseline lowering when native masks are unavailable.
  `Core.Math.Simd` also ships `storeLow4` and `storeLow8` with no load counterpart, so 4x4 and 8x8 block kernels need padded storage for a full load or explicit scalar partial
  loads. A masked or partial API must make those preconditions explicit.
- Done when: arbitrary byte counts can be processed without reading or writing outside the
  slice, sanitizer-style guard-page tests cover both ends, and AVX-512 uses native masks.
- Related: compiler.codegen.020, std.core.048, std.video.019, std.pixel.040.

### std.core.044 — Gather supports one shape; scatter, compress and expand are absent

- Evidence: `Swag.vecGather` / `Math.Simd.gather` support only `s32` lanes with `u32x4`
  indices, lowered to AVX2 `vpgatherdd`. Scatter, compress and expand have no surface. The
  earlier gather timings were taken while the SIMD wrappers were still cross-module calls,
  so they do not establish the operation's cost. They are not evidence behind the
  gather-driven rejections in std.pixel.image.054 and std.video.018 either.
- Next: time the inlined `vpgatherdd` against scalar lane loads on a hot-LUT
  microbenchmark and in one consumer, then specify bounds and aliasing semantics for
  indexed loads/stores and mask compaction/expansion, with a cost model allowed to pick
  scalar lane operations.
- Done when: bounds and aliasing semantics are explicit, AVX2 gather and AVX-512 scatter/
  compress/expand are encoded, and the fallback never performs an invalid masked access.
- Related: compiler.codegen.020, std.pixel.image.053, std.pixel.image.056, std.gui.pdf.044.

### std.core.045 — Packed memory access has no alignment or cache policy

- Next: add aligned load/store assertions or hints, broadcast loads, and non-temporal stores.
  `Swag.prefetch` already hints a read into every cache level (`prefetcht0`), never faults and is
  a no-op where a target has no such instruction; a locality or write-intent variant belongs here
  once a consumer measures a need for it.
- Done when: alignment violations are diagnosed or guarded as declared, large copy/fill and
  image-row benchmarks establish thresholds for streaming access, and ordinary unaligned access
  remains the default portable operation.
- Related: platform.portability.103, std.pixel.040, std.pixel.043.

### std.core.046 — AES round and key instructions have no typed surface

- Evidence: `Swag.vecCarrylessMul` and the four `Math.Simd.clmul...` wrappers already expose
  carry-less multiplication; `Hash.Crc32.foldClmul` consumes them and the x64 encoder has a byte
  test. AES round/key instructions have no equivalent typed API.
- Next: expose AES round/key operations with explicit availability and known-answer tests.
- Done when: feature gating prevents illegal instructions, known-answer tests cover operands
  and lane ordering, and portable fallbacks or explicit availability checks are part of the API.
- Related: platform.portability.103.

### std.core.047 — Vector rounding and transcendental families remain incomplete

- Evidence: vector sqrt, floor, ceil, trunc, abs, min/max, mul-add, sign, copysign, saturate and
  lerp already have public wrappers in `math/simd.swg`.
- Next: add vector `round`, reciprocal/reciprocal-square-root policy, exp, log, pow, and the
  trigonometric family with documented accuracy tiers instead of treating absent machine
  instructions as a permanent reason to keep callers scalar.
- Done when: error bounds, exceptional values, determinism policy, and scalar/vector parity are
  tested, and benchmarks justify the chosen polynomial/table implementations.
- Related: std.pixel.042, std.truetype.022, std.gui.pdf.044.

### std.core.048 — UTF-8 validation still lacks a profitable packed fast path

- Next: improve `isValid` beyond its current 8-byte scalar ASCII scan; a direct U8x16 bitmask
  path measured 20.76 to 20.42 GiB/s and was rejected.
- Done when: malformed boundaries and arbitrary tails match the scalar implementation and an
  ASCII-heavy benchmark improves rather than only replacing the load width.
- Related: std.core.043, compiler.optimization.138.

### std.core.049 — Vector4 and Pixel.Color do not use their native packed shape

- Next: implement component arithmetic, min/max, abs, floor/ceil, lerp, clamp, dot/length support,
  and reusable color arithmetic through `F32x4`/packed bytes without changing floating semantics;
  do not wrap the current scalar operators directly, which measured 321 to 637 ms in a Release
  array-arithmetic benchmark because the backend already vectorizes their contiguous form better.
- Done when: public math/color tests cover NaN, signed zero, normalization thresholds, rounding,
  and aliasing, and renderer/filter consumers measure a gain rather than only fewer source lines.
- Related: std.core.042, std.core.047, std.pixel.043.

### std.core.050 — NumericArray cannot specialize legal packed geometries

- Next: specialize generic equality, arithmetic, fill, copy, and mul-add when the instantiated
  element/count/operator combination has supported packed semantics.
- Done when: specialization is compile-time selected, unsupported shapes remain scalar, and
  generated-code tests prove no hidden conversion or temporary array.
- Related: compiler.codegen.019, std.core.042.

### std.core.051 — The Argon2 permutation remains scalar

- Evidence: Argon2id compression is scalar; independent lanes already use `parallel for`.
  Earlier packed attempts lost. These ran while the SIMD wrappers were still cross-module
  calls:
  - `U64x2` block XOR was 3.2% slower.
  - Paired BlaMka with a `u32 x u32 -> u64` low-half product (`pmuludq`) was 72% or more
    slower, because lane regrouping and state materialization erased the arithmetic gain.
- Next: retry only with a lowering that keeps the eight-word state in registers across both
  G halves and regroups 64-bit lanes from two sources without scalar extraction, or with a
  wider layout that amortizes the regrouping. Measure lane scaling at fixed worker counts on identical inputs.
- Done when: published vectors pass for all supported parameters and profile benchmarks
  isolate the packed kernel gain from independent-lane parallelism.

### std.core.052 — Blake2b compression remains scalar

- Evidence: pairing two G functions while packing and extracting scalar state at every
  half-round was 5.19x slower over 64 MiB. That measurement predates current inlining and
  the current allocator.
- Next: prototype paired G functions with persistent vector state and cheap 64-bit lane
  permutation (native rotates or shift/or), or independent messages per lane, and measure
  against the scalar kernel.
- Done when: incremental, keyed, and boundary-length vectors match and compression
  throughput improves without changing digest output.

### std.core.053 — Poly1305 remains scalar

- Next: implement a packed limb strategy or several-message kernel, selected only where it beats
  the current scalar carry chain.
- Done when: differential vectors cover every block-tail length, carry/reduction boundaries are
  exact, and authenticated-encryption throughput improves end to end.

### std.core.054 — SHA-1, SHA-256, and MD5 have no multi-buffer kernels

- Next: add batch APIs or internal batching that process independent message blocks across lanes,
  instead of attempting to vectorize one recurrence-dependent stream.
- Done when: one- through lane-width batches preserve streaming/finalization semantics, fall
  back for a single stream, and improve aggregate hashing throughput.

### std.core.055 — Use one contract for a normal lookup miss

- Evidence: [`HashTable.find`](../bin/std/modules/core/src/collections/hashtable.swg#L811)
  asserts on a missing key, while [`Regexp.find`](../bin/std/modules/core/src/text/regexp/regexp.swg#L231)
  returns a flag and span and changes capture state. UTF-8 index searches can return
  `Swag.U64.Max`. A caller guessing from the names can mishandle absence or mutate state.
- Next: normalize the Core collection, regex and text search families. Make normal absence
  explicit in the result, name required-presence operations separately, and expose when a
  search updates capture state. Choose a representation that cannot expose an unchecked
  span or index for a miss. Test empty input and an empty successful match separately.
- Done when: the same operation vocabulary predicts the miss, ownership and mutation
  contract across the audited families, and a miss cannot be consumed as a valid result.
- Related: language.design.053, language.design.055.
