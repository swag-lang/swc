#global public
#global namespace Viewer

using Core, Gui

// Options shared by file-backed and plugin-owned text searches.
struct SearchOptions
{
    public
    {
        matchCase:         bool                     // Whether letter case has to match.
        wholeWord:         bool                     // Whether word characters may touch either side of a match.
        regularExpression: bool                     // Whether the query is a regular expression rather than literal text.
        expression:        #null *Parser.RegExp     // Compiled expression borrowed for one synchronous collection.
    }
}

// Identifies one searchable location owned by a viewer.
//
// `major` and `minor` identify containers such as a PDF page or table cell. `offset` is a byte
// offset inside that container, or inside the source file when both container indexes are zero.
struct SearchMatch
{
    public
    {
        major:  u64     // Zero-based outer container index, such as a page or row.
        minor:  u64     // Zero-based inner container index, such as a span or cell.
        offset: u64     // Byte offset within the container, or within the file for zero indexes.
        length: u64     // Nonzero matched length in bytes.
    }
}

// Reveals one exact match without loading the preceding file content.
alias RevealSearchMatch = func(*Wnd, SearchMatch, string)->bool

// Returns the rendered bounds of one revealed match in surface coordinates.
alias SearchMatchBounds = func(*Wnd, SearchMatch, *Math.Rectangle)->bool

// Removes presentation left by the last revealed match.
alias ClearSearch = func(*Wnd)

// Collects every logical-text match owned by a viewer.
alias CollectSearchMatches = func(*Wnd, string, SearchOptions, *Array'SearchMatch)

// Applies the shared query as a live visibility filter owned by the viewer.
alias ApplySearchFilter = func(*Wnd, string, SearchOptions)

// Describes viewer-specific wording and option visibility for the shared search field.
struct SearchPresentation
{
    public
    {
        placeholder:       String          // Short query hint shown while the search field is empty.
        toolTip:           String          // Longer syntax help owned by the presentation value.
        filterPlaceholder: String          // Short hint used when this viewer is in filter mode.
        filterToolTip:     String          // Longer filter help owned by the presentation value.
        useTextOptions:    bool = true     // Whether case, whole-word, and regular-expression options apply.
        canFilter:         bool            // Whether the shared field can switch from finding to filtering.
    }
}

// Describes the active viewer's search syntax in the application's current language.
alias DescribeSearch = func(*Wnd, *SearchPresentation)

// Describes a streamed-file search prepared by a viewer.
struct SearchPlan
{
    public
    {
        span:  u64        // Greatest number of source bytes one match can cover.
        error: String     // Explanation shown beside the shared field when the query is invalid.
    }
}

// Parses a viewer-specific query before the host opens and scans the file.
alias PrepareSearch = func(*Wnd, string, *SearchPlan)->EditBoxCheckResult

// Collects candidates inside one host-owned streamed source window.
alias CollectFileMatches = func(*Wnd, string, u64, *Array'SearchMatch)

// Lets a viewer borrow the host-owned result index while the current query remains active.
alias UseSearchMatches = func(*Wnd, #null *Array'SearchMatch)

// Configures the optional search behavior of one attached document view.
//
// A null `collectMatches` asks the host to scan file bytes. The view and every callback remain
// owned by the plugin; the host calls them only while the attached view is alive.
struct SearchApi
{
    public
    {
        revealMatch:        #null RevealSearchMatch        // Makes one host-selected match visible.
        matchBounds:        #null SearchMatchBounds        // Reports the revealed match geometry.
        clear:              #null ClearSearch              // Removes the current match presentation.
        collectMatches:     #null CollectSearchMatches     // Replaces host file scanning with viewer search.
        filter:             #null ApplySearchFilter        // Reuses the shared query as a viewer-owned visibility filter.
        describe:           #null DescribeSearch           // Supplies localized query presentation.
        prepare:            #null PrepareSearch            // Validates a streamed-file query before scanning.
        collectFileMatches: #null CollectFileMatches       // Scans one host-owned streamed source window.
        useMatches:         #null UseSearchMatches         // Borrows the active host result index.
    }
}

// Reports whether `match` is bounded by non-word runes in `source`.
func isWholeWordMatch(source: string, match: u64, length: u64)->bool
{
    if match
    {
        let {c, ?} = Utf8.decodeLastRune(source[0 until match])
        if Unicode.isWord(c) do
            return false
    }

    let end = match + length
    if end < source.count
    {
        let {c, ?} = Utf8.decodeRune(source[end to])
        if Unicode.isWord(c) do
            return false
    }

    return true
}

// Appends every non-overlapping match in one text container.
func collectTextMatches(source, query: string, options: SearchOptions, major, minor, baseOffset: u64, result: *Array'SearchMatch)
{
    if !query.count do
        return

    if options.regularExpression
    {
        var localExpression: Parser.RegExp
        var expression = options.expression
        if !expression
        {
            catch localExpression.compile(query, ignoreCase: !options.matchCase) as expressionError
            if expressionError != null do
                return
            expression = &localExpression
        }

        let sourceData = source.buffer
        for value in expression!.grepAll(source)
        {
            // Zero-width expressions are meaningful to a parser, but there is no document span
            // for a viewer to outline or select.
            if !value.count do
                continue
            let found = cast(u64) cast(s64) (value.buffer - sourceData)
            if !options.wholeWord or isWholeWordMatch(source, found, value.count) do
                result.add({major, minor, baseOffset + found, value.count})
        }

        return
    }

    let comparison = options.matchCase ? Utf8.ComparisonType.Latin1 : Utf8.ComparisonType.Latin1NoCase
    var from       = 0'u64
    while from < source.count
    {
        let found = Utf8.indexOf(source, query, from, comparison)
        if found == Swag.U64.Max do
            break

        if !options.wholeWord or isWholeWordMatch(source, found, query.count) do
            result.add({major, minor, baseOffset + found, query.count})
        from = found + Math.max(query.count, 1)
    }
}

// Reports whether a non-empty regular-expression query can be compiled.
func patternIsValid(query: string, options: SearchOptions)->bool
{
    if !options.regularExpression or !query.count do
        return true
    discard catch Parser.RegExp.create(query, ignoreCase: !options.matchCase) as expressionError
    return expressionError == null
}

// Selects an exact UTF-8 byte range in a rich editor whose text came from `source`.
func highlightRichEditMatch(editor: *RichEditCtrl, source: string, start, length: u64)
{
    func cursorAt(source: string, byteOffset: u64)->RichEditCursor
    {
        var result: retval
        var scan = 0'u64
        while scan < Math.min(byteOffset, source.count)
        {
            let {c, eat} = Utf8.decodeRune(source[scan to])
            if !eat do
                break
            scan += eat
            if c == '\r' do
                continue
            if c == '\n'
            {
                result.lineIndex     += 1
                result.charPosInLine = 0
            }
            else do
                result.charPosInLine += 1
        }

        return result
    }

    let first = cursorAt(source, start)
    let last  = cursorAt(source, Math.min(start + length, source.count))
    editor.setSelection(first, last)
    editor.ensureCaretIsVisible(center: true)
    editor.invalidate()
}

// Reports the visible selection of a rich editor in surface coordinates.
func richEditMatchBounds(editor: *RichEditCtrl, result: *Math.Rectangle)->bool
{
    if editor.isSelectionEmpty() do
        return false

    let first  = editor.selectionStart()
    let last   = editor.selectionEnd()
    let height = editor.xGlyphSize().y
    let start  = editor.cursorDisplayPosition(first)
    let end    = editor.cursorDisplayPosition(last)
    let view   = editor.view

    var local: Math.Rectangle
    if first.lineIndex == last.lineIndex
    {
        local = {start.x, start.y - height, Math.max(end.x - start.x, 2), height}
    }
    else
    {
        local = {view.clientRect().x, start.y - height, view.clientRect().width, Math.max(end.y - start.y + height, height)}
    }

    local.offset(-view.scrollPos.x, -view.scrollPos.y)
    result[] = view.localToSurface(local)
    return !result.isEmpty()
}

// Removes the rich-editor selection left by the last revealed match.
func clearRichEditMatch(editor: *RichEditCtrl)
{
    editor.clearSelection()
    editor.invalidate()
}

// Reports one list row in surface coordinates.
//
// Structured and tabular viewers still provide the semantic row; the application gives that
// geometry the same current-occurrence treatment as an exact glyph range.
func listRowBounds(list: *ListCtrl, index: u32, result: *Math.Rectangle)->bool
{
    if index >= list.lineCount() do
        return false
    let view       = list.listView
    let lineHeight = list.lineHeight()
    let local      = Math.Rectangle{view.clientRect().x, cast(f32) index * lineHeight - view.scrollPos.y, view.clientRect().width, lineHeight}
    result[] = view.localToSurface(local)
    return !result.isEmpty()
}
