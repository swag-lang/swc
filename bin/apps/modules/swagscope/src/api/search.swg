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
//
// Report the band the view itself paints over the occurrence, exactly. The application draws one
// marker around what it is given, so a band that is not the one being framed leaves two
// rectangles of different sizes over one word. Report the wording rather than the line, the row
// or the cell that carries it, so the marker is the size of what was found in every viewer.
alias SearchMatchBounds = func(*Wnd, SearchMatch, *Math.Rectangle)->bool

// Removes presentation left by the last revealed match.
alias ClearSearch = func(*Wnd)

// Collects every logical-text match owned by a viewer, and reports whether the collection is
// complete.
//
// The host starts a query with `progress` at zero and an empty array. A viewer whose text is
// produced in the background appends what it can already answer for, records where it stopped
// in `progress`, and answers false; the host then calls again, with the same query, options,
// progress and array, until the viewer answers true. A viewer that has everything at hand
// appends every match and answers true at once.
alias CollectSearchMatches = func(*Wnd, string, SearchOptions, *u64, *Array'SearchMatch)->bool

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
//
// `source` is the text as it was handed to the editor, so a byte offset in it names an authored
// line and a rune inside it. The editor is asked to turn that pair into a cursor, because word
// wrap has since split those lines and an authored index is not a display index.
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
    editor.setSelection(editor.cursorFromLogicalPosition(first.lineIndex, first.charPosInLine),
                        editor.cursorFromLogicalPosition(last.lineIndex, last.charPosInLine))
    editor.ensureCaretIsVisible(center: true)
    editor.invalidate()
}

// Reports the visible selection of a rich editor in surface coordinates.
//
// It is the band the editor fills behind the selected run, so the marker drawn around it frames
// that band instead of sitting across it.
func richEditMatchBounds(editor: *RichEditCtrl, result: *Math.Rectangle)->bool
{
    result[] = editor.selectionRect()
    return !result.isEmpty()
}

// Removes the rich-editor selection left by the last revealed match.
func clearRichEditMatch(editor: *RichEditCtrl)
{
    editor.clearSelection()
    editor.invalidate()
}

// Reports where the matched part of one cell's text is drawn, in surface coordinates.
//
// `text` is what the cell displays and `offset`/`length` the part of it that matched, so a row
// in a table, a tree and a report is marked on its wording exactly as a word in a document is.
// A whole row, which is what these viewers used to report, put a band the width of the window
// beside markers that hug five letters. The band is the height of the list's font, centered in
// the row: a row carries leading the way a line of text does.
//
// False when the row is not laid out or the range falls outside the text. The rectangle is not
// clipped to the viewport, as no reported band is: the host intersects every one of them with the
// view it is drawing over, and decides there whether to follow the result or hide the marker.
func listCellMatchBounds(list: *ListCtrl, index: u32, column: u32, text: string, offset, length: u64, result: *Math.Rectangle)->bool
{
    if offset + length > text.count do
        return false

    let slot = list.cellTextRect(index, column)
    if slot.isEmpty() do
        return false

    let font   = list.font().regular!
    let prefix = Painter.measureString(text[0 until offset], font).width
    let width  = Painter.measureString(text[offset until offset + length], font).width

    var local = Math.Rectangle{slot.x + prefix, slot.y + (slot.height - font.height) * 0.5, Math.max(width, 2), font.height}
    local.intersect(slot)
    if local.isEmpty() do
        return false

    result[] = list.listView.localToSurface(local)
    return !result.isEmpty()
}
