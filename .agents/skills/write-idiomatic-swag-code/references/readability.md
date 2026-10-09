# Review Swag For Human Reading

Use this guide for a readability pass or a difficult layout decision. The skill's main rules
apply during ordinary edits too. Optimize how quickly a reader can reconstruct the operation
and verify it, not the number of characters, lines, comments, or extracted functions.

The examples assume the module imports `core` and the source has `using Core`.

## Review One Function, Then Its Neighbours

1. Read the signature and scan the body without opening helpers. Identify the result, main path,
   failure paths, and ownership. Mark the places that require rereading or horizontal scrolling.
2. Fix the strongest obstacle first: duplicated policy, hidden state, nested decisions, an opaque
   expression, a wall of statements, or excessive spacing. Shortening an already obvious accessor
   is lower value than clarifying one difficult branch.
3. Form paragraphs around operations. A paragraph ends when the reader's question changes from
   validation to transformation, for example. If a substantial paragraph needs a label, give it a
   short purpose comment; if its details overwhelm its caller, consider a named helper instead.
4. Format, then read again at an ordinary editor width. Check that wrapping has not turned one
   expression into a staircase and that alignment has not pushed the useful part far to the right.
5. Read the file and related module entry points together. Align terminology, sibling operation
   order, and failure conventions. Search for existing helpers before extracting another one.
   Keep type ownership and file boundaries from the main skill; do not fragment a type by phase.

A long function can still be clear when it is a linear, well-grouped operation. A short function
can be difficult when each line hides several decisions. Length is a prompt to inspect, never an
automatic reason to split. Likewise, a blank line is useful only when it identifies a boundary.

## A Lightweight Review Score

For a broad pass, optionally rate each dimension 0 (obstructs reading), 1 (needs a reread), or
2 (clear on a first read). Use the same reader assumptions before and after. This is a subjective
review aid, not a scientific cognitive metric or an automated acceptance gate.

| Dimension | What a clear function lets the reader see |
| --- | --- |
| Purpose | Names, signature, and result describe one operation. |
| Paragraphs | Spacing and short landmarks expose phases without scattering related lines. |
| Expressions | Width, operators, arguments, and intermediate names reveal each calculation. |
| Control and effects | Decisions, failure, mutation, ownership, and cleanup stay visible. |
| Density and navigation | Repetition is removed without forcing jumps through trivial helpers. |
| Local consistency | Related functions use comparable vocabulary and layout; exceptions remain explicit. |

Use the total out of 12 only to compare versions of the same function. Address zeros before
polishing twos. At module level, review the weakest functions and the relationships between them;
an average must not hide a difficult entry point. Do not claim every module has been reviewed
because a text search found no long lines.

Correctness is a prerequisite outside the score. Reject a prettier rewrite that changes
short-circuiting, evaluation count or order, overflow checks, borrowing, ownership, cleanup,
failure behavior, or deliberately tested syntax. Do not trade allocations or algorithmic work
for a smaller source footprint.

## Name The Bound, Keep The Guard

The compact form puts the signature, bounds check, subtraction, and packed-byte expression on
one line. One expression is doing several jobs:

```swag
func readU16OrZero(bytes: const [..] u8, offset: u64)->u16 => offset <= bytes.count and 2 <= bytes.count - offset ? cast(u16, bytes[offset]) | (cast(u16, bytes[offset + 1]) << 8) : 0
```

The expanded form exposes the rejection path and leaves the small byte operation together:

```swag
func readU16OrZero(bytes: const [..] u8, offset: u64)->u16
{
    if offset > bytes.count or 2 > bytes.count - offset do
        return 0

    return Math.make16(bytes[offset + 1], bytes[offset])
}
```

The left condition must guard the subtraction. Hoisting `bytes.count - offset` above the guard
to shorten it would change safety. The sentinel here belongs to this illustrative contract;
preserve a real reader's existing failure contract when applying the layout.

If several readers repeat this policy, a short `containsRange` helper can own it. Do not add
that indirection for this single use merely to make the function smaller. The existing
`Math.make16` already names byte assembly; its high-byte-first convention exposes the reversed
order of this little-endian reader. Keep explicit shifts when extracting actual bit fields.

## Group Construction With Its Subject

Suppose a module already owns a selection value with `offset`, `count`, and `reversed` fields.
Repeated receiver prefixes and blank-separated assignments obscure that they describe one value:

```swag
struct Selection
{
    offset: u64
    count: u64
    reversed: bool
}

func selectRange(first, last: u64)->Selection
{
    var result: retval
    result.offset = first < last ? first : last

    result.count = first < last ? last - first : first - last

    result.reversed = first > last
    return result
}
```

Keep the same type and construct one visible unit:

```swag
func selectRange(first, last: u64)->Selection
{
    with var result: retval
    {
        .offset = first < last ? first : last
        .count = first < last ? last - first : first - last
        .reversed = first > last
    }

    return result
}
```

Run the formatter to align these assignments. Here the conditionals are small and independent;
adding three helpers would increase navigation. Keep the enclosing receiver explicit as `me`
inside a method's `with` block, and do not nest subjects merely to remove more prefixes.

A name introduced by `with let control = ...` remains in the enclosing scope after the block.
When replacing several anonymous setup blocks, give their controls distinct meaningful names.
For an owning value, retain the original enclosing scope if leaving it would extend cleanup;
removing braces to save space must not change a resource's lifetime.

## Name Mathematical Roles Without Rewriting The Formula

Prefer names such as `direction`, `startProjection`, `denominator`, and `inverseDeterminant`
when they explain how a value is used. Retain conventional coefficients when expanding every
symbol would bury the algorithm; describe the parameter domain and the exceptional cases once.
Keep the original arithmetic order, widths, and wrapping operators. A named crossing coordinate
belongs inside the height guard that makes its division valid, not before that guard.

For SIMD code, keep a short domain qualifier such as `Simd` while removing repeated outer
namespace prefixes. Name a loaded block before a shuffle when nested loads and bit casts hide
which block is being reversed. Establish a channel-pair representation once at its construction
boundary when every later use needs that same bit view. Preserve lane widths, load/store order,
and scalar-tail arithmetic; verify both complete vector blocks and representative tail lengths.

When a vector loop reads farther than it advances, explain both widths once beside the guard.
For example, a 16-byte PCM24 load requires six available three-byte samples even when its shuffle
produces only four output samples. Name source bytes and output samples distinctly, and retain
tests around that threshold and odd destination capacities.

In an interleaved stream, distinguish encoded byte offsets, decoded byte counts, channel samples,
and sample frames in local names. A frame contains one sample per channel; `writtenBytes`,
`totalFrames`, and `channelCount` make their conversions inspectable. Keep source-file positions
distinct from logical playback positions. When trimming decoded output, name the portion that
actually exists in the buffer separately from an expected-but-missing prefix, and compute it only
after the bounds check that makes the subtraction valid. Do not merge codec-specific trimming
policies merely because their counters have the same units.

For a simulation, name the state and its rate separately: `angle` and `angularVelocity` explain
more than numbered abbreviations. Name a damping multiplier after the value it retains, rather
than implying that it is the amount removed. Keep familiar coordinates and short coefficients
when their geometric role is already clear.

A simulation step is a useful extraction boundary when its loops obscure an event handler. Keep
the step's read state stable until all dependent results have been computed; publish a replacement
buffer only after every cell is ready. A short comment should expose that dependency. Verify
representative sequences against the original implementation, including floating-point bit
patterns when only names and grouping changed. A startup smoke alone cannot establish that a
simulation still produces the same states.

Branches that only choose `true` or `false` for the same destination can often become one
readable predicate. For example, Life's rule is `neighbors == 3 or (wasAlive and neighbors == 2)`.
Keep the explanatory grouping and verify the truth table. Do not apply Boolean algebra across
fallible calls, callbacks, volatile state, or guarded accesses; their evaluation is part of the
behavior. A saved state value is appropriate only while that state is stable.

## Factor A Repeated Policy, Keep The Choice Visible

When several branches parse different numeric types but all reject overflow before writing the
destination, the repeated check and write belong in one private helper. Keep the type-to-parser
dispatch at the call site: a small table of explicit choices is easier to verify than a mode
parameter or a second dispatch hidden inside the helper. Name the helper after the operation,
such as `storeParsedNumber`, and keep it with the parser that owns the policy.

Preserve the failure boundary: the destination must stay untouched when parsing fails or the
value overflows. Check the existing tests for that property and for the consumed byte count;
add boundary coverage when the refactoring crosses a previously untested contract. Do not
generalize an unrelated reader merely because its statements look similar: JSON, for example,
also checks complete token consumption and reports its own syntax errors.

When branches already produce the same result record, a typed local can make the dispatch a
small table followed by one common completion step. Keep branches with different contracts, such
as textual values or Boolean parsing, separate. Preserve the chosen parser, cursor advancement,
and overflow policy; verify each numeric width rather than only the most common integer case.

A shared complete-number conversion check can remove repeated overflow/trailing-text guards from each numeric width,
but must still report overflow first when both conditions hold. Name that contract in the
helper (`requireCompleteNumber`), keep the parse operation visible at each caller, and test the
error precedence through the public conversions before and after factoring.

A large alternative path can also earn one helper when it owns a complete resource lifetime.
Keep acquisition, initialization, callbacks, and cleanup together in that helper, with the choice
between paths visible at the entry point. Preserve when cleanup runs on success, failure, and
early consumer cancellation; moving only the allocation or only the loop obscures that contract.

Check the caller's publication contract before extracting a private helper. Bodies of implicit
operations and inline functions travel to consuming modules; a generated API does not include
file-private helpers. Keep an elementary check in such a published body when factoring it would
introduce an unavailable dependency. Other methods whose compiled implementation stays in the
module can still share the private helper. Do not widen its public API solely to shorten a caller,
and verify a real importer when changing one of these published bodies.
Apply the same check to internal methods: being callable inside the provider does not prove that
a helper declaration is present in the generated API.

For repeated named-token scans, keep the lookup family explicit at the call site. A shared
scanner can consume one exact name and return its index; the caller still maps that index to a
weekday or a month. Preserve delimiter checks, index bases, cursor movement, and consumed-byte
counts. Exercise complete and truncated names as well as optional validation.

## Extract A Decision Without Eager Evaluation

For a scanner with a small ordinary-byte path and a large marker path, advance and `continue`
for ordinary bytes before entering the marker's phases. This can remove an indentation level
without fragmenting the state machine into helpers. Keep cursor advancement on the same paths,
preserve cleanup scopes, and check the final literal, escaped markers, and bounded string views.
Use separate names for the scan cursor, the pending literal's start, and the next argument index.

A loop should expose when it flushes a block, not require its reader to reconstruct a buffer
threshold, a size threshold, and a compression estimate from one nested condition. A private
`shouldFlushBlock` predicate can own that coherent decision even when it has one caller. Keep
it beside the owning implementation and name intermediate quantities, such as `recordBytes`
and `estimatedBytes`, in their actual units.

Preserve the original short-circuit order in the helper: return for an exhausted buffer first,
reject a small block next, and only then compute the estimate. Do not eagerly initialize every
predicate at the top. Keep checks, reads, arithmetic widths, and callbacks on the same paths as
before. For an encoder refactoring, compare representative encoded bytes before and after;
a successful decode alone does not show that its encoding decisions stayed the same.

## Use Comments As Landmarks, Not Filler

In a decoder, `// Validate the directory before allocating entries.` can identify a whole phase
whose purpose otherwise emerges only after reading its checks. Place it above that paragraph,
with a blank line before the comment and none between comment and code. Prefer a blank line
alone when the purpose is already obvious. Do not comment every step or invent phases to obtain
a regular number of lines between comments.

When a helper already says `validateDirectory`, repeating the sentence at the call site adds
little. Keep a comment if it explains why validation must precede allocation. Large decorative
separators and numbered step lists compete with the code and drift when phases move.

## Choose A Formatter Rule Only When Syntax Is Enough

The formatter can normalize spacing, indentation, excess blank lines, and the layout of authored
breaks. It cannot reliably discover business phases, invent names, extract helpers, or decide
which comment would relieve a reader. Preserve those author decisions.

For example, a long unbroken bitwise chain can be laid out by operand automatically. The
default `bitwise-chain-column-limit = 100` applies to chains of at least three `&`, `|`, or `^`
operands, measuring the chain plus line indentation, without call prefixes or trailing comments.
It leaves short masks, compact flag arguments, authored multiline chains, and literal table rows alone. This
is a readability fallback, not a reason to keep a low-level expression that an existing API
would explain better:

```swag
// Before: the reader has to reconstruct the byte order from the shifts.
let word = (cast(u32, bytes[0]) << 24) | (cast(u32, bytes[1]) << 16) |
           (cast(u32, bytes[2]) << 8) | bytes[3]
```

```swag
// After: the helper names assembly; arguments run from high byte to low byte.
let word = Math.make32(bytes[0], bytes[1], bytes[2], bytes[3])
```

Similarly, `Math.byteAt(word, 0)` names extraction of the least significant byte. Check the
range contract before replacing an arbitrary shift with this helper. Keep bit masks and shifts
for non-byte fields and SIMD operations; do not force a scalar byte API onto another domain.
When decoding a narrow unit into a wider working value, perform endian conversion at the encoded
width before widening. Be explicit about the initial byte order: `Math.make16(bytes[1], bytes[0])`
assembles a little-endian baseline. A reader supporting both orders can keep that `u16` for
little-endian input or swap it for big-endian input, then cast to `u32` for scalar comparisons.
By contrast, `Math.make16(bytes[0], bytes[1])` already assembles big-endian input and needs no swap.
Swapping after a cast to `u32` would exchange four bytes instead of two. Keep a boundary test when
the decoded unit decides whether a chunk must retain a complete surrogate pair.
For example, Unicode case mapping uses a low bit to select a member of an upper/lower pair.
Keep that bit operation explicit, and name the pair offset and case offset when their combination
otherwise needs a long explanatory comment. Retain the explanation of the invariant; remove
only narration that the new names make redundant.
Adding or adopting such helpers is a semantic refactoring with focused tests, outside the
strictly visual campaign in `backlog/repo.prompts.md`.

The same mechanical fallback applies to a long chain of conditions: the default
`logical-chain-column-limit = 100` splits at least three operands joined by the same `and` or
`or`, with the same width measurement and preservation rules. It keeps a parenthesized operand
whole and leaves mixed operators at the same depth for an author to review. Do not invent named
Boolean locals merely to shorten such a chain: eager evaluation can lose its short-circuit guards.
Explicit single-line policies still take precedence. A long condition with only two operands may
need authored wrapping or a meaningful predicate; this narrow rule does not decide that.

In a circular scan, a named partner index can expose what the comparison means without hiding the
wraparound rule: calculate `matchIndex = (i + offset) % values.length`, then compare against
`values[matchIndex]`. Keep `offset` visible when it describes the algorithm, such as `1` for the
next item or half the sequence length for its opposite. See the two inverse-captcha examples in
`bin/examples/modules/aoc2017/`.

When a loop counts matching records, `if matches do total += 1` shows the counting rule directly.
Avoid converting the predicate to an integer just to add it to the total; that hides the condition
inside a numeric conversion.

Use `text.startsWith("prefix")` for a literal prefix check instead of repeating one character
comparison per index. The string API already names both the operation and its boundary behavior;
keep direct indexing for checks that are not a prefix.

Calls use a separate `single-line-argument-column-limit` of 100 columns. It breaks an editable,
authored single-line call when the entire source line exceeds the limit, while preserving calls
already laid out across lines. Short calls and their argument order stay as written; literals,
parameter lists, comments, and long expressions outside the argument list are not wrapped by this
rule. Set the option to `0` to disable it. A single argument that is itself too long still needs
an author's judgement about a meaningful break.

```swag
// Before: the call runs far past the ordinary reading width.
let clip = EditCtrl.create(dialog, appStrings().ui_Width, Format.toString("%", capture.width), {80, 15}, flags: .RightAligned)
```

```swag
// After: one argument per line makes the controls and values easy to scan.
let clip = EditCtrl.create(
    dialog,
    appStrings().ui_Width,
    Format.toString("%", capture.width),
    {80, 15},
    flags: .RightAligned
)
```

The default style preserves the authored shape of named functions, including a multiline body
beside an accessor. Explicit `uniform-function-bodies` configuration can still request sibling
compaction. Do not force every accessor to expand or every single statement to collapse.

Alignment is useful only while the reader can connect both sides of the table. The same outlier
rule applies to declarations and trailing comments: an unusually long row keeps its own spacing
instead of moving the whole group's comments. Prefer this to padding short fields out to a distant
literal or shrinking useful names. Keep genuine data rows intact when their horizontal pattern
helps comparison.

Several long rows can form a legitimate width cluster rather than a single outlier. If a table
mixes different semantic families, separate those families with one blank line before formatting.
For example, group vector constants `Zero`, `One`, and `UnitX` together, then put numeric limits
such as `Max` and `Min` in their own paragraph. The comments can align close to each group without
teaching the formatter to guess what the constants mean. Do not split a coherent table solely to
obtain a lower line-width count.
The same grouping applies to enum values: `one-enum-value-per-line` separates values that share
a line while retaining authored blank lines between groups. It does not require a dense enum.

A flat literal can encode a two-dimensional object. When a long convolution kernel is difficult
to inspect, preserve its size and divisor first, then put each row of weights on one source line.
The authored rows expose symmetry and the center coefficient without changing the flat data.
Keep small neighbouring kernels compact when they remain easy to compare; do not expand every
literal just to obtain uniform heights. Verify that the formatter preserves the row boundaries.

For a table of records or test cases, keep one short record per row when the reader compares
inputs with expected results. A newline before the enclosing `]` or `)` does not make the last
record a multiline block: the formatter must preserve the rows instead of joining the entire
table as a header. Keep genuinely compact tables compact; only hug a trailing block when that
last item itself spans lines.

For a flat byte lookup table without semantic row boundaries, use a consistent modest row width
(sixteen byte values is often readable) rather than filling the entire editor width. Compare the
literal sequence before and after; reflow must not change a value, suffix, or order. Existing
semantic rows take precedence over this convenience.

Before changing an automatic rule, inspect representative declarations, guards, closures,
tables, comments, and deliberately unusual compiler fixtures. Verify the intended output and
second-pass stability, then follow `validate-swag-changes` for the real source formatting pass.
Keep semantic refactoring separate from automatic layout: a formatter should not evaluate or
reorder expressions to reach a visual target.
