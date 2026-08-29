#global namespace Parser

using Errors

// One occurrence of a pattern in a subject, as byte offsets into that subject.
public struct Span
{
    start: u64     // Offset of the first byte of the occurrence.
    end:   u64     // Offset just past its last byte.
}

// A compiled regular expression.
//
// A pattern is compiled once and then matched against as many subjects as needed. Compiling
// is the only step that can fail; every match operation answers rather than fails.
//
// ```swag
// var expr = try Parser.RegExp.create(#raw "(\d+)-(\w+)")
// if expr.match("42-answer")
// {
//     @assert(expr.getCapture(1) == "42")
//     @assert(expr.getCapture(2) == "answer")
// }
// ```
//
// Every operation reports what it found in the *last* subject it was given: [[Core.Parser.RegExp.getCapture]]
// and [[Core.Parser.RegExp.captures]] return slices of that subject, and they stay valid only
// as long as it does. A failed match clears them.
//
// The supported syntax is:
//
// | `.`               | any scalar value, line feed included
// | `*` `+` `?`       | zero or more, one or more, zero or one
// | `{n}` `{n,}` `{n,m}` | exactly, at least, or between that many repetitions
// | `*?` `+?` `??` `{n,m}?` | the same, preferring the shortest match
// | `a\|b`             | either side
// | `(...)`           | capturing group
// | `(?:...)`         | group that does not capture
// | `(?<name>...)`    | capturing group with a name, also spelled `(?'name'...)` and `(?P<name>...)`
// | `(?i)` `(?m)` `(?s)` | case-insensitive, multi-line, dot-matches-line-feed, for the rest of the group
// | `(?i:...)`        | the same, for one group only
// | `[abc]` `[a-z]`   | any of those scalar values
// | `[^abc]`          | any scalar value but those
// | `[[:alpha:]]`     | a POSIX class: `alnum`, `alpha`, `ascii`, `blank`, `cntrl`, `digit`, `graph`, `lower`, `print`, `punct`, `space`, `upper`, `word`, `xdigit`
// | `\d` `\w` `\s` `\l` `\u` | digit, word, space, lower-case and upper-case classes; the upper-case spelling of each is its complement
// | `\pL` `\p{Lu}`    | a Unicode property: `L`, `Ll`, `Lu`, `Lt`, `N`, `Nd`, `S`, `Sm`, `Z`; `\P` is its complement
// | `^` `$`           | start and end of the subject, or of a line under `(?m)`
// | `\A` `\z`         | start and end of the subject, whatever the flags
// | `\b` `\B`         | at a word boundary, and anywhere but at one
// | `\n` `\t` `\x41` `\x{1F600}` | one scalar value by escape, by hexadecimal byte, or by hexadecimal code point
// | `\1` to `\9`      | what that capture group matched
#[Swag.Opaque]
public struct RegExp
{
    private
    {
        program:            Regex.Program         // The compiled pattern.
        reverse:            Regex.Program         // The same pattern, to find where a match starts.
        prefilter:          Regex.Prefilter       // The vectorized scan that finds candidate offsets.
        emptyScan:          Regex.Prefilter       // No scan at all, for the searches that must not use one.
        anchorOnCandidates: bool                  // Whether the scan is selective enough to try the pattern at each hit.
        innerScan:          Regex.Prefilter       // The scan for a literal every match must contain.
        innerPrefix:        Regex.Program         // Reverse program of the pattern before that literal.
        innerDfa:           Regex.Dfa             // The automaton that runs it.
        useInner:           bool                  // Whether looking for the inner literal beats looking for a start byte.
        forwardDfa:         Regex.Dfa             // The automaton that finds where a match ends.
        reverseDfa:         Regex.Dfa             // The automaton that finds where it starts.
        vm:                 Regex.PikeVm          // The engine that reports capture groups.
        backtracker:        Regex.Backtracker     // The engine that runs backreferences.
        slots:              Array'u64             // Capture slots of the last match, when the pattern has groups.
        matchStart:         u64                   // Span of the last match. A pattern without capture
        matchEnd:           u64                   // groups needs nothing else, and pays for nothing else.
        captureNames:       Array'String          // Name of each capture group, empty when it has none.
        subject:            string = ""           // Subject of the last match; the captures point into it.
        matched:            bool                  // Whether the last match succeeded.
        automataAnswered:   bool                  // Whether the automata settled the last search on their own.
        compiled:           bool                  // Whether a pattern was compiled.
    }
}

public impl RegExp
{
    // Compiles a pattern and returns the expression.
    //
    // With `ignoreCase`, every literal and every class in the pattern matches both cases;
    // `(?i)` and `(?-i)` change that for part of a pattern.
    func create(expr: string, ignoreCase = false)->RegExp fail
    {
        var result: retval
        result.compile(expr, ignoreCase)
        return result
    }

    // Compiles a pattern into this expression, replacing whatever it held.
    mtd compile(expr: string, ignoreCase = false) fail
    {
        .clear()

        var flags: Regex.Flags
        flags.ignoreCase = ignoreCase

        var ast = Regex.Ast.parse(expr, flags)
        .program      = Regex.Program.compile(&ast, false)
        .reverse      = Regex.Program.compile(&ast, true)
        .prefilter    = Regex.Prefilter.fromProgram(&.program)
        .captureNames = ast.captureNames
        .compiled     = true

        .slots.resize(.program.slotCount)
        .forwardDfa.configure(&.program)
        .reverseDfa.configure(&.reverse)
        .prepareInnerLiteral(&ast)

        // A hit that costs one anchored attempt is only worth it while hits are rare; past
        // that, reading forwards once and backwards once over the whole subject is cheaper.
        const SelectiveScanRate = 50'u32
        .anchorOnCandidates = .prefilter.isEnabled() and
                              !.program.anchoredStart and
                              .prefilter.candidatesPerThousand() <= SelectiveScanRate
    }

    // Releases everything the expression holds and leaves it uncompiled.
    mtd clear()
    {
        .program = Regex.Program{}
        .reverse = Regex.Program{}
        .captureNames.clear()
        .slots.clear()
        .subject  = ""
        .matched  = false
        .compiled = false
    }

    // Releases resources owned by this value.
    mtd opDrop()
    {
        .clear()
    }

    // Number of capturing groups in the pattern, not counting the whole match.
    mtd const captureCount() => .program.captureCount

    //
    // Matching.
    //

    // Returns whether the whole subject matches the pattern.
    //
    // The subject must match from its first byte to its last one: `abc` matches the pattern
    // `abc` but `abcd` does not. Use [[Core.Parser.RegExp.grep]] to look for an occurrence
    // inside a subject.
    mtd match(str: #null string)->bool
    {
        return .search(str orelse "", 0, true, true)
    }

    // Compiles the pattern, then returns whether the whole subject matches it.
    mtd match(expr: string, str: string, ignoreCase = false)->bool fail
    {
        .compile(expr, ignoreCase)
        return .match(str)
    }

    // Returns the longest prefix of the subject that matches the pattern, or `null` when the
    // subject does not begin with an occurrence.
    //
    // The returned string points into `str`.
    mtd partialMatch(str: #null string)->#null string
    {
        if str == null do
            return null

        let subject = str orelse ""
        if !.search(subject, 0, true, false) do
            return null
        return .matchedText()
    }

    // Returns the first occurrence of the pattern in the subject, or `null` when there is none.
    //
    // The returned string points into `str`.
    mtd grep(str: #null string)->#null string
    {
        if str == null do
            return null

        let subject = str orelse ""
        if !.search(subject, 0, false, false) do
            return null
        return .matchedText()
    }

    // Compiles the pattern, then returns its first occurrence in the subject.
    func grep(expr: string, str: #null string)->#null string fail
    {
        var expression = create(expr)
        return expression.grep(str)
    }

    // Returns every occurrence of the pattern in the subject, in order.
    //
    // Occurrences never overlap: each search starts where the previous occurrence ended. An
    // empty occurrence is reported, and the next search then starts one scalar value further,
    // so a pattern that matches the empty string yields one occurrence per position rather
    // than looping. The returned strings point into `str`.
    mtd grepAll(str: #null string)->Array'(string)
    {
        var result: retval

        let subject = str orelse ""
        for &span in .findAll(str)
        {
            let data = @dataof(subject) + span.start
            result.add(@mkstring(data, span.end - span.start))
        }

        return result
    }

    // Compiles the pattern, then returns every occurrence of it in the subject.
    func grepAll(expr: string, str: #null string)->Array'(string) fail
    {
        var expression = create(expr)
        return expression.grepAll(str)
    }

    // Returns where the first occurrence of the pattern is in the subject, from `start`.
    //
    // The offsets are byte offsets into `str`. The capture groups of that occurrence are
    // readable afterwards, like after any other successful match.
    mtd find(str: #null string, start: u64 = 0)->{ found: bool, span: Span }
    {
        var result: retval

        let subject = str orelse ""
        if start > @countof(subject) do
            return result
        if !.search(subject, start, false, false) do
            return result

        result.found = true
        result.span  = .matchedSpan()
        return result
    }

    // Returns where every occurrence of the pattern is in the subject, in order.
    //
    // The rule for empty occurrences is the one [[Core.Parser.RegExp.grepAll]] describes.
    mtd findAll(str: #null string)->Array'Span
    {
        var result: retval

        let subject = str orelse ""
        var at      = .findAllFast(subject, &result)

        while at <= @countof(subject)
        {
            let step = .nextMatch(subject, at)
            if !step.found do
                break
            result.add(step.span)
            at = step.next
        }

        return result
    }

    //
    // Capture groups.
    //

    // Returns what capture group `rank` matched in the last successful match, or an empty
    // string when the group did not take part in it.
    //
    // Group zero is the whole match. The returned string points into the subject of that match.
    mtd getCapture(rank: u32)->string
    {
        let span = .captureSpan(rank)
        if !span.found do
            return ""
        return @mkstring(@dataof(.subject) + span.span.start, span.span.end - span.span.start)
    }

    // Returns what the capture group of that name matched, or an empty string when there is
    // no such group or it did not take part in the match.
    mtd getCapture(name: string)->string
    {
        for var rank = 0'u32; rank < .captureNames.count; rank += 1
        {
            if .captureNames[rank].toString() == name do
                return .getCapture(rank)
        }

        return ""
    }

    // Returns where capture group `rank` matched in the last successful match.
    mtd captureSpan(rank: u32)->{ found: bool, span: Span }
    {
        var result: retval
        if !.matched do
            return result

        // The whole match is always known, whether or not the pattern has capture groups.
        if rank == 0
        {
            result.found      = true
            result.span.start = .matchStart
            result.span.end   = .matchEnd
            return result
        }

        let opening = 2 * cast(u64) rank
        if opening + 1 >= .slots.count do
            return result

        let start = .slots[opening]
        let end   = .slots[opening + 1]
        if start == Regex.NoSlot or end == Regex.NoSlot or end < start do
            return result

        result.found = true
        result.span  = {start, end}
        return result
    }

    // Returns what every capture group that took part in the last match matched, in order.
    //
    // A group that did not take part is left out, so the result is not indexed by group rank.
    mtd captures()->Array'(string)
    {
        var result: retval

        for var rank = 1'u32; rank <= .program.captureCount; rank += 1
        {
            if .captureSpan(rank).found do
                result.add(.getCapture(rank))
        }

        return result
    }

    // Returns what capture group `idx` matched, the same as [[Core.Parser.RegExp.getCapture]].
    mtd opIndex(idx: u64)->string
    {
        return .getCapture(cast(u32) idx)
    }

    //
    // Rewriting.
    //

    // Returns the subject with every occurrence of the pattern replaced.
    //
    // In `replacement`, `$0` to `$9` stand for what that capture group matched, `${name}`
    // for what the group of that name matched, and `$$` for one dollar sign. A group that
    // did not take part in the occurrence contributes nothing.
    mtd replaceAll(str: #null string, replacement: string)->String
    {
        var result: retval

        let subject = str orelse ""
        var at      = 0'u64
        var copied  = 0'u64

        // The replacement is expanded as each occurrence is found, because the group
        // references in it read the capture groups of that occurrence.
        while at <= @countof(subject)
        {
            let step = .nextMatch(subject, at)
            if !step.found do
                break

            result.append(@mkstring(@dataof(subject) + copied, step.span.start - copied))
            .appendReplacement(&result, replacement)
            copied = step.span.end
            at     = step.next
        }

        result.append(@mkstring(@dataof(subject) + copied, @countof(subject) - copied))
        return result
    }

    // Returns the parts of the subject that the pattern separates.
    //
    // An occurrence of the pattern is the separator, so a subject with two occurrences yields
    // three parts, empty ones included. The returned strings point into `str`.
    mtd split(str: #null string)->Array'(string)
    {
        var result: retval

        let subject = str orelse ""
        var at      = 0'u64

        for &span in .findAll(str)
        {
            // An empty separator would only cut the subject into its scalar values.
            if span.end == span.start do
                continue
            result.add(@mkstring(@dataof(subject) + at, span.start - at))
            at = span.end
        }

        result.add(@mkstring(@dataof(subject) + at, @countof(subject) - at))
        return result
    }
}

private impl RegExp
{
    // Sets up the scan for a literal every match must contain, when looking for it stops on
    // fewer offsets than looking for the bytes a match can begin with.
    //
    // It costs a third program — the pattern before that literal, reversed — because a hit
    // says where the middle of a match is, and the start has to be found by reading backwards
    // from there.
    mtd prepareInnerLiteral(ast: *Regex.Ast) fail
    {
        .useInner = false
        if .prefilter.complete or .program.anchoredStart do
            return

        let inner = ast.extractInnerLiteral()
        if !inner.found do
            return

        let scan = Regex.Prefilter.fromLiteral(inner.bytes.toSlice())

        // A hit on the inner literal costs a walk backwards and a second walk forwards, where
        // a hit on a starting byte costs one automaton step; the two are compared with that
        // difference in them.
        if scan.estimatedCost(Regex.InnerCandidateCost) >= .prefilter.estimatedCost(Regex.CandidateCost) do
            return

        .innerScan   = scan
        .innerPrefix = Regex.Program.compile(ast, true, inner.prefixRoot)
        .innerDfa.configure(&.innerPrefix)
        .useInner = true
    }

    // Runs the engines over one subject and keeps what they found.
    //
    // The engines are tried from the fastest to the most general. A pattern that is one
    // literal string never reaches an automaton at all; anything else has its span found by
    // the two automata, and only a pattern with capture groups is then replayed by the
    // simulation over that span alone. The simulation runs over the whole subject only when
    // an automaton refuses it.
    mtd search(subject: string, start: u64, anchored, wholeSubject: bool)->bool
    {
        .matched = false
        .subject = subject

        if !.compiled do
            return false

        let hay   = @mkslice(@dataof(subject), @countof(subject))
        let limit = @countof(subject)

        // Only the backtracker can run a backreference; every other pattern goes to an engine
        // that no subject can make explode.
        if .program.hasBackref
        {
            if !.backtracker.run(&.program, hay, start, limit, anchored, wholeSubject) do
                return false
            .keepSlots(.backtracker.slots.buffer)
            return true
        }

        // An anchored search has one place to look, and the backtracking engine walks it
        // faster than the simulation does — four times faster on a line with capture groups,
        // because it follows one path instead of advancing every branch together. The
        // simulation, which no pattern can make explode, answers the rare one that exhausts
        // the budget given here.
        if anchored or wholeSubject
        {
            const AnchoredBudgetBase = 4096'u64
            const AnchoredBudgetRate = 256'u64

            var budget = AnchoredBudgetBase + AnchoredBudgetRate * limit
            if budget > Regex.BacktrackBudget do
                budget = Regex.BacktrackBudget

            if .backtracker.run(&.program, hay, start, limit, true, wholeSubject, budget)
            {
                .keepSlots(.backtracker.slots.buffer)
                return true
            }

            if !.backtracker.exhausted do
                return false
        }

        if !wholeSubject
        {
            if .searchWithAutomata(hay, start, limit, anchored) do
                return true
            if .automataAnswered do
                return false
        }

        if !.vm.run(&.program, hay, start, limit, anchored, wholeSubject) do
            return false

        .keepSlots(.vm.matchSlots.buffer)
        return true
    }

    // Keeps what a capture engine reported, and takes the span of the whole match out of it.
    mtd keepSlots(source: #null const [*] u64)
    {
        let count = .program.slotCount
        if count < 2 or source == null do
            return

        let destination = .slots.buffer!
        let filled      = source!
        for var s = 0'u64; s < count; s += 1 do
            destination[s] = filled[s]

        .matchStart = destination[0]
        .matchEnd   = destination[1]
        .matched    = true
    }

    // Finds the span of the match with the vectorized scan and the two automata.
    //
    // Returns whether the whole search is settled. When an automaton gives up — a subject byte
    // it may not read, or a state cache that filled up — nothing is settled and the caller
    // falls back to the simulation.
    mtd searchWithAutomata(hay: const [..] u8, start, limit: u64, anchored: bool)->bool
    {
        .automataAnswered = false

        // A pattern that is nothing but a literal string is answered by the scan itself.
        if .prefilter.complete and .program.captureCount == 0 and !anchored
        {
            .automataAnswered = true

            let at = .prefilter.find(hay, start)
            if at >= limit do
                return false

            .matchStart = at
            .matchEnd   = at + .prefilter.spanLength
            .matched    = true
            return true
        }

        if .useInner and !anchored do
            return .searchWithInnerLiteral(hay, start, limit)

        // A scan that names the offsets a match can begin at answers the question the reverse
        // automaton is there for, so the search is anchored at each of them and read forwards
        // only. It is worth it while the scan stops rarely enough that one anchored attempt per
        // hit costs less than the walk backwards it replaces.
        if !anchored and .anchorOnCandidates do
            return .searchFromCandidates(hay, start, limit)

        // A pattern that can only match at the start of the subject is searched there and
        // nowhere else, whatever the caller asked for.
        let anchoredSearch = anchored or .program.anchoredStart

        let forward = .forwardDfa.searchForward(&.program, &.prefilter, hay, start, limit, anchoredSearch)
        if forward.quit do
            return false

        .automataAnswered = true
        if !forward.found do
            return false

        var matchStart = start
        if !anchoredSearch
        {
            let backward = .reverseDfa.searchReverse(&.reverse, hay, start, forward.end)
            if backward.quit
            {
                .automataAnswered = false
                return false
            }

            if !backward.found
            {
                .automataAnswered = false
                return false
            }

            matchStart = backward.start
        }

        return .recordSpan(hay, matchStart, forward.end, limit)
    }

    // Tries the pattern at each offset the scan names, reading forwards only.
    //
    // The offsets come in order, so the first one that matches is the leftmost match, and its
    // start is where the attempt began — nothing has to be read backwards to find it.
    mtd searchFromCandidates(hay: const [..] u8, start, limit: u64)->bool
    {
        var at = start

        while at <= limit
        {
            let candidate = .prefilter.find(hay, at)
            if candidate >= limit
            {
                .automataAnswered = true
                return false
            }

            // A scan that decides its own matches has already answered; only the capture
            // groups are left to read.
            if .prefilter.complete
            {
                .automataAnswered = true
                return .recordSpan(hay, candidate, candidate + .prefilter.spanLength, limit)
            }

            let forward = .forwardDfa.searchForward(&.program, &.emptyScan, hay, candidate, limit, true)
            if forward.quit
            {
                .automataAnswered = false
                return false
            }

            if forward.found
            {
                .automataAnswered = true
                return .recordSpan(hay, candidate, forward.end, limit)
            }

            at = candidate + 1
        }

        .automataAnswered = true
        return false
    }

    // Looks for the literal every match must contain, and works outwards from each hit.
    //
    // A hit is only the middle of a possible match: reading backwards with the reversed
    // prefix gives the earliest offset a match could start at, and the ordinary forward
    // automaton then confirms it and finds the end. A hit that leads nowhere costs the two
    // short walks and the scan moves on.
    mtd searchWithInnerLiteral(hay: const [..] u8, start, limit: u64)->bool
    {
        var scanAt = start

        while scanAt <= limit
        {
            let candidate = .innerScan.find(hay, scanAt)
            if candidate >= limit
            {
                .automataAnswered = true
                return false
            }

            let backward = .innerDfa.searchReverse(&.innerPrefix, hay, start, candidate)
            if backward.quit
            {
                .automataAnswered = false
                return false
            }

            if backward.found
            {
                let forward = .forwardDfa.searchForward(&.program, &.prefilter, hay, backward.start, limit, true)
                if forward.quit
                {
                    .automataAnswered = false
                    return false
                }

                if forward.found
                {
                    .automataAnswered = true
                    return .recordSpan(hay, backward.start, forward.end, limit)
                }
            }

            scanAt = candidate + 1
        }

        .automataAnswered = true
        return false
    }

    // Keeps the span an automaton found, and replays the simulation over it when the pattern
    // has capture groups to report.
    mtd recordSpan(hay: const [..] u8, matchStart, matchEnd, limit: u64)->bool
    {
        if .program.captureCount != 0
        {
            // Over a span this short the backtracking engine is the faster way to read the
            // groups back, because it walks one path instead of every branch at once. It is
            // given a budget proportional to the span, and the simulation — which cannot
            // explode — answers the rare pattern that exhausts it.
            const ShortSpanBudgetBase = 4096'u64
            const ShortSpanBudgetRate = 64'u64

            let span = matchEnd - matchStart
            if span <= ShortSpanBudgetBase
            {
                let budget = ShortSpanBudgetBase + ShortSpanBudgetRate * span
                if .backtracker.run(&.program, hay, matchStart, limit, true, false, budget)
                {
                    .keepSlots(.backtracker.slots.buffer)
                    return true
                }
            }

            if !.vm.run(&.program, hay, matchStart, limit, true, false)
            {
                .automataAnswered = false
                return false
            }

            .keepSlots(.vm.matchSlots.buffer)
            return true
        }

        .matchStart = matchStart
        .matchEnd   = matchEnd
        .matched    = true
        return true
    }

    // Collects the occurrences the two automata can find on their own, and returns where the
    // ordinary search has to take over.
    //
    // Looking for every occurrence of a pattern is the one place where what a search costs
    // before it reads anything is paid over and over: a subject with two million occurrences
    // pays it two million times. This asks the two automata directly, so that a match costs
    // the two searches and nothing around them. Anything unusual — capture groups to fill, a
    // backreference, a scan that answers by itself, an automaton that gives up — is left to
    // the general path, which starts where this one stopped.
    mtd findAllFast(subject: string, out: *Array'Span)->u64
    {
        if !.compiled or .program.hasBackref or .program.captureCount != 0 do
            return 0
        if .prefilter.complete or .anchorOnCandidates or .program.anchoredStart do
            return 0

        .matched = false
        .subject = subject

        let hay   = @mkslice(@dataof(subject), @countof(subject))
        let limit = @countof(subject)

        // Occurrences are collected in batches: appending one at a time would put a container
        // call between every two matches, which on a subject with two million of them is a
        // tenth of the whole search.
        const BatchSize = 64'u64

        // How many offsets in a row may be tried and refused before the loop goes back to
        // reading forwards once and backwards once per match.
        const AnchoredMissBudget = 16'u32

        var batch: [BatchSize] Span
        var held = 0'u64
        var at   = 0'u64
        var quit = false

        var tryAnchored = !.useInner and !.prefilter.isEnabled()
        var misses      = 0'u32

        while at <= limit
        {
            var start = 0'u64
            var end   = 0'u64

            // The two ways to find one occurrence. The automata are asked here rather than
            // through a call, because this is the loop the cost per match is measured in.
            if .useInner
            {
                let step = .innerSpanAt(hay, at, limit)
                if step.quit
                {
                    quit = true
                    break
                }

                if !step.found do
                    break
                start = step.span.start
                end   = step.span.end
            }
            elif tryAnchored
            {
                // With no scan to skip ahead with, trying the pattern at the offset itself is
                // the cheapest thing there is: a match found this way needs nothing read
                // backwards, since it starts where the attempt began. A pattern that matches
                // every few bytes — which is exactly the kind that has no usable scan — then
                // costs one search per match instead of two.
                let endOffset = .forwardDfa.searchAnchoredEnd(&.program, hay, at, limit)
                if endOffset == Regex.QuitOffset
                {
                    quit = true
                    break
                }

                if endOffset == Regex.NoOffset
                {
                    // Nothing here. Past a few offsets in a row, this is the wrong way to look
                    // and reading forwards once over the rest of the subject is cheaper.
                    misses += 1
                    if misses > AnchoredMissBudget do
                        tryAnchored = false

                    if at >= limit do
                        break

                    // One byte, not one scalar value: a pattern that matches the empty string
                    // matches it at every offset, including inside the encoding of a scalar
                    // value, and an unanchored search would find it there.
                    at += 1
                    continue
                }

                misses = 0
                start  = at
                end    = endOffset
            }
            else
            {
                let forward = .forwardDfa.searchForward(&.program, &.prefilter, hay, at, limit, false)
                if forward.quit
                {
                    quit = true
                    break
                }

                if !forward.found do
                    break

                let backward = .reverseDfa.searchReverse(&.reverse, hay, at, forward.end)
                if backward.quit or !backward.found
                {
                    quit = true
                    break
                }

                start = backward.start
                end   = forward.end
            }

            batch[held].start = start
            batch[held].end   = end
            held              += 1
            if held == BatchSize
            {
                out.add(@mkslice(cast(const [*] Span) &batch[0], held))
                held = 0
            }

            .matchStart = start
            .matchEnd   = end
            .matched    = true

            if end > start
            {
                at = end
                continue
            }

            // An empty occurrence must not be found again at the same place, and the next
            // offset is the next scalar value rather than the next byte.
            at = end + 1
            while at < limit and (subject[at] & 0xC0) == 0x80 do
                at += 1
        }

        if held != 0 do
            out.add(@mkslice(cast(const [*] Span) &batch[0], held))
        return quit ? at : limit + 1
    }

    // One occurrence, found by looking for the literal every match contains and working
    // outwards from each hit.
    mtd innerSpanAt(hay: const [..] u8, at, limit: u64)->{ found: bool, quit: bool, span: Span }
    {
        var result: retval
        var scanAt = at

        while scanAt <= limit
        {
            let candidate = .innerScan.find(hay, scanAt)
            if candidate >= limit do
                return result

            let backward = .innerDfa.searchReverse(&.innerPrefix, hay, at, candidate)
            if backward.quit
            {
                result.quit = true
                return result
            }

            if backward.found
            {
                let forward = .forwardDfa.searchForward(&.program, &.emptyScan, hay, backward.start, limit, true)
                if forward.quit
                {
                    result.quit = true
                    return result
                }

                if forward.found
                {
                    result.found      = true
                    result.span.start = backward.start
                    result.span.end   = forward.end
                    return result
                }
            }

            scanAt = candidate + 1
        }

        return result
    }

    // Finds the occurrence at or after 'at', and says where the search for the next one
    // resumes.
    //
    // An empty occurrence must not be found again where it was just found, and the offset it
    // resumes at is the next scalar value rather than the next byte: a match never starts
    // inside the encoding of one.
    mtd nextMatch(subject: string, at: u64)->{ found: bool, span: Span, next: u64 }
    {
        var result: retval

        if !.search(subject, at, false, false) do
            return result

        result.found = true
        result.span  = .matchedSpan()

        if result.span.end > result.span.start
        {
            result.next = result.span.end
            return result
        }

        result.next = result.span.end + 1
        while result.next < @countof(subject) and (subject[result.next] & 0xC0) == 0x80 do
            result.next += 1
        return result
    }

    // The span of the whole match.
    mtd const matchedSpan()->Span
    {
        var result: retval
        result.start = .matchStart
        result.end   = .matchEnd
        return result
    }

    mtd matchedText()->string
    {
        let span = .matchedSpan()
        return @mkstring(@dataof(.subject) + span.start, span.end - span.start)
    }

    // Appends one replacement, expanding the group references it names.
    mtd appendReplacement(dest: *String, replacement: string)
    {
        var i = 0'u64
        while i < @countof(replacement)
        {
            let c = replacement[i]
            if c != '$' or i + 1 >= @countof(replacement)
            {
                dest.append(c)
                i += 1
                continue
            }

            let next = replacement[i + 1]
            if next == '$'
            {
                dest.append('$'u8)
                i += 2
                continue
            }

            if next >= '0' and next <= '9'
            {
                dest.append(.getCapture(cast(u32) (next - '0')))
                i += 2
                continue
            }

            if next == '{'
            {
                var name: String
                var j = i + 2
                while j < @countof(replacement) and replacement[j] != '}'
                {
                    name.append(replacement[j])
                    j += 1
                }

                if j < @countof(replacement)
                {
                    dest.append(.getCapture(name.toString()))
                    i = j + 1
                    continue
                }
            }

            dest.append(c)
            i += 1
        }
    }
}
