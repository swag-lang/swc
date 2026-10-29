#global internal
#global namespace Viewers.Hex

using Core, Pixel, Gui

// Describes the raw byte viewer to the host.
//
// It answers for every file, so a format nothing else reads is still openable.
func viewerPlugin()->Viewer.Plugin
{
    with var result: #returntype
    {
        .key          = "hex"
        .staticName   = "Hexadecimal"
        .attach       = &registerTexts
        .iconAtlas    = viewerIcons()
        .iconIndex    = cast(s32, ViewerIcons.Hex)
        .create       = &createViewer
        .smokeFixture = "viewer.hex"
        .addSelectors("*")
    }

    return result
}

private
{
    const RowWidthCount = 5'u32

    // The page: the air before the grid's offsets on a wide window, the height of the tabs over
    // the grid, and the floating inspector — its width, its distance from the window's edges, and
    // the narrowest window that leaves the grid sixteen bytes beside it.
    const PageInset      = 84.0
    const TabsHeight     = 48.0
    const InspectorWidth = 300.0
    const InspectorGap   = 24.0
    const InspectorTop   = 4.0
    const WideWidth      = 1040.0

    // Fields of one structure the inspector lists at most, around the one the caret stands on.
    const FieldLimit = 8'u64
}

// What the background load hands to the view: the file, its first window resident, and what the
// binary readers recognized in it.
struct Loaded
{
    document:  Document
    structure: Structure
}

// Opens `fileName`, makes its first window resident and reads its structure, outside the GUI thread.
private func loadDocument(fileName: string)->Loaded fail
{
    var result: #returntype
    if not result.document.open(fileName) do
        fail InvalidFormatError{Errors.mkString(result.document.failureReason)}
    let resident = Math.min(result.document.fileSize, WindowSize)
    if resident and not result.document.ensure(0, resident) do
        fail InvalidFormatError{Errors.mkString(result.document.failureReason)}

    result.structure = Structure.read(fileName)
    return result
}

// Returns a decimal number with its thousands set apart, as the inspector prints a reading; any
// other text, such as a hexadecimal or a float, is returned as it is.
func groupThousands(text: string)->String
{
    let digits = (text.count and text[0] == '-') ? text.count - 1 : text.count
    for index in text.count - digits until text.count where not Latin1.isDigit(text[index]) do
        return text

    var result: #returntype
    for byte, at in text
    {
        let left = text.count - at
        if at > text.count - digits and left % 3 == 0 do
            result += " "
        result += cast(rune, byte)
    }

    return result
}

// Reads `bytes` as one unsigned scalar, in the byte order `bigEndian` names.
func readScalar(bytes: const [..] u8, bigEndian: bool)->u64
{
    var result = 0'u64
    for index in bytes.count
    {
        let position = bigEndian ? index : bytes.count - 1 - index
        result = (result << 8) | bytes[position]
    }

    return result
}

// Hexadecimal view of any file, whatever its size.
//
// The view owns the grid the bytes are read in and the compact command group the host places in
// its action bar. Everything below streams — no part of this view ever holds more than one window
// of the file.
struct Panel
{
    using wnd: Wnd

    late
    {
        commands:       *Wnd
        analysisButton: *IconButton
        optionsButton:  *IconButton
        analysisView:   *AnalysisView
        grid:           *GridView
        tabs:           *StructureTabs
        inspector:      *FloatingPanel
        inspectorView:  *InspectorView
    }

    zoomLabel: *IconButton?
    built:     bool     // Whether every part the page places exists.

    // How the bytes are laid out and read, as the options chose it.
    rowWidthIndex:   u32      // Zero fits the window; otherwise 8, 16, 32 or 64 bytes per row.
    valueWidthIndex: u32      // One, two, four or eight bytes per value.
    formatIndex:     u32      // Hexadecimal, unsigned, signed, or float for the wide values.
    bigEndian:       bool     // Whether multi-byte values read their most significant byte first.

    searchPattern: SearchPattern
    analysis:      AnalysisOperation
    analysisTimer: *Timer?     // Refreshes the progress of a running analysis.
    fileName:      String
    details:       String
    structure:     Structure     // What the binary readers recognized; the tabs and the inspector read it.
    load:          Viewer.BackgroundLoad'Loaded
    services:      Viewer.HostServices
    failureReason: String
}

private impl IWnd for Panel
{
    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer != .analysisTimer
        {
            evt.accepted = false
            return
        }

        .analysisView.setProgress(.analysis.progress())
    }

    mtd impl onTaskEvent(evt: *TaskEvent)
    {
        if .analysis.claim(evt)
        {
            .stopTimer(&.analysisTimer)
            var result = .analysis.finish()
            .analysisView.publish(&result)
            .analysisButton.enable(.grid.doc.fileSize != 0)
            return
        }

        if not .load.claim(evt)
        {
            evt.accepted = false
            return
        }

        var loaded: Loaded
        .failureReason = .load.finish(&loaded)
        if not .failureReason.isEmpty()
        {
            .services.failed(me, .failureReason)
            return
        }

        .grid.exchangeDocument(&loaded.document)
        .grid.doc.reportFailure = func|view = me|(reason) { view.services.failed(view, reason) }

        // A recognized format says in which order its numbers are written, so the values read that
        // way from the start.
        .structure = #move loaded.structure
        .tabs.setStructure(&.structure)
        if not .structure.formatName.isEmpty() do
            .setBigEndian(.structure.bigEndian)

        .layoutPage()
        .applyLayout()
        .grid.refreshLayout()
        .refreshInspector()
        .analysisButton.enable(.grid.doc.fileSize != 0)
        .setInitialFocus(.grid)
        .services.loadingChanged(me)
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged do
            .retranslate()
        else do
            evt.accepted = false
    }

    mtd impl onResizeEvent(_: *ResizeEvent)
    {
        // The panel is sized while it is created, before the parts it places exist.
        if .built do
            .layoutPage()
    }
}

impl Panel
{
    // Stops the background load and analysis, and reports whether the view can be destroyed.
    //
    // A false result means a worker still borrows the view; the host polls again.
    mtd retire()->bool
    {
        if not .load.retire() or not .analysis.retire() do
            return false
        .stopTimer(&.analysisTimer)
        return true
    }

    private mtd analysisRange()->{range: AnalysisRange, selection: bool}
    {
        var result: #returntype
        result.selection = .grid.selectionLength() > 1
        result.range     = result.selection ?
                           AnalysisRange{.grid.selectionStart(), .grid.selectionLength()} :
                           AnalysisRange{0, .grid.doc.fileSize}
        return result
    }

    // Shows the analysis panel and analyzes the selection, or the whole file when one byte is selected.
    //
    // An analysis already running keeps going; the panel only shows it again.
    mtd startAnalysis()
    {
        if .analysis.started
        {
            .analysisView.show()
            .applyLayout()
            return
        }

        if not .grid.doc.fileSize do
            return
        let target = .analysisRange()
        .startAnalysisRange(target.range, target.selection)
    }

    private mtd startAnalysisRange(range: AnalysisRange, selection: bool)
    {
        .analysisView.show()
        .analysisView.begin(range, selection, .grid.offsetDigits)
        .applyLayout()
        .analysis.start(.fileName, range, me)
        .analysisTimer = .addTimer(Viewer.BackgroundPollInterval)
    }

    // Hides the analysis panel and cancels a running analysis.
    //
    // A checked host toggle is unchecked first, and its signal comes back here, so the toggle and
    // the panel never disagree.
    mtd closeAnalysis()
    {
        if .analysisButton.isChecked
        {
            .analysisButton.setChecked(false)
            .analysisButton.sigCheckedChanged.call(.analysisButton)
            return
        }

        if .analysis.started
        {
            .analysis.cancel()
            .analysisButton.enable(false)
        }

        .analysisView.hide()
        .applyLayout()
        .grid.setFocus()
    }

    // The grouping each entry of the width and format menus selects: one row per width, one column
    // per format (hexadecimal, unsigned, signed, float). The two narrow widths offer no float, so
    // their last column falls back to hexadecimal.
    const Groupings: [4, 4] Grouping = [[.Bytes, .Unsigned8, .Signed8, .Bytes],
                                        [.Hex16, .Unsigned16, .Signed16, .Hex16],
                                        [.Hex32, .Unsigned32, .Signed32, .Float32],
                                        [.Hex64, .Unsigned64, .Signed64, .Float64]]

    mtd selectedGrouping()->Grouping => Groupings[.valueWidthIndex, .formatIndex]

    // Reports how many representations the selected value width offers: the two narrow widths have no float.
    mtd formatCount()->u32 => .valueWidthIndex >= 2 ? 4 : 3

    // Reads `index` bytes at a time: one, two, four or eight.
    mtd setValueWidth(index: u32)
    {
        Swag.assert(index < 4)
        .valueWidthIndex = index
        if .formatIndex >= .formatCount() do
            .formatIndex = 0
        .grid.setGrouping(.selectedGrouping())
    }

    // Spells each value as hexadecimal, unsigned, signed or, for the wide values, float.
    mtd setFormat(index: u32)
    {
        Swag.assert(index < .formatCount())
        .formatIndex = index
        .grid.setGrouping(.selectedGrouping())
    }

    mtd setBigEndian(bigEndian: bool)
    {
        .bigEndian = bigEndian
        .grid.setBigEndian(bigEndian)
    }

    // Lays the bytes out to fit the window at index zero, or eight times two to the `index - 1` per row.
    mtd setRowWidth(index: u32)
    {
        Swag.assert(index < RowWidthCount)
        .rowWidthIndex = index
        if not index do
            .grid.setBytesPerRow(0, true)
        else do
            .grid.setBytesPerRow(4'u64 << index, false)
    }

    // Rebuilds what follows the language, keeping every choice, then republishes the details.
    mtd retranslate()
    {
        .optionsButton.toolTip  = appStrings().ui_Options
        .analysisButton.toolTip = texts().ui_AnalysisTip
        .analysisView.retranslate()
        .grid.invalidate()
        .refreshInspector()
    }

    // Opens how the bytes are laid out and read: row width, value width, representation, byte order.
    // Gives the lens the options and the zoom of the byte view.
    mtd describeLens(entries: *Viewer.LensEntries)
    {
        entries.add(appStrings().cmd_Options, func|view = me|() { view.showOptions() })
        entries.add(appStrings().cmd_ZoomMenu, func|view = me|() { view.showZoomMenu() })
    }

    mtd showOptions()
    {
        let sheet = OptionSheet.View.create(.optionsButton, func|view = me|(page) { view.describeOptions(page) }, owner: me)
        sheet.doModal(.optionsButton, autoDestroy: true)
    }

    mtd describeOptions(page: *OptionSheet.Page)
    {
        let strings = texts()
        page.addLink(strings.ui_RowWidth, rowWidthName(.rowWidthIndex), func|view = me|(rows)
        {
            for index in RowWidthCount do
                rows.addChoice(rowWidthName(index), index == view.rowWidthIndex, func|view, index|() { view.setRowWidth(index) })
        })

        page.addLink(strings.ui_ValueWidth, valueWidthName(.valueWidthIndex), func|view = me|(widths)
        {
            for index in 4'u32 do
                widths.addChoice(valueWidthName(index), index == view.valueWidthIndex, func|view, index|() { view.setValueWidth(index) })
        })

        page.addLink(strings.ui_Representation, formatName(.formatIndex), func|view = me|(formats)
        {
            for index in view.formatCount() do
                formats.addChoice(formatName(index), index == view.formatIndex, func|view, index|() { view.setFormat(index) })
        })

        page.addLink(strings.ui_ByteOrder, .bigEndian ? strings.ui_EndianBig : strings.ui_EndianLittle, func|view = me|(orders)
        {
            orders.addChoice(texts().ui_EndianLittle, not view.bigEndian, func|view|() { view.setBigEndian(false) })
            orders.addChoice(texts().ui_EndianBig, view.bigEndian, func|view|() { view.setBigEndian(true) })
        })
    }

    private mtd offsetText(offset: u64)->String => formatDigits(offset, .grid.offsetDigits)

    // Returns the zoom in use, read back from the font size of the grid.
    private mtd zoomPercent()->u32
    {
        let base = .themeMetrics().defaultFixedFontSize
        return cast(u32, Math.round(cast(f32, .grid.fontSize) * 100 / cast(f32, base)))
    }

    private mtd refreshZoom() => .zoomLabel?.setText(Viewer.zoomText(.zoomPercent()))

    // Lets the user pick a zoom and applies it as the grid's font size relative to the theme's
    // fixed font size; 100% restores the default.
    private mtd showZoomMenu()
    {
        if not .zoomLabel do
            return

        let percent = Viewer.pickZoom(me, .zoomLabel, .zoomPercent())
        if percent == 100
        {
            .grid.resetFontSize()
        }
        elif percent
        {
            let base = .themeMetrics().defaultFixedFontSize
            .grid.setFontSize(cast(u32, Math.max(Math.round(cast(f32, base) * cast(f32, percent) / 100), 1)))
        }
    }

    // Returns the short tag of the current value grouping, such as `x16` or `s32`.
    private mtd activeValueTag()->string
    {
        switch #complete .grid.grouping
        {
        case .Bytes:      return "u8"
        case .Hex16:      return "x16"
        case .Hex32:      return "x32"
        case .Hex64:      return "x64"
        case .Unsigned8:  return "u8"
        case .Unsigned16: return "u16"
        case .Unsigned32: return "u32"
        case .Unsigned64: return "u64"
        case .Signed8:    return "s8"
        case .Signed16:   return "s16"
        case .Signed32:   return "s32"
        case .Signed64:   return "s64"
        case .Float32:    return "f32"
        case .Float64:    return "f64"
        }
    }

    // Returns the byte order a multi-byte value is read in: the format's when a reader recognized
    // it, the one the options chose otherwise.
    private mtd readingBigEndian()->bool => .structure.formatName.isEmpty() ? .grid.bigEndian : .structure.bigEndian

    // Places the page: the grid on the reading edge with the tabs over it, and the inspector
    // floating at the right when the window leaves the grid its sixteen bytes beside it.
    mtd layoutPage()
    {
        let width = .position.width
        let wide  = width >= WideWidth
        let inset = wide ? PageInset : 0

        .tabs.left = inset + ViewInset
        .grid.scroll.margin = {inset, 0, wide ? InspectorWidth + 2 * InspectorGap : 0, 0}
        .inspector.show(wide and .grid.doc.fileSize != 0)
        if wide do
            .inspector.setPosition({width - InspectorWidth - InspectorGap, InspectorTop, InspectorWidth, .inspectorView.contentHeight()})
    }

    // Selects the bytes of the structure behind tab `index`, the caret on its first byte.
    mtd selectStructure(index: u64)
    {
        let tab = &.structure.tabs[index]
        .grid.selectRange(tab.offset, tab.length)
        .grid.setFocus()
    }

    // Shows what the caret stands on: the floating inspector, the tab of its structure, and the
    // reading line under the grid.
    mtd refreshInspector()
    {
        .tabs.follow(.grid.caret)
        .refreshDetails()

        with let view = .inspectorView
        {
            .headline.clear()
            .caption.clear()
            .readings.clear()
            .fields.clear()
        }

        defer
        {
            .layoutPage()
            .inspectorView.invalidate()
        }

        if not .grid.doc.fileSize do
            return
        let caret     = .grid.caret
        let bytes     = .grid.doc.read(caret, Math.min(8'u64, .grid.doc.fileSize - caret))
        let bigEndian = .readingBigEndian()
        if bytes.isEmpty() do
            return

        .describeValue(caret, bigEndian)
        .describeReadings(bytes.toSlice(), bigEndian)
        .describeFields(caret)
    }

    // Writes the value under the caret in large type, and what it was read as: the field of the
    // structure that holds the caret, or the value the grid shows there.
    private mtd describeValue(caret: u64, bigEndian: bool)
    {
        let view  = .inspectorView
        let order = bigEndian ? "BE" : "LE"
        let field = .structure.fieldAt(caret)
        if field != Swag.U64.Max
        {
            let row   = &.structure.report.rows[field]
            let bytes = .grid.doc.read(row.offset, row.length)
            if bytes.count == row.length
            {
                let kind = row.length == 1 ? String.from("u8") : Format.toString("u% %", row.length * 8, order)
                view.headline = groupThousands(Format.toString("%", readScalar(bytes.toSlice(), bigEndian)))
                view.caption  = Format.toString(texts().ui_InspectorAt, kind, .offsetText(row.offset))
                return
            }
        }

        // A byte is read as a number here: the grid already shows its hexadecimal digits.
        let start    = .grid.groupStart(caret)
        let size     = .grid.valueSize()
        let kind     = size == 1 ? String.from(.activeValueTag()) : Format.toString("% %", .activeValueTag(), order)
        let bytes    = .grid.doc.read(start, size)
        let grouping = .grid.grouping == .Bytes ? Grouping.Unsigned8 : .grid.grouping
        if bytes.count == size do
            view.headline = groupThousands(formatScalar(grouping, readScalar(bytes.toSlice(), bigEndian)))
        else do
            view.headline = String.from("--")
        view.caption = Format.toString(texts().ui_InspectorAt, kind, .offsetText(start))
    }

    // Lists the bytes under the caret in the readings a reader reaches for most: a byte, a short,
    // a signed and an unsigned word in both orders, and a float.
    private mtd describeReadings(bytes: const [..] u8, bigEndian: bool)
    {
        let view = .inspectorView
        view.readings.add({"u8", groupThousands(Format.toString("%", bytes[0])), false})
        if bytes.count >= 2
        {
            let value = readScalar(bytes[until 2], bigEndian)
            view.readings.add({"u16", groupThousands(Format.toString("%", value)), false})
        }

        if bytes.count < 4 do
            return
        let word  = readScalar(bytes[until 4], bigEndian)
        let other = readScalar(bytes[until 4], not bigEndian)
        view.readings.add({"s32", groupThousands(Format.toString("%", signedScalar(word, 4))), false})
        view.readings.add({bigEndian ? "u32 LE" : "u32 BE", groupThousands(Format.toString("%", other)), false})
        view.readings.add({"f32", Format.toString("%{g4}", cast #bit (f32, cast(u32, word))), false})
    }

    // Lists the fields of the structure that holds the caret, the one it stands on in strong ink.
    //
    // A structure with more fields than the card holds shows the ones around the caret.
    private mtd describeFields(caret: u64)
    {
        let group = .structure.groupAt(caret)
        if group == Swag.U64.Max do
            return

        let rows  = .structure.fieldsOf(group)
        let field = .structure.fieldAt(caret)
        var first = 0'u64
        for row, index in rows where row == field and index >= FieldLimit do
            first = index + 1 - FieldLimit

        for index in first until Math.min(first + FieldLimit, rows.count)
        {
            let row = &.structure.report.rows[rows[index]]
            var line: InspectorLine
            line.label  = row.label
            line.value  = groupThousands(row.value)
            line.strong = rows[index] == field
            if not row.detail.isEmpty() do
                line.value = Format.toString("% · %", line.value, row.detail)
            .inspectorView.fields.add(#move line)
        }
    }

    // Writes the reading line under the grid: the selected range and its length, or the caret's
    // offset. The host adds the size of the file after it.
    mtd refreshDetails()
    {
        if .grid.selectionLength() > 1
        {
            .details = Format.toString(texts().ui_DetailsSelection,
                                       Format.toString("0x%{X}", .grid.selectionStart()),
                                       Format.toString("0x%{X}", .grid.selectionEnd()),
                                       groupThousands(Format.toString("%", .grid.selectionLength())))
        }
        else
        {
            .details = Format.toString("0x%", .offsetText(.grid.caret))
        }

        .services.showDetails(me, .details)
    }

    mtd describeSearch(result: *Viewer.SearchPresentation)
    {
        result.placeholder    = texts().ui_SearchPlaceholder
        result.toolTip        = texts().ui_SearchHelp
        result.useTextOptions = false
    }

    // Parses `query` in the current grouping and byte order and keeps the pattern for the search,
    // reporting a visible error for an invalid value or pattern.
    mtd prepareSearch(query: string, result: *Viewer.SearchPlan)->EditBoxCheckResult
    {
        var parsed = parseSearch(query, .grid.grouping, .grid.bigEndian)
        switch #complete parsed.state
        {
        case .Incomplete:
            return .Incomplete

        case .Invalid:
            result.error = parsed.error == .Value ? texts().ui_SearchValueError : texts().ui_SearchPatternError
            return .InvalidVisible

        case .Valid:
            .searchPattern = #move parsed.pattern
            result.span    = .searchPattern.length()
            return .Valid
        }
    }

    mtd collectSearchMatches(source: string, baseOffset: u64, result: *Array'Viewer.SearchMatch)
    {
        .searchPattern.collectMatches(source, baseOffset, result)
    }

    // Reveals the byte range the host's search matched, and reports whether `offset` lies inside the file.
    mtd revealOffset(offset, length: u64)->bool
    {
        if not .grid.revealRange(offset, length) do
            return false
        .grid.setFocus()
        return true
    }
}

impl Panel
{
    // Builds the hex panel: command bar, analysis panel, information group and byte grid. Loads the
    // file in the background.
    func create(host: Viewer.Host)->*Panel
    {
        let services = host.services()

        with let result = Wnd.create'Panel(host.contentParent(), "scope.hex")
        {
            .backgroundStyle = .View
            .services        = services
            .fileName        = host.fileName()
        }

        result.createCommandBar(host)
        result.createAnalysisPanel(host)
        result.createZoomControl(host)
        result.createTabs()
        result.createGrid()
        result.createInspector()

        result.built = true
        result.layoutPage()
        result.applyLayout()
        result.grid.refreshLayout()
        result.refreshInspector()
        result.refreshZoom()
        result.setInitialFocus(result.grid)
        result.load.start(host.fileName(), &loadDocument, result)
        return result
    }

    // Creates the command group: the options of the layout and reading of the bytes.
    private mtd createCommandBar(host: Viewer.Host)
    {
        .commands = host.createCommandGroup(themeDropDownButtonWidth(.themeMetrics()))
        with .optionsButton = Viewer.createOptionsButton(.commands)
        {
            .dockStyle  = .Left
            .sigPressed += func|view = me|(_) { view.showOptions() }
        }
    }

    // Creates the analysis side panel, and wires the host toggle that opens it.
    private mtd createAnalysisPanel(host: Viewer.Host)
    {
        let sidePanel = host.createSidePanel(AnalysisView.PanelWidth, .theme().icon(.Information, themeActionIconSize(.themeMetrics())), texts().ui_AnalysisTip)
        with .analysisButton = sidePanel.toggle
        {
            .enable(false)
            .sigCheckedChanged += func|view = me|(button)
            {
                if button.isChecked do
                    view.startAnalysis()
                else do
                    view.closeAnalysis()
            }
        }

        with .analysisView = AnalysisView.create(sidePanel.content)
        {
            .sigAnalyze += func|view = me|(_)
            {
                view.startAnalysis()
            }

            .sigCancel += func|view = me|(_)
            {
                view.analysis.cancel()
            }

            .sigClose += func|view = me|(_)
            {
                view.closeAnalysis()
            }

            .sigNavigate += func|view = me|(_, offset, length)
            {
                discard view.grid.revealRange(offset, length)
                view.refreshInspector()
                view.grid.setFocus()
            }
        }
    }

    // Creates the zoom menu at the right of the reading line.
    private mtd createZoomControl(host: Viewer.Host)
    {
        let info = host.createInfoGroup(Viewer.ZoomSlotWidth)
        with .zoomLabel = Viewer.createZoomButton(info, "scope.hex.zoom", texts().ui_ZoomMenu)
        {
            .dockStyle  = .Right
            .sigPressed += func|view = me|(_) { view.showZoomMenu() }
        }
    }

    // Creates the strip of structure tabs over the grid; picking a tab selects its bytes.
    private mtd createTabs()
    {
        with .tabs = StructureTabs.create(me)
        {
            .position.height = TabsHeight
            .hide()
            .sigPicked += func|view = me|(_, index) { view.selectStructure(index) }
        }
    }

    // Creates the byte grid, whose caret and zoom feed the inspector, the tabs and the reading line.
    private mtd createGrid()
    {
        with .grid = GridView.create(me)
        {
            .sigCaretChanged += func|view = me|(_) { view.refreshInspector() }
            .sigZoomChanged  += func|view = me|(_) { view.refreshZoom() }
        }
    }

    // Creates the inspector floating at the right of the grid.
    private mtd createInspector()
    {
        with .inspector = FloatingPanel.create(me, {0, 0, InspectorWidth, 0}, "scope.hex.inspector")
        {
            .padding = {}
            .hide()
        }

        .inspectorView = InspectorView.create(.inspector)
    }
}

// Creates the integrated hexadecimal view.
func createViewer(host: Viewer.Host)
{
    let view = Panel.create(host)

    host.attachView(view)
    host.setDetails(view.details)

    with var search: Viewer.SearchApi
    {
        .revealMatch        = func|view|(match, _) => view.revealOffset(match.offset, match.length)
        .matchBounds        = func|view|(_, bounds) => view.grid.matchBounds(bounds)
        .clear              = func|view|() => view.grid.clearSearchMatch()
        .describe           = func|view|(presentation) => view.describeSearch(presentation)
        .prepare            = func|view|(query, plan) => view.prepareSearch(query, plan)
        .collectFileMatches = func|view|(source, baseOffset, matches) => view.collectSearchMatches(source, baseOffset, matches)
        .useMatches         = func|view|(matches) => view.grid.setSearchMatches(matches)
    }

    host.setSearch(search)
    host.setLensSource(func|view|(entries) { view.describeLens(entries) })

    host.setLifecycle(Viewer.loadLifecycle(view))
}
