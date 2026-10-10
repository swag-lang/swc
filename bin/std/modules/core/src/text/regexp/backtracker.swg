#global namespace Parser.Regex
#global internal

// The engine for the one construct an automaton cannot express: a backreference.
//
// A backreference makes the language non-regular — what it matches depends on what a group
// matched earlier — so no automaton can decide it, and this engine explores the branches one
// after another instead of all at once. It is used for nothing else, and a step budget keeps
// a pathological pattern from running away with the process.
// One capture slot as it was before a branch changed it.
//
// A branch that fails has to leave the slots the way it found them. Writing them down as they
// change, rather than restoring them on the way out of a call, is what lets the search follow a
// pattern without branches — most of them — without recursing at all.
struct TrailEntry
{
    slot:  u32     // The slot that was written.
    value: u64     // What it held before.
}

// One branch of the pattern that has not been tried yet.
struct ChoicePoint
{
    pc:   u32     // Where that branch starts.
    pos:  u64     // The offset it starts at.
    mark: u64     // How much of the trail to undo before taking it.
}

struct Backtracker
{
    trail:        Array'TrailEntry      // Slots to put back when a branch fails.
    trailTop:     u64                   // How much of it is in use.
    choices:      Array'ChoicePoint     // Branches left to try.
    choicesTop:   u64                   // How many of them there are.
    slots:        Array'u64             // Capture slots of the branch being explored, and of the match once one is found.
    budget:       u64                   // Steps left before the search gives up.
    limit:        u64                   // Offset the search may not read past.
    ignoreCase:   bool                  // Whether a backreference compares without case.
    exhausted:    bool                  // Whether the budget ran out, so a refusal is not an answer.
    wholeSubject: bool                  // Whether only a match ending at 'limit' counts.
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
    mtd run(program: const *Program,
            hay: const [..] u8,
            start: u64,
            limit: u64,
            anchored: bool,
            wholeSubject: bool,
            budget = BacktrackBudget)->bool
    {
        .slots.resize(program.slotCount)
        .budget       = budget
        .exhausted    = false
        .limit        = limit
        .ignoreCase   = program.ignoreCase
        .wholeSubject = wholeSubject

        var pos = start
        for
        {
            .slots.fill(NoSlot)
            .trailTop   = 0
            .choicesTop = 0
            if .step(program, hay, program.start, pos) do
                return true

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

    // Explores the branches of the pattern, in the order it prefers them.
    //
    // Nothing recurses and nothing is pushed through a container. A branch writes the side that
    // is not taken into its stack, with the offset and the point of the trail it has to come
    // back to; a step that fails takes the last one back. That matters because a repetition is
    // a branch per byte: both the call and the container access would be paid once per byte a
    // greedy repetition consumes.
    mtd step(program: const *Program, hay: const [..] u8, startPc: u32, startPos: u64)->bool
    {
        // The program and the capture slots are read once per instruction, so they are read
        // through pointers: an indexed container access is a call, and this loop turns once per
        // instruction of the pattern for every byte of the span.
        let instructions = program.insts.storage()
        let byteSets     = program.byteSets.buffer
        let slots        = .slots.buffer
        let slotCount    = .slots.count
        let data         = hay.buffer

        var pc  = startPc
        var pos = startPos

        for
        {
            if .budget == 0
            {
                .exhausted = true
                return false
            }

            .budget -= 1

            let instruction = instructions + pc
            var failed      = false
            switch instruction.kind
            {
            case .ByteRange:
                if pos >= .limit or data[pos] < instruction.lo or data[pos] > instruction.hi
                {
                    failed = true
                }
                else
                {
                    pc  = instruction.next
                    pos += 1
                }

            case .ByteSet:
                if pos >= .limit or not byteSets![instruction.slot].contains(data[pos])
                {
                    failed = true
                }
                else
                {
                    pc  = instruction.next
                    pos += 1
                }

            case .Save:
                let slot = instruction.slot
                if slot < slotCount
                {
                    if .trailTop >= .trail.count do
                        me.growTrail()

                    let entry = .trail.storage() + .trailTop
                    entry.slot  = slot
                    entry.value = slots![slot]
                    .trailTop   += 1
                    slots[slot] = pos
                }

                pc = instruction.next

            case .Assert:
                if not assertionHolds(instruction.assertion, hay, pos) do
                    failed = true
                else do
                    pc = instruction.next

            case .Split:
                if .choicesTop >= .choices.count do
                    me.growChoices()

                let choice = .choices.storage() + .choicesTop
                choice.pc   = instruction.alt
                choice.pos  = pos
                choice.mark = .trailTop
                .choicesTop += 1
                pc          = instruction.next

            case .Backref:
                let opening = 2 * cast(u64, instruction.slot)
                let closing = opening + 1
                if closing >= slotCount
                {
                    failed = true
                }
                elif slots![opening] == NoSlot or slots[closing] == NoSlot
                {
                    // A group that did not take part in the match stands for the empty string,
                    // so a reference to a group behind a `{0}` or an unused branch still matches.
                    pc = instruction.next
                }
                else
                {
                    let referenced   = Swag.makeSlice(data + slots[opening], slots[closing] - slots[opening])
                    let matchedBytes = .matchReference(hay, referenced, pos)
                    if matchedBytes == NoSlot
                    {
                        failed = true
                    }
                    else
                    {
                        pos += matchedBytes
                        pc  = instruction.next
                    }
                }

            case .Match:
                if not .wholeSubject or pos == .limit do
                    return true
                failed = true
            }

            if failed
            {
                if .choicesTop == 0 do
                    return false

                .choicesTop -= 1
                let choice = .choices.storage() + .choicesTop
                .unwind(choice.mark)
                pc  = choice.pc
                pos = choice.pos
            }
        }

        return false
    }

    // Both stacks grow by doubling, and only when a pattern actually needs the room.
    mtd growTrail()
    {
        .trail.resize(.trail.count == 0 ? 64 : .trail.count * 2)
    }

    mtd growChoices()
    {
        .choices.resize(.choices.count == 0 ? 64 : .choices.count * 2)
    }

    // Puts the capture slots back the way they were before a branch was tried.
    mtd unwind(mark: u64)
    {
        while .trailTop > mark
        {
            .trailTop -= 1
            let entry = .trail.storage() + .trailTop
            .slots[entry.slot] = entry.value
        }
    }

    // Returns how many bytes of the subject at 'pos' repeat 'referenced', or 'NoSlot' when
    // it does not appear there.
    mtd matchReference(hay: const [..] u8, referenced: const [..] u8, pos: u64)->u64
    {
        let referenceBytes = referenced.count
        if referenceBytes == 0 do
            return 0

        if not .ignoreCase
        {
            if pos + referenceBytes > .limit do
                return NoSlot
            for var i = 0'u64; i < referenceBytes; i += 1
            {
                if hay[pos + i] != referenced[i] do
                    return NoSlot
            }

            return referenceBytes
        }

        // Case-insensitively, the repeat may take a different number of bytes than the
        // capture did, because two spellings of one letter can have different encodings.
        var subjectOffset   = pos
        var referenceOffset = 0'u64
        while referenceOffset < referenceBytes
        {
            if subjectOffset >= .limit do
                return NoSlot

            let subjectRune = Utf8.decodeRune(Swag.makeSlice(hay.buffer + subjectOffset,
                                                             .limit - subjectOffset))
            let referenceRune = Utf8.decodeRune(Swag.makeSlice(referenced.buffer + referenceOffset,
                                                               referenceBytes - referenceOffset))
            if Unicode.toUpper(subjectRune.c) != Unicode.toUpper(referenceRune.c) do
                return NoSlot

            subjectOffset   += subjectRune.eat
            referenceOffset += referenceRune.eat
        }

        return subjectOffset - pos
    }
}
