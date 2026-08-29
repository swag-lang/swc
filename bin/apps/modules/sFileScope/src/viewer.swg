#global internal

using Core, Gui

const ViewerBackgroundPollInterval: Time.Duration = 16'ms

// Owns one value-producing operation that must not run on the GUI thread.
//
// The worker borrows this object until `isDone` answers true. Its owner therefore exposes the
// operation through [[ViewerRetire]] and is destroyed only after `retire` succeeds.
struct(T) ViewerBackgroundLoad
{
    job:      Jobs.Job
    fileName: String
    value:    T
    error:    #null any
    load:     func(string)->T fail = undefined
    started:  bool
}

impl ViewerBackgroundLoad
{
    mtd start(fileName: string, load: func(string)->T fail)
    {
        Debug.assert(!.started)
        .fileName   = fileName
        .load       = load
        .job.lambda = func(data: #null *void)
        {
            let operation = cast(*ViewerBackgroundLoad'T) data!
            operation.value = catch operation.load(operation.fileName.toString()) as loadError
            operation.error = loadError
        }
        .job.data = me
        .started  = true
        Jobs.schedule(&.job)
    }

    mtd const isDone()->bool => .started and Jobs.isDone(&.job)

    // Publishes the loaded value and returns the captured failure message.
    mtd finish(value: *T)->String
    {
        Debug.assert(.isDone())
        Jobs.wait(&.job)
        value[] = #move .value
        let result = Errors.message(.error)
        .error   = null
        .started = false
        return result
    }

    // Reports when the borrowed worker state may be destroyed without waiting on the GUI thread.
    mtd retire()->bool
    {
        if !.started do
            return true
        if !.isDone() do
            return false
        Jobs.wait(&.job)
        .started = false
        return true
    }

    mtd opDrop()
    {
        if .started do
            Jobs.wait(&.job)
    }
}

// Options shared by file-backed and viewer-owned searches.
struct ViewerSearchOptions
{
    matchCase: bool     // Whether letter case has to match.
    wholeWord: bool     // Whether word characters may touch either side of a match.
}

// One searchable location. `major` and `minor` identify viewer-owned containers such as a PDF
// page or table cell; `offset` is a byte offset inside that container, or inside the source file
// when both container indexes are zero.
struct ViewerSearchMatch
{
    major:  u64
    minor:  u64
    offset: u64
    length: u64
}

// Reveals one exact match without loading the preceding file content.
alias ViewerRevealMatch = func(*Wnd, ViewerSearchMatch, string)->bool

// Returns the current rendered bounds of one revealed match in surface coordinates. Progressive
// viewers may answer false until the requested window has been materialized; the host polls while
// the occurrence remains current and owns all highlight presentation.
alias ViewerSearchBounds = func(*Wnd, ViewerSearchMatch, *Math.Rectangle)->bool

// Removes presentation left by the last revealed match.
alias ViewerClearSearch = func(*Wnd)

// Collects every logical-text match owned by a viewer. A null callback asks the host to scan the
// file bytes and use `revealMatch` to materialize the selected occurrence.
alias ViewerCollectMatches = func(*Wnd, string, ViewerSearchOptions, *Array'ViewerSearchMatch)

// Reports whether a view is still doing work whose result has not reached the screen.
alias ViewerIsLoading = func(*Wnd)->bool

// Reports whether unfinished work has left the viewer with no useful content to present.
alias ViewerNeedsLoadingOverlay = func(*Wnd)->bool

// Requests release of a viewer's external resources without blocking the GUI thread.
//
// Returns true once the view can be destroyed. A false result is polled by the host while the
// viewer finishes cancellable background work.
alias ViewerRetire = func(*Wnd)->bool

// Notifies the application that [[ViewerIsLoading]] may now answer differently.
alias ViewerReportLoadingChanged = func(*Wnd)

// Hands a decoder error discovered after creation back to the application that owns its presentation.
alias ViewerReportFailure = func(*Wnd, string)

// Hands format statistics that changed after creation back to the application status band.
alias ViewerReportDetails = func(*Wnd, string)

// Re-measures viewer-owned action and information content after its visible shape changes.
alias ViewerReportChromeChanged = func(*Wnd)

// Requests a neighboring file from the host when a viewer assigns meaning to that direction.
alias ViewerNavigateFile = func(*Wnd, s32)

private func mediaWholeTimeText(total: u64)->String
{
    let hours   = total / 3_600
    let minutes = total / 60 % 60
    let rest    = total % 60
    if hours do
        return Format.toString("%:%{02}:%{02}", hours, minutes, rest)
    return Format.toString("%:%{02}", total / 60, rest)
}

// Formats a media clock as m:ss, or h:mm:ss once an hour is reached.
func mediaTimeText(seconds: f64)->String
{
    return mediaWholeTimeText(cast(u64) Math.max(Math.floor(seconds), 0))
}

// Formats a total duration, rounding a non-empty final fraction up so it never reads as zero.
func mediaDurationText(seconds: f64)->String
{
    return mediaWholeTimeText(cast(u64) Math.max(Math.ceil(seconds), 0))
}

// Formats the current and total positions of a media transport.
func mediaTimeRangeText(current, duration: f64)->String
{
    return Format.toString("% / %", mediaTimeText(current), mediaDurationText(duration))
}

// What the application asks one integrated viewer to display.
struct ViewerRequest
{
    contentParent:        *Wnd = undefined                     // Parent the document view must be created under.
    commandParent:        *Wnd = undefined                     // Parent for an optional full-width viewer command group.
    fileName:             string                               // File the view has to show.
    actionParent:         *Wnd = undefined                     // Parent for compact actions shown in the host action bar.
    infoParent:           *Wnd = undefined                     // Parent for compact values shown in the host information bar.
    reportFailure:        #null ViewerReportFailure            // Reports a decoder error discovered after creation.
    reportDetails:        #null ViewerReportDetails            // Reports format statistics that changed after creation.
    reportChromeChanged:  #null ViewerReportChromeChanged      // Re-measures viewer-owned action and information content.
    reportLoadingChanged: #null ViewerReportLoadingChanged     // Re-evaluates application-owned wait feedback.
    navigateFile:         #null ViewerNavigateFile             // Opens a neighboring file when this viewer owns that gesture.
}

// What one integrated viewer gives back.
//
// A successful viewer returns `view`. When decoding stops, it leaves `view` null and returns the
// decoder's explanation through `failureReason`; the application then owns the complete error
// surface. `actions` occupies the action bar's centre whenever search is unavailable, `info`
// extends the file-information row, and `commands` owns the optional full-width band below the
// content. A viewer leaves unused regions null. One that cannot reveal an offset leaves
// `revealMatch` null, and a view that does no progressive work leaves `isLoading` null.
struct ViewerResult
{
    view:                #null *Wnd                          // Document view the viewer owns, or null when decoding stopped.
    actions:             #null *Wnd                          // Compact centre group in the host action bar, or null.
    info:                #null *Wnd                          // Compact trailing group in the host information bar, or null.
    commands:            #null *Wnd                          // Full-width lower command group, or null.
    details:             String                              // Short format-specific summary shown by the application.
    failureReason:       String                              // Decoder explanation when `view` is null, or empty on success.
    revealMatch:         #null ViewerRevealMatch             // Reveals a byte offset, or null when not searchable.
    searchBounds:        #null ViewerSearchBounds            // Reports rendered match geometry, or null when unavailable.
    clearSearch:         #null ViewerClearSearch             // Removes the viewer-owned selection or marker.
    collectMatches:      #null ViewerCollectMatches          // Viewer-owned text indexing, or null to scan the file.
    isLoading:           #null ViewerIsLoading               // Reports unfinished visible work, or null for an immediate view.
    needsLoadingOverlay: #null ViewerNeedsLoadingOverlay     // Reports that loading currently has no useful presentation.
    retire:              #null ViewerRetire                  // Cooperatively releases resources before deferred window deletion.
}

// Creates an integrated view and reports its optional commands, details, and search callbacks.
//
// Creation runs on the GUI thread and must return promptly. A viewer never opens, probes, reads,
// decodes, or otherwise waits for external content here: it creates its presentation, starts that
// work in the background, and publishes the result from a timer. While background work borrows the
// view, `isLoading`, `needsLoadingOverlay`, and `retire` describe its lifecycle to the host.
alias ViewerCreate = func(const *ViewerRequest, *ViewerResult)

// Reports whether `match` is bounded by non-word runes in `source`.
func viewerMatchIsWholeWord(source: string, match: u64, length: u64)->bool
{
    if match
    {
        let {c, ?} = Utf8.decodeLastRune(source[0 until match])
        if Unicode.isWord(c) do
            return false
    }

    let end = match + length
    if end < @countof(source)
    {
        let {c, ?} = Utf8.decodeRune(source[end to])
        if Unicode.isWord(c) do
            return false
    }

    return true
}

// Appends every non-overlapping match in one text container.
func collectViewerTextMatches(source, query: string, options: ViewerSearchOptions, major, minor, baseOffset: u64, result: *Array'ViewerSearchMatch)
{
    if !@countof(query) do
        return

    let comparison = options.matchCase ? Utf8.ComparisonType.Latin1 : Utf8.ComparisonType.Latin1NoCase
    var from       = 0'u64
    while from < @countof(source)
    {
        let found = Utf8.indexOf(source, query, from, comparison)
        if found == Swag.U64.Max do
            break

        if !options.wholeWord or viewerMatchIsWholeWord(source, found, @countof(query)) do
            result.add({major, minor, baseOffset + found, @countof(query)})
        from = found + Math.max(@countof(query), 1)
    }
}

// Selects an exact UTF-8 byte range in a rich editor whose text came from `source`.
func highlightRichEditMatch(editor: *RichEditCtrl, source: string, start, length: u64)
{
    func cursorAt(source: string, byteOffset: u64)->RichEditCursor
    {
        var result: retval
        var scan = 0'u64
        while scan < Math.min(byteOffset, @countof(source))
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
    let last  = cursorAt(source, Math.min(start + length, @countof(source)))
    editor.setSelection(first, last)
    editor.ensureCaretIsVisible(center: true)
    editor.invalidate()
}

// Reports the visible selection of a rich editor in surface coordinates.
func richEditSearchBounds(editor: *RichEditCtrl, result: *Math.Rectangle)->bool
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

func clearRichEditSearch(editor: *RichEditCtrl)
{
    editor.clearSelection()
    editor.invalidate()
}

// Reports one list row in surface coordinates. Structured and tabular viewers still provide the
// semantic row; the application gives that geometry the same current-occurrence treatment as an
// exact glyph range.
func listRowSearchBounds(list: *ListCtrl, index: u32, result: *Math.Rectangle)->bool
{
    if index >= list.lineCount() do
        return false
    let view       = list.listView
    let lineHeight = list.lineHeight()
    let local      = Math.Rectangle{view.clientRect().x, cast(f32) index * lineHeight - view.scrollPos.y, view.clientRect().width, lineHeight}
    result[] = view.localToSurface(local)
    return !result.isEmpty()
}
