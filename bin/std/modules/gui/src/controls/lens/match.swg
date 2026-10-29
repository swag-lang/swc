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
    var result: #returntype
    if query.count == 0
    {
        result.matched = true
        return result
    }

    let needle   = foldRunes(query)
    let haystack = foldRunes(text)
    if needle.count == 0
    {
        result.matched = true
        return result
    }

    if needle.count > haystack.count do
        return tolerateTypos ? typoMatch(needle.toSlice(), haystack.toSlice()) : result

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

    let words = wordMatch(needle.toSlice(), haystack.toSlice())
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
            return tolerateTypos ? typoMatch(needle.toSlice(), haystack.toSlice()) : Match{}

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
