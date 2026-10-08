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
    insts:     const [*] Inst            // The program.
    byteSets:  const [*] ByteBitmap?     // The sets its 'ByteSet' instructions name.
    hay:       const [..] u8             // The subject, whole, because the assertions read around a position.
    limit:     u64                       // Offset the run may not read past.
    slotCount: u64                       // Capture slots per branch.

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
// For patterns without backreferences, it also reports capture groups: a search that needs
// them lets the automata find the span and runs this one over that span alone. Patterns with
// backreferences use Backtracker, which records its captures while matching.
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

        with var frame: Frame
        {
            .insts     = program.insts.storage()
            .byteSets  = program.byteSets.buffer
            .hay       = hay
            .limit     = limit
            .slotCount = program.slotCount
            .pcs       = [me.pcsCurrent.storage(), me.pcsNext.storage()]
            .slots     = [me.slotsCurrent.storage(), me.slotsNext.storage()]
            .counts    = [0'u64, 0]
            .gens      = [0'u32, 0]
            .work      = me.work.storage()
            .visited   = me.visited.storage()
            .stack     = me.stack.storage()
            .stackTop  = 0
            .lastGen   = me.lastGen
        }

        let matched = frame.run(program, start, anchored, wholeSubject, .matchSlots.storage())
        .lastGen = frame.lastGen
        return matched
    }

    // Gives every buffer the size the program needs. A list never holds more branches than the
    // program has instructions, since a program counter joins it at most once.
    mtd resize(program: const *Program)
    {
        let instructionCount = program.insts.count
        let slotsPerBranch   = program.slotCount
        if .sizedInsts == instructionCount and .sizedSlots == slotsPerBranch do
            return

        .pcsCurrent.resize(instructionCount)
        .pcsNext.resize(instructionCount)
        .slotsCurrent.resize(instructionCount * slotsPerBranch + slotsPerBranch)
        .slotsNext.resize(instructionCount * slotsPerBranch + slotsPerBranch)
        .visited.resize(instructionCount)
        .visited.fill(0)
        .stack.resize(2 * instructionCount + 8)
        .work.resize(slotsPerBranch)
        .matchSlots.resize(slotsPerBranch)

        .lastGen    = 0
        .sizedInsts = instructionCount
        .sizedSlots = slotsPerBranch
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
            let currentList = current
            let nextList    = 1 - current

            // A new branch starts at every offset until something matches, which is what makes
            // the reported match the leftmost one. It joins the list last, because every branch
            // already running started earlier and so outranks it.
            if not matched and (not anchored or pos == start)
            {
                for var s = 0'u64; s < .slotCount; s += 1 do
                    .work[s] = NoSlot
                .addBranch(program.start, pos, currentList)
            }

            if .counts[currentList] == 0 and (matched or anchored) do
                break

            let readable = pos < .limit
            let byte     = readable ? .hay[pos] : 0'u8

            .counts[nextList] = 0
            .lastGen          += 1
            .gens[nextList]   = .lastGen

            let liveCount = .counts[currentList]
            let livePcs   = .pcs[currentList]
            let liveSlots = .slots[currentList]

            for var i = 0'u64; i < liveCount; i += 1
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

                if not readable or not .accepts(pc, byte) do
                    continue

                for var s = 0'u64; s < .slotCount; s += 1 do
                    .work[s] = liveSlots[i * .slotCount + s]
                .addBranch(.insts[pc].next, pos + 1, nextList)
            }

            if pos >= .limit do
                break

            pos     += 1
            current = nextList
        }

        return matched
    }

    // Whether the byte-reading instruction at one program counter accepts one byte.
    #[Swag.Inline]
    mtd const accepts(pc: u32, value: u8)->bool
    {
        let instruction = .insts + pc
        if instruction.kind == InstKind.ByteSet do
            return .byteSets![instruction.slot].contains(value)
        return value >= instruction.lo and value <= instruction.hi
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
            let stepCode = .stack[.stackTop].what

            if (stepCode & RestoreStep) != 0
            {
                .work[stepCode & ~RestoreStep] = .stack[.stackTop].value
                continue
            }

            if .visited[stepCode] == generation do
                continue
            .visited[stepCode] = generation

            let instruction = .insts + stepCode
            switch instruction.kind
            {
            case .Split:

                // The lower-priority branch goes in first, so the other one comes out first.
                .stack[.stackTop].what     = instruction.alt
                .stack[.stackTop + 1].what = instruction.next
                .stackTop += 2

            case .Save:
                let slot = instruction.slot
                if slot < .slotCount
                {
                    .stack[.stackTop].what  = slot | RestoreStep
                    .stack[.stackTop].value = .work[slot]
                    .stackTop               += 1
                    .work[slot]             = pos
                }

                .stack[.stackTop].what = instruction.next
                .stackTop += 1

            case .Assert:
                if assertionHolds(instruction.assertion, .hay, pos)
                {
                    .stack[.stackTop].what = instruction.next
                    .stackTop += 1
                }

            default:

                // A byte to read, or the match: the branch waits here until the next offset.
                let index = .counts[list]
                .pcs[list][index] = stepCode
                let slotOffset = index * .slotCount
                for var s = 0'u64; s < .slotCount; s += 1 do
                    .slots[list][slotOffset + s] = .work[s]
                .counts[list] = index + 1
            }
        }
    }
}

// The value of a capture slot that was never set.
const NoSlot = 0xFFFF_FFFF_FFFF_FFFF'u64
