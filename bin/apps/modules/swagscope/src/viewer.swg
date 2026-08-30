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

alias ViewerSearchOptions        = FileViewer.SearchOptions
alias ViewerSearchMatch          = FileViewer.SearchMatch
alias ViewerRevealMatch          = FileViewer.RevealSearchMatch
alias ViewerSearchBounds         = FileViewer.SearchMatchBounds
alias ViewerClearSearch          = FileViewer.ClearSearch
alias ViewerCollectMatches       = FileViewer.CollectSearchMatches
alias ViewerSearchPresentation   = FileViewer.SearchPresentation
alias ViewerDescribeSearch       = FileViewer.DescribeSearch
alias ViewerSearchPlan           = FileViewer.SearchPlan
alias ViewerPrepareSearch        = FileViewer.PrepareSearch
alias ViewerCollectFileMatches   = FileViewer.CollectFileMatches
alias ViewerUseSearchMatches     = FileViewer.UseSearchMatches
alias ViewerIsLoading            = FileViewer.IsLoading
alias ViewerNeedsLoadingOverlay  = FileViewer.NeedsLoadingOverlay
alias ViewerRetire               = FileViewer.Retire
alias ViewerReportLoadingChanged = FileViewer.ReportLoadingChanged
alias ViewerReportFailure        = FileViewer.ReportFailure
alias ViewerReportDetails        = FileViewer.ReportDetails
alias ViewerReportChromeChanged  = FileViewer.ReportChromeChanged
alias ViewerNavigateFile         = FileViewer.NavigateFile

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

// One plugin instance and every contribution the host owns with it.
struct ViewerSession
{
    view:                #null *Wnd
    actions:             #null *Wnd
    info:                #null *Wnd
    commands:            #null *Wnd
    sidePanelHost:       #null *Wnd
    sidePanel:           #null *Wnd
    sidePanelButton:     #null *IconButton
    revealMatch:         #null ViewerRevealMatch
    searchBounds:        #null ViewerSearchBounds
    clearSearch:         #null ViewerClearSearch
    collectMatches:      #null ViewerCollectMatches
    describeSearch:      #null ViewerDescribeSearch
    prepareSearch:       #null ViewerPrepareSearch
    collectFileMatches:  #null ViewerCollectFileMatches
    useSearchMatches:    #null ViewerUseSearchMatches
    isLoading:           #null ViewerIsLoading
    needsLoadingOverlay: #null ViewerNeedsLoadingOverlay
    retire:              #null ViewerRetire
    details:             String
    failureReason:       String
}

impl ViewerSession
{
    // Requests resource release and reports whether GUI destruction may proceed.
    mtd retireView()->bool
    {
        if !.view or !.retire do
            return true
        if !.retire!(.view!) do
            return false
        .retire = null
        return true
    }
}

// Implements the shared plugin API for one Swag Scope viewer instance.
struct ViewerPluginHost
{
    session:         *ViewerSession = undefined
    documentParent:  *Wnd           = undefined
    sidePanelParent: *Wnd           = undefined
    actionParent:    *Wnd           = undefined
    infoParent:      *Wnd           = undefined
    commandParent:   *Wnd           = undefined
    sourceFileName:  string
    pluginIcon:      Icon
    hostServices:    FileViewer.HostServices
}

private impl ViewerPluginHost
{
    mtd createGroup(parent: *Wnd, width: f32)->*Wnd
    {
        let result = Wnd.create'Wnd(parent, {0, 0, width, 36})
        result.backgroundStyle = .Transparent
        return result
    }
}

impl FileViewer.Host for ViewerPluginHost
{
    mtd impl application()->*Application        => .documentParent.app()
    mtd impl contentParent()->*Wnd              => .documentParent
    mtd impl fileName()->string                 => .sourceFileName
    mtd impl icon()->Icon                       => .pluginIcon
    mtd impl services()->FileViewer.HostServices => .hostServices

    mtd impl createActionGroup(width: f32)->*Wnd
    {
        Debug.assert(.session.actions == null)
        .session.actions = .createGroup(.actionParent, width)
        return .session.actions!
    }

    mtd impl createInfoGroup(width: f32)->*Wnd
    {
        Debug.assert(.session.info == null)
        .session.info = .createGroup(.infoParent, width)
        .session.info!.style.addStyleSheetColors("label_TextLight $label_TextFaint")
        .session.info!.computeStyle()
        return .session.info!
    }

    mtd impl createCommandGroup(width: f32)->*Wnd
    {
        Debug.assert(.session.commands == null)
        .session.commands = .createGroup(.commandParent, width)
        return .session.commands!
    }

    mtd impl createSidePanel(width: f32, icon: Icon, toolTip: string)->FileViewer.SidePanel
    {
        Debug.assert(.session.sidePanelHost == null)
        Debug.assert(width > 0)

        let gutter = .sidePanelParent.themeMetrics().panel_GutterSize
        with .session.sidePanelHost = Wnd.create'Wnd(.sidePanelParent, {0, 0, width + gutter, 0})
        {
            .dockStyle       = .Right
            .backgroundStyle = .ToolBar

            // The information lane already owns the seam above. The viewer bar owns the chrome
            // below, so the side panel meets it directly instead of accumulating a second edge.
            .padding = {0, 0, gutter, 0}
            .hide()
        }

        with .session.sidePanel = Wnd.create'Wnd(.session.sidePanelHost!)
        {
            .dockStyle       = .Center
            .backgroundStyle = .Panel
        }

        let panelParent = .sidePanelParent
        let panelHost   = .session.sidePanelHost!
        let actionSize  = themeActionButtonSize(.infoParent.themeMetrics())
        with .session.sidePanelButton = IconButton.create(.infoParent, icon, {0, 0, actionSize, actionSize}, flags: .Toggle)
        {
            .toolTip = toolTip
            .setCheckIndicator(.Frame)
            .hide()
            .sigCheckedChanged += func|parent = panelParent, panel = panelHost|(button)
            {
                panel.show(button.isChecked)
                parent.applyLayout()
                parent.invalidate()
            }
        }

        return {.session.sidePanel!, .session.sidePanelButton!}
    }

    mtd impl attachView(view: *Wnd)
    {
        Debug.assert(.session.view == null)
        .session.view = view
    }

    mtd impl setDetails(details: string)
    {
        .session.details = details
    }

    mtd impl reject(reason: string)
    {
        Debug.assert(.session.view == null)
        .session.actions?.destroy()
        .session.info?.destroy()
        .session.commands?.destroy()
        .session.sidePanelButton?.destroy()
        .session.sidePanelHost?.destroy()
        .session.actions         = null
        .session.info            = null
        .session.commands        = null
        .session.sidePanelHost   = null
        .session.sidePanel       = null
        .session.sidePanelButton = null
        .session.failureReason   = reason
    }

    mtd impl setSearch(api: FileViewer.SearchApi)
    {
        .session.revealMatch        = api.revealMatch
        .session.searchBounds       = api.matchBounds
        .session.clearSearch        = api.clear
        .session.collectMatches     = api.collectMatches
        .session.describeSearch     = api.describe
        .session.prepareSearch      = api.prepare
        .session.collectFileMatches = api.collectFileMatches
        .session.useSearchMatches   = api.useMatches
    }

    mtd impl setLifecycle(api: FileViewer.LifecycleApi)
    {
        .session.isLoading           = api.isLoading
        .session.needsLoadingOverlay = api.needsLoadingOverlay
        .session.retire              = api.retire
    }
}

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
    if end < source.count
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
            if !options.wholeWord or viewerMatchIsWholeWord(source, found, value.count) do
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

        if !options.wholeWord or viewerMatchIsWholeWord(source, found, query.count) do
            result.add({major, minor, baseOffset + found, query.count})
        from = found + Math.max(query.count, 1)
    }
}

// Reports whether a non-empty regular-expression query can be compiled.
func viewerSearchPatternIsValid(query: string, options: ViewerSearchOptions)->bool
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
