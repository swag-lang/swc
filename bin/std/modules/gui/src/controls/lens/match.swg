#global public
#global namespace Lens

using Core

// A run of matched bytes in a text.
struct Span
{
    public
    {
        start: u32     // Byte offset of the first matched byte.
        count: u32     // Number of matched bytes.
    }
}

// How well a query answers a text, and which of its characters it matched.
struct Match
{
    public
    {
        matched: bool           // Whether the query answers the text at all.
        score:   s32            // How well it answers; higher is better, and only `matched` texts compare.
        spans:   Array'Span     // Byte runs of the text the query matched, in order; empty for an empty query.
    }
}

// A query folded once, to be matched against many texts.
//
// A lens matches one query against every row it may show, on every keystroke. Folding the
// query's case and accents once, and handing the result to [[Gui.Lens.match]] for each text,
// leaves only the texts to read. A default query is empty and answers every text.
struct Query
{
    runes:    Array'FoldedRune     // Characters of the query, folded as those of a text are.
    oneWord:  bool     // Whether the query holds no space between its characters.
    required: u64      // Positions of the characters other than spaces, among the first 64.
}

impl Query
{
    // Folds `query` once for [[Gui.Lens.match]], with the same rules as matching the string itself.
    func create(query: string)->Query
    {
        var result: #returntype
        result.runes   = foldRunes(query)
        result.oneWord = true
        for r, i in result.runes
        {
            if r.folded == ' '
            {
                result.oneWord = false
                continue
            }

            if i < 64 do
                result.required |= 1'u64 << i
        }

        return result
    }

    // Returns how much of the query `text` holds, as every answer needs: a whole occurrence, the
    // initials and scattered letters take a single word's characters in order, words given in any
    // order each take their own somewhere, and a typo of a single word leaves out one character at
    // most. With `tolerateTypos`, a text that holds less than the whole query may still answer.
    //
    // The text is decoded without being stored. Its spaces and combining accents are compared
    // too, which can only let more texts through, never fewer.
    private mtd const holding(text: string, tolerateTypos: bool)->Holding
    {
        let needle = .runes.toSlice()
        if not .oneWord and needle.count > 64 do
            return .All

        var held    = 0'u64     // Characters of a single word found in order.
        var spare   = 0'u64     // Characters of a single word found in order, but for one left out.
        var missing = .required
        var offset  = 0'u64
        while offset < text.count
        {
            var folded: rune
            let byte = text[offset]
            if byte < 0x80
            {
                folded = cast(rune, Latin1.toLower(byte))
                offset += 1
            }
            else
            {
                let rest    = Swag.makeSlice(text.buffer + offset, text.count - offset)
                let decoded = Utf8.decodeRune(rest)
                folded = foldAccent(Unicode.toLower(decoded.c))
                offset += Math.max(decoded.eat, 1)
            }

            if .oneWord
            {
                if tolerateTypos
                {
                    spare = Math.max(spare, held + 1)
                    if spare < needle.count and needle[spare].folded == folded do
                        spare += 1
                }

                if folded != needle[held].folded do
                    continue
                held += 1
                if held == needle.count do
                    return .All
                continue
            }

            for i in needle.count where needle[i].folded == folded do
                missing &= ~(1'u64 << i)
            if missing == 0 do
                return .All
        }

        // Only a word of four letters or more is corrected, and words given in any order are not
        // followed here, so a query of several words may hold a typo whatever this text lacks.
        if not tolerateTypos do
            return .Nothing
        if not .oneWord do
            return .AllButOne
        if needle.count >= 4 and Math.max(spare, held + 1) >= needle.count do
            return .AllButOne
        return .Nothing
    }
}

// How much of a query a text holds, in the order an answer takes it.
private enum Holding
{
    Nothing       // Too little for any answer.
    AllButOne     // Enough for a typo only.
    All           // Enough for any answer.
}

// Matches `query` against `text`, ignoring case and common Latin accents, with original UTF-8 spans.
//
// A query found whole in the text answers best, and better still where a word starts — at the
// beginning of the text, after a separator, or at a capital inside a camel-case name — and the
// earlier the better. Word prefixes separated by spaces may appear in any order, followed by
// the initials of its words in order: "cla" answers "Capture Last Area".
// Otherwise its characters must appear in the text in order, which answers less well the further
// they are scattered. An empty query answers every text with a score of zero.
// Whitespace is trimmed and collapsed. With `tolerateTypos`, one word of at least four
// letters may contain one insertion, deletion, substitution or transposition. Other query words
// must match distinct word prefixes exactly, in any order; the whole query has a one-edit budget.
// This fallback ranks below precise matches and is intended for commands, not paths or numbers.
//
// ```swag
// let found = Lens.match("cgr", "centerGroup")
// Swag.assert(found.matched and found.spans.count == 2)
// ```
func match(query: string, text: string, tolerateTypos = false)->Match
{
    return match(Query.create(query), text, tolerateTypos)
}

// Matches the folded `query` against `text`, exactly as matching its original string would.
//
// A caller that matches one query against many texts folds it once with
// [[Gui.Lens.Query.create]] and passes it here for each text.
//
// ```swag
// let query = Lens.Query.create("cgr")
// Swag.assert(Lens.match(query, "centerGroup").matched and not Lens.match(query, "close").matched)
// ```
func match(query: Query, text: string, tolerateTypos = false)->Match
{
    var result: #returntype
    let needle = query.runes.toSlice()
    if needle.count == 0
    {
        result.matched = true
        return result
    }

    // Most texts lack the query's characters, so they are turned down before their characters are
    // folded, and one that holds enough for a typo alone is only tried for a typo.
    let held = query.holding(text, tolerateTypos)
    if held == .Nothing do
        return result

    let haystack = foldRunes(text)
    if held != .All or needle.count > haystack.count do
        return tolerateTypos ? typoMatch(needle, haystack.toSlice()) : result

    // A whole occurrence: the first one that starts a word, else the first one at all.
    var found = Swag.U64.Max
    for start in haystack.count - needle.count + 1
    {
        var same = true
        for i in needle.count where haystack[start + i].folded != needle[i].folded
        {
            same = false
            break
        }

        if not same do
            continue
        if found == Swag.U64.Max do
            found = start
        if haystack[start].wordStart
        {
            found = start
            break
        }
    }

    if found != Swag.U64.Max
    {
        let first = haystack[found]
        let last  = haystack[found + needle.count - 1]
        result.matched = true
        result.score   = WholeScore - cast(s32, found) - cast(s32, haystack.count - needle.count)
        if first.wordStart do
            result.score += WordStartBonus
        result.spans.add(Span{first.offset, last.offset + last.size - first.offset})
        return result
    }

    let words = wordMatch(needle, haystack.toSlice())
    if words.matched do
        return words

    // The initials of the words, in order, each the next word start that carries it.
    var initials: Array'Span
    var at = 0'u64
    for r in needle
    {
        while at < haystack.count and not (haystack[at].wordStart and haystack[at].folded == r.folded) do
            at += 1
        if at == haystack.count do
            break
        initials.add(Span{haystack[at].offset, haystack[at].size})
        at += 1
    }

    if initials.count == needle.count
    {
        result.matched = true
        result.score   = InitialsScore - cast(s32, haystack.count)
        result.spans   = #move initials
        return result
    }

    // The characters in order, each taken as early as it comes.
    var next      = 0'u64
    var scattered = 0's32
    for r in needle
    {
        while next < haystack.count and haystack[next].folded != r.folded do
            next += 1
        if next == haystack.count do
            return tolerateTypos ? typoMatch(needle, haystack.toSlice()) : Match{}

        let at = haystack[next]
        if not result.spans.isEmpty() and result.spans.back().start + result.spans.back().count == at.offset
        {
            result.spans.backPtr().count += at.size
        }
        else
        {
            if not result.spans.isEmpty() do
                scattered += 1
            result.spans.add(Span{at.offset, at.size})
        }

        next += 1
    }

    result.matched = true
    result.score   = OrderScore - scattered * ScatterCost - cast(s32, result.spans.front().start)
    return result
}

// Words typed in another order still name the same task; each must consume a distinct word.
private func wordMatch(needle, haystack: const [..] FoldedRune, tolerateTypos = false)->Match
{
    var result: #returntype
    var used:   Array'u64
    var corrected = false
    var begin     = 0'u64
    while begin < needle.count
    {
        var end = begin
        while end < needle.count and Unicode.isLetter(needle[end].folded) do
            end += 1
        if end == begin or (end < needle.count and needle[end].folded != ' ') do
            return Match{}

        var found = false
        for start in haystack.count
        {
            if not haystack[start].wordStart or
               used.contains(start) or
               start + end - begin > haystack.count do
                continue
            var same = true
            for i in end - begin
            {
                if haystack[start + i].folded != needle[begin + i].folded or
                   (i != 0 and haystack[start + i].wordStart)
                {
                    same = false
                    break
                }
            }

            if not same do
                continue
            let first = haystack[start]
            let last  = haystack[start + end - begin - 1]
            result.spans.add({first.offset, last.offset + last.size - first.offset})
            used.add(start)
            found = true
            break
        }

        if not found and tolerateTypos and not corrected and end - begin >= 4
        {
            for start in haystack.count where haystack[start].wordStart and
                                              Unicode.isLetter(haystack[start].folded) and
                                              not used.contains(start)
            {
                var wordEnd = start + 1
                while wordEnd < haystack.count and
                      Unicode.isLetter(haystack[wordEnd].folded) and
                      not haystack[wordEnd].wordStart do
                    wordEnd += 1
                if not oneEditApart(needle[begin until end], haystack[start until wordEnd]) do
                    continue
                let first = haystack[start]
                let last  = haystack[wordEnd - 1]
                result.spans.add({first.offset, last.offset + last.size - first.offset})
                used.add(start)
                found     = true
                corrected = true
                break
            }
        }

        if not found do
            return Match{}
        begin = end + 1
    }

    result.matched = used.count > 1 or corrected
    result.score   = (corrected ? 3000 : 9000) - cast(s32, haystack.count)
    result.spans.sort(func(a, b) => a.start <=> b.start)
    return result
}

// Bounded edit distance, including adjacent transposition, without a matrix allocation.
private func oneEditApart(a, b: const [..] FoldedRune)->bool
{
    if a.count > b.count + 1 or b.count > a.count + 1 do
        return false
    var i, j  = 0'u64
    var edits = 0
    while i < a.count and j < b.count
    {
        if a[i].folded == b[j].folded
        {
            i += 1
            j += 1
            continue
        }

        edits += 1
        if edits > 1 do
            return false
        if a.count > b.count
        {
            i += 1
        }
        elif b.count > a.count
        {
            j += 1
        }
        elif i + 1 < a.count and
             j + 1 < b.count and
             a[i].folded == b[j + 1].folded and
             a[i + 1].folded == b[j].folded
        {
            i += 2
            j += 2
        }
        else
        {
            i += 1
            j += 1
        }
    }

    return edits + cast(s32, a.count - i + b.count - j) <= 1
}

private func typoMatch(needle, haystack: const [..] FoldedRune)->Match
{
    return wordMatch(needle, haystack, tolerateTypos: true)
}

// Scores of the three ways a query answers. A whole occurrence always ranks above the initials of
// the words, and they above characters found in order, whatever their positions.
private const WholeScore     = 10000's32
private const WordStartBonus = 1000's32
private const InitialsScore  = 8000's32
private const OrderScore     = 5000's32
private const ScatterCost    = 100's32

// Lowest score of an answer better than scattered letters: a lens that holds one of those leaves
// the scattered ones out.
internal const ClearMatchScore = 6000's32

// One character of a text, folded for comparison and placed in the bytes of its text.
private struct FoldedRune
{
    folded:    rune     // The character in lower case.
    offset:    u32      // Byte offset of the character in its text.
    size:      u32      // Number of bytes the character takes.
    wordStart: bool     // Whether a word starts at the character.
}

// Decodes `text` into folded characters, noting where each word starts.
private func foldRunes(text: string)->Array'FoldedRune
{
    var result:   #returntype
    var previous: rune
    var offset = 0'u32

    // A text holds at most one character per byte, so one allocation holds them all.
    result.reserve(text.count)
    while offset < text.count
    {
        let decoded = Utf8.decodeRune(Swag.makeSlice(text.buffer + offset, text.count - offset))
        let size    = Math.max(decoded.eat, 1)
        let c       = decoded.c

        let afterSeparator = offset == 0 or not Unicode.isLetterOrDigit(previous)
        let camelHump      = Unicode.isUpper(c) and Unicode.isLower(previous)
        if c >= 0x300 and c <= 0x36F and not result.isEmpty()
        {
            result.backPtr().size += size
            offset += size
            continue
        }

        if Unicode.isSpace(c)
        {
            if not result.isEmpty() and result.back().folded != ' ' do
                result.add(FoldedRune{' ', offset, size, false})
        }
        else
        {
            result.add(FoldedRune{foldAccent(Unicode.toLower(c)), offset, size, afterSeparator or camelHump})
        }

        previous = c
        offset   += size
    }

    if not result.isEmpty() and result.back().folded == ' ' do
        discard result.popBack()
    return result
}

private func foldAccent(c: rune)->rune
{
    switch c
    {
    case 'à', 'á', 'â', 'ã', 'ä', 'å': return 'a'
    case 'ç':                          return 'c'
    case 'è', 'é', 'ê', 'ë':           return 'e'
    case 'ì', 'í', 'î', 'ï':           return 'i'
    case 'ñ':                          return 'n'
    case 'ò', 'ó', 'ô', 'õ', 'ö':      return 'o'
    case 'ù', 'ú', 'û', 'ü':           return 'u'
    case 'ý', 'ÿ':                     return 'y'
    default:                           return c
    }
}
