#global public
#global namespace Text

using Swag

// Selects how a literal query relates to the candidate text.
public enum NameMatchMode
{
    Contains       // Matches anywhere in the candidate.
    StartsWith     // Matches only at the start of the candidate.
    Exact          // Requires the candidate and query to be equal.
}

// Options shared by queries that match text in names or other short labels.
public struct NameMatchOptions
{
    public
    {
        mode:              NameMatchMode       = .Contains         // Relationship between query and candidate.
        matchCase:         bool                                    // Whether letter case must match.
        wholeWord:         bool                                    // Whether both ends of a match must be word boundaries.
        regularExpression: bool                                    // Whether the query is a regular expression.
        comparisonType:    Utf8.ComparisonType = .Latin1NoCase     // Case folding used for literal matches.
    }
}

// One non-empty occurrence in UTF-8 text, measured in bytes.
public struct NameSpan
{
    public
    {
        start:  u64     // Byte offset of the first matched byte.
        length: u64     // Number of matched bytes.
    }
}

// Compares names for a consumer-defined ordering, returning negative, zero or positive.
public alias NameCompare = func||(const [..] u8, const [..] u8)->s32

// Selects the shared textual ordering for names.
public struct NameOrderOptions
{
    public
    {
        matchCase: bool = false     // Whether letter case affects the order.
        natural:   bool = true      // Whether ASCII digit runs compare by numeric value.
        compare:   NameCompare?     // Overrides the built-in order for consumer-specific or typed text.
    }
}

// A prepared text query that can be reused across many candidate names.
//
// Literal matching is a UTF-8 substring search using `comparisonType` when `matchCase` is false;
// setting `matchCase` selects exact case. Regular expressions use [[Core.Parser.RegExp]] and report
// malformed patterns from [[Core.Text.NameMatcher.create]]. Whole-word boundaries use Unicode
// word-character rules.
// Results are byte ranges in the original candidate; empty regular-expression matches are skipped.
//
// ```swag
// using Core
//
// let query = try Text.NameMatcher.create("file", {matchCase: false})
// if query.isMatch("Readme_File.txt") do
//     Swag.assert(query.findAll("Readme_File.txt").count == 1)
// ```
#[Swag.Opaque]
public struct NameMatcher
{
    private
    {
        query:              String
        options:            NameMatchOptions
        expression:         Parser.RegExp
        borrowedExpression: *Parser.RegExp?
    }
}

public impl NameMatcher
{
    // Prepares a query for repeated matching; fails when a regular expression is invalid.
    //
    // `expression` can reuse a compiled regular expression owned by the caller. The caller keeps it
    // alive and unchanged until the matcher is no longer used, and compiles it with the same case
    // behavior selected by `options`.
    func create(query: string, options: NameMatchOptions = {}, expression: *Parser.RegExp? = null)->NameMatcher fail
    {
        var result: #returntype
        result.query   = query
        result.options = options
        if options.regularExpression
        {
            if expression do
                result.borrowedExpression = expression
            else do
                try result.expression.compile(query, ignoreCase: not options.matchCase)
        }

        return result
    }

    // Returns whether the query has at least one non-empty match in `candidate`.
    mtd isMatch(candidate: string)->bool
    {
        if .query.isEmpty() do
            return false

        if .options.regularExpression
        {
            let expression = .expressionForUse()
            for span in expression.findAll(candidate) where span.end > span.start
            {
                if .options.mode == .StartsWith and span.start do
                    continue
                if .options.mode == .Exact and
                   (span.start != 0 or span.end != candidate.count) do
                    continue
                if not .options.wholeWord or isNameWordBoundary(candidate, span.start, span.end) do
                    return true
            }

            return false
        }

        let comparison = .options.matchCase ? Utf8.ComparisonType.Latin1 : .options.comparisonType
        if .options.mode == .Exact do
            return Utf8.compare(candidate, .query.toString(), comparison) == 0

        var start = 0'u64
        while start < candidate.count
        {
            let match = Utf8.indexOfMatch(candidate, .query.toString(), start, comparison)
            if not match.found do
                return false
            if .options.mode == .StartsWith and match.index do
                return false
            let end = match.index + match.length
            if not .options.wholeWord or isNameWordBoundary(candidate, match.index, end) do
                return true
            start = match.index + 1
        }

        return false
    }

    // Appends each non-overlapping, non-empty match as a byte range in `candidate`.
    mtd findAll(candidate: string)->Array'NameSpan
    {
        var result: #returntype
        if .query.isEmpty() do
            return result

        if .options.regularExpression
        {
            let expression = .expressionForUse()
            for span in expression.findAll(candidate) where span.end > span.start
            {
                if .options.mode == .StartsWith and span.start do
                    continue
                if .options.mode == .Exact and
                   (span.start != 0 or span.end != candidate.count) do
                    continue
                if not .options.wholeWord or isNameWordBoundary(candidate, span.start, span.end) do
                    result.add(NameSpan{span.start, span.end - span.start})
            }

            return result
        }

        let comparison = .options.matchCase ? Utf8.ComparisonType.Latin1 : .options.comparisonType
        if .options.mode == .Exact
        {
            if Utf8.compare(candidate, .query.toString(), comparison) == 0 do
                result.add(NameSpan{0, candidate.count})
            return result
        }

        var start = 0'u64
        while start < candidate.count
        {
            let match = Utf8.indexOfMatch(candidate, .query.toString(), start, comparison)
            if not match.found do
                break
            if .options.mode == .StartsWith and match.index do
                break
            let end = match.index + match.length
            if not .options.wholeWord or isNameWordBoundary(candidate, match.index, end) do
                result.add(NameSpan{match.index, match.length})
            start = end
        }

        return result
    }
}

private impl NameMatcher
{
    mtd expressionForUse()->*Parser.RegExp
    {
        if .borrowedExpression do
            return .borrowedExpression
        return &.expression
    }
}

// Orders names ordinally or naturally, with case-insensitive natural ordering by default.
//
// For a domain-specific order, compare the consumer's typed keys first and use this operation as
// a textual tie-breaker. This keeps dates, sizes and other typed values out of name heuristics.
func compareNames(left, right: const [..] u8, options: NameOrderOptions = {})->s32
{
    if options.compare do
        return options.compare(left, right)
    if options.natural do
        return Latin1.compareNatural(left, right, ignoreCase: not options.matchCase)
    return Utf8.compare(left, right, options.matchCase ? .Latin1 : .Latin1NoCase)
}

// Returns whether a byte range in `text` is separated from word characters on both sides.
func isWholeWordMatch(text: string, start, length: u64)->bool
{
    if start > text.count or length > text.count - start do
        return false
    return isNameWordBoundary(text, start, start + length)
}

private func isNameWordBoundary(text: string, start, end: u64)->bool
{
    if start
    {
        let {c, eat: _} = Utf8.decodeLastRune(text[until start])
        if Unicode.isWord(c) do
            return false
    }

    if end < text.count
    {
        let {c, eat: _} = Utf8.decodeRune(text[end to])
        if Unicode.isWord(c) do
            return false
    }

    return true
}
