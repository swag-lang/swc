# Structural compilation savings, 2026-10-20

This prompt-4 session starts at `71f642e258`, on `perf/prompt4-20261020` in an
external worktree. Planned compiler work uses its checkout-local DevMode compiler
and at most six workers. `SWC_BUILD_NUM` remains 1173. No timing, profiler, or
benchmark campaign is run; compilation-time targets remain unverified.

| Retained change | Compiler work removed | Equivalence and storage evidence |
| --- | --- | --- |
| Initialize conservative CFG reachability with its final value | Zeroing every instruction byte immediately before filling the same bytes with ones | The existing conservative predicate selects the initial byte. Supported graphs retain their zero initialization and traversal; missing roots retain their later all-ones fallback. The DevMode function shrinks from 1,197 to 1,151 code bytes with the same 112-byte stack reservation. |
| Query normalized integer words directly | Reconstructing and masking the low word for each 64-bit conversion; computing a rounded minimum width merely to test 64-bit capacity | Constructors and mutations normalize the active top word. The low word is already the required truncation; 64-bit capacity depends only on the remaining live words. No fields, allocations or representations change. The capacity query shrinks from 289 to 37 code bytes and loses its stack reservation. |
| Initialize fresh integer temporaries once | Normalizing an all-zero constructor result and clearing fresh division, boundary-value and signed-formatting temporaries again | The constructor already clears every live word. The narrow division remainder is built directly with its final low word; traversal, overflow and normalization of nonzero values remain unchanged. Inspected frames do not grow, and the arithmetic object's code and retained data sections shrink overall. |
| Test integer powers of two in one walk | A preliminary all-zero word scan | The existing one-bit scan already returns false when no word contains a bit. Word order and acceptance are unchanged; the helper shrinks from 86 to 57 code bytes without a frame. |
| Build builtin integer bounds at C++ compile time | Twenty runtime constructions, CRT initialization calls and repeated initialization-guard checks | A private immediate constructor checks normalized words for the same twenty 8/16/32/64/128-bit values. Other widths keep their existing helpers. All four bound functions lose CRT initialization references and reduce their stack reservations from 48 to 32 bytes; object code and retained data sections both shrink. |
| Remove the unread reverse keyword map | Building and destroying 157 hash-map entries and their allocations | The field has no readers; forward keyword insertion, lookups and assertions are unchanged. Keyword setup loses code and reduces its stack reservation from 21,744 to 21,120 bytes. |
| Construct character flags from a constant template | Runtime clearing and merging passes over the character-class table | The same rules build a 1,024-byte template at C++ compile time. Setup copies it to the original member location, preserving every lookup. All 346 lexer code sections remain byte-identical. The template is smaller than the removed reverse map's minimum 2,826-byte key/view payload, before node and bucket overhead. |
| Check the reserved namespace without an owning string | Copying a namespace, lowercasing its entire contents and destroying the copy | Length and four unsigned-byte `tolower` checks preserve the existing locale-sensitive result. The helper shrinks from 225 to 91 code bytes and its stack reservation from 80 to 32 bytes. |
| Borrow assignment and generic-declaration AST lists | Copying node references into temporary vectors and destroying those vectors | Chunk iteration preserves source order, skipped assignment targets and recursive parameter expansion. Assignment-list code shrinks from 880 to 876 bytes and its frame from 1,080 to 856 bytes; generic-root parameter collection shrinks from 1,417 to 1,384 bytes and its frame from 744 to 488 bytes. The 102-byte span helper already exists elsewhere and is folded by the linker. |
| Borrow generic parameter declarations during deduction | Copying declaration references before expanding their descriptions | The ordered recursive expansion reads the same immutable AST chunks. The collector shrinks from 1,261 to 1,252 code bytes and its frame from 800 to 528 bytes; one temporary cleanup disappears. The existing span helper is shared. |
| Append cloned parameter declarations directly to their worklist | A temporary reference vector and a second per-reference append loop | The index-based worklist keeps the same order across growth. Its identifier collector shrinks from 1,923 to 1,627 code bytes and its frame from 1,032 to 728 bytes. No AST entries or identifiers change. |
| Preserve normalized words without remasking them | Eight redundant normalization tails after bitwise operations, logical right shift, remainder construction and unsigned widening | These operations cannot set a bit above the existing width, or already finish through a normalizing mutation. Both bitwise inputs have the same normalized width; the raw-word OR masks its input first. Arithmetic that can introduce upper bits retains its mask. |
| Query minimum integer widths from normalized words | Reconstructing the unsigned top-word mask and clamping an already bounded highest bit; masking the signed input word again | The highest live set bit is inside the width. Signed queries retain the mask on their synthesized sign fill. All ten changed bodies shrink and their frames remain stable or shrink. The integer object's code shrinks from 20,407 to 20,108 bytes and retained data from 5,653 to 5,561 bytes. |
| Clear COFF output at its public entry point | A second `clear` call in the sole private builder | The public object builder clears the output before any possible failure and does not write it before calling the private file builder. The later resize still initializes every output byte. The private builder keeps its 2,283-byte body and 352-byte frame while losing one call. |
| Validate intrinsic-name spelling at C++ compile time | A length check and five-byte prefix comparison for each intrinsic-name query | The definition table is statically constrained to `Swag.` names or dot-prefixed member intrinsics. A one-byte member check preserves the empty names for `.count` and `.buffer`; all other accepted names lose the same five bytes. The helper shrinks from 98 to 85 code bytes without a frame; its registry initializer shrinks from 981 to 935 bytes with the same 120-byte frame. |
| Reuse each keyword validation lookup | A second identical hash-table probe after each of 157 keyword insertions | One pointer feeds the existing presence and value assertions. A compile-time assertion-mode branch removes the entire check when assertions are disabled. Insertion order, slots and capacity do not change. Setup code shrinks from 105,131 to 89,385 bytes and its stack reservation from 21,120 to 16,032 bytes; the object loses code and retained data overall. |
| Check field uniqueness through insertion's result | A separate membership query before each struct-field insertion | The existing `emplace` reports duplicates and still supplies the same field ordinal. The assertion remains active; using-field flag publication, map insertion and field publication keep their order for valid input. `addField` shrinks from 426 to 236 code bytes with the same 80-byte reservation. |
| Reuse a contiguous span's aligned offset | Recomputing the aligned data position after a successful capacity check | The capacity comparison uses the same unsigned footprint arithmetic. A new page recomputes the offset from zero; existing-page writes reuse it. Header, payload and publication order are unchanged. The builder shrinks from 429 to 426 code bytes with the same 56-byte reservation. |
| Read a message listener's source file once | A duplicate source-view/file lookup before preparing the same request | The existing saved pointer still controls rejection of a missing file and populates the request. Other argument guards and queue operations retain their order. The function shrinks from 578 to 555 code bytes with the same 80-byte reservation and one fewer call. |

Validation uses fresh machine-load admission before each command. C++ tests use
isolated temporary/cache roots. The default C++ suite omits filesystem tests
requiring `--dev-full`.

The first retained batch builds successfully and passes all 1,486 C++ tests,
including a new reachability regression covering multiple/duplicate roots,
detached instructions, absent roots, unresolved jumps and address-taken labels.
The discarded index-list trial also passed seven focused native tests; those
results are not a validation claim for a retained index-list change.

Two arithmetic defects found while checking the representation invariant were
reproduced with independent bit-by-bit C++ oracles. Unsigned subtraction now
retains the borrow when adding the incoming borrow wraps the subtrahend word.
Negative arithmetic shifts sign-extend a partial top word before moving words or
propagating bit carries. The shift oracle covers every width from 1 through 128,
five input patterns, and shifts through one beyond the width. The subtraction
oracle covers all those widths and 49 input pairs. Both tests fail before their
repairs; the repaired DevMode compiler passes all 1,488 C++ tests. These are
correctness repairs, not compilation-speed gains.

A later division regression starts the overflow output as true and divides zero
or the maximum value by one at every width from 1 through 128. The old narrow
division path leaves that output unchanged: the new test fails while the other
1,500 pass. Division now initializes the output before either path, and all
1,501 C++ tests pass. This is another correctness repair, not a speed gain.

The normalized-integer batch passes 1,490 C++ tests, including bit-based query
oracles and narrow/wide-divisor remainder checks, the complete JIT suite (1,539),
and the complete native suite (3,900), with the DevMode compiler and `devmode`
program configuration. Native validation includes the expected idle, pending and
hardware recovery probes; the tool exits zero.

The constant-bound batch passes 1,491 C++ tests. Its new oracle checks every
active boundary bit at widths 1 through 128 and the zero-width default. Focused
semantic validation with `--file-filter literal` checks 40 normal and 32
expected-error inputs, including runtime sources, with the DevMode compiler and
`devmode` configuration. Semantic validation checks diagnostics and compile-time
assertions rather than executing `#test` bodies.

The lexical-initialization milestone passes 1,495 C++ tests, including every byte
class and out-of-range values, an owning-fold namespace oracle and all sixteen
ASCII casing combinations. The full lexer suites check 33 normal and 50
expected-error inputs; namespace-focused semantics checks 31 and 29 respectively,
including runtime sources. Full JIT passes 1,539 tests and full native passes
3,904, including the expected recovery probes. This milestone uses the combined
base `db9b65ad9c`, including concurrent compare-scan and loop-rotation changes.

The borrowed-list batch passes 1,500 C++ tests, five native multiple-assignment
tests and generic-focused semantic checks over 68 normal and 45 expected-error
inputs, including runtime sources. The existing paged-span tests cover chunk
boundaries and growth; the borrowed views remain inside the original AST owner's
lifetime. This batch uses base `62434c120a`, including the imported invariant
subtraction and scaled-add optimizer changes.
The same compiler also passes all 315 native optimizer tests.

The deduction/cloning batch passes 1,500 C++ tests, generic-focused semantic
checks over 68 normal and 45 expected-error inputs, all 152 native tests in the
`generics` directory, and the native macro-parameter-shadowing case. The broader
singular `generic` filter excluded the shared allocator used by some selected
examples; its missing-symbol failure was a selection error and is not counted
as validation. The corrected directory selection includes its provider files.

The normalization/minimum-width batch passes 1,503 C++ tests. The bit oracle now
checks signed and unsigned minimum widths, signed 64-bit capacity, and zero
extension into a larger width. Additional cases cover every single bit and its
complement at widths 1 through 128, logical shifts and bitwise mutations, and
signed quotient/remainder normalization at widths 3 through 128.

The COFF milestone on base `0614ed6b6c` passes all 1,565 C++ tests with
`--dev-full`, including the extended-relocation writer case, all 1,539 JIT tests
and all 3,908 native tests. Native recovery probes fail as expected and the
outer tool exits zero. This milestone also validates the combined AST and
integer changes integrated at that base.

The intrinsic-name batch passes 1,504 C++ tests, including round trips for every
named intrinsic and rejection of member/non-intrinsic names. Intrinsic-focused
parser validation checks 29 normal and 29 expected-error inputs, including
runtime sources.

The keyword-validation batch passes 1,504 C++ tests and the complete lexer
suites (33 normal and 50 expected-error inputs, including runtime). C++ inlining
also folds the lookup helper into the two public queries: the hashed query's
reservation falls from 56 to 32 bytes, while the unhashed query retains 48 bytes;
both lose an intermediate helper call. Table storage and query results remain
unchanged. A lambda-based trial added per-keyword calls and was replaced by the
direct compile-time-gated block before validation.

The field-insertion batch passes 1,504 C++ tests and the native `struct_layout`
case, including packed fields, explicit alignment and overlapping field offsets.
The two affected name-lookup wrappers retain or shrink their reservations while
C++ inlining removes an intermediate helper call; their source logic is unchanged.

The contiguous-span batch on combined base `a0e8332edc` passes 1,505 C++ tests,
including raw-span payload/alignment checks for existing and fresh pages and
zero alignment. Overload-focused semantics checks 34 normal and 31 expected-error
inputs, including runtime sources, and the native optimizer selection passes
316 tests, covering the concurrent optimizer changes imported at that base.

The listener-file batch passes 1,505 C++ tests and message-focused semantic
checks over 29 normal and 29 expected-error inputs, including runtime sources.
These inputs exercise compiler message type metadata and cyclic message work.

Rejected trials:

- Returning a separately constructed all-ones reachability vector duplicated
  generated construction code and grew the frame. The retained version constructs
  one vector with the predicate-selected initial byte.
- Borrowing index-list AST chunks removed their temporary reference vector and
  reduced the frame, but grew the generated caller body. Both the initial form and
  a form sharing initial header decoding were discarded. The original index-list
  implementation is restored.
- Reusing `nthNode`'s initial chunk total for bounds checking would decode a
  chunk for legitimate out-of-range queries that currently read only the total.
  That work tradeoff was left aside; no AST lookup change is retained.
- Inlining the two `ByteArray::data` getters removed fourteen calls and 112 code
  bytes from the inspected COFF writer, but increased the allocation-section
  builder's stack reservation from 352 to 368 bytes. The trial is discarded;
  both accessors keep their original out-of-line definitions.
- Borrowing generic parameter-name token chunks grew each of the two inspected
  collectors by 281 code bytes. The extra token-span API and its callers are
  restored. Borrowing partial-lambda parameter chunks grew that caller by 13
  bytes and is also restored; none of these trials is retained.
- Removing the scalar divider's final normalization changed its inlining into
  unsigned formatting: `toString` grew from 439 to 550 code bytes and its frame
  from 112 to 144 bytes. That one tail is restored; formatting returns to its
  original body and frame while the other normalization savings remain.
- Returning early from Tarjan's recursive connector for a graph sink removed
  stack operations on that path, but grew the connector from 450 to 501 code
  bytes and cycle discovery from 742 to 781 bytes. The trial is restored.
- Caching the COFF output pointer and deferring read-only-data span construction
  removed calls or unused work, but each affected builder's frame grew from 352
  to 368 bytes. Restoring the private clear and shortening the span lifetime did
  not remove that growth. Those pointer/span rewrites are restored.
- Pre-reserving the keyword table was left aside: a static insertion model
  changes collision order and lengthens some individual lookups, including
  `if`. The allocation saving would therefore require a timing tradeoff; no
  keyword-table reservation change is retained.
- Starting decimal formatting loops with `do` removed an already-proved first
  zero check, and copying the signed minimum avoided rebuilding its magnitude.
  The unsigned body shrank by five bytes, but the signed variants grew and
  reserved 16 more stack bytes. Even the unsigned-only change crossed an
  inlining threshold and grew signed formatting from 2,093 to 2,454 bytes. All
  formatting changes and their trial-only oracle are restored.
- Peeling the first paged-span write removed its repeated first-reference test,
  but grew `pushSpanRaw` from 330 to 347 code bytes and its reservation from 104
  to 120 bytes. The original chunk loop is restored.
