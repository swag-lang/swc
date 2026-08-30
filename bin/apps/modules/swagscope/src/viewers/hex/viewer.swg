#global internal

using Core, Pixel, Gui

private const HexCommandWidth = 516.0
private const HexComboWidth   = 150.0
private const HexEndianWidth  = 150.0
private const HexInfoWidth    = 420.0

// Writes an unsigned scalar in the binary spelling used by the inspector.
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

    return String.from(Swag.makeString(text.buffer!, text.count))
}

// Writes an unsigned scalar in the octal spelling used by the inspector.
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

    return String.from(Swag.makeString(text.buffer!, text.count))
}

private func loadHexDocument(fileName: string)->HexDocument fail
{
    var result: retval
    if !result.open(fileName) do
        fail InvalidFormatError{Errors.mkString(result.failureReason.toString())}
    if result.fileSize and !result.ensure(0, Math.min(result.fileSize, HexWindowSize)) do
        fail InvalidFormatError{Errors.mkString(result.failureReason.toString())}
    return #move result
}

// Hexadecimal view of any file, whatever its size.
//
// The view owns the grid the bytes are read in and the compact command group the host places in
// its action bar. Everything below streams — no part of this view ever holds more than one window
// of the file.
internal struct HexViewer
{
    using wnd: Wnd

    #[Swag.Late]
    {
        commands:       *Wnd
        analysisButton: *IconButton
        moreButton:     *IconButton
        widthCombo:     *ComboBox
        formatCombo:    *ComboBox
        byteOrderCombo: *ComboBox
        analysisView:   *HexAnalysisView
        grid:           *HexGridView
    }

    info:                 #null *Wnd
    inspectorLabel:       #null *Label
    searchPattern:        HexSearchPattern
    analysis:             HexAnalysisOperation
    analysisTimer:        #null *Timer
    fileName:             String
    details:              String
    load:                 ViewerBackgroundLoad'HexDocument
    loadTimer:            #null *Timer
    reportFailure:        #null ViewerReportFailure
    reportDetails:        #null ViewerReportDetails
    reportLoadingChanged: #null ViewerReportLoadingChanged
    failureReason:        String
}

private impl IWnd for HexViewer
{
    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer == .analysisTimer
        {
            if !.analysis.isDone()
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

        if !.load.isDone() do
            return

        .removeTimer(evt.timer)
        .loadTimer = null
        var document: HexDocument
        .failureReason = .load.finish(&document)
        if !.failureReason.isEmpty()
        {
            if .reportFailure do
                .reportFailure!(me, .failureReason.toString())
            return
        }

        .grid.exchangeDocument(&document)
        if .reportFailure
        {
            let report = .reportFailure!
            .grid.doc.reportFailure = func|view = me, report|(reason) { report(cast(*Wnd) view, reason) }
        }

        .applyLayout()
        .grid.refreshLayout()
        .refreshInspector()
        .analysisButton.enable(.grid.doc.fileSize != 0)
        .setInitialFocus(.grid)
        if .reportLoadingChanged do
            .reportLoadingChanged!(me)
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged do
            .retranslate()
        else do
            evt.accepted = false
    }
}

internal impl HexViewer
{
    mtd retire()->bool
    {
        if !.load.retire() do
            return false
        if !.analysis.retire() do
            return false
        if .loadTimer
        {
            .removeTimer(.loadTimer!)
            .loadTimer = null
        }

        if .analysisTimer
        {
            .removeTimer(.analysisTimer!)
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

    mtd startAnalysis()
    {
        if .analysis.started
        {
            .analysisView.show()
            .applyLayout()
            return
        }

        if !.grid.doc.fileSize do
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
        .analysisTimer = .addTimer(ViewerBackgroundPollInterval)
    }

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
        .moreButton.toolTip     = hexStrings().ui_TipCommands
        .analysisButton.toolTip = hexStrings().ui_AnalysisTip
        .analysisView.retranslate()
        .details = hexStrings().ui_Details
        if .reportDetails do
            .reportDetails!(me, .details.toString())
        .commands.applyLayout()
        .grid.invalidate()
        .refreshInspector()
    }

    private mtd offsetText(offset: u64)->String
    {
        var bytes: Array'u8
        appendHexDigits(&bytes, offset, .grid.offsetDigits)
        return String.from(Swag.makeString(bytes.buffer!, bytes.count))
    }

    private mtd inspectorScalar(bytes: const [..] u8, size: u64)->u64
    {
        var result: retval
        for index in size
        {
            let position = .grid.bigEndian ? index : size - 1 - index
            result = (result << 8) | bytes[position]
        }

        return result
    }

    private mtd activeValueTag()->string
    {
        switch .grid.grouping
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

    // Keeps the most useful exact-caret readings in the information band. The compact line is
    // glanceable; its tooltip spells the same bytes at every common scalar width.
    mtd refreshInspector()
    {
        if !.inspectorLabel do
            return
        let label = .inspectorLabel!
        if !.grid.doc.fileSize
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

    mtd describeSearch(result: *ViewerSearchPresentation)
    {
        result.placeholder    = hexStrings().ui_SearchPlaceholder
        result.toolTip        = hexStrings().ui_SearchHelp
        result.useTextOptions = false
    }

    mtd prepareSearch(query: string, result: *ViewerSearchPlan)->EditBoxCheckResult
    {
        var parsed = parseHexSearch(query, .grid.grouping, .grid.bigEndian)
        switch parsed.state
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

    mtd collectSearchMatches(source: string, baseOffset: u64, result: *Array'ViewerSearchMatch)
    {
        .searchPattern.collectMatches(source, baseOffset, result)
    }

    // Reveals the byte range the host's search matched.
    mtd revealOffset(offset, length: u64)->bool
    {
        if !.grid.revealRange(offset, length) do
            return false
        .grid.setFocus()
        return true
    }
}

internal impl HexViewer
{
    func create(host: FileViewer.Host)->*HexViewer
    {
        let services = host.services()
        let result   = Wnd.create'HexViewer(host.contentParent(), "scope.hex")
        result.backgroundStyle      = .View
        result.reportFailure        = services.reportFailure
        result.reportDetails        = services.reportDetails
        result.reportLoadingChanged = services.reportLoadingChanged
        result.fileName             = host.fileName()

        result.commands = host.createCommandGroup(HexCommandWidth)

        let sidePanel = host.createSidePanel(HexAnalysisPanelWidth, result.theme().icon(.Information, themeActionIconSize(result.themeMetrics())), hexStrings().ui_AnalysisTip)
        result.analysisButton = sidePanel.toggle
        result.analysisButton.enable(false)
        result.analysisButton.sigCheckedChanged += func|view = result|(button)
        {
            if button.isChecked do
                view.startAnalysis()
            else do
                view.closeAnalysis()
        }

        result.info = host.createInfoGroup(HexInfoWidth)
        with result.inspectorLabel = Label.create(result.info!, "", {0, 0, HexInfoWidth, 32}, null, .SecondaryText | .Ellipsis)
        {
            .dockStyle = .Center
            .style.setFont(result.theme().createDefaultFontFS(12), .Regular)
            .setTextAlignment(.Right, .OpticalCenter)
        }

        with result.moreButton = IconButton.create(result.commands, result.theme().icon(.More, themeActionIconSize(result.themeMetrics())), {0, 0, themeActionButtonSize(result.themeMetrics()), themeActionButtonSize(result.themeMetrics())})
        {
            .dockStyle  = .Left
            .margin.x   = 8
            .toolTip    = hexStrings().ui_TipCommands
            .sigPressed += func|view = result|(button)
            {
                view.grid.showContextMenu(button.localToSurface(Math.Point{0, button.position.height}))
            }
        }

        with result.widthCombo = ComboBox.create(result.commands, {0, 0, HexComboWidth, 36})
        {
            .dockStyle = .Left
            .margin.x  = 8
            .toolTip   = hexStrings().ui_TipWidth
            .addItem(hexStrings().ui_Width8)
            .addItem(hexStrings().ui_Width16)
            .addItem(hexStrings().ui_Width32)
            .addItem(hexStrings().ui_Width64)
            .setSelectedIndex(0, notify: false)
            .sigChanged += func|view = result|(combo, index)
            {
                discard combo
                discard index
                view.rebuildFormats()
            }
        }

        with result.formatCombo = ComboBox.create(result.commands, {0, 0, HexComboWidth, 36})
        {
            .dockStyle = .Left
            .margin.x  = 8
            .toolTip   = hexStrings().ui_TipFormat
            .addItem(hexStrings().ui_FormatHex)
            .addItem(hexStrings().ui_FormatUns)
            .addItem(hexStrings().ui_FormatSigned)
            .setSelectedIndex(0, notify: false)
            .sigChanged += func|view = result|(combo, index)
            {
                discard combo
                discard index
                view.applyValueMode()
            }
        }

        with result.byteOrderCombo = ComboBox.create(result.commands, {0, 0, HexEndianWidth, 36})
        {
            .dockStyle = .Left
            .margin.x  = 8
            .toolTip   = hexStrings().ui_TipEndian
            .addItem(hexStrings().ui_EndianLittle)
            .addItem(hexStrings().ui_EndianBig)
            .setSelectedIndex(0, notify: false)
            .sigChanged += func|view = result|(combo, index)
            {
                discard combo
                discard index
                view.applyByteOrder()
            }
        }

        result.analysisView            = HexAnalysisView.create(sidePanel.content)
        result.analysisView.sigAnalyze += func|view = result|(panel)
        {
            discard panel
            view.startAnalysis()
        }
        result.analysisView.sigCancel += func|view = result|(panel)
        {
            discard panel
            view.analysis.cancel()
        }
        result.analysisView.sigClose += func|view = result|(panel)
        {
            discard panel
            view.closeAnalysis()
        }
        result.analysisView.sigNavigate += func|view = result|(panel, offset, length)
        {
            discard panel
            discard view.grid.revealRange(offset, length)
            view.refreshInspector()
            view.grid.setFocus()
        }

        result.grid                 = HexGridView.create(result)
        result.grid.sigCaretChanged += func|view = result|(grid)
        {
            discard grid
            view.refreshInspector()
        }
        if services.reportFailure
        {
            let report = services.reportFailure!
            result.grid.doc.reportFailure = func|result, report|(reason) { report(cast(*Wnd) result, reason) }
        }

        result.details = hexStrings().ui_Details
        result.applyLayout()
        result.grid.refreshLayout()
        result.refreshInspector()
        result.setInitialFocus(result.grid)
        result.load.start(host.fileName(), &loadHexDocument)
        result.loadTimer = result.addTimer(ViewerBackgroundPollInterval)
        return result
    }
}

// Creates the integrated hexadecimal view.
func createHexViewer(host: FileViewer.Host)
{
    registerHexStrings(host.application())
    let view = HexViewer.create(host)

    host.attachView(view)
    host.setDetails(view.details.toString())
    host.setSearch({
        revealMatch: func(wnd, match, text)->bool
    {
        discard text
        return (cast(*HexViewer) wnd).revealOffset(match.offset, match.length)
    },
        matchBounds: func(wnd, match, bounds)->bool
    {
        discard match
        return (cast(*HexViewer) wnd).grid.matchBounds(bounds)
    },
        clear: func(wnd) { (cast(*HexViewer) wnd).grid.clearSearchMatch() },
        describe: func(wnd, presentation) { (cast(*HexViewer) wnd).describeSearch(presentation) },
        prepare: func(wnd, query, plan)->EditBoxCheckResult { return (cast(*HexViewer) wnd).prepareSearch(query, plan) },
        collectFileMatches: func(wnd, source, baseOffset, matches) { (cast(*HexViewer) wnd).collectSearchMatches(source, baseOffset, matches) },
        useMatches: func(wnd, matches) { (cast(*HexViewer) wnd).grid.setSearchMatches(matches) }})
    host.setLifecycle({
        isLoading: func(wnd)->bool { return (cast(*HexViewer) wnd).loadTimer != null },
        needsLoadingOverlay: func(wnd)->bool { return (cast(*HexViewer) wnd).loadTimer != null },
        retire: func(wnd)->bool { return (cast(*HexViewer) wnd).retire() }})
}
