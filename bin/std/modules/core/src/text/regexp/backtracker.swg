#global namespace Parser.Regex
#global internal

// The engine for the one construct an automaton cannot express: a backreference.
//
// A backreference makes the language non-regular — what it matches depends on what a group
// matched earlier — so no automaton can decide it, and this engine explores the branches one
// after another instead of all at once. It is used for nothing else, and a step budget keeps
// a pathological pattern from running away with the process.
struct Backtracker
{
    slots:        Array'u64     // Capture slots of the branch being explored.
    matchSlots:   Array'u64     // Capture slots of the match, once one is found.
    budget:       u64           // Steps left before the search gives up.
    limit:        u64           // Offset the search may not read past.
    ignoreCase:   bool          // Whether a backreference compares without case.
    wholeSubject: bool          // Whether only a match ending at 'limit' counts.
}

// How many instruction steps one search may take. A backreference pattern can be exponential
// in the length of the subject, and an interactive caller must still get an answer.
const BacktrackBudget = 20_000_000'u64

impl Backtracker
{
    // Runs the pattern from one offset, or from every offset when the search is unanchored.
    //
    // The budget bounds how far the branches are explored. A caller that has another engine to
    // fall back on passes a small one and treats a refusal as "ask the other engine"; the
    // default is large enough that only a genuinely pathological pattern reaches it.
    mtd run(program: const *Program, hay: const [..] u8, start, limit: u64, anchored, wholeSubject: bool, budget = BacktrackBudget)->bool
    {
        .slots.resize(program.slotCount)
        .matchSlots.resize(program.slotCount)
        .budget       = budget
        .limit        = limit
        .ignoreCase   = program.ignoreCase
        .wholeSubject = wholeSubject

        var pos = start
        for
        {
            .slots.fill(NoSlot)
            if .step(program, hay, program.start, pos)
            {
                for var s = 0'u64; s < program.slotCount; s += 1 do
                    .matchSlots[s] = .slots[s]
                return true
            }

            if anchored or pos >= limit do
                return false

            // The next attempt starts at the next scalar value: a match never starts inside
            // the encoding of one.
            pos += 1
            while pos < limit and (hay[pos] & 0xC0) == 0x80 do
                pos += 1
        }

        return false
    }

    // Explores one branch, and every branch it leads to, in the order the pattern prefers.
    mtd step(program: const *Program, hay: const [..] u8, pc: u32, pos: u64)->bool
    {
        if .budget == 0 do
            return false
        .budget -= 1

        let inst = program.insts[pc]
        switch inst.kind
        {
        case .ByteRange:
            if pos >= .limit do
                return false
            let byte = hay[pos]
            if byte < inst.lo or byte > inst.hi do
                return false
            return .step(program, hay, inst.next, pos + 1)

        case .Split:
            if .step(program, hay, inst.next, pos) do
                return true
            return .step(program, hay, inst.alt, pos)

        case .Save:
            if inst.slot >= program.slotCount do
                return .step(program, hay, inst.next, pos)

            let saved = .slots[inst.slot]
            .slots[inst.slot] = pos
            if .step(program, hay, inst.next, pos) do
                return true
            .slots[inst.slot] = saved
            return false

        case .Assert:
            if !assertionHolds(inst.assertion, hay, pos) do
                return false
            return .step(program, hay, inst.next, pos)

        case .Backref:
            let opening = 2 * cast(u64) inst.slot
            let closing = opening + 1
            if closing >= .slots.count do
                return false

            // A group that did not take part in the match stands for the empty string, so a
            // reference to a group behind a `{0}` or an unused branch still matches.
            if .slots[opening] == NoSlot or .slots[closing] == NoSlot do
                return .step(program, hay, inst.next, pos)

            let referenced = @mkslice(@dataof(hay) + .slots[opening], .slots[closing] - .slots[opening])
            let eaten      = .matchReference(hay, referenced, pos)
            if eaten == NoSlot do
                return false
            return .step(program, hay, inst.next, pos + eaten)

        case .Match:
            return !.wholeSubject or pos == .limit
        }

        return false
    }

    // Returns how many bytes of the subject at 'pos' repeat 'referenced', or 'NoSlot' when
    // it does not appear there.
    mtd matchReference(hay: const [..] u8, referenced: const [..] u8, pos: u64)->u64
    {
        let wanted = @countof(referenced)
        if wanted == 0 do
            return 0

        if !.ignoreCase
        {
            if pos + wanted > .limit do
                return NoSlot
            for var i = 0'u64; i < wanted; i += 1
            {
                if hay[pos + i] != referenced[i] do
                    return NoSlot
            }

            return wanted
        }

        // Case-insensitively, the repeat may take a different number of bytes than the
        // capture did, because two spellings of one letter can have different encodings.
        var here  = pos
        var there = 0'u64
        while there < wanted
        {
            if here >= .limit do
                return NoSlot

            let left  = Utf8.decodeRune(@mkslice(@dataof(hay) + here, .limit - here))
            let right = Utf8.decodeRune(@mkslice(@dataof(referenced) + there, wanted - there))
            if Unicode.toUpper(left.c) != Unicode.toUpper(right.c) do
                return NoSlot

            here  += left.eat
            there += right.eat
        }

        return here - pos
    }
}
