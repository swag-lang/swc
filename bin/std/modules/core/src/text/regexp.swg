#global namespace Parser
#global #[Swag.ExplicitNullability]
using Errors

const RuneAsciiDigit  = cast(rune) 0x8000_0000
const RuneAsciiLetter = cast(rune) 0x8000_0001
const RuneAsciiLower  = cast(rune) 0x8000_0002
const RuneAsciiUpper  = cast(rune) 0x8000_0003
const RuneAsciiSpace  = cast(rune) 0x8000_0004
const RuneAscii       = cast(rune) 0x8000_0005
const RuneOpenParen   = cast(rune) 0x8000_0006
const RuneCloseParen  = cast(rune) 0x8000_0007
const RuneAsciiAlNum  = cast(rune) 0x8000_0008
const RuneAsciiWord   = cast(rune) 0x8000_0009
const RuneAsciiBlank  = cast(rune) 0x8000_000A
const RuneAsciiHexa   = cast(rune) 0x8000_000B
const RuneStart       = cast(rune) 0x8000_000C
const RuneEnd         = cast(rune) 0x8000_000D
const RuneWordSwap    = cast(rune) 0x8000_000E
const RuneGroup1      = cast(rune) 0x8000_0010
const RuneGroup2      = cast(rune) 0x8000_0020
const RuneGroup3      = cast(rune) 0x8000_0030
const RuneGroup4      = cast(rune) 0x8000_0040
const RuneGroup5      = cast(rune) 0x8000_0050
const RuneGroup6      = cast(rune) 0x8000_0060
const RuneGroup7      = cast(rune) 0x8000_0070
const RuneGroup8      = cast(rune) 0x8000_0080
const RuneGroup9      = cast(rune) 0x8000_0090
const RuneWhatever    = cast(rune) 0x8000_00A0
const RuneEmpty       = cast(rune) 0x8000_00A1

const RuneUnicodeLetter      = cast(rune) 0x8001_0006
const RuneUnicodeLetterLower = cast(rune) 0x8001_0007
const RuneUnicodeLetterUpper = cast(rune) 0x8001_0008
const RuneUnicodeNumber      = cast(rune) 0x8001_0009
const RuneUnicodeSymbol      = cast(rune) 0x8001_000a
const RuneUnicodeSymbolMath  = cast(rune) 0x8001_000b

const RuneInvert = cast(rune) 0x0400_0000

struct NfaTable
{
    level:     u32
    nodes:     Array'(#nonull *NfaNode)
}

struct NfaNode
{
    transitions:     HashTable'(rune, Array'(#nonull *NfaNode))
    group:           u32
    terminal:        bool
}

struct DfaNode
{
    table:           Array'(#nonull *NfaNode)
    transitions:     HashTable'(rune, #null *DfaNode)
    rawGroup:        u32
    group:           u32
    terminal:        bool
}

struct RegExpGroup
{
    rank:      u32
    value:     #nonull string
}

struct ActiveGroup
{
    rawGroup:     u32
    rank:         u32
    startIdx:     s32
}

struct DfaState
{
    node:           #null *DfaNode
    parseIdx:       s32
    activeGroups:   Array'ActiveGroup
    groups:         Array'RegExpGroup
}

// Simple regular expression matcher.
// | *                | zero or more
// | ?                | zero or one
// | +                | one or more
// | .                | any rune
// | ^<expr>          | start of buffer
// | <expr>$          | end of buffer
// | a\|b             | a or b
// | [abc]            | match any in list
// | [a-zA-Z]         | match any in range
// | [[:digit:]]      | [0-9]
// | [[:xdigit:]]     | [a-fA-F0-9]
// | [[:alpha:]]      | [a-zA-Z]
// | [[:alnum:]]      | [a-zA-Z0-9]
// | [[:lower:]]      | [a-z]
// | [[:upper:]]      | [A-Z]
// | [[:blank:]]      | whitespace or tab
// | [[:space:]]      | and whitespace character
// | [[:word:]]       | [a-zA-Z0-9_]
// | [[:ascii:]]      | Any ascii character
// | [^<interval>]    | Inverse of <interval>
// | \d               | [[:digit:]]
// | \D               | [^[:digit:]]
// | \l               | [[:lower:]]
// | \L               | [^[:lower:]]
// | \u               | [[:upper:]]
// | \U               | [^[:upper:]]
// | \s               | [[:space:]]
// | \S               | [^[:space:]]
// | \w               | [[:word:]]
// | \W               | [^[:word:]]
// | \b               | start or end of word
// | \pL              | unicode letter
// | \pN              | unicode number
// | \pS              | unicode symbol
// | \p{Ll}           | unicode lower letter
// | \p{Lu}           | unicode upper letter
// | \p{Sm}           | unicode symbol math
// | \1 to \9         | backreference to a capture block
#[Swag.Opaque]
public struct RegExp
{
    nfaNodes:           ArrayPtr'(NfaNode)
    dfaNodes:           ArrayPtr'(DfaNode)
    nfaTables:          ArrayPtr'(NfaTable)
    nfaStack:           Array'(#nonull *NfaTable)
    charSet:            HashSet'rune
    groups:             Array'RegExpGroup
    groupTransform:     Array'u32
    groupParent:        Array'u32
    captureRanks:       Array'u32
    captureRankStack:   Array'u32
    openParen:          Array'u32
    orOpStack:          Array'rune
    orOpLevel:          Array'u32
    preprocessed:       Array'rune
    group:              u32
    captureRankMax:     u32
    captureRankIdx:     u64
    hasStarted:         bool
    wasWord:            bool
    ignoreCase:         bool
    bufStart:           #null const [*] u8
    bufLength:          u64
}

impl RegExp
{
    public mtd opDrop()
    {
        .clear()
    }

    // You can get a capture group value by using the derefence syntax.
    // Returns 'null' if the capture group does not exist
    public mtd opIndex(idx: u64)->#nonull string
    {
        for v in .groups
        {
            if v.rank == idx do
                return v.value
        }

        unreachable
    }

    mtd clearMatch()
    {
        .hasStarted, .wasWord = false
        .group = 0
        .groups.clear()
    }

    mtd resetMatchContext(atBufferStart: bool, prevWasWord = false)
    {
        .clearMatch()
        if !atBufferStart
        {
            .hasStarted = true
            .wasWord    = prevWasWord
        }
    }

    // Clear content
    public mtd clear()
    {
        .nfaNodes.clear()
        .dfaNodes.clear()
        .nfaTables.clear()
        .nfaStack.clear()
        .charSet.clear()
        .groupTransform.clear()
        .groupTransform.add(0)
        .groupParent.clear()
        .groupParent.add(0)
        .captureRanks.clear()
        .captureRankStack.clear()
        .openParen.clear()
        .orOpStack.clear()
        .orOpLevel.clear()
        .preprocessed.clear()
        .captureRankMax = 0
        .captureRankIdx = 0

        .clearMatch()
    }

    mtd addPatternRune(c: rune)
    {
        .preprocessed.add(.ignoreCase ? Unicode.toUpper(c) : c)
    }

    // Creates and return an expression
    public func create(expr: #nonull string, ignoreCase = false)->RegExp throw
    {
        var result: retval
        result.compile(expr, ignoreCase)
        return result
    }

    // Compile the expression
    public mtd compile(expr: #nonull string, ignoreCase = false) throw
    {
        .clear()
        .ignoreCase = ignoreCase
        .preprocess(expr)
        .nfaBuild()
        .dfaBuild()
    }

    // Returns the parsed string associated with a given captured group
    public mtd getCapture(rank: u32)->#nonull string
    {
        for g in .groups
        {
            if g.rank == rank do
                return g.value
        }

        return ""
    }

    // Returns all the captured strings, in order
    public mtd getCaptures()->Array'(#nonull string)
    {
        var result: retval
        for v in .groups do
            result.add(v.value)
        return result
    }

    // Compile and match the expression.
    public mtd match(expr: #nonull string, str: #null string, ignoreCase = false)->bool throw
    {
        .compile(expr, ignoreCase)
        return .match(str)
    }

    // Returns true if 'str' matches the regexp.
    // Should have been compiled before.
    public mtd match(str: #null string)->bool
    {
        .resetMatchContext(true)
        let (ok, ?) = .matchInternal(str orelse "", false)
        return ok
    }

    // Find all the occurences in the string
    public func grepAll(expr: #nonull string, str: #null string)->Array'(#nonull string) throw
    {
        var r = create(expr)
        return r.grepAll(str)
    }

    // Find all the occurences in the string
    public mtd grepAll(str: #null string)->Array'(#nonull string)
    {
        var result: retval

        if str == null do
            return result

        var res              = str orelse ""
        let end              = @dataof(res) + @countof(res)
        var atBufferStart    = true
        var previousWasWord  = false

        for
        {
            let val = .internalGrep(res, atBufferStart, previousWasWord)
            if !val do
                break
            let safeVal = val orelse ""
            result.add(safeVal)

            var newStart = @dataof(safeVal) + @countof(safeVal)
            if @countof(safeVal) == 0
            {
                // Empty matches are valid, but a grep-all must still move forward.
                if newStart == end do
                    break
                let (c, eat) = Utf8.decodeRune(@mkslice(newStart, end - newStart))
                previousWasWord = Unicode.isWord(c)
                newStart += eat
            }
            else do
                previousWasWord = Unicode.isWord(Utf8.lastRune(safeVal))

            atBufferStart = false
            res = @mkstring(newStart, end - newStart)
        }

        return result
    }

    // Find the first occurence in the string
    public func grep(expr: #nonull string, str: #null string)->#null string throw
    {
        var r = create(expr)
        return r.grep(str)
    }

    // Find the first occurence in the string
    public mtd grep(str: #null string)->#null string
    {
        if str == null do
            return null
        return .internalGrep(str orelse "")
    }

    // Try to match the start of the string, and returns the matched value or null.
    public mtd partialMatch(str: #null string)->#null string
    {
        if str == null do
            return null
        .resetMatchContext(true)
        let beg  = cast(const [*] u8) @dataof(str)
        let last = beg + @countof(str)

        let res = .matchInternal(@mkstring(beg, last - beg), true)
        if res.ok do
            return @mkstring(beg, res.buf - beg)
        return null
    }

    mtd internalGrep(str: #nonull string, atBufferStart = true, prevWasWord = false)->#null string
    {
        var beg  = cast(const [*] u8) @dataof(str)
        let last = beg + @countof(str)
        var atStart   = atBufferStart
        var wasWord   = prevWasWord

        for
        {
            .resetMatchContext(atStart, wasWord)
            let res = .matchInternal(@mkstring(beg, last - beg), true)
            if res.ok do
                return @mkstring(beg, res.buf - beg)
            if beg == last do
                break

            let (c, eat) = Utf8.decodeRune(@mkslice(beg, last - beg))
            wasWord = Unicode.isWord(c)
            atStart = false
            beg += eat
        }

        return null
    }

    func setCapture(state: #nonull *DfaState, rank: s32, str: #nonull string)
    {
        for &v in state.groups
        {
            if v.rank == rank
            {
                v.value = str
                return
            }
        }

        state.groups.add({rank, str})
    }

    mtd hasActiveCapture(state: #nonull *DfaState, rank: u32)->bool
    {
        for g in state.activeGroups
        {
            if g.rank == rank do
                return true
        }

        return false
    }

    mtd rawGroupDepth(rawGroup: u32)->u32
    {
        var depth: retval
        var group = rawGroup
        while group and group < .groupParent.count
        {
            depth += 1
            group = .groupParent[group]
        }

        return depth
    }

    mtd closeActiveGroup(state: #nonull *DfaState, idx: u64)
    {
        let group = state.activeGroups[idx]
        let ptr   = .bufStart + state.parseIdx
        let start = .bufStart + group.startIdx
        let value = @mkstring(start, ptr - start)
        setCapture(state, cast(s32) group.rank, value)
    }

    mtd matchInternal(str: #nonull string, forGrep: bool)->{ ok: bool, buf: #null const [*] u8 }
    {
        var result: retval

        if .dfaNodes.isEmpty() do
            return result

        .bufStart  = @dataof(str)
        .bufLength = @countof(str)

        var stack1, stack2: Array'DfaState
        var grepTerm: DfaState

        var st: DfaState
        st.node = .dfaNodes[0]
        stack1.add(st)

        var pstack1 = &stack1
        var pstack2 = &stack2

        var mustEnd = false
        while !pstack1.isEmpty() and !mustEnd
        {
            while !pstack1.isEmpty()
            {
                var curState = pstack1.popBack()
                let curNode = assume curState.node
                if curNode.terminal and forGrep do
                    grepTerm = curState
                if curState.parseIdx >= .bufLength
                {
                    pstack2.add(curState)
                    continue
                }

                let bufStart = assume .bufStart
                let ptr = bufStart + curState.parseIdx
                let (cr, eat) = Utf8.decodeRune(@mkslice(ptr, .bufLength - curState.parseIdx))
                let c = .ignoreCase ? Unicode.toUpper(cr) : cr

                .dfaMatch(pstack2, c, eat, &curState)
            }

            swap(&pstack1, &pstack2)

            var cptReachedEnd = 0
            for &v in dref pstack1
            {
                if v.parseIdx >= .bufLength do
                    cptReachedEnd += 1

                let node = assume v.node
                if node.terminal and forGrep do
                    grepTerm = v
                elif node.terminal and v.parseIdx >= .bufLength do
                    mustEnd = true
            }

            if cptReachedEnd == pstack1.count do
                mustEnd = true
        }

        // Get the latest terminal node for a grep
        if pstack1.isEmpty() and grepTerm.node do
            pstack1.add(grepTerm)

        for
        {
            while !pstack1.isEmpty()
            {
                var curState = pstack1.popBack()
                let curNode = assume curState.node
                if curNode.terminal and (forGrep or curState.parseIdx >= .bufLength)
                {
                    .closeGroup(&curState)
                    .groups = #move curState.groups
                    let bufStart = assume .bufStart
                    return {true, bufStart + curState.parseIdx}
                }

                .dfaMatch(pstack2, RuneEnd, 0, &curState)
            }

            if pstack2.isEmpty() do
                break
            swap(&pstack1, &pstack2)
        }

        return result
    }

    mtd closeGroup(state: #nonull *DfaState)
    {
        while state.activeGroups.count
        {
            let idx = state.activeGroups.count - 1
            .closeActiveGroup(state, idx)
            discard state.activeGroups.popBack()
        }
    }

    mtd syncActiveGroups(state: #nonull *DfaState, nextRawGroup: u32)
    {
        var desiredRawGroups: Array'u32
        var rawGroup = nextRawGroup
        while rawGroup and rawGroup < .groupParent.count
        {
            let rank = .groupTransform[rawGroup]
            if rank do
                desiredRawGroups.add(rawGroup)
            rawGroup = .groupParent[rawGroup]
        }

        var common: u64 = 0
        while common < state.activeGroups.count and common < desiredRawGroups.count
        {
            let desiredRaw = desiredRawGroups[desiredRawGroups.count - common - 1]
            if state.activeGroups[common].rawGroup != desiredRaw do
                break
            common += 1
        }

        while state.activeGroups.count > common
        {
            let idx = state.activeGroups.count - 1
            .closeActiveGroup(state, idx)
            discard state.activeGroups.popBack()
        }

        var idx = desiredRawGroups.count - common
        while idx
        {
            idx -= 1
            let raw = desiredRawGroups[idx]
            state.activeGroups.add({raw, .groupTransform[raw], state.parseIdx})
        }
    }

    mtd backward(out: #nonull *Array'DfaState, what: rune, state: #nonull *DfaState)
    {
        let stateNode = assume state.node
        let grp = stateNode.transitions.tryFind(what)
        if grp
        {
            let grpNode = assume grp.value
            var st = dref state
            .syncActiveGroups(&st, grpNode.rawGroup)
            var strGroup: #nonull string = ""
            var hasGroup = false
            let rank = 1 + (what - RuneGroup1)
            for g in st.groups
            {
                if g.rank == rank
                {
                    hasGroup = true
                    strGroup = g.value
                    break
                }
            }

            if !hasGroup
            {
                hasGroup = .hasAvailableEmptyCapture(&st, rank)
            }

            if hasGroup
            {
                let bufStart = assume .bufStart
                let ptr = bufStart + st.parseIdx
                if !@countof(strGroup) or Utf8.startsWith(@mkslice(ptr, .bufLength - st.parseIdx), strGroup, .ignoreCase ? .UnicodeNoCase : .Unicode)
                {
                    st.node = grpNode
                    st.parseIdx += cast(s32) @countof(strGroup)
                    out.add(st)
                }
            }
        }
    }

    mtd hasCapture(state: #nonull *DfaState, rank: u32)->bool
    {
        for g in state.groups
        {
            if g.rank == rank do
                return true
        }

        return false
    }

    mtd hasAvailableEmptyCapture(state: #nonull *DfaState, rank: u32)->bool
    {
        let stateNode = assume state.node
        for n in stateNode.table
        {
            if .groupTransform[n.group] == rank do
                return true
        }

        for var raw = 1; raw < .groupTransform.count; raw += 1
        {
            if .groupTransform[raw] != rank do
                continue

            var parent = .groupParent[raw]
            while parent != 0
            {
                for n in stateNode.table
                {
                    if n.group == parent and .groupTransform[parent] != 0 do
                        return true
                }

                parent = .groupParent[parent]
            }
        }

        if .captureRanks.contains(rank) do
            return true

        return false
    }

    mtd canReachTransition(table: #nonull *Array'(#nonull *NfaNode), fromNode: #nonull *NfaNode, c: rune)->bool
    {
        var stack: Array'(#nonull *NfaNode)
        var done: Array'(#nonull *NfaNode)
        stack.add(fromNode)
        while stack.count
        {
            let node = stack.popBack()
            if done.contains(node) do
                continue
            done.add(node)

            if node.transitions.tryFind(c) do
                return true

            let epsilon = node.transitions.tryFind(0'rune)
            if !epsilon do
                continue

            for next in epsilon.value
            {
                if table.contains(next) and !done.contains(next) do
                    stack.add(next)
            }
        }

        return false
    }

    mtd transitionTargetRawGroup(state: #nonull *DfaState, c: rune)->u32
    {
        var result: retval
        var bestDepth: u32
        let currentRaw  = state.activeGroups.count ? state.activeGroups.back().rawGroup : 0
        let currentRank = state.activeGroups.count ? state.activeGroups.back().rank : 0
        let stateNode = assume state.node
        for node in stateNode.table
        {
            let find = node.transitions.tryFind(c)
            if !find do
                continue

            for next in find.value
            {
                let depth = .rawGroupDepth(next.group)
                let rank  = .groupTransform[next.group]
                if depth > bestDepth or (depth == bestDepth and result == currentRaw and next.group != currentRaw and rank == currentRank)
                {
                    bestDepth = depth
                    result    = next.group
                }
            }
        }

        return result
    }

    mtd findDisappearingEmptyGroup(state: #nonull *DfaState, nextNode: #nonull *DfaNode, c: rune)->u32
    {
        var rank: retval
        let stateNode = assume state.node
        for n in stateNode.table
        {
            let grp = .groupTransform[n.group]
            if grp == 0 or .hasActiveCapture(state, grp) do
                continue
            if !.canReachTransition(&stateNode.table, n, c) do
                continue

            var stillThere = false
            for nn in nextNode.table
            {
                if .groupTransform[nn.group] == grp
                {
                    stillThere = true
                    break
                }
            }

            if !stillThere and grp > rank do
                rank = grp
        }

        return rank
    }

    mtd dfaMatch(out: #nonull *Array'DfaState, c: rune, eat: s32, curState: #nonull *DfaState)
    {
        var ok = false

        #[Swag.Mixin]
        mtd checkTr(c: rune, length: s32)
        {
            let #uniq2 = assume curState.node
            let #uniq1 = #uniq2.transitions.tryFind(c)
            if #uniq1
            {
                var st = dref curState
                let #uniq3 = assume #uniq1.value
                let pendingEmptyGroup = .findDisappearingEmptyGroup(&st, #uniq3, c)
                if pendingEmptyGroup do
                    setCapture(&st, cast(s32) pendingEmptyGroup, "")

                let directRaw = .transitionTargetRawGroup(&st, c)
                var nextRaw   = #uniq3.rawGroup
                if directRaw and nextRaw and directRaw != nextRaw and st.activeGroups.count and st.activeGroups.back().rank != .groupTransform[directRaw] do
                    nextRaw = directRaw
                .syncActiveGroups(&st, nextRaw)
                st.node = #uniq3
                st.parseIdx += length
                out.add(st)
                ok = true
            }
        }

        // Word transition
        if !.hasStarted
        {
            .checkTr(RuneStart, 0)
            if Unicode.isWord(c) do
                .checkTr(RuneWordSwap, 0)
            .hasStarted = true
            if ok do
                return
        }
        elif !.wasWord and Unicode.isWord(c)
        {
            .wasWord = true
            .checkTr(RuneWordSwap, 0)
            if ok do
                return
        }
        elif .wasWord and !Unicode.isWord(c)
        {
            .wasWord = false
            .checkTr(RuneWordSwap, 0)
            if ok do
                return
        }

        // Backreference
        for 9
        {
            .backward(out, RuneGroup1 + @index, curState)
        }

        if Unicode.isAscii(c)
        {
            let c8 = cast(u8) c

            if Latin1.isDigit(c8) do
                .checkTr(RuneAsciiDigit, eat)
            else do
                .checkTr(RuneAsciiDigit | RuneInvert, eat)

            if Latin1.isHexDigit(c8) do
                .checkTr(RuneAsciiHexa, eat)
            else do
                .checkTr(RuneAsciiHexa | RuneInvert, eat)

            if Latin1.isLetter(c8) do
                .checkTr(RuneAsciiLetter, eat)
            else do
                .checkTr(RuneAsciiLetter | RuneInvert, eat)

            if Latin1.isLower(c8) do
                .checkTr(RuneAsciiLower, eat)
            else do
                .checkTr(RuneAsciiLower | RuneInvert, eat)

            if Latin1.isUpper(c8) do
                .checkTr(RuneAsciiUpper, eat)
            else do
                .checkTr(RuneAsciiUpper | RuneInvert, eat)

            if Latin1.isLetterOrDigit(c8) do
                .checkTr(RuneAsciiAlNum, eat)
            else do
                .checkTr(RuneAsciiAlNum | RuneInvert, eat)

            if Latin1.isLetterOrDigit(c8) or c8 == '_' do
                .checkTr(RuneAsciiWord, eat)
            else do
                .checkTr(RuneAsciiWord | RuneInvert, eat)

            if Latin1.isSpace(c8) do
                .checkTr(RuneAsciiSpace, eat)
            else do
                .checkTr(RuneAsciiSpace | RuneInvert, eat)

            if c8 == ' ' or c8 == '\t' do
                .checkTr(RuneAsciiBlank, eat)
            else do
                .checkTr(RuneAsciiBlank | RuneInvert, eat)

            .checkTr(RuneAscii, eat)
        }
        else
        {
            .checkTr(RuneAscii | RuneInvert, eat)
        }

        if Unicode.isLetter(c) do
            .checkTr(RuneUnicodeLetter, eat)
        if Unicode.isLower(c) do
            .checkTr(RuneUnicodeLetterLower, eat)
        if Unicode.isUpper(c) do
            .checkTr(RuneUnicodeLetterUpper, eat)
        if Unicode.isNumber(c) do
            .checkTr(RuneUnicodeNumber, eat)
        if Unicode.isSymbol(c) do
            .checkTr(RuneUnicodeSymbol, eat)
        if Unicode.isSymbolMath(c) do
            .checkTr(RuneUnicodeSymbolMath, eat)

        .checkTr(c, eat)
        .checkTr(RuneWhatever, eat)
        .checkTr(0'rune, eat)
    }

    func addTransition(node: #nonull *NfaNode, c: rune, toNode: #nonull *NfaNode)
    {
        var here = node.transitions.tryFind(c)
        if !here
        {
            let toT: Array'(#nonull *NfaNode)
            here = node.transitions.add(c, toT)
        }

        here.value.add(toNode)
    }

    mtd nfaPop()->#nonull *NfaTable throw
    {
        if .nfaStack.isEmpty() do
            throw SyntaxError{"nfaPop"}
        return .nfaStack.popBack()
    }

    // Creates 2 new states, and one transition (by c) between them
    mtd nfaPush(c: rune)
    {
        let table = .nfaTables.addNewPtr()
        let s1    = .nfaNodes.addNewPtr()
        let s2    = .nfaNodes.addNewPtr()

        table.level = cast(u32) .openParen.count
        s1.addTransition(c, s2)

        table.nodes.add(s1)
        table.nodes.add(s2)
        .nfaStack.add(table)

        // Add the character to the list of used characters
        .charSet.add(c)
    }

    mtd nfaPushEmpty()
    {
        let table = .nfaTables.addNewPtr()
        let s1    = .nfaNodes.addNewPtr()
        let s2    = .nfaNodes.addNewPtr()

        table.level = cast(u32) .openParen.count
        s1.addTransition(0'rune, s2)

        table.nodes.add(s1)
        table.nodes.add(s2)
        .nfaStack.add(table)
    }

    mtd tableHasGroup(table: #nonull *NfaTable)->bool
    {
        for n in table.nodes
        {
            if n.group != 0 do
                return true
        }

        return false
    }

    mtd unionValidate() throw
    {
        if .orOpStack.isEmpty() do
            return
        if .nfaStack.count < 2 do
            return

        // Check if the two tables have the same nested level
        let table2 = .nfaPop()
        let table1 = .nfaPop()
        .nfaStack.add(table1)
        .nfaStack.add(table2)
        if table1.level != table2.level do
            return

        // Operator must be at the same level
        if .orOpLevel[.orOpLevel.count - 1] != table1.level do
            return

        // Else validate union
        .orOpStack.removeBack()
        .orOpLevel.removeBack()
        .operatorUnion()
    }

    mtd operatorUnion() throw
    {
        let table2 = .nfaPop()
        let table1 = .nfaPop()

        let ns1 = Memory.new'NfaNode()
        let ns2 = Memory.new'NfaNode()
        .nfaNodes.add(ns1)
        .nfaNodes.add(ns2)

        let sa1 = table1.nodes.front()
        let sa2 = table1.nodes.back()
        let sb1 = table2.nodes.front()
        let sb2 = table2.nodes.back()

        ns1.addTransition(0'rune, sa1)
        ns1.addTransition(0'rune, sb1)
        sa2.addTransition(0'rune, ns2)
        sb2.addTransition(0'rune, ns2)

        table1.nodes.add(table2.nodes.toSlice())
        table1.nodes.insertAt(0, ns1)
        table1.nodes.add(ns2)
        .nfaStack.add(table1)
    }

    mtd operatorConcat(cpt: u64, canGroup = true, logicalRank: u32 = 0) throw
    {
        var count = cpt
        while count >= 2
        {
            let table2 = .nfaPop()
            let table1 = .nfaPop()

            // Update nested level
            table1.level = cast(u32) .openParen.count
            table2.level = cast(u32) .openParen.count

            let s1 = table1.nodes.back()
            let s2 = table2.nodes.front()
            s1.addTransition(0'rune, s2)

            table1.nodes.add(table2.nodes.toSlice())
            .nfaStack.add(table1)

            count -= 1
        }

        // Update nested level
        if count == 1
        {
            let table1 = .nfaPop()
            table1.level = cast(u32) .openParen.count

            if canGroup
            {
                .group += 1
                if .groupTransform.count <= .group do
                    .groupTransform.resize(cast(u64) .group + 1)
                if .groupParent.count <= .group
                {
                    let oldCount = .groupParent.count
                    .groupParent.resize(cast(u64) .group + 1)
                    for var i = oldCount; i < .groupParent.count; i += 1 do
                        .groupParent[i] = 0
                }
                .groupTransform[.group] = logicalRank
                .groupParent[.group] = 0
                for n in table1.nodes
                {
                    if n.group != 0
                    {
                        var rootGroup = n.group
                        while .groupParent[rootGroup] != 0
                            do rootGroup = .groupParent[rootGroup]
                        if rootGroup != .group and .groupParent[rootGroup] == 0 do
                            .groupParent[rootGroup] = .group
                    }
                    if n.group == 0 do
                        n.group = .group
                }
            }

            .nfaStack.add(table1)
        }
    }

    mtd operatorStar() throw
    {
        let table = .nfaPop()
        let s1    = table.nodes.front()
        let s2    = table.nodes.back()
        if .tableHasGroup(table)
        {
            let ns1 = .nfaNodes.addNewPtr()
            let ns2 = .nfaNodes.addNewPtr()
            let ns3 = .nfaNodes.addNewPtr()
            ns1.addTransition(0'rune, s1)
            ns1.addTransition(0'rune, ns3)
            s2.addTransition(0'rune, ns2)
            ns2.addTransition(0'rune, s1)
            ns2.addTransition(0'rune, ns3)

            table.nodes.insertAt(0, ns1)
            table.nodes.add(ns2)
            table.nodes.add(ns3)
            .nfaStack.add(table)
            return
        }

        s1.addTransition(0'rune, s2)
        s2.addTransition(0'rune, s1)
        .nfaStack.add(table)
    }

    mtd operatorPlus() throw
    {
        let table = .nfaPop()
        let s1    = table.nodes.front()
        let s2    = table.nodes.back()
        s2.addTransition(0'rune, s1)
        .nfaStack.add(table)
    }

    mtd operatorQuestion() throw
    {
        let table = .nfaPop()
        let s1    = table.nodes.front()
        let s2    = table.nodes.back()
        if .tableHasGroup(table)
        {
            let ns1 = .nfaNodes.addNewPtr()
            let ns2 = .nfaNodes.addNewPtr()
            ns1.addTransition(0'rune, s1)
            ns1.addTransition(0'rune, ns2)
            s2.addTransition(0'rune, ns2)

            table.nodes.insertAt(0, ns1)
            table.nodes.add(ns2)
            .nfaStack.add(table)
            return
        }

        s1.addTransition(0'rune, s2)
        .nfaStack.add(table)
    }

    func isReservedChar(c: rune)->bool
    {
        switch c
        {
        case '\\', '(', ')', '*', '?', '+', '.', '|', '[', ']', '{', '}', '/', '^', '$', '-':
            return true
        }

        return false
    }

    mtd nfaBuild() throw
    {
        if .preprocessed.isEmpty()
        {
            .nfaPushEmpty()
            return
        }

        var pz  = .preprocessed.buffer
        var cpt = 0
        var expectAltExpr = true

        while cpt < .preprocessed.count
        {
            var c = dref pz
            switch c
            {
            case '(', RuneOpenParen:
                .openParen.add(cast(u32) .nfaStack.count)

            case RuneCloseParen:
                let op = .openParen.popBack()
                if .nfaStack.count == op do
                    .nfaPushEmpty()
                .unionValidate()
                .operatorConcat(.nfaStack.count - op, false)
                expectAltExpr = false

            case ')':
                if .openParen.isEmpty() do
                    throw SyntaxError{"unexpected right parenthesis"}
                let op = .openParen.popBack()
                if .nfaStack.count == op do
                    .nfaPushEmpty()
                .unionValidate()
                let rank = .captureRanks[.captureRankIdx]
                .captureRankIdx += 1
                .operatorConcat(.nfaStack.count - op, true, rank)
                expectAltExpr = false

            case '*':
                .operatorStar()
                expectAltExpr = false

            case '+':
                .operatorPlus()
                expectAltExpr = false

            case '?':
                .operatorQuestion()
                expectAltExpr = false

            case '|':
                if expectAltExpr do
                    .nfaPushEmpty()
                .unionValidate()
                .orOpStack.add(c)
                .orOpLevel.add(cast(u32) .openParen.count)
                expectAltExpr = true

            case '.':
                .unionValidate()
                .nfaPush(RuneWhatever)
                expectAltExpr = false

            case RuneEmpty:
                .unionValidate()
                .nfaPushEmpty()
                expectAltExpr = false

            case '\\':
                if isReservedChar(pz[1])
                {
                    c = pz[1]
                    cpt, pz += 1
                }

                .unionValidate()
                .nfaPush(c)
                expectAltExpr = false

            default:
                .unionValidate()
                .nfaPush(c)
                expectAltExpr = false
            }

            cpt, pz += 1
        }

        if expectAltExpr and !.orOpStack.isEmpty() do
            .nfaPushEmpty()

        // Remaining operators
        .unionValidate()
        if !.orOpStack.isEmpty() do
            throw SyntaxError{}
        if !.openParen.isEmpty() do
            throw SyntaxError{"missing ')'"}

        // Concat the remaining nodes
        .operatorConcat(.nfaStack.count, true, 0)
    }

    func dfaEClosure(inH, outH: #nonull *Array'(#nonull *NfaNode))
    {
        outH.clear()

        var stack: Array'(#nonull *NfaNode)
        for n in dref inH do
            stack.add(n)

        while stack.count
        {
            let state = stack.popBack()
            outH.addOnce(state)

            let find = state.transitions.tryFind(0'rune)
            if !find do
                continue

            for t in find.value
            {
                if !outH.contains(t) do
                    stack.add(t)
            }
        }
    }

    mtd setTable(node: #nonull *DfaNode, tbl: #nonull *Array'(#nonull *NfaNode))
    {
        node.table = #move dref tbl
        for n in node.table
        {
            if node.rawGroup == 0 do
                node.rawGroup = n.group

            if n.terminal do
                node.terminal = true
        }

        node.group = .groupTransform[node.rawGroup]
    }

    func dfaMoveNode(out: #nonull *Array'(#nonull *NfaNode), c: rune, inH: Array'(#nonull *NfaNode))
    {
        out.clear()
        for state in inH
        {
            // The real terminal character
            let pfind = state.transitions.tryFind(c)
            if pfind
            {
                for t in pfind.value do
                    out.add(t)
            }
        }
    }

    func equals(s1, s2: #nonull *Array'(#nonull *NfaNode))->bool
    {
        if s1.count != s2.count do
            return false
        for t1 in dref s1
        {
            if !s2.contains(t1) do
                return false
        }

        return true
    }

    mtd dfaBuild() throw
    {
        // One table must remain
        let table = .nfaPop()

        // Last state of NFA table is a terminal
        table.nodes.back().terminal = true

        // Build the first state of the DFA table
        var nfaStart, dfaStart: Array'(#nonull *NfaNode)
        nfaStart.addOnce(table.nodes.front())
        dfaEClosure(&nfaStart, &dfaStart)

        var state = Memory.new'DfaNode() orelse cast(#nonull *DfaNode) 1'u64
        .setTable(state, &dfaStart)
        .dfaNodes.add(state)

        var moveRes, epsilonRes: Array'(#nonull *NfaNode)
        var stack: Array'(#nonull *DfaNode)
        stack.add(state)
        while stack.count
        {
            state = stack.popBack()
            for c in .charSet
            {
                dfaMoveNode(&moveRes, c, state.table)
                if moveRes.count == 0 do
                    continue
                dfaEClosure(&moveRes, &epsilonRes)

                var found: #null *DfaNode
                for tstate in .dfaNodes
                {
                    if equals(&tstate.table, &epsilonRes)
                    {
                        found = tstate
                        break
                    }
                }

                if !found
                {
                    let newNode = Memory.new'DfaNode() orelse cast(#nonull *DfaNode) 1'u64
                    found = newNode
                    .setTable(newNode, &epsilonRes)
                    stack.add(newNode)
                    .dfaNodes.add(newNode)
                }

                state.transitions.add(c, found)
            }
        }
    }

    #[Swag.Discardable]
    mtd preprocessInter(sl: #nonull const [..] rune)->#nonull const [*] rune throw
    {
        var pz      = @dataof(sl)
        let pzStart = pz
        let pzEnd   = pz + @countof(sl)

        .preprocessed.add(RuneOpenParen)
        pz += 1

        // Negation
        var invert: rune
        if dref pz == '^'
        {
            invert = RuneInvert
            pz += 1
        }

        var firstExp = true
        while pz != pzEnd and pz[0] != ']'
        {
            if pz[0] == 0 do
                throw SyntaxError{"unterminated '['"}

            if !firstExp do
                .preprocessed.add('|')
            firstExp = false

            let subSlice = @mkslice(pz, pzEnd - pz)

            // Predefined sets
            if pz[0] == '['
            {
                if Unicode.compare(subSlice, #runes("[:digit:]"), false, 9) == 0
                {
                    .preprocessed.add(RuneAsciiDigit | invert)
                    pz += 9
                    continue
                }

                if Unicode.compare(subSlice, #runes("[:xdigit:]"), false, 10) == 0
                {
                    .preprocessed.add(RuneAsciiHexa | invert)
                    pz += 10
                    continue
                }

                if Unicode.compare(subSlice, #runes("[:alpha:]"), false, 9) == 0
                {
                    .preprocessed.add(RuneAsciiLetter | invert)
                    pz += 9
                    continue
                }

                if Unicode.compare(subSlice, #runes("[:alnum:]"), false, 9) == 0
                {
                    .preprocessed.add(RuneAsciiAlNum | invert)
                    pz += 9
                    continue
                }

                if Unicode.compare(subSlice, #runes("[:lower:]"), false, 9) == 0
                {
                    .preprocessed.add((.ignoreCase ? RuneAsciiLetter : RuneAsciiLower) | invert)
                    pz += 9
                    continue
                }

                if Unicode.compare(subSlice, #runes("[:upper:]"), false, 9) == 0
                {
                    .preprocessed.add((.ignoreCase ? RuneAsciiLetter : RuneAsciiUpper) | invert)
                    pz += 9
                    continue
                }

                if Unicode.compare(@mkslice(pz, pzEnd - pz), #runes("[:blank:]"), false, 9) == 0
                {
                    .preprocessed.add(RuneAsciiBlank | invert)
                    pz += 9
                    continue
                }

                if Unicode.compare(@mkslice(pz, pzEnd - pz), #runes("[:space:]"), false, 9) == 0
                {
                    .preprocessed.add(RuneAsciiSpace | invert)
                    pz += 9
                    continue
                }

                if Unicode.compare(@mkslice(pz, pzEnd - pz), #runes("[:ascii:]"), false, 9) == 0
                {
                    .preprocessed.add(RuneAscii | invert)
                    pz += 9
                    continue
                }

                if Unicode.compare(@mkslice(pz, pzEnd - pz), #runes("[:word:]"), false, 8) == 0
                {
                    .preprocessed.add(RuneAsciiWord | invert)
                    pz += 8
                    continue
                }

                if @countof(subSlice) >= 2 and pz[1] == ':' do
                    throw SyntaxError{"invalid predefined class"}
            }

            // Specified interval
            if @countof(subSlice) >= 3 and pz[1] == '-' and pz[2] != ']'
            {
                var first = pz[0]
                var end   = pz[2]
                if first > end do
                    swap(&first, &end)

                if first == 'A' and end == 'Z' do
                    .preprocessed.add((.ignoreCase ? RuneAsciiLetter : RuneAsciiUpper) | invert)
                elif first == 'a' and end == 'z' do
                    .preprocessed.add((.ignoreCase ? RuneAsciiLetter : RuneAsciiLower) | invert)
                elif first == '0' and end == '9' do
                    .preprocessed.add(RuneAsciiDigit | invert)
                else
                {
                    while first < end
                    {
                        .addPatternRune(first)
                        .preprocessed.add('|')
                        first += 1
                    }

                    .addPatternRune(first)
                }

                pz += 3
                continue
            }

            // This is not an interval
            if dref pz == '\\'
            {
                pz = .preprocessEscape(@mkslice(pz, pzEnd - pz), true)
            }
            elif isReservedChar(dref pz)
            {
                .preprocessed.add('\\')
                .addPatternRune(dref pz)
                pz += 1
            }
            else
            {
                pz = .preprocessEscape(@mkslice(pz, pzEnd - pz), true)
            }
        }

        if pz != pzEnd do
            pz += 1
        .preprocessed.add(RuneCloseParen)

        return pz
    }

    func toI32(pz, pzEnd: #nonull const [*] rune, val: #nonull *s32)->#nonull const [*] rune throw
    {
        if !Unicode.isLatin1(pz[0]) or !Latin1.isDigit(cast(u8) pz[0]) do
            throw SyntaxError{}

        var pzStart = pz
        var n       = 0
        while pzStart != pzEnd and Unicode.isLatin1(pzStart[0]) and Latin1.isDigit(cast(u8) pzStart[0])
        {
            n *= 10
            n += cast(u8) pzStart[0] - '0'
            pzStart += 1
        }

        dref val = n
        return pzStart
    }

    mtd preprocessEnum(sl: #nonull const [..] rune)->#nonull const [*] rune throw
    {
        var pz    = @dataof(sl)
        let pzEnd = pz + @countof(sl)

        if .preprocessed.count == 0 do
            throw SyntaxError{"'{' without a previous expression"}

        var m = -1
        pz += 1

        // n value
        var n: s32 = 0
        pz = toI32(pz, pzEnd, &n)

        // m value
        if pz[0] == ','
        {
            m = -1
            pz += 1
            if pz[0] != '}' do
                pz = toI32(pz, pzEnd, &m)
        }
        else
        {
            m = n
        }

        if pz[0] != '}' do
            throw SyntaxError{"enum, missing '}'"}
        if m != -1 and m < n do
            throw SyntaxError{"enum m < n in {n,m}"}

        pz += 1
        let expr      = .previousExpression()
        let exprRanks = .previousExpressionCaptureRanks(expr)

        if m == 0 and n == 0
        {
            .preprocessed.resize(.preprocessed.count - expr.count)
            .captureRanks.resize(.captureRanks.count - exprRanks.count)
            .preprocessed.add(.emptyExpression(expr).toSlice())
            .captureRanks.add(exprRanks.toSlice())
            return pz
        }

        if n == 0 and m == -1 do
            .preprocessed.add('*')
        elif n == 0 and m == 1 do
            .preprocessed.add('?')
        elif n == 1 and m == -1 do
            .preprocessed.add('+')
        elif n != 1 or m != 1 // {1,1}
        {
            if n == 0 do
                .preprocessed.add('?')
            else
            {
                var i = n - 1
                while i
                {
                    .preprocessed.add(expr.toSlice())
                    .captureRanks.add(exprRanks.toSlice())
                    i -= 1
                }
            }

            if m == -1
            {
                .preprocessed.add('+')
            }
            else
            {
                if n == 0 do
                    m -= 1
                m -= n
                while m
                {
                    .preprocessed.add(expr.toSlice())
                    .captureRanks.add(exprRanks.toSlice())
                    .preprocessed.add('?')
                    m -= 1
                }
            }
        }

        return pz
    }

    mtd previousExpression()->Array'rune throw
    {
        let pze      = .preprocessed.buffer + .preprocessed.count - 1
        var pz1      = pze
        var cptParen = 0
        if pz1 != .preprocessed.buffer and (pz1 - 1)[0] == '\\' and isReservedChar(pz1[0]) do
            pz1 -= 1
        elif pz1[0] == ')' or pz1[0] == RuneCloseParen do
            cptParen += 1
        while cptParen and pz1 != .preprocessed.buffer
        {
            pz1 -= 1
            if pz1[0] == ')' or pz1[0] == RuneCloseParen do
                cptParen += 1
            if pz1[0] == '(' or pz1[0] == RuneOpenParen do
                cptParen -= 1
        }

        if cptParen do
            throw SyntaxError{"missing '('"}

        var expr: retval
        while pz1 <= pze
        {
            expr.add(pz1[0])
            pz1 += 1
        }

        return expr
    }

    mtd previousExpressionCaptureRanks(expr: Array'rune)->Array'u32
    {
        var count = 0
        var idx   = 0
        while idx < expr.count
        {
            if expr[idx] == '\\' and idx + 1 < expr.count and isReservedChar(expr[idx + 1])
            {
                idx += 2
                continue
            }

            if expr[idx] == ')' do
                count += 1
            idx += 1
        }

        var result: retval
        if count == 0 do
            return result

        let start = .captureRanks.count - count
        for var i = start; i < .captureRanks.count; i += 1 do
            result.add(.captureRanks[i])
        return result
    }

    mtd emptyExpression(expr: Array'rune)->Array'rune
    {
        var result: retval
        var idx = 0
        while idx < expr.count
        {
            let c = expr[idx]
            if c == '\\' and idx + 1 < expr.count and isReservedChar(expr[idx + 1])
            {
                idx += 2
                continue
            }

            switch c
            {
            case '(', RuneOpenParen:
                result.add(c)

            case ')', RuneCloseParen:
                result.add(RuneEmpty)
                result.add(c)
            }

            idx += 1
        }

        if result.isEmpty() do
            result.add(RuneEmpty)
        return result
    }

    mtd preprocessUnicode(sl: #nonull const [..] rune)->#nonull const [*] rune throw
    {
        let pz    = @dataof(sl) + 2
        let pzEnd = @dataof(sl) + @countof(sl)

        if pz[0] == '{'
        {
            if pz + 3 < pzEnd and pz[1] == 'L' and pz[3] == '}'
            {
                switch pz[2]
                {
                case 'l':
                    .preprocessed.add(.ignoreCase ? RuneUnicodeLetter : RuneUnicodeLetterLower)
                    return pz + 4
                case 'u':
                    .preprocessed.add(.ignoreCase ? RuneUnicodeLetter : RuneUnicodeLetterUpper)
                    return pz + 4
                }
            }
            elif pz + 3 < pzEnd and pz[1] == 'S' and pz[3] == '}'
            {
                switch pz[2]
                {
                case 'm':
                    .preprocessed.add(RuneUnicodeSymbolMath)
                    return pz + 4
                }
            }
        }

        switch pz[0]
        {
        case 'L':
            .preprocessed.add(RuneUnicodeLetter)
            return pz + 1
        case 'N':
            .preprocessed.add(RuneUnicodeNumber)
            return pz + 1
        case 'S':
            .preprocessed.add(RuneUnicodeSymbol)
            return pz + 1
        }

        throw SyntaxError{"invalid unicode property"}
    }

    mtd preprocessEscape(sl: #nonull const [..] rune, inInter = false)->#nonull const [*] rune throw
    {
        var pz = @dataof(sl)
        let c  = dref pz
        if c == '\\'
        {
            if pz[1] == 0 do
                throw SyntaxError{"unterminated escape"}

            if isReservedChar(pz[1])
            {
                .preprocessed.add('\\')
                .addPatternRune(pz[1])
                return pz + 2
            }

            switch pz[1]
            {
            case 'd':
                .preprocessInter(#runes("[[:digit:]]"))
                return pz + 2
            case 'D':
                .preprocessInter(#runes("[^[:digit:]]"))
                return pz + 2
            case 'w':
                .preprocessInter(#runes("[[:word:]]"))
                return pz + 2
            case 'W':
                .preprocessInter(#runes("[^[:word:]]"))
                return pz + 2
            case 's':
                .preprocessInter(#runes("[[:space:]]"))
                return pz + 2
            case 'S':
                .preprocessInter(#runes("[^[:space:]]"))
                return pz + 2
            case 'l':
                .preprocessInter(#runes("[[:lower:]]"))
                return pz + 2
            case 'L':
                .preprocessInter(#runes("[^[:lower:]]"))
                return pz + 2
            case 'u':
                .preprocessInter(#runes("[[:upper:]]"))
                return pz + 2
            case 'U':
                .preprocessInter(#runes("[^[:upper:]]"))
                return pz + 2
            case 'a':
                .preprocessed.add('\a')
                return pz + 2
            case 'b':
                .preprocessed.add(inInter ? '\b' : RuneWordSwap)
                return pz + 2
            case 'f':
                .preprocessed.add('\f')
                return pz + 2
            case 'n':
                .preprocessed.add('\n')
                return pz + 2
            case 'r':
                .preprocessed.add('\r')
                return pz + 2
            case 't':
                .preprocessed.add('\t')
                return pz + 2
            case 'v':
                .preprocessed.add('\v')
                return pz + 2
            case 'p':
                pz = .preprocessUnicode(sl)
                return pz
            case '1', '2', '3', '4', '5', '6', '7', '8', '9':
                .preprocessed.add(RuneGroup1 + (pz[1] - '1'))
                return pz + 2
            }

            throw SyntaxError{"invalid escape"}
        }

        if c == '^' and !inInter do
            .preprocessed.add(RuneStart)
        elif c == '$' and !inInter do
            .preprocessed.add(RuneEnd)
        else
        {
            .addPatternRune(c)
            if c == '('
            {
                .captureRankMax += 1
                .captureRankStack.add(.captureRankMax)
            }
            elif c == ')' and !.captureRankStack.isEmpty()
            {
                .captureRanks.add(.captureRankStack.back())
                discard .captureRankStack.popBack()
            }
        }

        return pz + 1
    }

    func addParenthesis(uni32: &Array'rune)
    {
        #[Swag.Discardable]
        func isEscaped(uni32: &Array'rune, idx: s32)->bool
        {
            var count = 0
            var i     = idx - 1
            while i >= 0 and uni32[i] == '\\'
            {
                count += 1
                i -= 1
            }

            return (count & 1) != 0
        }

        for var i = 1's32; i < uni32.count - 1; i += 1
        {
            if uni32[i] == '|' and !isEscaped(uni32, i)
            {
                uni32.insertAt(cast() i, RuneCloseParen)
                uni32.insertAt(cast() (i + 2), RuneOpenParen)

                var cpt0, cpt1, cpt2: s32
                var iminus = i - 1

                #scope(Loop)
                while iminus != -1
                {
                    switch uni32[iminus]
                    {
                    case ']':
                        if isEscaped(uni32, iminus) do
                            break
                        cpt0 += 1
                    case ')':
                        if isEscaped(uni32, iminus) do
                            break
                        cpt1 += 1
                    case RuneCloseParen:
                        cpt1 += 1
                    case '}':
                        if isEscaped(uni32, iminus) do
                            break
                        cpt2 += 1
                    case '[':
                        if isEscaped(uni32, iminus) do
                            break
                        if cpt0 == 0 do
                            break to Loop
                        cpt0 -= 1
                    case '(':
                        if isEscaped(uni32, iminus) do
                            break
                        if cpt1 == 0 do
                            break to Loop
                        cpt1 -= 1
                    case RuneOpenParen:
                        if cpt1 == 0 do
                            break to Loop
                        cpt1 -= 1
                    case '{':
                        if isEscaped(uni32, iminus) do
                            break
                        if cpt2 == 0 do
                            break to Loop
                        cpt2 -= 1
                    }

                    iminus -= 1
                }

                uni32.insertAt(cast() (iminus + 1), RuneOpenParen)

                cpt0, cpt1, cpt2 = 0
                var iplus = i + 4

                #scope(Loop)
                while iplus != uni32.count
                {
                    switch uni32[iplus]
                    {
                    case '[':
                        if isEscaped(uni32, iplus) do
                            break
                        cpt0 += 1
                    case '(':
                        if isEscaped(uni32, iplus) do
                            break
                        cpt1 += 1
                    case RuneOpenParen:
                        cpt1 += 1
                    case '{':
                        if isEscaped(uni32, iplus) do
                            break
                        cpt2 += 1
                    case ']':
                        if isEscaped(uni32, iplus) do
                            break
                        if cpt0 == 0 do
                            break to Loop
                        cpt0 -= 1
                    case ')':
                        if isEscaped(uni32, iplus) do
                            break
                        if cpt1 == 0 do
                            break to Loop
                        cpt1 -= 1
                    case RuneCloseParen:
                        if cpt1 == 0 do
                            break to Loop
                        cpt1 -= 1
                    case '}':
                        if isEscaped(uni32, iplus) do
                            break
                        if cpt2 == 0 do
                            break to Loop
                        cpt2 -= 1
                    }

                    iplus += 1
                }

                uni32.insertAt(cast() iplus, RuneCloseParen)
                i += 4
            }
        }
    }

    mtd preprocess(inStr: #nonull string) throw
    {
        var in32 = Unicode.fromUtf8(inStr)
        addParenthesis(&in32)
        in32.add(0'rune)

        var pz    = cast(const [*] rune) in32.buffer
        let pzEnd = pz + in32.count

        var c = .ignoreCase ? Unicode.toUpper(pz[0]) : pz[0]
        while c
        {
            switch c
            {
            case '[':
                pz = .preprocessInter(@mkslice(pz, pzEnd - pz))
            case '{':
                pz = .preprocessEnum(@mkslice(pz, pzEnd - pz))
            default:
                pz = .preprocessEscape(@mkslice(pz, pzEnd - pz))
            }

            if !pz do
                break
            c = .ignoreCase ? Unicode.toUpper(pz[0]) : pz[0]
        }
    }
}
