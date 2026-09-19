#global internal

using Core, Pixel, Gui

// Describes the raw byte viewer to the host.
//
// It answers for every file, so a format nothing else reads is still openable.
func hexViewerPlugin()->Viewer.Plugin
{
    with var result: retval
    {
        .key          = "hex"
        .staticName   = "Hexadecimal"
        .attach       = &registerHexStrings
        .iconAtlas    = viewerIcons()
        .iconIndex    = cast(s32) ViewerIcons.Hex
        .create       = &createHexViewer
        .smokeFixture = "viewer.hex"
        .addSelectors("*")
    }

    return result
}

private const HexCommandWidth   = 640.0
private const HexComboWidth     = 120.0
private const HexInspectorWidth = 420.0
private const HexInfoWidth      = HexInspectorWidth + ViewerZoomSlotWidth

// Returns `value`, a `bits`-bit scalar, as `0b` and one binary digit per bit, as the inspector spells it.
private func formatHexBinaryScalar(value, bits: u64)->String
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

    return String.from(cast(string) text.toSlice())
}

// Returns `value`, a `bits`-bit scalar, as `0o` and its octal digits, as the inspector spells it.
private func formatHexOctalScalar(value, bits: u64)->String
{
    let digits = (bits + 2) / 3
    var text: Array'u8
    text.reserve(digits + 2)
    text.add('0'u8)
    text.add('o'u8)
    for index in digits
    {
        let shift = (digits - 1 - index) * 3
        text.add('0'u8 + cast(u8) ((value >> shift) & 7))
    }

    return String.from(cast(string) text.toSlice())
}

// Opens `fileName` and makes its first window resident, outside the GUI thread.
private func loadHexDocument(fileName: string)->HexDocument fail
{
    var result: retval
    if not result.open(fileName) do
        fail InvalidFormatError{Errors.mkString(result.failureReason.toString())}
    if result.fileSize and not result.ensure(0, Math.min(result.fileSize, HexWindowSize)) do
        fail InvalidFormatError{Errors.mkString(result.failureReason.toString())}
    return #move result
}

// Hexadecimal view of any file, whatever its size.
//
// The view owns the grid the bytes are read in and the compact command group the host places in
// its action bar. Everything below streams — no part of this view ever holds more than one window
// of the file.
struct HexViewer
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
        analysisView:   *HexAnalysisView
        grid:           *HexGridView
    }

    inspectorLabel:       *Label?
    zoomLabel:            *IconButton?
    searchPattern:        HexSearchPattern
    analysis:             HexAnalysisOperation
    analysisTimer:        *Timer?
    fileName:             String
    details:              String
    load:                 Viewer.BackgroundLoad'HexDocument
    loadTimer:            *Timer?
    reportFailure:        Viewer.ReportFailure?
    reportDetails:        Viewer.ReportDetails?
    reportLoadingChanged: Viewer.ReportLoadingChanged?
    failureReason:        String
}

private impl IWnd for HexViewer
{
    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer == .analysisTimer
        {
            if not .analysis.isDone()
            {
                .analysisView.setProgress(.analysis.progress())
                return
            }

            .removeTimer(evt.timer)
            .analysisTimer = null
            var result = .analysis.finish()
            .analysisView.publish(&result)
            .analysisButton.enable(.grid.doc.fileSize != 0)
            return
        }

        if evt.timer != .loadTimer
        {
            evt.accepted = false
            return
        }

        if not .load.isDone() do
            return

        .removeTimer(evt.timer)
        .loadTimer = null
        var document: HexDocument
        .failureReason = .load.finish(&document)
        if not .failureReason.isEmpty()
        {
            if .reportFailure do
                .reportFailure(me, .failureReason.toString())
            return
        }

        .grid.exchangeDocument(&document)
        if .reportFailure
        {
            let report: Viewer.ReportFailure = .reportFailure
            .grid.doc.reportFailure = func|view = me, report|(reason) { report(cast(*Wnd) view, reason) }
        }

        .applyLayout()
        .grid.refreshLayout()
        .refreshInspector()
        .analysisButton.enable(.grid.doc.fileSize != 0)
        .setInitialFocus(.grid)
        if .reportLoadingChanged do
            .reportLoadingChanged(me)
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged do
            .retranslate()
        else do
            evt.accepted = false
    }
}

impl HexViewer
{
    // Stops the background load and analysis, and reports whether the view can be destroyed.
    //
    // A false result means a worker still borrows the view; the host polls again.
    mtd retire()->bool
    {
        if not .load.retire() do
            return false
        if not .analysis.retire() do
            return false
        if .loadTimer
        {
            .removeTimer(.loadTimer)
            .loadTimer = null
        }

        if .analysisTimer
        {
            .removeTimer(.analysisTimer)
            .analysisTimer = null
        }

        return true
    }

    private mtd analysisRange()->{range: HexAnalysisRange, selection: bool}
    {
        var result: retval
        result.selection = .grid.selectionLength() > 1
        result.range     = result.selection ? HexAnalysisRange{.grid.selectionStart(), .grid.selectionLength()} : HexAnalysisRange{0, .grid.doc.fileSize}
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

    private mtd startAnalysisRange(range: HexAnalysisRange, selection: bool)
    {
        .analysisView.show()
        .analysisView.begin(range, selection, .grid.offsetDigits)
        .applyLayout()
        .analysis.start(.fileName.toString(), range)
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

    mtd selectedGrouping()->HexGrouping
    {
        let width  = .widthCombo.selectedIndex
        let format = .formatCombo.selectedIndex
        switch width
        {
        case 0:  return format == 1 ? .Unsigned8 : format == 2 ? .Signed8 : .Bytes
        case 1:  return format == 1 ? .Unsigned16 : format == 2 ? .Signed16 : .Hex16
        case 2:  return format == 1 ? .Unsigned32 : format == 2 ? .Signed32 : format == 3 ? .Float32 : .Hex32
        default: return format == 1 ? .Unsigned64 : format == 2 ? .Signed64 : format == 3 ? .Float64 : .Hex64
        }
    }

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
        .formatCombo.addItem(hexStrings().ui_FormatHex)
        .formatCombo.addItem(hexStrings().ui_FormatUns)
        .formatCombo.addItem(hexStrings().ui_FormatSigned)
        if .widthCombo.selectedIndex >= 2 do
            .formatCombo.addItem(hexStrings().ui_FormatFloat)
        let next = previous < .formatCombo.items.count ? previous : 0
        .formatCombo.setSelectedIndex(cast(u32) next, notify: false)
        .applyValueMode()
    }

    mtd retranslate()
    {
        let rowWidth = .rowWidthCombo.selectedIndex
        .rowWidthCombo.clear()
        .rowWidthCombo.addItem(hexStrings().ui_RowAuto)
        .rowWidthCombo.addItem("8")
        .rowWidthCombo.addItem("16")
        .rowWidthCombo.addItem("32")
        .rowWidthCombo.addItem("64")
        .rowWidthCombo.setSelectedIndex(rowWidth, notify: false)
        .rowWidthCombo.toolTip = hexStrings().ui_RowWidth

        let width = .widthCombo.selectedIndex
        .widthCombo.clear()
        .widthCombo.addItem(hexStrings().ui_Width8)
        .widthCombo.addItem(hexStrings().ui_Width16)
        .widthCombo.addItem(hexStrings().ui_Width32)
        .widthCombo.addItem(hexStrings().ui_Width64)
        .widthCombo.setSelectedIndex(width, notify: false)
        .widthCombo.toolTip  = hexStrings().ui_TipWidth
        .formatCombo.toolTip = hexStrings().ui_TipFormat
        .rebuildFormats()

        let byteOrder = .byteOrderCombo.selectedIndex
        .byteOrderCombo.clear()
        .byteOrderCombo.addItem(hexStrings().ui_EndianLittle)
        .byteOrderCombo.addItem(hexStrings().ui_EndianBig)
        .byteOrderCombo.setSelectedIndex(byteOrder, notify: false)
        .byteOrderCombo.toolTip = hexStrings().ui_TipEndian
        .analysisButton.toolTip = hexStrings().ui_AnalysisTip
        .analysisView.retranslate()
        .details.clear()
        if .reportDetails do
            .reportDetails(me, .details.toString())
        .fitCommandBar()
        .grid.invalidate()
        .refreshInspector()
    }

    private mtd offsetText(offset: u64)->String => formatHexDigits(offset, .grid.offsetDigits)

    private mtd refreshZoom()
    {
        let base    = .themeMetrics().defaultFixedFontSize
        let percent = cast(u32) Math.round(cast(f32) .grid.fontSize * 100 / cast(f32) base)
        .zoomLabel?.setText(Format.toString("% %", percent, "%"))
    }

    private mtd showZoomMenu()
    {
        if not .zoomLabel do
            return
        let base      = .themeMetrics().defaultFixedFontSize
        with let menu = MenuCtrl.createPopup(me, owner: me)
        {
            .addItem("75%", "scope.hex.zoom75")
            .addItem("100%", "scope.hex.zoom100")
            .addItem("125%", "scope.hex.zoom125")
            .addItem("150%", "scope.hex.zoom150")
            .addItem("200%", "scope.hex.zoom200")
        }

        switch menu.doModal(.zoomLabel, autoDestroy: true) orelse ""
        {
        case "scope.hex.zoom75":  .grid.setFontSize(cast(u32) Math.max(Math.round(cast(f32) base * 0.75), 1))
        case "scope.hex.zoom100": .grid.resetFontSize()
        case "scope.hex.zoom125": .grid.setFontSize(cast(u32) Math.max(Math.round(cast(f32) base * 1.25), 1))
        case "scope.hex.zoom150": .grid.setFontSize(cast(u32) Math.max(Math.round(cast(f32) base * 1.5), 1))
        case "scope.hex.zoom200": .grid.setFontSize(base * 2)
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
            label.setText(hexStrings().ui_InspectorEmpty)
            label.toolTip = hexStrings().ui_InspectorEmpty
            return
        }

        let available = Math.min(8'u64, .grid.doc.fileSize - .grid.caret)
        let bytes     = .grid.doc.read(.grid.caret, available)
        if bytes.isEmpty()
        {
            label.setText(hexStrings().ui_InspectorEmpty)
            label.toolTip = hexStrings().ui_InspectorEmpty
            return
        }

        let offset  = .offsetText(.grid.caret)
        let size    = .grid.valueSize()
        let active  = size <= bytes.count ? formatHexScalar(.grid.grouping, .inspectorScalar(bytes.toSlice(), size)) : String.from("--")
        let percent = .grid.doc.fileSize > 1 ? cast(f64) .grid.caret * 100 / cast(f64) (.grid.doc.fileSize - 1) : 0
        label.setText(Format.toString("@% · %{f1}%% · % B · % %", offset, percent, .grid.selectionLength(), .activeValueTag(), active))

        var details = Format.toString("@% (%) · %{f1}%%\n[%..%] % B\n%", offset, .grid.caret, percent, .offsetText(.grid.selectionStart()), .offsetText(.grid.selectionEnd()), .grid.selectionLength(), .grid.bigEndian ? "BE" : "LE")
        let raw8    = .inspectorScalar(bytes.toSlice(), 1)
        details += Format.toString("\nu8 % · s8 % · x8 0x%{X02} · b8 % · o8 % · bool %", raw8, hexSignedScalar(raw8, 1), raw8, formatHexBinaryScalar(raw8, 8), formatHexOctalScalar(raw8, 8), raw8 ? "true" : "false")
        if isHexPrintable(cast(u8) raw8) do
            details += Format.toString(" · ASCII '%'", cast(u8) raw8)
        if bytes.count >= 2
        {
            let raw = .inspectorScalar(bytes.toSlice(), 2)
            details += Format.toString("\nu16 % · s16 % · x16 0x%{X04} · b16 % · o16 %", raw, hexSignedScalar(raw, 2), raw, formatHexBinaryScalar(raw, 16), formatHexOctalScalar(raw, 16))
        }

        if bytes.count >= 4
        {
            let raw = .inspectorScalar(bytes.toSlice(), 4)
            details += Format.toString("\nu32 % · s32 % · x32 0x%{X08} · b32 % · o32 % · f32 %{g9}", raw, hexSignedScalar(raw, 4), raw, formatHexBinaryScalar(raw, 32), formatHexOctalScalar(raw, 32), cast #bit (f32) (cast(u32) raw))
        }

        if bytes.count >= 8
        {
            let raw = .inspectorScalar(bytes.toSlice(), 8)
            details += Format.toString("\nu64 % · s64 % · x64 0x%{X016} · b64 % · o64 % · f64 %{g15}", raw, hexSignedScalar(raw, 8), raw, formatHexBinaryScalar(raw, 64), formatHexOctalScalar(raw, 64), cast #bit (f64) raw)
        }

        label.toolTip = #move details
    }

    mtd describeSearch(result: *Viewer.SearchPresentation)
    {
        result.placeholder    = hexStrings().ui_SearchPlaceholder
        result.toolTip        = hexStrings().ui_SearchHelp
        result.useTextOptions = false
    }

    mtd prepareSearch(query: string, result: *Viewer.SearchPlan)->EditBoxCheckResult
    {
        var parsed = parseHexSearch(query, .grid.grouping, .grid.bigEndian)
        switch #complete parsed.state
        {
        case .Incomplete:
            return .Incomplete

        case .Invalid:
            result.error = parsed.error == .Value ? hexStrings().ui_SearchValueError : hexStrings().ui_SearchPatternError
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

impl HexViewer
{
    func create(host: Viewer.Host)->*HexViewer
    {
        let services    = host.services()
        with let result = Wnd.create'HexViewer(host.contentParent(), "scope.hex")
        {
            .backgroundStyle      = .View
            .reportFailure        = services.reportFailure
            .reportDetails        = services.reportDetails
            .reportLoadingChanged = services.reportLoadingChanged
            .fileName             = host.fileName()
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
        result.load.start(host.fileName(), &loadHexDocument)
        result.loadTimer = result.addTimer(Viewer.BackgroundPollInterval)
        return result
    }

    // Creates the command group: the row width, value width, representation, and byte order selectors.
    private mtd createCommandBar(host: Viewer.Host)
    {
        .commands = host.createCommandGroup(HexCommandWidth)

        with .rowWidthCombo = ComboBox.create(.commands, {0, 0, HexComboWidth, 36})
        {
            .dockStyle = .Left
            .margin.x  = 8
            .toolTip   = hexStrings().ui_RowWidth
            .addItem(hexStrings().ui_RowAuto)
            .addItem("8")
            .addItem("16")
            .addItem("32")
            .addItem("64")
            .setSelectedIndex(0, notify: false)
            .sigChanged += func|view = me|(combo, index)
            {
                discard combo
                discard index
                view.applyRowWidth()
            }
        }

        with .widthCombo = ComboBox.create(.commands, {0, 0, HexComboWidth, 36})
        {
            .dockStyle = .Left
            .margin.x  = 8
            .toolTip   = hexStrings().ui_TipWidth
            .addItem(hexStrings().ui_Width8)
            .addItem(hexStrings().ui_Width16)
            .addItem(hexStrings().ui_Width32)
            .addItem(hexStrings().ui_Width64)
            .setSelectedIndex(0, notify: false)
            .sigChanged += func|view = me|(combo, index)
            {
                discard combo
                discard index
                view.rebuildFormats()
            }
        }

        with .formatCombo = ComboBox.create(.commands, {0, 0, HexComboWidth, 36})
        {
            .dockStyle = .Left
            .margin.x  = 8
            .toolTip   = hexStrings().ui_TipFormat
            .addItem(hexStrings().ui_FormatHex)
            .addItem(hexStrings().ui_FormatUns)
            .addItem(hexStrings().ui_FormatSigned)
            .setSelectedIndex(0, notify: false)
            .sigChanged += func|view = me|(combo, index)
            {
                discard combo
                discard index
                view.applyValueMode()
            }
        }

        with .byteOrderCombo = ComboBox.create(.commands, {0, 0, HexComboWidth, 36})
        {
            .dockStyle = .Left
            .margin.x  = 8
            .toolTip   = hexStrings().ui_TipEndian
            .addItem(hexStrings().ui_EndianLittle)
            .addItem(hexStrings().ui_EndianBig)
            .setSelectedIndex(0, notify: false)
            .sigChanged += func|view = me|(combo, index)
            {
                discard combo
                discard index
                view.applyByteOrder()
            }
        }
    }

    // Creates the analysis side panel, and wires the host toggle that opens it.
    private mtd createAnalysisPanel(host: Viewer.Host)
    {
        let sidePanel = host.createSidePanel(HexAnalysisPanelWidth, .theme().icon(.Information, themeActionIconSize(.themeMetrics())), hexStrings().ui_AnalysisTip)
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

        with .analysisView = HexAnalysisView.create(sidePanel.content)
        {
            .sigAnalyze += func|view = me|(panel)
            {
                discard panel
                view.startAnalysis()
            }

            .sigCancel += func|view = me|(panel)
            {
                discard panel
                view.analysis.cancel()
            }

            .sigClose += func|view = me|(panel)
            {
                discard panel
                view.closeAnalysis()
            }

            .sigNavigate += func|view = me|(panel, offset, length)
            {
                discard panel
                discard view.grid.revealRange(offset, length)
                view.refreshInspector()
                view.grid.setFocus()
            }
        }
    }

    // Creates the information group: the zoom menu and the caret inspector.
    private mtd createInfoGroup(host: Viewer.Host)
    {
        let info = host.createInfoGroup(HexInfoWidth)
        with .zoomLabel = IconButton.create(info, {}, {0, 0, ViewerZoomButtonWidth, 32}, "scope.hex.zoom", .CenterContent)
        {
            .dockStyle = .Right
            .margin    = {ViewerInfoControlInset, 0, ViewerInfoControlInset, 0}
            .setText("100%")
            .setArrowPosition(.RightDownward)
            .setForm(.Rectangle)
            .style.setFont(me.theme().createDefaultFontFs(11), .Regular)
            .toolTip    = hexStrings().ui_ZoomMenu
            .sigPressed += func|view = me|(button)
            {
                discard button
                view.showZoomMenu()
            }
        }

        with .inspectorLabel = Label.create(info, "", {0, 0, HexInspectorWidth, 32}, null, .SecondaryText | .Ellipsis)
        {
            .dockStyle = .Center
            .style.setFont(me.theme().createDefaultFontFs(12), .Regular)
            .setTextAlignment(.Right, .OpticalCenter)
        }
    }

    // Creates the byte grid, whose caret and zoom feed the information group.
    private mtd createGrid()
    {
        with .grid = HexGridView.create(me)
        {
            .sigCaretChanged += func|view = me|(grid)
            {
                discard grid
                view.refreshInspector()
            }

            .sigZoomChanged += func|view = me|(grid)
            {
                discard grid
                view.refreshZoom()
            }
        }
    }
}

// Creates the integrated hexadecimal view.
func createHexViewer(host: Viewer.Host)
{
    let view = HexViewer.create(host)

    host.attachView(view)
    host.setDetails(view.details.toString())
    host.setSearch({
        revealMatch: func(wnd, match, text)->bool
    {
        discard text
        return (cast #assume (*HexViewer) wnd).revealOffset(match.offset, match.length)
    },
        matchBounds: func(wnd, match, bounds)->bool
    {
        discard match
        return (cast #assume (*HexViewer) wnd).grid.matchBounds(bounds)
    },
        clear: func(wnd) { (cast #assume (*HexViewer) wnd).grid.clearSearchMatch() },
        describe: func(wnd, presentation) { (cast #assume (*HexViewer) wnd).describeSearch(presentation) },
        prepare: func(wnd, query, plan)->EditBoxCheckResult => (cast #assume (*HexViewer) wnd).prepareSearch(query, plan),
        collectFileMatches: func(wnd, source, baseOffset, matches) { (cast #assume (*HexViewer) wnd).collectSearchMatches(source, baseOffset, matches) },
        useMatches: func(wnd, matches) { (cast #assume (*HexViewer) wnd).grid.setSearchMatches(matches) }})
    host.setLifecycle({
        isLoading: func(wnd)->bool => (cast #assume (*HexViewer) wnd).loadTimer != null,
        needsLoadingOverlay: func(wnd)->bool => (cast #assume (*HexViewer) wnd).loadTimer != null,
        retire: func(wnd)->bool => (cast #assume (*HexViewer) wnd).retire()})
}
