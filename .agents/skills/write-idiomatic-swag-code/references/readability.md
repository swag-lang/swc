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

## Extract A Decision Without Eager Evaluation

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
default `bitwise-chain-column-limit = 120` applies to chains of at least three `&`, `|`, or `^`
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
For example, Unicode case mapping uses a low bit to select a member of an upper/lower pair.
Keep that bit operation explicit, and name the pair offset and case offset when their combination
otherwise needs a long explanatory comment. Retain the explanation of the invariant; remove
only narration that the new names make redundant.
Adding or adopting such helpers is a semantic refactoring with focused tests, outside the
strictly visual campaign in `backlog/repo.prompts.md`.

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

Before changing an automatic rule, inspect representative declarations, guards, closures,
tables, comments, and deliberately unusual compiler fixtures. Verify the intended output and
second-pass stability, then follow `validate-swag-changes` for the real source formatting pass.
Keep semantic refactoring separate from automatic layout: a formatter should not evaluate or
reorder expressions to reach a visual target.
