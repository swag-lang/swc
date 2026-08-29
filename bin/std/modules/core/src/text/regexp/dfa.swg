#global namespace Parser.Regex
#global internal

// The state that no match can continue from; its identifier is zero so a cleared transition
// table reads as "dead" rather than as a valid state.
const DeadState = 0'u32

// The answer of a transition that has not been computed yet.
const UnknownState = 0xFFFF_FFFF'u32

// The answer of an automaton that cannot go on: a byte it must not read, or a cache that
// filled up. The caller falls back to the simulation.
const QuitState = 0xFFFF_FFFE'u32

// The offset that means "no match was seen".
const NoOffset = 0xFFFF_FFFF_FFFF_FFFF'u64

// A state remembers what the byte on the side it came from was, because that is what the
// zero-width assertions read.
const FlagIsMatch     = 0x01'u32     // A match ended just before the byte that led here.
const FlagFromStart   = 0x02'u32     // There was no byte on that side: the subject ended there.
const FlagFromWord    = 0x04'u32     // That byte was a word byte.
const FlagFromNewline = 0x08'u32     // That byte was a line feed.
const FlagIsStart     = 0x10'u32     // Nothing of the pattern is matched yet.

// A state identifier carries the two facts the search loop tests on every byte, so that the
// loop reads the transition table and nothing else.
//
// Both are properties of the state, so tagging its identifier costs nothing and saves one
// dependent load per byte of the subject — which is a large part of the cost of a step.
const TagMatch       = 0x8000_0000'u32     // A match ended just before the byte that led here.
const TagStart       = 0x4000_0000'u32     // Nothing of the pattern is matched yet.
const TagMask        = 0xC000_0000'u32     // Both of them.
const StateIndexMask = 0x3FFF_FFFF'u32     // What is left: the index of the state itself.

// How many transitions one automaton may cache: four megabytes of table for the widest
// patterns, and far less for an ordinary one.
const MaxCachedTransitions = 1_000_000'u64

// Hashes the content of a state.
//
// The overflow of the multiplication is the mixing, not a mistake.
#[Swag.Safety(.Overflow, false)]
func hashState(flags: u32, pcs: const [..] u32)->u64
{
    const Offset = 0xCBF2_9CE4_8422_2325'u64
    const Prime  = 0x0000_0100_0000_01B3'u64

    var hash = (Offset ^ cast(u64) flags) * Prime
    for pc in pcs do
        hash = (hash ^ cast(u64) pc) * Prime
    return hash
}

// The lazy deterministic automaton: the engine that reads the subject one byte at a time and
// does nothing else.
//
// Determinizing a pattern ahead of time can cost exponentially many states, so states are
// built while the subject is read and kept in a cache: the first pass over a byte class costs
// a set closure, every later one costs an indexed load. That is what turns a simulation
// walking every alive branch per byte into one table lookup per byte.
//
// The automaton reports where a match ends, never what its groups captured — a determinized
// state has forgotten which branch it came from. A search that needs a span runs it forwards
// for the end, backwards for the start, and only then hands that span to the simulation.
struct Dfa
{
    stateOffset: Array'u64     // State identifier to where its program counters start in 'stateData'.
    stateFlags:  Array'u32     // Flags of each state, read once per byte by the search loops.
    stateData:   Array'u32     // For each state: its count of program counters, then those.
    trans:       Array'u32     // Transitions, 'stride' of them per state.
    hashSlots:   Array'u32     // Open-addressed index of the interned states, holding identifier plus one.
    hashMask:    u64           // Size of that index, minus one.
    stride:      u64           // Transitions per state, rounded up to a power of two.
    strideShift: u64           // The base-two logarithm of that stride.
    maxStates:   u64           // How many states fit in the transition budget.
    startCache:  [32] u32      // Start state of each look-behind context, or 'UnknownState'.
    reverse:     bool          // Whether the automaton walks the subject backwards.
    matchAll:    bool          // Whether a match keeps the lower-priority branches alive.
    quitHigh:    bool          // Whether a byte outside ASCII must stop the automaton.
    exhausted:   bool          // Whether the cache filled up, so the automaton no longer answers.

    stack:      Array'u32     // Closure walk.
    seen:       Array'u32     // Generation at which each program counter was last closed over.
    generation: u32
    closure:    Array'u32     // Program counters reached without consuming a byte.
    stepped:    Array'u32     // Program counters reached by consuming one byte.
    roots:      Array'u32     // The one program counter a start state holds.
}

impl Dfa
{
    // Prepares the automaton for one program, dropping whatever it cached for another.
    //
    // The reverse automaton searches for where a match starts, which is why it keeps every
    // branch alive after a match: the leftmost start is found by the branch that reaches
    // furthest back, not by the one the pattern prefers.
    mtd configure(program: const *Program)
    {
        // A state identifier is stored already multiplied by the stride, and the stride is a
        // power of two: the transition for the byte being read is then one addition away from
        // the identifier, with no multiplication in the chain of dependent steps that the
        // whole search is made of.
        .strideShift = 0
        .stride      = 1
        while .stride < cast(u64) program.byteClassCount + 1
        {
            .stride      *= 2
            .strideShift += 1
        }

        .maxStates = MaxCachedTransitions / .stride
        .reverse   = program.reverse
        .matchAll  = program.reverse
        .quitHigh  = program.hasWordAssert

        .seen.resize(program.insts.count)
        .seen.fill(0)
        .generation = 0

        .reset()
    }

    // Empties the cache, keeping only the dead state.
    mtd reset()
    {
        .stateOffset.clear()
        .stateFlags.clear()
        .stateData.clear()
        .trans.clear()
        .hashSlots.clear()
        .hashSlots.resize(1024)
        .hashSlots.fill(0)
        .hashMask  = .hashSlots.count - 1
        .exhausted = false

        for var i = 0; i < 32; i += 1 do
            .startCache[i] = UnknownState

        // The dead state has to be the first one, so that a zero in the transition table means
        // exactly "nothing can match from here".
        .stepped.clear()
        discard .intern(.stepped.toSlice(), 0)
    }

    //
    // The state cache.
    //

    // Returns the identifier of the state holding those program counters and flags, creating
    // it when it is new.
    mtd intern(pcs: const [..] u32, flags: u32)->u32
    {
        var tags = 0'u32
        if (flags & FlagIsMatch) != 0 do
            tags |= TagMatch
        if (flags & FlagIsStart) != 0 do
            tags |= TagStart

        var slot = hashState(flags, pcs) & .hashMask
        while .hashSlots[slot] != 0
        {
            let candidate = .hashSlots[slot] - 1
            if .sameState(candidate, pcs, flags) do
                return .identifierOf(candidate) | tags
            slot = (slot + 1) & .hashMask
        }

        if .stateOffset.count >= .maxStates
        {
            .exhausted = true
            return QuitState
        }

        let stateId = cast(u32) .stateOffset.count
        .stateOffset.add(.stateData.count)
        .stateFlags.add(flags)
        .stateData.add(cast(u32) @countof(pcs))
        .stateData.add(pcs)

        let base = .trans.count
        .trans.resize(base + .stride)
        for var i = 0'u64; i < .stride; i += 1 do
            .trans[base + i] = UnknownState

        .hashSlots[slot] = stateId + 1
        if (.stateOffset.count * 2) > .hashSlots.count do
            .growIndex()

        return .identifierOf(stateId) | tags
    }

    // The identifier a search carries for one state: its index, multiplied by the stride so
    // that a transition is an addition away.
    mtd const identifierOf(index: u32)->u32 => cast(u32) (cast(u64) index << .strideShift)

    // The index behind an identifier, tags stripped.
    mtd const indexOf(identifier: u32)->u64 => cast(u64) (identifier & StateIndexMask) >> .strideShift

    mtd const sameState(stateId: u32, pcs: const [..] u32, flags: u32)->bool
    {
        if .stateFlags[stateId] != flags do
            return false

        let offset = .stateOffset[stateId]
        if .stateData[offset] != cast(u32) @countof(pcs) do
            return false

        for var i = 0'u64; i < @countof(pcs); i += 1
        {
            if .stateData[offset + 1 + i] != pcs[i] do
                return false
        }

        return true
    }

    mtd growIndex()
    {
        let wanted = .hashSlots.count * 2
        .hashSlots.clear()
        .hashSlots.resize(wanted)
        .hashSlots.fill(0)
        .hashMask = .hashSlots.count - 1

        for var stateId = 0'u64; stateId < .stateOffset.count; stateId += 1
        {
            let offset = .stateOffset[stateId]
            let count  = .stateData[offset]
            let pcs    = @mkslice(cast(const [*] u32) &.stateData[offset + 1], cast(u64) count)

            var slot = hashState(.stateFlags[stateId], pcs) & .hashMask
            while .hashSlots[slot] != 0 do
                slot = (slot + 1) & .hashMask
            .hashSlots[slot] = cast(u32) stateId + 1
        }
    }

    //
    // Transitions.
    //

    // Builds the state the automaton reaches from one state on one byte class.
    //
    // Two things happen at once here. The branches waiting in the state first take every step
    // that consumes nothing — which is where the zero-width assertions are decided, since both
    // the byte behind the position and the byte in front of it are known — and only then does
    // each of them read the byte.
    mtd computeTransition(program: const *Program, stateId: u32, symbol: u64)->u32
    {
        let index  = .indexOf(stateId)
        let offset = .stateOffset[index]
        let flags  = .stateFlags[index]
        let count  = .stateData[offset]

        let atEnd = symbol == .stride - 1
        var byte  = 0'u8
        if !atEnd do
            byte = program.classFirstByte[symbol]

        // The state remembers the side it came from; the byte being read is on the other side,
        // and the two sides swap when the automaton walks backwards.
        let fromStart   = (flags & FlagFromStart) != 0
        let fromWord    = (flags & FlagFromWord) != 0
        let fromNewline = (flags & FlagFromNewline) != 0
        let byteWord    = !atEnd and isWordByte(byte)
        let byteNewline = !atEnd and byte == '\n'

        var previousIsStart, previousIsWord, previousIsNewline: bool
        var nextIsEnd, nextIsWord, nextIsNewline:               bool

        if .reverse
        {
            previousIsStart   = atEnd
            previousIsWord    = byteWord
            previousIsNewline = byteNewline
            nextIsEnd         = fromStart
            nextIsWord        = fromWord
            nextIsNewline     = fromNewline
        }
        else
        {
            previousIsStart   = fromStart
            previousIsWord    = fromWord
            previousIsNewline = fromNewline
            nextIsEnd         = atEnd
            nextIsWord        = byteWord
            nextIsNewline     = byteNewline
        }

        .closure.clear()
        .stack.clear()
        .generation += 1

        for var i = count; i > 0; i -= 1 do
            .stack.add(.stateData[offset + i])

        var isMatch = false
        while !.stack.isEmpty()
        {
            let pc = .stack.popBack()
            if .seen[pc] == .generation do
                continue
            .seen[pc] = .generation

            let inst = program.insts[pc]
            switch inst.kind
            {
            case .Split:
                .stack.add(inst.alt)
                .stack.add(inst.next)

            case .Save:
                .stack.add(inst.next)

            case .Assert:
                var holds = false
                switch inst.assertion
                {
                case .StartText:       holds = previousIsStart
                case .EndText:         holds = nextIsEnd
                case .StartLine:       holds = previousIsStart or previousIsNewline
                case .EndLine:         holds = nextIsEnd or nextIsNewline
                case .WordBoundary:    holds = previousIsWord != nextIsWord
                case .NotWordBoundary: holds = previousIsWord == nextIsWord
                }

                if holds do
                    .stack.add(inst.next)

            case .Match:
                isMatch = true

                // Every branch still waiting is one the pattern likes less than this match, so
                // none of them can take part in the leftmost match any more. Dropping them is
                // also what stops the search: the branch that skips ahead looking for a later
                // start is one of them.
                if !.matchAll do
                    .stack.clear()

            case .ByteRange, .ByteSet:
                .closure.add(pc)

            default:

                // A backreference never reaches an automaton.
                return QuitState
            }
        }

        .stepped.clear()
        if !atEnd
        {
            for pc in .closure
            {
                if program.acceptsByte(pc, byte) do
                    .stepped.add(program.insts[pc].next)
            }
        }

        var newFlags = 0'u32
        if isMatch do
            newFlags |= FlagIsMatch
        if byteWord do
            newFlags |= FlagFromWord
        if byteNewline do
            newFlags |= FlagFromNewline

        // A state holding nothing but the entry point has matched nothing yet, so a search
        // sitting in it may skip ahead to the next offset a match could begin at.
        if !.reverse and .stepped.count == 1 and .stepped[0] == program.startUnanchored do
            newFlags |= FlagIsStart

        return .intern(.stepped.toSlice(), newFlags)
    }

    // The state a forward search starts in, at one offset of the subject.
    mtd startState(program: const *Program, hay: const [..] u8, at: u64, anchored: bool)->u32
    {
        // Every search begins here, so the answer is a table read and the state is built only
        // the first time each look-behind context is seen.
        //
        // A word boundary reads the scalar value before the offset, not the byte, so a search
        // that begins just after a byte outside ASCII has to be refused the same way one that
        // reads such a byte is: what stands there may be a letter, and only the simulation
        // knows.
        var flags = FlagIsStart
        if at == 0 do
            flags |= FlagFromStart
        else
        {
            let previous = hay[at - 1]
            if .quitHigh and previous >= 0x80 do
                return QuitState
            if isWordByte(previous) do
                flags |= FlagFromWord
            if previous == '\n' do
                flags |= FlagFromNewline
        }

        let index  = cast(u64) ((flags >> 1) & 0x0F) | (anchored ? 16'u64 : 0'u64)
        let cached = .startCache[index]
        if cached != UnknownState do
            return cached

        return .createStartState(program, flags, index, anchored)
    }

    // Builds one start state, the first time its look-behind context is met.
    mtd createStartState(program: const *Program, flags: u32, index: u64, anchored: bool)->u32
    {
        .roots.clear()
        .roots.add(anchored ? program.start : program.startUnanchored)

        let stateId = .intern(.roots.toSlice(), flags)
        if stateId != QuitState do
            .startCache[index] = stateId
        return stateId
    }

    // The state a reverse search starts in, at the offset a match ends at.
    mtd startStateReverse(program: const *Program, hay: const [..] u8, at: u64)->u32
    {
        var flags = FlagIsStart
        if at == @countof(hay) do
            flags |= FlagFromStart
        else
        {
            let following = hay[at]
            if .quitHigh and following >= 0x80 do
                return QuitState
            if isWordByte(following) do
                flags |= FlagFromWord
            if following == '\n' do
                flags |= FlagFromNewline
        }

        let index  = cast(u64) ((flags >> 1) & 0x0F) | 16'u64
        let cached = .startCache[index]
        if cached != UnknownState do
            return cached

        return .createStartState(program, flags, index, true)
    }

    //
    // Searching.
    //

    // Finds where the leftmost match ends, reading the subject forwards.
    //
    // 'quit' means the automaton refused the subject — a byte outside ASCII where a word
    // boundary needs the whole scalar value, or a cache that filled up — and the caller must
    // run the simulation instead. It never means "no match".
    mtd searchForward(program: const *Program, prefilter: const *Prefilter, hay: const [..] u8, start, limit: u64, anchored: bool)->{ found: bool, quit: bool, end: u64 }
    {
        var result: retval

        if .exhausted
        {
            result.quit = true
            return result
        }

        var stateId = .startState(program, hay, start, anchored)
        if stateId == QuitState
        {
            result.quit = true
            return result
        }

        // The loop below sees every byte of the subject, so everything it needs is read once
        // into a local: the tables as raw pointers, and the two settings it tests. Everything
        // that happens rarely is a call, to keep this function — and its stack frame — small.
        let usePrefilter = !anchored and prefilter.isEnabled()
        let classes      = cast(const [*] u8) &program.byteClass[0]
        let data         = @dataof(hay)
        let quitHigh     = .quitHigh
        var transitions  = .trans.buffer!
        var lastMatch    = NoOffset
        var pos          = start

        while pos < limit
        {
            let byte = data[pos]
            if quitHigh and byte >= 0x80
            {
                result.quit = true
                return result
            }

            let slot = cast(u64) (stateId & StateIndexMask) + cast(u64) classes[byte]
            var next = transitions[slot]
            if next == UnknownState
            {
                next = .computeTransition(program, stateId, cast(u64) classes[byte])
                if next == QuitState
                {
                    result.quit = true
                    return result
                }

                transitions       = .trans.buffer!
                transitions[slot] = next
            }

            pos += 1

            if (next & TagMask) != 0
            {
                if (next & TagMatch) != 0 do
                    lastMatch = pos - 1

                // Nothing of the pattern is matched here, so the subject may be skipped up to
                // the next offset a match could begin at.
                if usePrefilter and lastMatch == NoOffset and (next & TagStart) != 0
                {
                    let jump = .resync(program, prefilter, hay, pos, limit)
                    if jump.quit
                    {
                        result.quit = true
                        return result
                    }

                    if !jump.found do
                        return forwardResult(lastMatch)

                    pos         = jump.at
                    stateId     = jump.state
                    transitions = .trans.buffer!
                    continue
                }
            }

            if next == DeadState do
                return forwardResult(lastMatch)

            stateId = next
        }

        let last = .transition(program, stateId, .stride - 1)
        if last == QuitState
        {
            result.quit = true
            return result
        }

        if (last & TagMatch) != 0 do
            lastMatch = limit
        return forwardResult(lastMatch)
    }

    // Skips to the next offset a match could begin at, and re-enters the automaton there.
    mtd resync(program: const *Program, prefilter: const *Prefilter, hay: const [..] u8, pos, limit: u64)->{ found: bool, quit: bool, at: u64, state: u32 }
    {
        var result: retval

        let candidate = prefilter.find(hay, pos)
        if candidate >= limit do
            return result

        let state = .startState(program, hay, candidate, false)
        if state == QuitState
        {
            result.quit = true
            return result
        }

        result.found = true
        result.at    = candidate
        result.state = state
        return result
    }

    // Finds where the match that ends at 'end' starts, reading the subject backwards.
    //
    // The search does not stop at the first start it finds: it keeps going until no branch is
    // alive, so what it reports is the earliest start, which is the leftmost match. A start
    // below 'start' belongs to a match the caller has already reported, so the walk stops
    // there.
    mtd searchReverse(program: const *Program, hay: const [..] u8, start, end: u64)->{ found: bool, quit: bool, start: u64 }
    {
        var result: retval

        if .exhausted
        {
            result.quit = true
            return result
        }

        var stateId = .startStateReverse(program, hay, end)
        if stateId == QuitState
        {
            result.quit = true
            return result
        }

        let classes     = cast(const [*] u8) &program.byteClass[0]
        let data        = @dataof(hay)
        let quitHigh    = .quitHigh
        var transitions = .trans.buffer!
        var lastMatch   = NoOffset
        var alive       = true
        var pos         = end

        // A match starting at one offset is only seen by the step that reads the byte before
        // it, so the walk has to take that step for the lowest offset it may report — the
        // search start itself — and only then stop.
        while pos > 0 and pos >= start
        {
            let byte = data[pos - 1]
            if quitHigh and byte >= 0x80
            {
                result.quit = true
                return result
            }

            let symbol = cast(u64) classes[byte]
            let slot   = cast(u64) (stateId & StateIndexMask) + symbol
            var next   = transitions[slot]
            if next == UnknownState
            {
                next = .computeTransition(program, stateId, symbol)
                if next == QuitState
                {
                    result.quit = true
                    return result
                }

                transitions       = .trans.buffer!
                transitions[slot] = next
            }

            if (next & TagMatch) != 0 do
                lastMatch = pos
            if next == DeadState
            {
                alive = false
                break
            }

            stateId = next
            pos     -= 1
        }

        // A match that starts where the subject does is only seen by the step that has no byte
        // left to read.
        if alive and pos == 0 and start == 0
        {
            let last = .transition(program, stateId, .stride - 1)
            if last == QuitState
            {
                result.quit = true
                return result
            }

            if (last & TagMatch) != 0 do
                lastMatch = 0
        }

        result.found = lastMatch != NoOffset
        result.start = lastMatch
        return result
    }

    // Returns where the automaton goes from one state on one byte class, computing it the
    // first time it is asked. The search loops inline this; it is here for the steps that are
    // not on the hot path.
    mtd transition(program: const *Program, stateId: u32, symbol: u64)->u32
    {
        let slot   = cast(u64) (stateId & StateIndexMask) + symbol
        let cached = .trans[slot]
        if cached != UnknownState do
            return cached

        let computed = .computeTransition(program, stateId, symbol)
        if computed == QuitState do
            return QuitState

        .trans[slot] = computed
        return computed
    }
}

// The outcome of a forward search that did not have to give up.
func forwardResult(lastMatch: u64)->{ found: bool, quit: bool, end: u64 }
{
    var result: retval
    result.found = lastMatch != NoOffset
    result.end   = lastMatch
    return result
}
