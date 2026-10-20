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
