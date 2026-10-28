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
    const InspectorWidth = 420.0
    const RowWidthCount  = 5'u32
    const InfoWidth      = InspectorWidth + Viewer.ZoomSlotWidth
}

// Returns `value`, a `bits`-bit scalar, as `0b` and one binary digit per bit, as the inspector spells it.
private func formatBinaryScalar(value, bits: u64)->String
{
    var text: Array'u8
    text.reserve(bits + 2)
    text.add('0'u8)
    text.add('b'u8)
    for index in bits
    {
        let shift = bits - 1 - index
        text.add(value & (1'u64 << shift) ? '1'u8 : '0'u8)
    }

    return cast(string, text.toSlice())
}

// Returns `value`, a `bits`-bit scalar, as `0o` and its octal digits, as the inspector spells it.
private func formatOctalScalar(value, bits: u64)->String
{
    let digits = (bits + 2) / 3
    var text: Array'u8
    text.reserve(digits + 2)
    text.add('0'u8)
    text.add('o'u8)
    for index in digits
    {
        let shift = (digits - 1 - index) * 3
        text.add('0'u8 + cast(u8, ((value >> shift) & 7)))
    }

    return cast(string, text.toSlice())
}

// Opens `fileName` and makes its first window resident, outside the GUI thread.
private func loadDocument(fileName: string)->Document fail
{
    var result: #returntype
    if not result.open(fileName) do
        fail InvalidFormatError{Errors.mkString(result.failureReason)}
    if result.fileSize and not result.ensure(0, Math.min(result.fileSize, WindowSize)) do
        fail InvalidFormatError{Errors.mkString(result.failureReason)}
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
    }

    inspectorLabel: *Label?
    zoomLabel:      *IconButton?

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
    load:          Viewer.BackgroundLoad'Document
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

        var document: Document
        .failureReason = .load.finish(&document)
        if not .failureReason.isEmpty()
        {
            .services.failed(me, .failureReason)
            return
        }

        .grid.exchangeDocument(&document)
        .grid.doc.reportFailure = func|view = me|(reason) { view.services.failed(view, reason) }

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
        .details.clear()
        .services.showDetails(me, .details)
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

    private mtd inspectorScalar(bytes: const [..] u8, size: u64)->u64
    {
        var result = 0'u64
        for index in size
        {
            let position = .grid.bigEndian ? index : size - 1 - index
            result = (result << 8) | bytes[position]
        }

        return result
    }

    // Returns the short tag of the current value grouping, such as `x16` or `s32`.
    private mtd activeValueTag()->string
    {
        switch #complete .grid.grouping
        {
        case .Bytes:      return "x8"
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

    // Shows the caret offset, its position in the file, the selection length, and the active value in the information band.
    //
    // The compact line is glanceable; its tooltip spells the same bytes at every common scalar width.
    mtd refreshInspector()
    {
        if not .inspectorLabel do
            return
        let label = .inspectorLabel
        if not .grid.doc.fileSize
        {
            label.setText(texts().ui_InspectorEmpty)
            label.toolTip = texts().ui_InspectorEmpty
            return
        }

        let available = Math.min(8'u64, .grid.doc.fileSize - .grid.caret)
        let bytes     = .grid.doc.read(.grid.caret, available)
        if bytes.isEmpty()
        {
            label.setText(texts().ui_InspectorEmpty)
            label.toolTip = texts().ui_InspectorEmpty
            return
        }

        let offset = .offsetText(.grid.caret)
        let size   = .grid.valueSize()
        let active = size <= bytes.count ?
                     formatScalar(.grid.grouping, .inspectorScalar(bytes.toSlice(), size)) :
                     String.from("--")
        let percent = .grid.doc.fileSize > 1 ?
                      cast(f64, .grid.caret) * 100 / cast(f64, .grid.doc.fileSize - 1) :
                      0
        label.setText(Format.toString("@% · %{f1}%% · % B · % %",
                                      offset,
                                      percent,
                                      .grid.selectionLength(),
                                      .activeValueTag(),
                                      active))

        var details = Format.toString("@% (%) · %{f1}%%\n[%..%] % B\n%",
                                      offset,
                                      .grid.caret,
                                      percent,
                                      .offsetText(.grid.selectionStart()),
                                      .offsetText(.grid.selectionEnd()),
                                      .grid.selectionLength(),
                                      .grid.bigEndian ? "BE" : "LE")
        let raw8 = .inspectorScalar(bytes.toSlice(), 1)
        details += Format.toString("\nu8 % · s8 % · x8 0x%{X02} · b8 % · o8 % · bool %",
                                   raw8,
                                   signedScalar(raw8, 1),
                                   raw8,
                                   formatBinaryScalar(raw8, 8),
                                   formatOctalScalar(raw8, 8),
                                   raw8 ? "true" : "false")
        if isPrintable(cast(u8, raw8)) do
            details += Format.toString(" · ASCII '%'", cast(u8, raw8))
        if bytes.count >= 2
        {
            let raw = .inspectorScalar(bytes.toSlice(), 2)
            details += Format.toString("\nu16 % · s16 % · x16 0x%{X04} · b16 % · o16 %",
                                       raw,
                                       signedScalar(raw, 2),
                                       raw,
                                       formatBinaryScalar(raw, 16),
                                       formatOctalScalar(raw, 16))
        }

        if bytes.count >= 4
        {
            let raw = .inspectorScalar(bytes.toSlice(), 4)
            details += Format.toString("\nu32 % · s32 % · x32 0x%{X08} · b32 % · o32 % · f32 %{g9}",
                                       raw,
                                       signedScalar(raw, 4),
                                       raw,
                                       formatBinaryScalar(raw, 32),
                                       formatOctalScalar(raw, 32),
                                       cast #bit (f32, cast(u32, raw)))
        }

        if bytes.count >= 8
        {
            let raw = .inspectorScalar(bytes.toSlice(), 8)
            details += Format.toString("\nu64 % · s64 % · x64 0x%{X016} · b64 % · o64 % · f64 %{g15}",
                                       raw,
                                       signedScalar(raw, 8),
                                       raw,
                                       formatBinaryScalar(raw, 64),
                                       formatOctalScalar(raw, 64),
                                       cast #bit (f64, raw))
        }

        label.toolTip = #move details
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
        result.createInfoGroup(host)
        result.createGrid()

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

    // Creates the information group: the zoom menu and the caret inspector.
    private mtd createInfoGroup(host: Viewer.Host)
    {
        let info = host.createInfoGroup(InfoWidth)
        with .zoomLabel = Viewer.createZoomButton(info, "scope.hex.zoom", texts().ui_ZoomMenu)
        {
            .dockStyle  = .Right
            .sigPressed += func|view = me|(_) { view.showZoomMenu() }
        }

        with .inspectorLabel = Label.create(info, "", {0, 0, InspectorWidth, 32}, null, .SecondaryText | .Ellipsis)
        {
            .dockStyle = .Center
            .style.setFont(me.theme().createDefaultFontFs(12), .Regular)
            .setTextAlignment(.Right, .OpticalCenter)
        }
    }

    // Creates the byte grid, whose caret and zoom feed the information group.
    private mtd createGrid()
    {
        with .grid = GridView.create(me)
        {
            .sigCaretChanged += func|view = me|(_) { view.refreshInspector() }
            .sigZoomChanged  += func|view = me|(_) { view.refreshZoom() }
        }
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
