#global internal
#global namespace Viewers.Hex

using Core, Pixel, Gui

// Describes the raw byte viewer to the host.
//
// It answers for every file, so a format nothing else reads is still openable.
func viewerPlugin()->Viewer.Plugin
{
    with var result: retval
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
    const CommandWidth   = 640.0
    const ComboWidth     = 120.0
    const InspectorWidth = 420.0
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
    var result: retval
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
        rowWidthCombo:  *ComboBox
        widthCombo:     *ComboBox
        formatCombo:    *ComboBox
        byteOrderCombo: *ComboBox
        analysisView:   *AnalysisView
        grid:           *GridView
    }

    inspectorLabel: *Label?
    zoomLabel:      *IconButton?
    searchPattern:  SearchPattern
    analysis:       AnalysisOperation
    fileName:       String
    details:        String
    load:           Viewer.BackgroundLoad'Document
    services:       Viewer.HostServices
    failureReason:  String
}

private impl IWnd for Panel
{
    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer == .analysis.timer
        {
            if not .analysis.poll()
            {
                .analysisView.setProgress(.analysis.progress())
                return
            }

            var result = .analysis.finish()
            .analysisView.publish(&result)
            .analysisButton.enable(.grid.doc.fileSize != 0)
            return
        }

        if evt.timer != .load.timer
        {
            evt.accepted = false
            return
        }

        if not .load.poll() do
            return

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
        return .load.retire() and .analysis.retire()
    }

    private mtd analysisRange()->{range: AnalysisRange, selection: bool}
    {
        var result: retval
        result.selection = .grid.selectionLength() > 1
        result.range     = result.selection ? AnalysisRange{.grid.selectionStart(), .grid.selectionLength()} : AnalysisRange{0, .grid.doc.fileSize}
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
        .analysis.start(.fileName, range)
        .analysis.pollFrom(me)
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

    mtd selectedGrouping()->Grouping => Groupings[Math.min(.widthCombo.selectedIndex, 3), Math.min(.formatCombo.selectedIndex, 3)]

    mtd applyValueMode()
    {
        .grid.setGrouping(.selectedGrouping())
    }

    mtd applyByteOrder()
    {
        .grid.setBigEndian(.byteOrderCombo.selectedIndex == 1)
    }

    mtd applyRowWidth()
    {
        let index = .rowWidthCombo.selectedIndex
        if not index
        {
            .grid.setBytesPerRow(0, true)
            return
        }

        .grid.setBytesPerRow(4'u64 << index, false)
    }

    // Sizes each selector to its widest localized entry, and the command group to exactly those widths and their leading gaps.
    //
    // A fixed width would truncate a long vocabulary and leave unused room around a short one.
    private mtd fitCommandBar()
    {
        let rowWidth  = Math.ceil(.rowWidthCombo.itf.measureContent({}).x)
        let value     = Math.ceil(.widthCombo.itf.measureContent({}).x)
        let format    = Math.ceil(.formatCombo.itf.measureContent({}).x)
        let byteOrder = Math.ceil(.byteOrderCombo.itf.measureContent({}).x)
        .rowWidthCombo.preferredSize.x  = rowWidth
        .widthCombo.preferredSize.x     = value
        .formatCombo.preferredSize.x    = format
        .byteOrderCombo.preferredSize.x = byteOrder
        .rowWidthCombo.resize(rowWidth, 36)
        .widthCombo.resize(value, 36)
        .formatCombo.resize(format, 36)
        .byteOrderCombo.resize(byteOrder, 36)

        let width = rowWidth + value + format + byteOrder + .rowWidthCombo.margin.x + .widthCombo.margin.x + .formatCombo.margin.x + .byteOrderCombo.margin.x
        .commands.preferredSize.x = width
        .commands.resize(width, 36)
        .commands.applyLayout()
    }

    mtd rebuildFormats()
    {
        let previous = .formatCombo.selectedIndex
        .formatCombo.clear()
        .formatCombo.addItem(texts().ui_FormatHex)
        .formatCombo.addItem(texts().ui_FormatUns)
        .formatCombo.addItem(texts().ui_FormatSigned)
        if .widthCombo.selectedIndex >= 2 do
            .formatCombo.addItem(texts().ui_FormatFloat)
        let next = previous < .formatCombo.items.count ? previous : 0
        .formatCombo.setSelectedIndex(cast(u32, next), notify: false)
        .applyValueMode()
    }

    // Rebuilds the localized combo items and tooltips in the current language, keeping every
    // selection, then republishes the details.
    mtd retranslate()
    {
        let rowWidth = .rowWidthCombo.selectedIndex
        .rowWidthCombo.clear()
        .rowWidthCombo.addItem(texts().ui_RowAuto)
        .rowWidthCombo.addItem("8")
        .rowWidthCombo.addItem("16")
        .rowWidthCombo.addItem("32")
        .rowWidthCombo.addItem("64")
        .rowWidthCombo.setSelectedIndex(rowWidth, notify: false)
        .rowWidthCombo.toolTip = texts().ui_RowWidth

        let width = .widthCombo.selectedIndex
        .widthCombo.clear()
        .widthCombo.addItem(texts().ui_Width8)
        .widthCombo.addItem(texts().ui_Width16)
        .widthCombo.addItem(texts().ui_Width32)
        .widthCombo.addItem(texts().ui_Width64)
        .widthCombo.setSelectedIndex(width, notify: false)
        .widthCombo.toolTip  = texts().ui_TipWidth
        .formatCombo.toolTip = texts().ui_TipFormat
        .rebuildFormats()

        let byteOrder = .byteOrderCombo.selectedIndex
        .byteOrderCombo.clear()
        .byteOrderCombo.addItem(texts().ui_EndianLittle)
        .byteOrderCombo.addItem(texts().ui_EndianBig)
        .byteOrderCombo.setSelectedIndex(byteOrder, notify: false)
        .byteOrderCombo.toolTip = texts().ui_TipEndian
        .analysisButton.toolTip = texts().ui_AnalysisTip
        .analysisView.retranslate()
        .details.clear()
        .services.showDetails(me, .details)
        .fitCommandBar()
        .grid.invalidate()
        .refreshInspector()
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

        let offset  = .offsetText(.grid.caret)
        let size    = .grid.valueSize()
        let active  = size <= bytes.count ? formatScalar(.grid.grouping, .inspectorScalar(bytes.toSlice(), size)) : String.from("--")
        let percent = .grid.doc.fileSize > 1 ? cast(f64, .grid.caret) * 100 / cast(f64, .grid.doc.fileSize - 1) : 0
        label.setText(Format.toString("@% · %{f1}%% · % B · % %", offset, percent, .grid.selectionLength(), .activeValueTag(), active))

        var details = Format.toString("@% (%) · %{f1}%%\n[%..%] % B\n%", offset, .grid.caret, percent, .offsetText(.grid.selectionStart()), .offsetText(.grid.selectionEnd()), .grid.selectionLength(), .grid.bigEndian ? "BE" : "LE")
        let raw8    = .inspectorScalar(bytes.toSlice(), 1)
        details += Format.toString("\nu8 % · s8 % · x8 0x%{X02} · b8 % · o8 % · bool %", raw8, signedScalar(raw8, 1), raw8, formatBinaryScalar(raw8, 8), formatOctalScalar(raw8, 8), raw8 ? "true" : "false")
        if isPrintable(cast(u8, raw8)) do
            details += Format.toString(" · ASCII '%'", cast(u8, raw8))
        if bytes.count >= 2
        {
            let raw = .inspectorScalar(bytes.toSlice(), 2)
            details += Format.toString("\nu16 % · s16 % · x16 0x%{X04} · b16 % · o16 %", raw, signedScalar(raw, 2), raw, formatBinaryScalar(raw, 16), formatOctalScalar(raw, 16))
        }

        if bytes.count >= 4
        {
            let raw = .inspectorScalar(bytes.toSlice(), 4)
            details += Format.toString("\nu32 % · s32 % · x32 0x%{X08} · b32 % · o32 % · f32 %{g9}", raw, signedScalar(raw, 4), raw, formatBinaryScalar(raw, 32), formatOctalScalar(raw, 32), cast #bit (f32, cast(u32, raw)))
        }

        if bytes.count >= 8
        {
            let raw = .inspectorScalar(bytes.toSlice(), 8)
            details += Format.toString("\nu64 % · s64 % · x64 0x%{X016} · b64 % · o64 % · f64 %{g15}", raw, signedScalar(raw, 8), raw, formatBinaryScalar(raw, 64), formatOctalScalar(raw, 64), cast #bit (f64, raw))
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

        result.fitCommandBar()
        result.applyLayout()
        result.grid.refreshLayout()
        result.refreshInspector()
        result.refreshZoom()
        result.setInitialFocus(result.grid)
        result.load.startPolled(result, host.fileName(), &loadDocument)
        return result
    }

    // Creates the command group: the row width, value width, representation, and byte order selectors.
    private mtd createCommandBar(host: Viewer.Host)
    {
        .commands = host.createCommandGroup(CommandWidth)

        with .rowWidthCombo = ComboBox.create(.commands, {0, 0, ComboWidth, 36})
        {
            .dockStyle = .Left
            .margin.x  = 8
            .toolTip   = texts().ui_RowWidth
            .addItem(texts().ui_RowAuto)
            .addItem("8")
            .addItem("16")
            .addItem("32")
            .addItem("64")
            .setSelectedIndex(0, notify: false)
            .sigChanged += func|view = me|(?, ?) { view.applyRowWidth() }
        }

        with .widthCombo = ComboBox.create(.commands, {0, 0, ComboWidth, 36})
        {
            .dockStyle = .Left
            .margin.x  = 8
            .toolTip   = texts().ui_TipWidth
            .addItem(texts().ui_Width8)
            .addItem(texts().ui_Width16)
            .addItem(texts().ui_Width32)
            .addItem(texts().ui_Width64)
            .setSelectedIndex(0, notify: false)
            .sigChanged += func|view = me|(?, ?) { view.rebuildFormats() }
        }

        with .formatCombo = ComboBox.create(.commands, {0, 0, ComboWidth, 36})
        {
            .dockStyle = .Left
            .margin.x  = 8
            .toolTip   = texts().ui_TipFormat
            .addItem(texts().ui_FormatHex)
            .addItem(texts().ui_FormatUns)
            .addItem(texts().ui_FormatSigned)
            .setSelectedIndex(0, notify: false)
            .sigChanged += func|view = me|(?, ?) { view.applyValueMode() }
        }

        with .byteOrderCombo = ComboBox.create(.commands, {0, 0, ComboWidth, 36})
        {
            .dockStyle = .Left
            .margin.x  = 8
            .toolTip   = texts().ui_TipEndian
            .addItem(texts().ui_EndianLittle)
            .addItem(texts().ui_EndianBig)
            .setSelectedIndex(0, notify: false)
            .sigChanged += func|view = me|(?, ?) { view.applyByteOrder() }
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
            .sigAnalyze += func|view = me|(?)
            {
                view.startAnalysis()
            }

            .sigCancel += func|view = me|(?)
            {
                view.analysis.cancel()
            }

            .sigClose += func|view = me|(?)
            {
                view.closeAnalysis()
            }

            .sigNavigate += func|view = me|(?, offset, length)
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
            .sigPressed += func|view = me|(?) { view.showZoomMenu() }
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
            .sigCaretChanged += func|view = me|(?) { view.refreshInspector() }
            .sigZoomChanged  += func|view = me|(?) { view.refreshZoom() }
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
        .revealMatch        = func|view|(match, ?) => view.revealOffset(match.offset, match.length)
        .matchBounds        = func|view|(?, bounds) => view.grid.matchBounds(bounds)
        .clear              = func|view|() => view.grid.clearSearchMatch()
        .describe           = func|view|(presentation) => view.describeSearch(presentation)
        .prepare            = func|view|(query, plan) => view.prepareSearch(query, plan)
        .collectFileMatches = func|view|(source, baseOffset, matches) => view.collectSearchMatches(source, baseOffset, matches)
        .useMatches         = func|view|(matches) => view.grid.setSearchMatches(matches)
    }

    host.setSearch(search)

    host.setLifecycle(Viewer.loadLifecycle(view))
}
