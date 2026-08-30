#global namespace Parser.Regex
#global internal

using Errors

// What one instruction of a compiled pattern does.
enum InstKind
{
    ByteRange     // Consumes one byte in '[lo, hi]', then continues at 'next'.
    ByteSet       // Consumes one byte belonging to the set 'slot', then continues at 'next'.
    Split         // Continues at 'next', or at 'alt' when that fails; 'next' has priority.
    Save          // Records the current offset in slot 'slot', then continues at 'next'.
    Assert        // Continues at 'next' only where the assertion holds.
    Backref       // Consumes what capture group 'slot' matched, then continues at 'next'.
    Match         // The pattern matched here.
}

// One instruction of a compiled pattern.
//
// The program is a byte machine, not a scalar-value one: a pattern that names scalar values
// compiles to the UTF-8 encodings of those values. Every engine then reads the subject one
// byte at a time, which is what makes a byte-indexed transition table — and the vectorized
// scans that feed it — possible.
struct Inst
{
    kind:      InstKind       // What the instruction does.
    lo:        u8             // ByteRange: first byte of the interval.
    hi:        u8             // ByteRange: last byte of the interval, included.
    assertion: AssertKind     // Assert: which assertion.
    next:      u32            // Where to continue.
    alt:       u32            // Split: the lower-priority branch.
    slot:      u32            // Save: the capture slot. Backref: the capture group.
}

// The bytes one 'ByteSet' instruction accepts, as a bit per byte.
//
// A class such as `\w` is four intervals, and writing it as four byte ranges makes every engine
// that walks branches try them one after another for every byte of the subject. One bit test
// answers the same question.
struct ByteBitmap
{
    words: [4] u64     // One bit per byte value, lowest value in the lowest bit.
}

impl ByteBitmap
{
    #[Swag.Inline]
    mtd add(value: u8)
    {
        .words[value >> 6] |= 1'u64 << (value & 63)
    }

    #[Swag.Inline]
    mtd const contains(value: u8)->bool
    {
        return (.words[value >> 6] & (1'u64 << (value & 63))) != 0
    }
}

// A compiled pattern, in the form every engine reads.
struct Program
{
    insts:           Array'Inst           // The instructions; an index into this is a program counter.
    byteSets:        Array'ByteBitmap     // The sets the 'ByteSet' instructions name.
    start:           u32                  // Entry point of a match anchored at the search offset.
    startUnanchored: u32                  // Entry point that first skips any number of bytes.
    matchPc:         u32                  // The single 'Match' instruction.
    captureCount:    u32                  // Number of capturing groups, not counting the whole match.
    slotCount:       u32                  // Number of capture slots, two per group.
    minLength:       u32                  // Shortest match, in bytes.
    anchoredStart:   bool                 // Whether every match must start at the beginning of the subject.
    hasBackref:      bool                 // Whether a backreference appears, which only the backtracker can run.
    hasAssert:       bool                 // Whether any zero-width assertion appears.
    hasWordAssert:   bool                 // Whether a word boundary appears, which reads the scalar values around a position.
    ignoreCase:      bool                 // Whether the pattern matches without case, which a backreference also obeys.
    reverse:         bool                 // Whether the program matches the subject read backwards.

    byteClass:      [256] u8     // Equivalence class of every byte, for the lazy automaton.
    classFirstByte: [256] u8     // One byte of each class, which stands for all of them.
    byteClassCount: u32          // Number of distinct byte classes.
}

impl Program
{
    // Compiles a pattern tree.
    //
    // The reverse form matches the same language read backwards; it exists so a search can
    // find where a match starts once the forward pass has found where it ends. It carries no
    // capture slots, since nothing reads captures from it.
    func compile(ast: const *Ast, reverse: bool, rootNode = NoNode)->Program fail
    {
        var result: retval

        let entry = rootNode == NoNode ? ast.root : rootNode

        result.reverse      = reverse
        result.captureCount = ast.captureCount
        result.slotCount    = 2 * (ast.captureCount + 1)
        result.hasBackref   = ast.hasBackref
        result.ignoreCase   = ast.ignoreCase

        result.matchPc = result.addInst({kind: .Match})

        var tail = result.matchPc
        if !reverse do
            tail = result.addInst({kind: .Save, slot: 1, next: tail})

        let body = result.emit(ast, entry, tail)

        result.start = body
        if !reverse do
            result.start = result.addInst({kind: .Save, slot: 0, next: body})

        // The unanchored entry prefers entering the pattern over consuming one more byte,
        // which is what makes a search find the leftmost match rather than any match.
        let skip    = result.addInst({kind: .Split, next: result.start})
        let anyByte = result.addInst({kind: .ByteRange, lo: 0, hi: 0xFF, next: skip})
        result.insts[skip].alt = anyByte
        result.startUnanchored = skip

        result.anchoredStart = rootNode == NoNode and ast.startsAnchored()
        result.minLength     = ast.minLength(entry)
        result.computeByteClasses()

        return result
    }

    mtd addInst(inst: Inst)->u32
    {
        .insts.add(inst)
        return cast(u32) .insts.count - 1
    }

    mtd emitByteRange(lo, hi: u8, next: u32)->u32
    {
        return .addInst({kind: .ByteRange, lo: lo, hi: hi, next: next})
    }

    // Emits the automaton for one node, continuing at 'next' once the node has matched.
    //
    // Emission runs backwards, from the end of the pattern towards its start, so every
    // instruction already knows where it continues and nothing has to be patched later. The
    // two repetition forms that need a cycle are the only exception.
    mtd emit(ast: const *Ast, node: u32, next: u32)->u32 fail
    {
        let current = ast.nodes[node]

        switch current.kind
        {
        case .Empty:
            return next

        case .Literal:
            return .emitLiteral(current.value, next)

        case .Class:
            return .emitClass(&ast.classes[current.classIndex], next)

        case .Assert:

            // An assertion keeps its meaning in the reverse program: the reverse engines walk
            // the real subject backwards rather than a reversed copy of it, so a position is
            // the same position in both directions.
            .hasAssert = true
            let kind = current.assertion
            if kind == AssertKind.WordBoundary or kind == AssertKind.NotWordBoundary do
                .hasWordAssert = true
            return .addInst({kind: .Assert, assertion: kind, next: next})

        case .Backref:
            return .addInst({kind: .Backref, slot: current.reference, next: next})

        case .Group:
            let child = ast.kids[current.first]
            if current.capture == 0 or .reverse do
                return .emit(ast, child, next)

            let close = .addInst({kind: .Save, slot: 2 * current.capture + 1, next: next})
            let inner = .emit(ast, child, close)
            return .addInst({kind: .Save, slot: 2 * current.capture, next: inner})

        case .Concat:
            var tail = next
            if .reverse
            {
                for var i = 0'u32; i < current.count; i += 1 do
                    tail = .emit(ast, ast.kids[current.first + i], tail)
            }
            else
            {
                for var i = current.count; i > 0; i -= 1 do
                    tail = .emit(ast, ast.kids[current.first + i - 1], tail)
            }

            return tail

        case .Alternate:

            // The branches are tried in order, so the chain of splits keeps their order.
            var entry = .emit(ast, ast.kids[current.first + current.count - 1], next)
            for var i = current.count - 1; i > 0; i -= 1
            {
                let branch = .emit(ast, ast.kids[current.first + i - 1], next)
                entry = .addInst({kind: .Split, next: branch, alt: entry})
            }

            return entry

        case .Repeat:
            return .emitRepeat(ast, node, next)
        }

        return next
    }

    // Emits one scalar value as the bytes of its UTF-8 encoding.
    mtd emitLiteral(value: rune, next: u32)->u32
    {
        var buffer: [4] u8
        let count = Utf8.encodeRune(buffer, value)

        var pc = next
        if .reverse
        {
            for var i = 0'u32; i < count; i += 1 do
                pc = .emitByteRange(buffer[i], buffer[i], pc)
        }
        else
        {
            for var i = count; i > 0; i -= 1 do
                pc = .emitByteRange(buffer[i - 1], buffer[i - 1], pc)
        }

        return pc
    }

    // Emits one class as the alternation of the byte sequences that encode it.
    //
    // The one-byte sequences — the ASCII part of the class — are not part of that alternation:
    // they become one set instruction, so that reading a byte against them costs one bit test
    // whatever the class looks like.
    mtd emitClass(value: const *RuneClass, next: u32)->u32
    {
        var sequences: Array'ByteSequence
        for &r in value.ranges do
            appendUtf8Sequences(&sequences, r.lo, r.hi)

        if sequences.isEmpty()
        {
            // A class matching nothing: a byte range that no byte satisfies.
            return .addInst({kind: .ByteRange, lo: 1, hi: 0, next: next})
        }

        var single: ByteBitmap
        var singles = 0'u32
        var longer: Array'ByteSequence

        for &seq in sequences
        {
            if seq.count != 1
            {
                longer.add(seq)
                continue
            }

            singles += 1
            for var b = cast(u32) seq.lo[0]; b <= cast(u32) seq.hi[0]; b += 1 do
                single.add(cast(u8) b)
        }

        var entry = NoNode
        if !longer.isEmpty()
        {
            entry = .emitSequence(longer.back(), next)
            for var i = longer.count - 1; i > 0; i -= 1
            {
                let branch = .emitSequence(longer[i - 1], next)
                entry = .addInst({kind: .Split, next: branch, alt: entry})
            }
        }

        if singles == 0 do
            return entry

        // One interval is a byte range, which every engine reads without a table.
        var ascii = NoNode
        if singles == 1 and sequences.count == 1 do
            ascii = .emitSequence(sequences[0], next)
        else
        {
            .byteSets.add(single)
            ascii = .addInst({kind: .ByteSet, slot: cast(u32) .byteSets.count - 1, next: next})
        }

        if entry == NoNode do
            return ascii
        return .addInst({kind: .Split, next: ascii, alt: entry})
    }

    mtd emitSequence(sequence: ByteSequence, next: u32)->u32
    {
        var pc = next
        if .reverse
        {
            for var i = 0'u32; i < sequence.count; i += 1 do
                pc = .emitByteRange(sequence.lo[i], sequence.hi[i], pc)
        }
        else
        {
            for var i = sequence.count; i > 0; i -= 1 do
                pc = .emitByteRange(sequence.lo[i - 1], sequence.hi[i - 1], pc)
        }

        return pc
    }

    // Emits a repetition. The counted forms unroll, which is what keeps the machine free of
    // counters: a program is a graph of positions, and every engine is a walk over it.
    mtd emitRepeat(ast: const *Ast, node: u32, next: u32)->u32 fail
    {
        let current = ast.nodes[node]
        let child   = ast.kids[current.first]
        let greedy  = current.greedy

        if current.minCount == 0 and current.maxCount == RepeatInfinite
        {
            let split = .addInst({kind: .Split})
            let body  = .emit(ast, child, split)
            .setSplit(split, body, next, greedy)
            return split
        }

        if current.maxCount == RepeatInfinite
        {
            // One or more, preceded by the copies the low bound requires.
            let split = .addInst({kind: .Split})
            let body  = .emit(ast, child, split)
            .setSplit(split, body, next, greedy)

            var entry = body
            for var i = 1'u32; i < current.minCount; i += 1 do
                entry = .emit(ast, child, entry)
            return entry
        }

        // A bounded form: the optional copies first, nested so that leaving one leaves them
        // all, then the required ones in front.
        var tail = next
        for var i = current.minCount; i < current.maxCount; i += 1
        {
            let body  = .emit(ast, child, tail)
            let split = .addInst({kind: .Split})
            .setSplit(split, body, next, greedy)
            tail = split
        }

        for var i = 0'u32; i < current.minCount; i += 1 do
            tail = .emit(ast, child, tail)
        return tail
    }

    // Points a split at its two branches, in the order the repetition prefers.
    mtd setSplit(split, taken, skipped: u32, greedy: bool)
    {
        if greedy
        {
            .insts[split].next = taken
            .insts[split].alt  = skipped
        }
        else
        {
            .insts[split].next = skipped
            .insts[split].alt  = taken
        }
    }

    // The byte string every match must begin with, when there is one.
    //
    // Walking the compiled program rather than the pattern finds the prefix whatever spelling
    // produced it. 'complete' says the program holds nothing but that string, and a scan for
    // it is then the whole search.
    mtd const startingLiteral()->{ bytes: Array'u8, complete: bool }
    {
        const LongestUsefulLiteral = 64'u64

        var result: retval
        var pc        = .start
        var sawAssert = false

        for
        {
            let inst = .insts[pc]
            switch inst.kind
            {
            case .Save:
                pc = inst.next

            case .Assert:

                // The literal is still required, but a hit is no longer a whole match on its
                // own: the assertion has to hold too.
                sawAssert = true
                pc        = inst.next

            case .ByteRange:
                if inst.lo != inst.hi do
                    return result
                result.bytes.add(inst.lo)
                if result.bytes.count >= LongestUsefulLiteral do
                    return result
                pc = inst.next

            case .Match:
                result.complete = !sawAssert
                return result

            default:
                return result
            }
        }

        return result
    }

    // Whether every match is a fixed sequence of byte sets, and what those sets are.
    //
    // `(?i)sherlock` is one: eight offsets, each accepting one letter in either case, and
    // nothing else. So is `\d{4}-\d{2}-\d{2}`. A pattern shaped like that needs no automaton
    // at all — checking the bytes against the sets decides a match — which is what turns a scan
    // that stops fifty thousand times into a scan that answers fifty thousand times.
    //
    // The shape is recognized on the compiled program: at every offset the byte reads must all
    // continue at the same place, so that what one offset accepts never constrains another.
    // `ab|cd` fails that test, which is why it is not enough to collect the sets.
    mtd const fixedSetSequence(sets: *Array'ByteSet, maxLength: u32)->bool
    {
        var roots: Array'u32
        roots.add(.start)

        var seen: Array'bool
        seen.resize(.insts.count)

        for var depth = 0'u32; depth <= maxLength; depth += 1
        {
            var reachable: Array'u32
            var reachesMatch = false
            seen.fill(false)

            if !.closeOverKeepingMatch(roots.toSlice(), &reachable, &seen, &reachesMatch) do
                return false

            // The end of the chain: nothing left to read, and a match is what is left.
            if reachesMatch do
                return reachable.isEmpty() and depth > 0

            if reachable.isEmpty() or depth == maxLength do
                return false

            // Every byte read here has to continue at the same place, or one offset would
            // depend on what another accepted.
            let continuation = .insts[reachable[0]].next
            var set: ByteSet
            var added        = 0'u32
            for pc in reachable
            {
                if .insts[pc].next != continuation do
                    return false
                me.addAcceptedBytes(pc, &set, &added)
            }

            sets.add(set)
            roots.clear()
            roots.add(continuation)
        }

        return false
    }

    // The same walk as 'closeOver', but a match is reported rather than refused.
    mtd const closeOverKeepingMatch(roots: const [..] u32, out: *Array'u32, seen: *Array'bool, reachesMatch: *bool)->bool
    {
        var stack: Array'u32
        stack.add(roots)

        while !stack.isEmpty()
        {
            let pc = stack.popBack()
            if seen[pc] do
                continue
            seen[pc] = true

            switch .insts[pc].kind
            {
            case .Split:
                stack.add(.insts[pc].next)
                stack.add(.insts[pc].alt)

            case .Save:
                stack.add(.insts[pc].next)

            case .ByteRange, .ByteSet:
                out.add(pc)

            case .Match:
                reachesMatch[] = true

            default:

                // An assertion or a backreference: the shape is not a plain chain of bytes.
                return false
            }
        }

        return true
    }

    // What every match must hold at each of its first offsets.
    //
    // Depth zero is the set of bytes a match can begin with, depth one what must follow it, and
    // so on. A scan is free to look at any one of those offsets, which is what saves a pattern
    // whose first byte is common but whose third is not.
    //
    // The walk stops as soon as a match can end, or as soon as a backreference appears: past
    // that point there is nothing every match must hold.
    mtd const collectPositionSets(sets: *Array'ByteSet, scores: *Array'u32, counts: *Array'u32, maxDepth: u32)
    {
        var roots: Array'u32
        roots.add(.start)

        var seen: Array'bool
        seen.resize(.insts.count)

        for var depth = 0'u32; depth < maxDepth; depth += 1
        {
            var reachable: Array'u32
            seen.fill(false)
            if !.closeOver(roots.toSlice(), &reachable, &seen) do
                return
            if reachable.isEmpty() do
                return

            var set: ByteSet
            var count = 0'u32
            for pc in reachable do
                me.addAcceptedBytes(pc, &set, &count)

            sets.add(set)
            scores.add(setScore(&set))
            counts.add(count)

            roots.clear()
            for pc in reachable do
                roots.add(.insts[pc].next)
        }
    }

    // Collects the byte reads a set of program counters leads to without consuming anything.
    //
    // Returns false when the walk meets the end of a match or a backreference, which is where
    // the caller must stop: nothing is required of the offsets beyond it.
    mtd const closeOver(roots: const [..] u32, out: *Array'u32, seen: *Array'bool)->bool
    {
        var stack: Array'u32
        stack.add(roots)

        while !stack.isEmpty()
        {
            let pc = stack.popBack()
            if seen[pc] do
                continue
            seen[pc] = true

            switch .insts[pc].kind
            {
            case .Split:
                stack.add(.insts[pc].next)
                stack.add(.insts[pc].alt)

            case .Save, .Assert:
                stack.add(.insts[pc].next)

            case .ByteRange, .ByteSet:
                out.add(pc)

            default:
                return false
            }
        }

        return true
    }

    // Groups the bytes that every instruction treats identically.
    //
    // The lazy automaton indexes its transitions by class rather than by byte, so a pattern
    // over a handful of letters needs a row of five entries instead of one of 256. The
    // assertions take part too: a byte that a word boundary or a line assertion tells apart
    // from its neighbour cannot share its class.
    mtd computeByteClasses()
    {
        var boundary: [257] bool
        boundary[0] = true

        for &inst in .insts
        {
            if inst.kind == InstKind.ByteRange
            {
                boundary[inst.lo]               = true
                boundary[cast(u32) inst.hi + 1] = true
                continue
            }

            if inst.kind != InstKind.ByteSet do
                continue

            // Every byte where the set starts or stops accepting is a boundary, the same way
            // the ends of an interval are.
            for var b = 1'u32; b < 256; b += 1
            {
                if .byteSets[inst.slot].contains(cast(u8) b) != .byteSets[inst.slot].contains(cast(u8) (b - 1)) do
                    boundary[b] = true
            }

            if .byteSets[inst.slot].contains(0) do
                boundary[0] = true
        }

        if .hasWordAssert
        {
            for var b = 1'u32; b < 256; b += 1
            {
                if isWordByte(cast(u8) b) != isWordByte(cast(u8) (b - 1)) do
                    boundary[b] = true
            }
        }

        if .hasAssert
        {
            const NewLineByte = cast(u32) '\n'
            boundary[NewLineByte]     = true
            boundary[NewLineByte + 1] = true
        }

        var current = 0'u8
        for var b = 0'u32; b < 256; b += 1
        {
            if b != 0 and boundary[b]
            {
                current += 1
                .classFirstByte[current] = cast(u8) b
            }

            .byteClass[b] = current
        }

        .byteClassCount = cast(u32) current + 1
    }
}

// Whether the byte-reading instruction at one program counter accepts one byte.
impl Program
{
    #[Swag.Inline]
    mtd const acceptsByte(pc: u32, value: u8)->bool
    {
        if .insts[pc].kind == InstKind.ByteSet do
            return .byteSets[.insts[pc].slot].contains(value)
        return value >= .insts[pc].lo and value <= .insts[pc].hi
    }

    // Adds every byte one instruction accepts to a set, and counts the ones that were not
    // there already.
    //
    // An interval is walked over its own bounds rather than over all two hundred and
    // fifty-six byte values: compiling a pattern asks this once per offset per instruction,
    // and a literal of eight characters was paying two thousand answers for eight bytes.
    mtd const addAcceptedBytes(pc: u32, set: *ByteSet, added: *u32)
    {
        let before = set.members

        if .insts[pc].kind == InstKind.ByteSet
        {
            for var b = 0'u32; b < 256; b += 1
            {
                if .byteSets[.insts[pc].slot].contains(cast(u8) b) do
                    set.add(cast(u8) b)
            }
        }
        else
        {
            for var b = cast(u32) .insts[pc].lo; b <= cast(u32) .insts[pc].hi; b += 1 do
                set.add(cast(u8) b)
        }

        added[] += set.members - before
    }
}

// Whether one byte is a word byte, which is what a word boundary reads on the ASCII range.
#[Swag.Inline]
func isWordByte(value: u8)->bool
{
    return (value >= 'a' and value <= 'z') or
           (value >= 'A' and value <= 'Z') or
           (value >= '0' and value <= '9') or
           value == '_'
}

// Whether one assertion holds at one offset of the subject.
//
// A word boundary reads scalar values, not bytes: the letters outside ASCII are word
// characters, so `\bcat\b` must not match inside a word that begins with one.
func assertionHolds(kind: AssertKind, hay: const [..] u8, pos: u64)->bool
{
    let count = hay.count

    switch kind
    {
    case .StartText: return pos == 0
    case .EndText:   return pos == count
    case .StartLine: return pos == 0 or hay[pos - 1] == '\n'
    case .EndLine:   return pos == count or hay[pos] == '\n'
    }

    var beforeIsWord = false
    if pos > 0
    {
        let before = Utf8.decodeLastRune(Swag.makeSlice(hay.buffer, pos))
        beforeIsWord = Unicode.isWord(before.c)
    }

    var afterIsWord = false
    if pos < count
    {
        let after = Utf8.decodeRune(Swag.makeSlice(hay.buffer + pos, count - pos))
        afterIsWord = Unicode.isWord(after.c)
    }

    if kind == AssertKind.WordBoundary do
        return beforeIsWord != afterIsWord
    return beforeIsWord == afterIsWord
}

// One UTF-8 encoding shape: up to four byte intervals, read in order.
struct ByteSequence
{
    lo:    [4] u8     // First byte accepted at each position.
    hi:    [4] u8     // Last byte accepted at each position.
    count: u32        // Number of byte positions.
}

// Splits a scalar-value interval into the byte-interval sequences that encode exactly it.
//
// This is what makes a byte machine able to match Unicode: `[é-ÿ]` is not a byte interval,
// but it is a small alternation of them. The split is the classic one — cut at every length
// boundary, then at every position where the trailing bytes do not span their whole range.
func appendUtf8Sequences(out: *Array'ByteSequence, lowValue, highValue: rune)
{
    var lo = lowValue
    var hi = highValue

    if lo > hi do
        return

    // Surrogates have no UTF-8 encoding, so no sequence may cover them.
    const SurrogateLow  = 0xD800'rune
    const SurrogateHigh = 0xDFFF'rune
    if lo <= SurrogateHigh and hi >= SurrogateLow
    {
        if lo < SurrogateLow do
            appendUtf8Sequences(out, lo, SurrogateLow - 1)
        if hi > SurrogateHigh do
            appendUtf8Sequences(out, SurrogateHigh + 1, hi)
        return
    }

    // Split where the encoded length changes.
    const Bounds: [4] rune = [0x7F, 0x7FF, 0xFFFF, 0x10FFFF]
    for var i = 0; i < 3; i += 1
    {
        let bound = Bounds[i]
        if lo <= bound and hi > bound
        {
            appendUtf8Sequences(out, lo, bound)
            appendUtf8Sequences(out, bound + 1, hi)
            return
        }
    }

    let length = encodedLength(lo)
    if length == 1
    {
        var seq: ByteSequence
        seq.count = 1
        seq.lo[0] = cast(u8) lo
        seq.hi[0] = cast(u8) hi
        out.add(seq)
        return
    }

    // Split until every trailing byte of the interval spans its whole range, which is what
    // lets one sequence of independent byte intervals describe the whole interval.
    for var i = 1'u32; i < length; i += 1
    {
        let mask = (1'rune << (6 * i)) - 1
        if (lo & ~mask) == (hi & ~mask) do
            continue

        if (lo & mask) != 0
        {
            appendUtf8Sequences(out, lo, lo | mask)
            appendUtf8Sequences(out, (lo | mask) + 1, hi)
            return
        }

        if (hi & mask) != mask
        {
            appendUtf8Sequences(out, lo, (hi & ~mask) - 1)
            appendUtf8Sequences(out, hi & ~mask, hi)
            return
        }
    }

    var seq:                 ByteSequence
    var lowBytes, highBytes: [4] u8
    seq.count = Utf8.encodeRune(lowBytes, lo)
    discard Utf8.encodeRune(highBytes, hi)
    for var i = 0'u32; i < seq.count; i += 1
    {
        seq.lo[i] = lowBytes[i]
        seq.hi[i] = highBytes[i]
    }

    out.add(seq)
}

// Number of bytes the UTF-8 encoding of one scalar value takes.
func encodedLength(value: rune)->u32
{
    if value <= 0x7F do
        return 1
    if value <= 0x7FF do
        return 2
    if value <= 0xFFFF do
        return 3
    return 4
}
