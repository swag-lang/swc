#global namespace Parser.Regex
#global internal

// One entry of the closure walk: either a program counter to visit, or a capture slot to put
// back the way it was once the branch that changed it has been explored.
//
// The two shapes share one small record, and the high bit of the first field says which is
// which. Pushing a program counter is then a single store, which matters: the walk pushes
// several entries for every instruction it passes.
struct ClosureStep
{
    what:  u32     // Program counter to visit, or the slot to restore with 'RestoreStep' set.
    value: u64     // Value to put back in that slot.
}

// Marks a closure step as a slot to restore rather than a program counter to visit.
const RestoreStep = 0x8000_0000'u32

// The working set of one run, as plain pointers into the buffers the simulation owns.
//
// Every buffer is sized before a run starts, so nothing here can move while the run walks the
// subject. That is what lets the inner loops read and write them directly: a container access
// per program counter per byte would cost more than the step it is part of.
struct Frame
{
    insts:     const [*] Inst                 // The program.
    byteSets:  #null const [*] ByteBitmap     // The sets its 'ByteSet' instructions name.
    hay:       const [..] u8                  // The subject, whole, because the assertions read around a position.
    limit:     u64                            // Offset the run may not read past.
    slotCount: u64                            // Capture slots per branch.

    pcs:      [2] [*] u32         // Program counters alive now and next, in priority order.
    slots:    [2] [*] u64         // Their capture slots.
    counts:   [2] u64             // How many branches each list holds.
    gens:     [2] u32             // Generation of each list.
    work:     [*] u64             // Capture slots of the branch being explored.
    visited:  [*] u32             // Generation at which each program counter last joined a list.
    stack:    [*] ClosureStep     // The closure walk.
    stackTop: u64                 // How deep that walk is.
    lastGen:  u32                 // Last generation handed out.
}

// The Thompson simulation: every branch of the pattern advances together, one byte at a time.
//
// It is the engine that always answers, whatever the pattern and the subject: it visits every
// program counter at most once per offset, so its cost is the length of the subject times the
// size of the program, and no pattern can make it explode the way a backtracking engine does.
// It is also the only engine that reports capture groups, which is why a search that needs
// them lets the automata find the span and runs this one over that span alone.
struct PikeVm
{
    pcsCurrent:   Array'u32     // Program counters of the two lists.
    pcsNext:      Array'u32
    slotsCurrent: Array'u64     // Their capture slots, 'slotCount' per branch.
    slotsNext:    Array'u64
    visited:      Array'u32     // Generation marks, never cleared between runs.
    stack:        Array'ClosureStep
    work:         Array'u64
    matchSlots:   Array'u64     // Capture slots of the match, once one is found.
    lastGen:      u32           // Last generation handed out, kept across runs.
    sizedInsts:   u64           // Program size the buffers were sized for.
    sizedSlots:   u64           // Slot count they were sized for.
}

impl PikeVm
{
    // Runs the simulation between two offsets and reports whether the pattern matched.
    //
    // An anchored run only tries a match starting exactly at 'start'; an unanchored one keeps
    // starting new branches until one matches, which yields the leftmost match. Once a match
    // is found the branches that outrank it keep running, so what is reported is the leftmost
    // match with the branch order the pattern asks for.
    //
    // A whole-subject run only accepts a match that ends at 'limit'. It cannot be replaced by
    // running the ordinary way and comparing the end: the branch order would settle on a
    // shorter match and never try the longer branch that consumes everything.
    mtd run(program: const *Program, hay: const [..] u8, start, limit: u64, anchored, wholeSubject: bool)->bool
    {
        .resize(program)

        var frame: Frame = undefined
        frame.insts     = program.insts.buffer!
        frame.byteSets  = program.byteSets.buffer
        frame.hay       = hay
        frame.limit     = limit
        frame.slotCount = program.slotCount
        frame.pcs[0]    = .pcsCurrent.buffer!
        frame.pcs[1]    = .pcsNext.buffer!
        frame.slots[0]  = .slotsCurrent.buffer!
        frame.slots[1]  = .slotsNext.buffer!
        frame.work      = .work.buffer!
        frame.visited   = .visited.buffer!
        frame.stack     = .stack.buffer!
        frame.lastGen   = .lastGen

        let matched = frame.run(program, start, anchored, wholeSubject, .matchSlots.buffer!)
        .lastGen = frame.lastGen
        return matched
    }

    // Gives every buffer the size the program needs. A list never holds more branches than the
    // program has instructions, since a program counter joins it at most once.
    mtd resize(program: const *Program)
    {
        let insts = program.insts.count
        let slots = program.slotCount
        if .sizedInsts == insts and .sizedSlots == slots do
            return

        .pcsCurrent.resize(insts)
        .pcsNext.resize(insts)
        .slotsCurrent.resize(insts * slots + slots)
        .slotsNext.resize(insts * slots + slots)
        .visited.resize(insts)
        .visited.fill(0)
        .stack.resize(2 * insts + 8)
        .work.resize(slots)
        .matchSlots.resize(slots)

        .lastGen    = 0
        .sizedInsts = insts
        .sizedSlots = slots
    }
}

impl Frame
{
    mtd run(program: const *Program, start: u64, anchored, wholeSubject: bool, matchSlots: [*] u64)->bool
    {
        // The generations are never reset between runs, so the marks of the previous one are
        // already stale and nothing has to be cleared here.
        if .lastGen >= 0xFFFF_0000
        {
            for var i = 0'u64; i < program.insts.count; i += 1 do
                .visited[i] = 0
            .lastGen = 0
        }

        var current = 0'u32
        .counts[0] = 0
        .counts[1] = 0
        .lastGen   += 1
        .gens[0]   = .lastGen

        var matched = false
        var pos     = start

        for
        {
            let cur  = current
            let next = 1 - current

            // A new branch starts at every offset until something matches, which is what makes
            // the reported match the leftmost one. It joins the list last, because every branch
            // already running started earlier and so outranks it.
            if !matched and (!anchored or pos == start)
            {
                for var s = 0'u64; s < .slotCount; s += 1 do
                    .work[s] = NoSlot
                .addBranch(program.start, pos, cur)
            }

            if .counts[cur] == 0 and (matched or anchored) do
                break

            let readable = pos < .limit
            let byte     = readable ? .hay[pos] : 0'u8

            .counts[next] = 0
            .lastGen      += 1
            .gens[next]   = .lastGen

            let live      = .counts[cur]
            let livePcs   = .pcs[cur]
            let liveSlots = .slots[cur]

            for var i = 0'u64; i < live; i += 1
            {
                // Only the fields the step needs are read: a branch that does not match the
                // byte costs two loads and a comparison.
                let pc = livePcs[i]
                if .insts[pc].kind == InstKind.Match
                {
                    if wholeSubject and pos != .limit do
                        continue

                    matched = true
                    for var s = 0'u64; s < .slotCount; s += 1 do
                        matchSlots[s] = liveSlots[i * .slotCount + s]

                    // Every branch after this one has lower priority, so it can no longer take
                    // part in the match that was just found.
                    break
                }

                if !readable or !.accepts(pc, byte) do
                    continue

                for var s = 0'u64; s < .slotCount; s += 1 do
                    .work[s] = liveSlots[i * .slotCount + s]
                .addBranch(.insts[pc].next, pos + 1, next)
            }

            if pos >= .limit do
                break

            pos     += 1
            current = next
        }

        return matched
    }

    // Whether the byte-reading instruction at one program counter accepts one byte.
    #[Swag.Inline]
    mtd const accepts(pc: u32, value: u8)->bool
    {
        if .insts[pc].kind == InstKind.ByteSet do
            return .byteSets![.insts[pc].slot].contains(value)
        return value >= .insts[pc].lo and value <= .insts[pc].hi
    }

    // Adds one branch to a list, along with everything it reaches without consuming a byte.
    //
    // The walk is explicit rather than recursive, because a program is as deep as the pattern
    // is long and a counted repetition unrolls: a recursive closure would put a thousand
    // frames on the stack for `(ab){1000}`.
    mtd addBranch(pc: u32, pos: u64, list: u32)
    {
        let generation = .gens[list]

        .stack[0].what = pc
        .stackTop      = 1

        while .stackTop != 0
        {
            .stackTop -= 1
            let what = .stack[.stackTop].what

            if (what & RestoreStep) != 0
            {
                .work[what & ~RestoreStep] = .stack[.stackTop].value
                continue
            }

            if .visited[what] == generation do
                continue
            .visited[what] = generation

            switch .insts[what].kind
            {
            case .Split:

                // The lower-priority branch goes in first, so the other one comes out first.
                .stack[.stackTop].what     = .insts[what].alt
                .stack[.stackTop + 1].what = .insts[what].next
                .stackTop                  += 2

            case .Save:
                let slot = .insts[what].slot
                if slot < .slotCount
                {
                    .stack[.stackTop].what  = slot | RestoreStep
                    .stack[.stackTop].value = .work[slot]
                    .stackTop               += 1
                    .work[slot]             = pos
                }

                .stack[.stackTop].what = .insts[what].next
                .stackTop              += 1

            case .Assert:
                if assertionHolds(.insts[what].assertion, .hay, pos)
                {
                    .stack[.stackTop].what = .insts[what].next
                    .stackTop              += 1
                }

            default:

                // A byte to read, or the match: the branch waits here until the next offset.
                let index = .counts[list]
                .pcs[list][index] = what
                let target = index * .slotCount
                for var s = 0'u64; s < .slotCount; s += 1 do
                    .slots[list][target + s] = .work[s]
                .counts[list] = index + 1
            }
        }
    }
}

// The value of a capture slot that was never set.
const NoSlot = 0xFFFF_FFFF_FFFF_FFFF'u64
