#global namespace Parser.Regex
#global internal

using Math

// How a prefilter looks for the places a match could begin.
enum PrefilterKind
{
    None         // No prefilter: every offset is a candidate.
    Bytes        // One of up to three bytes sits at a known offset of every match.
    Set          // One of a larger set of bytes sits at a known offset of every match.
    PairSet      // Two such sets, at two known offsets, both of which must hold.
    Literal      // A whole byte string starts every match.
    Sequence     // Every match is one byte set per offset, and nothing else.
}

// Roughly how often each byte appears in a thousand bytes of ordinary text.
//
// The exact numbers do not matter; their order does. Choosing which byte of a pattern to scan
// for, and whether scanning for a set of bytes is worth anything at all, is entirely a question
// of how often the candidate appears — a scan for `e` in English text stops on one byte in ten
// and saves nothing.
const ByteFrequency: [256] u8 = [
    1, 1, 1, 1, 1, 1, 1, 1, 1, 4, 20, 1, 1, 10, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    180, 4, 2, 4, 4, 4, 4, 2, 1, 1, 4, 4, 12, 2, 12, 4,
    8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 4, 4, 4, 4, 4, 4,
    4, 5, 2, 2, 2, 8, 2, 2, 3, 4, 2, 2, 2, 2, 4, 5,
    2, 2, 4, 4, 6, 2, 2, 2, 2, 2, 2, 4, 4, 4, 4, 4,
    4, 65, 12, 23, 31, 100, 18, 15, 45, 59, 2, 5, 32, 20, 57, 61,
    15, 1, 48, 53, 72, 21, 8, 15, 2, 15, 1, 4, 4, 4, 4, 1,
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3,
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3,
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3,
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3,
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3,
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3,
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3,
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3]

// What each way of scanning costs, in nanoseconds per thousand bytes of subject, and what one
// candidate costs the automaton it hands the offset to.
//
// A prefilter is worth having only when the two together come to less than letting the
// automaton read everything, and choosing between two prefilters is the same question: a scan
// that stops ten times less often but reads five times slower is the worse of the two. These
// are the measured orders of magnitude, not precise figures — what they have to get right is
// which of two scans is cheaper.
const ScanCostBytes      = 40'u32       // A scan for up to three bytes: one comparison per vector.
const ScanCostLiteral    = 60'u32       // A scan for a literal: two comparisons per vector.
const ScanCostSet        = 250'u32      // A scan for a byte set: two shuffles and a select per vector.
const ScanCostPair       = 320'u32      // The same, at two offsets at once.
const CandidateCost      = 25'u32       // What one candidate costs: a start state and a few steps.
const ScanCostTwoOffsets = 90'u32       // A scan comparing two offsets of the same match at once.
const SequenceVerifyCost = 20'u32       // What checking one candidate against a fixed shape costs.
const InnerCandidateCost = 80'u32       // What one inner-literal candidate costs: two short walks.
const AutomatonCost      = 3000'u32     // What reading a thousand bytes costs with no scan at all.

// How many offsets of a match are examined when looking for the rarest bytes in it.
const PrefilterDepth = 12'u32

// The longest fixed shape a scan will decide on its own.
const PrefilterSequenceDepth = 40'u32

// A set of bytes, in the shape a byte shuffle can test sixteen at a time.
//
// The entry of a byte's low nibble names the high nibbles that go with it. Sixteen high nibbles
// do not fit in one byte of flags, so the ASCII half and the half above it get one table each.
struct ByteSet
{
    lowHalf:  [16] u8     // For each low nibble, the high nibbles of the ASCII bytes in the set.
    highHalf: [16] u8     // The same, for the bytes outside ASCII.
    members:  u32         // How many bytes are in it.
    weight:   u32         // How often those bytes appear in a thousand bytes of ordinary text.
}

impl ByteSet
{
    // Adds one byte, and keeps what the set is worth up to date.
    //
    // How many bytes a set holds and how often they appear are asked once per offset while a
    // pattern is compiled; counting them as they arrive costs nothing, and counting them
    // afterwards means walking all two hundred and fifty-six values per question.
    #[Swag.Inline]
    mtd add(value: u8)
    {
        if .contains(value) do
            return

        let bit = cast(u8) (1 << ((value >> 4) & 7))
        if value < 0x80 do
            .lowHalf[value & 0x0F] |= bit
        else do
            .highHalf[value & 0x0F] |= bit

        .members += 1
        .weight  += cast(u32) ByteFrequency[value]
    }

    // Whether one byte belongs to the set. This is on the hot path of a scan that decides its
    // own matches, so it is inlined rather than called eight times per candidate.
    #[Swag.Inline]
    mtd const contains(value: u8)->bool
    {
        let bit   = cast(u8) (1 << ((value >> 4) & 7))
        let entry = value < 0x80 ? .lowHalf[value & 0x0F] : .highHalf[value & 0x0F]
        return (entry & bit) != 0
    }
}

// The vectorized scan that skips the parts of a subject where no match can begin.
//
// This is what makes a search fast on a subject that mostly does not match. The automaton
// visits one byte at a time, at best a few bytes per nanosecond; a scan for the rarest byte a
// match must contain reads sixteen bytes per instruction and skips everything between two
// candidates. Nearly all of the difference between a fast search and a slow one on a large
// subject is how much of it never reaches the automaton at all.
struct Prefilter
{
    kind:       PrefilterKind     // How the scan works.
    bytes:      [3] u8            // The bytes to look for, for the small-set form.
    byteCount:  u32               // How many of them there are.
    sets:       [2] ByteSet       // The byte sets to look for, for the two set forms.
    offsets:    [2] u32           // Where in a match those bytes sit.
    sequence:   Array'ByteSet     // Sequence form: what each offset of a match accepts.
    scanAt:     u32               // Sequence form: the offset whose set is rarest.
    scanAt2:    u32               // Sequence form: the second offset scanned, when two pay off.
    bytes2:     [3] u8            // The bytes accepted at that second offset.
    byteCount2: u32               // How many of them there are, zero when only one offset is scanned.
    spanLength: u64               // Length of the match a hit stands for, when the scan decides one.
    literal:    Array'u8          // Literal form: the byte string every match starts with.
    rareLow:    u32               // Literal form: offset of its rarest byte.
    rareHigh:   u32               // Literal form: offset of its second rarest byte.
    complete:   bool              // Whether a hit is a whole match, and not only its start.
}

impl Prefilter
{
    // Derives the fastest scan the pattern allows.
    //
    // The program is read rather than the pattern tree: what a match must contain is a property
    // of the compiled automaton, and reading it there also catches what only appears once the
    // pattern has been compiled.
    func fromProgram(program: const *Program)->Prefilter
    {
        var result: retval

        // A pattern that is nothing but one byte set per offset is decided by the scan itself,
        // which is worth more than any other scan: a candidate costs a handful of byte tests
        // instead of a walk through the automaton.
        var sequence: Array'ByteSet
        if program.fixedSetSequence(&sequence, PrefilterSequenceDepth)
        {
            var rarest    = 0'u32
            var bestScore = 0xFFFF'u32
            var singles   = true

            for var i = 0'u64; i < sequence.count; i += 1
            {
                let score = setScore(&sequence[i])
                if score < bestScore
                {
                    bestScore = score
                    rarest    = cast(u32) i
                }

                if setCount(&sequence[i]) != 1 do
                    singles = false
            }

            // A sequence of single bytes is a literal, and comparing a literal outright beats
            // testing it set by set — except for a lone byte, which is a plain byte scan.
            if !singles
            {
                result.kind       = .Sequence
                result.sequence   = sequence
                result.scanAt     = rarest
                result.complete   = true
                result.spanLength = sequence.count

                // The rarest offset is what the vector loop looks for, and a comparison beats
                // a shuffle when the set is small enough to compare against directly.
                if setCount(&sequence[rarest]) <= 3
                {
                    for var b = 0'u32; b < 256; b += 1
                    {
                        if !sequence[rarest].contains(cast(u8) b) do
                            continue
                        result.bytes[result.byteCount] = cast(u8) b
                        result.byteCount               += 1
                    }

                    result.addSecondScan(&sequence, rarest, bestScore)
                }

                return result
            }

            if sequence.count == 1
            {
                result.kind       = .Bytes
                result.byteCount  = 1
                result.complete   = true
                result.spanLength = 1

                for var b = 0'u32; b < 256; b += 1
                {
                    if sequence[0].contains(cast(u8) b) do
                        result.bytes[0] = cast(u8) b
                }

                return result
            }
        }

        let literal = program.startingLiteral()
        if literal.bytes.count >= 2
        {
            result.kind       = .Literal
            result.literal    = literal.bytes
            result.complete   = literal.complete
            result.spanLength = literal.bytes.count
            result.pickRareBytes()
            return result
        }

        // What every match must hold at each of its first offsets. A pattern whose first byte
        // is common — `(?i)sherlock` begins with `s` or `S` — is usually rare a few bytes in.
        var sets:   Array'ByteSet
        var scores: Array'u32
        var counts: Array'u32
        program.collectPositionSets(&sets, &scores, &counts, PrefilterDepth)
        if sets.isEmpty() do
            return result

        // Every offset is a candidate scan, and so is every pair of offsets; the cheapest of
        // them wins, and none of them wins against reading the subject with the automaton.
        var bestCost   = AutomatonCost
        var bestSingle = NoPosition
        var bestLow    = NoPosition
        var bestHigh   = NoPosition

        for var i = 0'u64; i < sets.count; i += 1
        {
            let scan = counts[i] <= 3 ? ScanCostBytes : ScanCostSet
            let cost = scan + scores[i] * CandidateCost
            if cost < bestCost
            {
                bestCost   = cost
                bestSingle = cast(u32) i
                bestLow    = NoPosition
            }
        }

        // Two offsets tested together stop on the product of their rates, which is what turns
        // a hopeless scan into a good one — at the price of a slower scan.
        for var i = 0'u64; i < sets.count; i += 1
        {
            for var j = i + 1; j < sets.count; j += 1
            {
                var rate = (scores[i] * scores[j]) / 1000
                if rate < 1 do
                    rate = 1

                let cost = ScanCostPair + rate * CandidateCost
                if cost < bestCost
                {
                    bestCost   = cost
                    bestSingle = NoPosition
                    bestLow    = cast(u32) i
                    bestHigh   = cast(u32) j
                }
            }
        }

        if bestLow != NoPosition
        {
            result.kind       = .PairSet
            result.sets[0]    = sets[bestLow]
            result.sets[1]    = sets[bestHigh]
            result.offsets[0] = bestLow
            result.offsets[1] = bestHigh
            return result
        }

        if bestSingle == NoPosition do
            return result

        result.offsets[0] = bestSingle
        if counts[bestSingle] <= 3
        {
            result.kind      = .Bytes
            result.byteCount = counts[bestSingle]

            var written = 0'u32
            for var b = 0'u32; b < 256; b += 1
            {
                if !sets[bestSingle].contains(cast(u8) b) do
                    continue
                result.bytes[written] = cast(u8) b
                written               += 1
            }

            return result
        }

        result.kind    = .Set
        result.sets[0] = sets[bestSingle]
        return result
    }

    // What this scan is expected to cost over a thousand bytes, the work it hands the
    // automaton included.
    mtd const estimatedCost(candidateCost: u32)->u32
    {
        switch .kind
        {
        case .None:     return AutomatonCost
        case .Bytes:    return ScanCostBytes + .candidatesPerThousand() * candidateCost
        case .Literal:  return ScanCostLiteral + .candidatesPerThousand() * candidateCost
        case .Set:      return ScanCostSet + .candidatesPerThousand() * candidateCost
        case .PairSet:  return ScanCostPair + .candidatesPerThousand() * candidateCost
        case .Sequence: return ScanCostSet + .candidatesPerThousand() * candidateCost
        }

        return AutomatonCost
    }

    // Adds a second offset to the scan when testing two of them stops far more often than
    // testing one.
    //
    // A case-insensitive literal is the reason this exists: every offset of `(?i)sherlock`
    // accepts two bytes, and no single one of them is rare — but two of them together are, and
    // comparing two vectors is barely more work than comparing one.
    mtd addSecondScan(sequence: const *Array'ByteSet, rarest: u32, rarestScore: u32)
    {
        var second      = 0'u32
        var secondScore = 0xFFFF'u32

        for var i = 0'u64; i < sequence.count; i += 1
        {
            if cast(u32) i == rarest do
                continue
            if setCount(&sequence[i]) > 3 do
                continue

            let score = setScore(&sequence[i])
            if score < secondScore
            {
                secondScore = score
                second      = cast(u32) i
            }
        }

        if secondScore == 0xFFFF do
            return

        // Two offsets stop on the product of their rates, which is worth the second vector
        // only when the offsets it saves the verification of cost more than reading it.
        var paired = (rarestScore * secondScore) / 1000
        if paired < 1 do
            paired = 1

        let oneOffset  = ScanCostBytes + rarestScore * SequenceVerifyCost
        let twoOffsets = ScanCostTwoOffsets + paired * SequenceVerifyCost
        if twoOffsets >= oneOffset do
            return

        .scanAt2 = second
        for var b = 0'u32; b < 256; b += 1
        {
            if !sequence[second].contains(cast(u8) b) do
                continue
            .bytes2[.byteCount2] = cast(u8) b
            .byteCount2          += 1
        }
    }

    // Builds the scan for one literal string, which is how an inner literal is looked for.
    func fromLiteral(bytes: const [..] u8)->Prefilter
    {
        var result: retval
        if bytes.count == 0 do
            return result

        result.kind = .Literal
        result.literal.add(bytes)
        result.pickRareBytes()
        return result
    }

    // How many offsets out of a thousand the scan is expected to stop on.
    //
    // This is what decides between two possible scans: the one that hands the fewest offsets to
    // the automaton wins, whatever it looks for.
    mtd const candidatesPerThousand()->u32
    {
        switch .kind
        {
        case .None:
            return 1000

        case .Bytes:
            var total = 0'u32
            for var i = 0'u32; i < .byteCount; i += 1 do
                total += cast(u32) ByteFrequency[.bytes[i]]
            return total

        case .Set:
            return setScore(&.sets[0])

        case .PairSet:
            let paired = (setScore(&.sets[0]) * setScore(&.sets[1])) / 1000
            return paired < 1 ? 1 : paired

        case .Sequence:
            return setScore(&.sequence[.scanAt])

        case .Literal:
            let rarest = cast(u32) ByteFrequency[.literal[.rareLow]]
            if .rareHigh == .rareLow do
                return rarest

            let paired = (rarest * cast(u32) ByteFrequency[.literal[.rareHigh]]) / 1000
            return paired < 1 ? 1 : paired
        }

        return 1000
    }

    // Picks the two offsets of the literal whose bytes are rarest, which are the ones worth
    // comparing sixteen at a time.
    mtd pickRareBytes()
    {
        var bestScore = 0xFFFF'u32
        for var i = 0'u32; i < .literal.count; i += 1
        {
            let score = cast(u32) ByteFrequency[.literal[i]]
            if score < bestScore
            {
                bestScore = score
                .rareLow  = i
            }
        }

        .rareHigh = .rareLow
        bestScore = 0xFFFF'u32
        for var i = 0'u32; i < .literal.count; i += 1
        {
            if i == .rareLow do
                continue
            let score = cast(u32) ByteFrequency[.literal[i]]
            if score < bestScore
            {
                bestScore = score
                .rareHigh = i
            }
        }
    }

    mtd const isEnabled() => .kind != PrefilterKind.None

    // Returns the first offset at or after 'at' where a match could begin, or the length of the
    // subject when there is none left.
    mtd const find(hay: const [..] u8, at: u64)->u64
    {
        let count = hay.count

        switch .kind
        {
        case .Bytes:
            let from = at + .offsets[0]
            if from >= count do
                return count
            var hit = count
            if .byteCount == 1 do
                hit = findByte(hay, from, .bytes[0])
            elif .byteCount == 2 do
                hit = findByte2(hay, from, .bytes[0], .bytes[1])
            else do
                hit = findByte3(hay, from, .bytes[0], .bytes[1], .bytes[2])
            return hit >= count ? count : hit - .offsets[0]

        case .Set:
            let from = at + .offsets[0]
            if from >= count do
                return count
            let hit = .findSet(hay, from, 0)
            return hit >= count ? count : hit - .offsets[0]

        case .Sequence:
            return .findSequence(hay, at)

        case .PairSet:
            return .findPair(hay, at)

        case .Literal:
            return .findLiteral(hay, at)
        }

        return at
    }

    // Scans for a fixed shape: one byte set per offset.
    //
    // The rarest offset is looked for sixteen bytes at a time, and a hit is then checked offset
    // by offset. Because the shape is the whole pattern, a check that passes is a match.
    mtd const findSequence(hay: const [..] u8, at: u64)->u64
    {
        let count  = hay.count
        let data   = hay.buffer
        let length = .sequence.count
        if length == 0 or count < length do
            return count

        var pos = at
        while pos + length <= count
        {
            var candidate = count
            if .byteCount2 != 0
            {
                candidate = .findTwoOffsets(hay, pos)
                if candidate >= count do
                    return count
            }
            else
            {
                var hit = count
                if .byteCount == 1 do
                    hit = findByte(hay, pos + .scanAt, .bytes[0])
                elif .byteCount == 2 do
                    hit = findByte2(hay, pos + .scanAt, .bytes[0], .bytes[1])
                elif .byteCount == 3 do
                    hit = findByte3(hay, pos + .scanAt, .bytes[0], .bytes[1], .bytes[2])
                else do
                    hit = .findSet(hay, pos + .scanAt, .scanAt)

                if hit >= count do
                    return count
                if hit < .scanAt do
                    return count
                candidate = hit - .scanAt
            }

            if candidate + length > count do
                return count

            // The sets are read through a pointer: this runs once per offset of the shape for
            // every hit, and an indexed container access is a call.
            let shape   = .sequence.buffer!
            var matched = true
            for var i = 0'u64; i < length; i += 1
            {
                if shape[i].contains(data[candidate + i]) do
                    continue
                matched = false
                break
            }

            if matched do
                return candidate
            pos = candidate + 1
        }

        return count
    }

    // Finds the next offset whose two scanned positions both hold one of their bytes.
    //
    // The two sets are small enough to compare against directly, which is what keeps this
    // nearly as fast as looking for one byte while stopping a hundred times less often.
    mtd const findTwoOffsets(hay: const [..] u8, at: u64)->u64
    {
        let count = hay.count
        let data  = hay.buffer
        let first = .scanAt
        let last  = .scanAt2
        let far   = first > last ? first : last

        let firstA  = Simd.splat(.bytes[0])
        let firstB  = Simd.splat(.byteCount > 1 ? .bytes[1] : .bytes[0])
        let secondA = Simd.splat(.bytes2[0])
        let secondB = Simd.splat(.byteCount2 > 1 ? .bytes2[1] : .bytes2[0])

        var pos = at
        while pos + far + 64 <= count
        {
            let mask = combinedMask(twoOffsetMask(data + pos, first, last, firstA, firstB, secondA, secondB),
                                    twoOffsetMask(data + pos + 16, first, last, firstA, firstB, secondA, secondB),
                                    twoOffsetMask(data + pos + 32, first, last, firstA, firstB, secondA, secondB),
                                    twoOffsetMask(data + pos + 48, first, last, firstA, firstB, secondA, secondB))
            if mask != 0 do
                return pos + Math.trailingZeros(mask)
            pos += 64
        }

        while pos + far + 16 <= count
        {
            let mask = Simd.bitmask(twoOffsetMask(data + pos, first, last, firstA, firstB, secondA, secondB))
            if mask != 0 do
                return pos + Math.trailingZeros(mask)
            pos += 16
        }

        while pos + far < count
        {
            if .matchesScanByte(data[pos + first], &.bytes[0], .byteCount) and .matchesScanByte(data[pos + last], &.bytes2[0], .byteCount2) do
                return pos
            pos += 1
        }

        return count
    }

    #[Swag.Inline]
    mtd const matchesScanByte(value: u8, wanted: const [*] u8, count: u32)->bool
    {
        for var i = 0'u32; i < count; i += 1
        {
            if value == wanted[i] do
                return true
        }

        return false
    }

    // Scans for a byte set, sixteen bytes at a time.
    //
    // A byte belongs to the set when the table entry of its low nibble names its high nibble.
    // Two byte shuffles answer that for sixteen bytes at once: one reads the table entry of
    // every low nibble, the other turns every high nibble into the bit that would name it.
    mtd const findSet(hay: const [..] u8, at: u64, which: u64)->u64
    {
        let count = hay.count
        let data  = hay.buffer
        var pos   = at

        let wanted    = .kind == PrefilterKind.Sequence ? &.sequence[which] : &.sets[which]
        let lowTable  = Simd.load(cast(const [*] u8) &wanted.lowHalf[0])
        let highTable = Simd.load(cast(const [*] u8) &wanted.highHalf[0])

        while pos + 16 <= count
        {
            let mask = setMask(Simd.load(data + pos), lowTable, highTable)
            if mask != 0 do
                return pos + Math.trailingZeros(mask)
            pos += 16
        }

        while pos < count
        {
            if wanted.contains(data[pos]) do
                return pos
            pos += 1
        }

        return count
    }

    // Scans for two byte sets at two offsets of the same match.
    //
    // Both have to hold, so the scan stops on the product of their rates rather than on either
    // of them: a pattern whose first byte is common is usually rare a few bytes further in.
    mtd const findPair(hay: const [..] u8, at: u64)->u64
    {
        let count = hay.count
        let data  = hay.buffer
        let first = .offsets[0]
        let last  = .offsets[1]

        let lowTable0  = Simd.load(cast(const [*] u8) &.sets[0].lowHalf[0])
        let highTable0 = Simd.load(cast(const [*] u8) &.sets[0].highHalf[0])
        let lowTable1  = Simd.load(cast(const [*] u8) &.sets[1].lowHalf[0])
        let highTable1 = Simd.load(cast(const [*] u8) &.sets[1].highHalf[0])

        var pos = at
        while pos + last + 16 <= count
        {
            let hits0 = setMask(Simd.load(data + pos + first), lowTable0, highTable0)
            let hits1 = setMask(Simd.load(data + pos + last), lowTable1, highTable1)
            let mask  = hits0 & hits1
            if mask != 0 do
                return pos + Math.trailingZeros(mask)
            pos += 16
        }

        while pos + last < count
        {
            if .sets[0].contains(data[pos + first]) and .sets[1].contains(data[pos + last]) do
                return pos
            pos += 1
        }

        return count
    }

    // Scans for a literal, comparing its two rarest bytes sixteen offsets at a time.
    //
    // Comparing the rarest bytes rather than the first one is what keeps the scan going: in
    // ordinary text `Sherlock` shares its `e` with a tenth of the subject, and its `k` with one
    // byte in two hundred.
    mtd const findLiteral(hay: const [..] u8, at: u64)->u64
    {
        let count  = hay.count
        let data   = hay.buffer
        let wanted = .literal.count
        if wanted == 0 or count < wanted do
            return count

        let needle = cast(const [*] u8) (.literal).buffer!

        // One byte is looked for by the plain byte scan; there is no second byte to pair it
        // with, and comparing the same byte twice would only halve the throughput.
        if wanted == 1 do
            return findByte(hay, at, needle[0])

        let low  = Simd.splat(.literal[.rareLow])
        let high = Simd.splat(.literal[.rareHigh])

        var pos = at
        while pos + wanted + 63 <= count
        {
            let mask = combinedMask((Simd.load(data + pos + .rareLow) == low) & (Simd.load(data + pos + .rareHigh) == high),
                                    (Simd.load(data + pos + 16 + .rareLow) == low) & (Simd.load(data + pos + 16 + .rareHigh) == high),
                                    (Simd.load(data + pos + 32 + .rareLow) == low) & (Simd.load(data + pos + 32 + .rareHigh) == high),
                                    (Simd.load(data + pos + 48 + .rareLow) == low) & (Simd.load(data + pos + 48 + .rareHigh) == high))

            var remaining = mask
            while remaining != 0
            {
                let candidate = pos + Math.trailingZeros(remaining)
                if Memory.compare(data + candidate, needle, wanted) == 0 do
                    return candidate
                remaining &= remaining - 1
            }

            pos += 64
        }

        while pos + wanted + 15 <= count
        {
            let chunkLow  = Simd.load(data + pos + .rareLow)
            let chunkHigh = Simd.load(data + pos + .rareHigh)
            var mask      = Simd.bitmask((chunkLow == low) & (chunkHigh == high))

            while mask != 0
            {
                let candidate = pos + Math.trailingZeros(mask)
                if Memory.compare(data + candidate, needle, wanted) == 0 do
                    return candidate
                mask &= mask - 1
            }

            pos += 16
        }

        while pos + wanted <= count
        {
            if data[pos] == needle[0] and Memory.compare(data + pos, needle, wanted) == 0 do
                return pos
            pos += 1
        }

        return count
    }
}

// The offset that means "no position was chosen".
const NoPosition = 0xFFFF_FFFF'u32

// How many bytes one set holds.
#[Swag.Inline]
func setCount(set: const *ByteSet)->u32 => set.members

// How often the bytes of a set appear in a thousand bytes of ordinary text.
#[Swag.Inline]
func setScore(set: const *ByteSet)->u32 => set.weight

// Marks the bytes of a vector that belong to a set, one bit per byte.
#[Swag.Inline]
func setMask(chunk, lowTable, highTable: Simd.U8x16)->u32
{
    let nibble   = chunk & Simd.splat(0x0F'u8)
    let outside  = (chunk & Simd.splat(0x80'u8)) == Simd.splat(0x80'u8)
    let selected = Simd.select(outside, Simd.shuffle(highTable, nibble), Simd.shuffle(lowTable, nibble))
    let wanted   = Simd.shuffle(cast(Simd.U8x16) [1'u8, 2, 4, 8, 16, 32, 64, 128, 1, 2, 4, 8, 16, 32, 64, 128], (chunk >> 4) & Simd.splat(0x07'u8))
    return ~Simd.bitmask((selected & wanted) == Simd.splat(0'u8)) & 0xFFFF
}

// Marks the offsets of a vector where both scanned positions hold one of their bytes.
#[Swag.Inline]
func twoOffsetMask(data: const [*] u8, first, last: u32, firstA, firstB, secondA, secondB: Simd.U8x16)->Simd.U8x16
{
    let head = Simd.load(data + first)
    let tail = Simd.load(data + last)
    return ((head == firstA) | (head == firstB)) & ((tail == secondA) | (tail == secondB))
}

// Gathers the results of four vector comparisons into one integer, one bit per byte.
//
// Reading sixty-four bytes per turn rather than sixteen is what keeps the scan ahead of the
// memory it reads: the four loads have no dependency on each other, so they overlap, and the
// single test at the end costs the same as one would.
#[Swag.Inline]
func combinedMask(m0, m1, m2, m3: Simd.U8x16)->u64
{
    return cast(u64) Simd.bitmask(m0) |
           (cast(u64) Simd.bitmask(m1) << 16) |
           (cast(u64) Simd.bitmask(m2) << 32) |
           (cast(u64) Simd.bitmask(m3) << 48)
}

// Returns the first offset at or after 'at' holding that byte, or the length of the subject.
func findByte(hay: const [..] u8, at: u64, value: u8)->u64
{
    let count = hay.count
    let data  = hay.buffer
    var pos   = at

    let wanted = Simd.splat(value)
    while pos + 64 <= count
    {
        let mask = combinedMask(Simd.load(data + pos) == wanted,
                                Simd.load(data + pos + 16) == wanted,
                                Simd.load(data + pos + 32) == wanted,
                                Simd.load(data + pos + 48) == wanted)
        if mask != 0 do
            return pos + Math.trailingZeros(mask)
        pos += 64
    }

    while pos + 16 <= count
    {
        let mask = Simd.bitmask(Simd.load(data + pos) == wanted)
        if mask != 0 do
            return pos + Math.trailingZeros(mask)
        pos += 16
    }

    while pos < count
    {
        if data[pos] == value do
            return pos
        pos += 1
    }

    return count
}

// The same, for either of two bytes.
func findByte2(hay: const [..] u8, at: u64, first, second: u8)->u64
{
    let count = hay.count
    let data  = hay.buffer
    var pos   = at

    let wanted1 = Simd.splat(first)
    let wanted2 = Simd.splat(second)
    while pos + 16 <= count
    {
        let chunk = Simd.load(data + pos)
        let mask  = Simd.bitmask((chunk == wanted1) | (chunk == wanted2))
        if mask != 0 do
            return pos + Math.trailingZeros(mask)
        pos += 16
    }

    while pos < count
    {
        let value = data[pos]
        if value == first or value == second do
            return pos
        pos += 1
    }

    return count
}

// The same, for any of three bytes.
func findByte3(hay: const [..] u8, at: u64, first, second, third: u8)->u64
{
    let count = hay.count
    let data  = hay.buffer
    var pos   = at

    let wanted1 = Simd.splat(first)
    let wanted2 = Simd.splat(second)
    let wanted3 = Simd.splat(third)
    while pos + 16 <= count
    {
        let chunk = Simd.load(data + pos)
        let mask  = Simd.bitmask((chunk == wanted1) | (chunk == wanted2) | (chunk == wanted3))
        if mask != 0 do
            return pos + Math.trailingZeros(mask)
        pos += 16
    }

    while pos < count
    {
        let value = data[pos]
        if value == first or value == second or value == third do
            return pos
        pos += 1
    }

    return count
}
