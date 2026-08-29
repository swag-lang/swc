#global internal

using Core, Pixel, Gui

private const HexCommandWidth = 512.0
private const HexComboWidth   = 150.0
private const HexInfoWidth    = 420.0

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
        widthCombo:     *ComboBox
        formatCombo:    *ComboBox
        byteOrder:      *CheckButton
        analysisView:   *HexAnalysisView
        grid:           *HexGridView
    }

    info:                 #null *ViewerCommandBar
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
        if .analysis.started do
            .analysis.cancel()
        .analysisView.hide()
        .analysisButton.setChecked(false)
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

        .byteOrder.setText(hexStrings().ui_Endian)
        .byteOrder.toolTip      = hexStrings().ui_TipEndian
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
        return String.from(@mkstring(bytes.buffer!, bytes.count))
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

        let offset = .offsetText(.grid.caret)
        let size   = .grid.valueSize()
        let active = size <= bytes.count ? formatHexScalar(.grid.grouping, .inspectorScalar(bytes.toSlice(), size)) : String.from("--")
        label.setText(Format.toString("@% · % B · % %", offset, .grid.selectionLength(), .activeValueTag(), active))

        var details = Format.toString("@% (%)\n[%..%] % B\n%", offset, .grid.caret, .offsetText(.grid.selectionStart()), .offsetText(.grid.selectionEnd()), .grid.selectionLength(), .grid.bigEndian ? "BE" : "LE")
        let raw8    = .inspectorScalar(bytes.toSlice(), 1)
        details += Format.toString("\nu8 % · s8 % · x8 0x%{X02}", raw8, hexSignedScalar(raw8, 1), raw8)
        if isHexPrintable(cast(u8) raw8) do
            details += Format.toString(" · ASCII '%'", cast(u8) raw8)
        if bytes.count >= 2
        {
            let raw = .inspectorScalar(bytes.toSlice(), 2)
            details += Format.toString("\nu16 % · s16 % · x16 0x%{X04}", raw, hexSignedScalar(raw, 2), raw)
        }

        if bytes.count >= 4
        {
            let raw = .inspectorScalar(bytes.toSlice(), 4)
            details += Format.toString("\nu32 % · s32 % · x32 0x%{X08} · f32 %{g9}", raw, hexSignedScalar(raw, 4), raw, cast #bit (f32) (cast(u32) raw))
        }

        if bytes.count >= 8
        {
            let raw = .inspectorScalar(bytes.toSlice(), 8)
            details += Format.toString("\nu64 % · s64 % · x64 0x%{X016} · f64 %{g15}", raw, hexSignedScalar(raw, 8), raw, cast #bit (f64) raw)
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
    func create(contentParent, commandParent: *Wnd, fileName: string, reportFailure: #null ViewerReportFailure = null, reportDetails: #null ViewerReportDetails = null, reportLoadingChanged: #null ViewerReportLoadingChanged = null, infoParent: #null *Wnd = null)->*HexViewer
    {
        let result = Wnd.create'HexViewer(contentParent, "sFileScope.hex")
        result.backgroundStyle      = .View
        result.reportFailure        = reportFailure
        result.reportDetails        = reportDetails
        result.reportLoadingChanged = reportLoadingChanged
        result.fileName             = fileName

        result.commands                 = Wnd.create'Wnd(commandParent, {0, 0, HexCommandWidth, 36})
        result.commands.backgroundStyle = .Transparent

        with result.analysisButton = IconButton.create(result.commands, result.theme().icon(.Information), {0, 0, 36, 36}, flags: .Toggle)
        {
            .dockStyle = .Left
            .margin.x  = 8
            .toolTip   = hexStrings().ui_AnalysisTip
            .setCheckIndicator(.Frame)
            .enable(false)
            .sigCheckedChanged += func|view = result|(button)
            {
                if button.isChecked do
                    view.startAnalysis()
                else do
                    view.closeAnalysis()
            }
        }

        if infoParent
        {
            result.info = ViewerCommandBar.create(infoParent!, HexInfoWidth)
            with result.inspectorLabel = Label.create(result.info!, "", {0, 0, HexInfoWidth, 32}, null, .SecondaryText | .Ellipsis)
            {
                .dockStyle = .Center
                .style.setFont(result.theme().createDefaultFontFS(12), .Regular)
                .setTextAlignment(.Right, .OpticalCenter)
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

        with result.byteOrder = CheckButton.create(result.commands, hexStrings().ui_Endian, {0, 0, 132, 36})
        {
            .dockStyle = .Left
            .margin.x  = 8
            .toolTip   = hexStrings().ui_TipEndian
            .setState(.Checked)
            .sigChanged += func|view = result|(button)
            {
                view.grid.setBigEndian(!button.isChecked())
            }
        }

        result.analysisView = HexAnalysisView.create(result)
        result.analysisView.hide()
        Separator.create(result.analysisView, .Left)
        result.analysisView.sigRefresh += func|view = result|(panel)
        {
            view.startAnalysisRange(panel.result.range, panel.selection)
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
        if reportFailure
        {
            let report = reportFailure!
            result.grid.doc.reportFailure = func|result, report|(reason) { report(cast(*Wnd) result, reason) }
        }

        result.details = hexStrings().ui_Details
        result.applyLayout()
        result.grid.refreshLayout()
        result.refreshInspector()
        result.setInitialFocus(result.grid)
        result.load.start(fileName, &loadHexDocument)
        result.loadTimer = result.addTimer(ViewerBackgroundPollInterval)
        return result
    }
}

// Creates the integrated hexadecimal view.
func createHexViewer(request: const *ViewerRequest, result: *ViewerResult)
{
    registerHexStrings(request.contentParent.app())
    let view = HexViewer.create(request.contentParent, request.commandParent, request.fileName, request.reportFailure, request.reportDetails, request.reportLoadingChanged, request.infoParent)

    result.view        = view
    result.info        = view.info
    result.commands    = view.commands
    result.details     = view.details
    result.revealMatch = func(wnd, match, text)->bool
    {
        discard text
        return (cast(*HexViewer) wnd).revealOffset(match.offset, match.length)
    }
    result.searchBounds = func(wnd, match, bounds)->bool
    {
        discard match
        return (cast(*HexViewer) wnd).grid.matchBounds(bounds)
    }
    result.clearSearch         = func(wnd) { (cast(*HexViewer) wnd).grid.clearSearchMatch() }
    result.describeSearch      = func(wnd, presentation) { (cast(*HexViewer) wnd).describeSearch(presentation) }
    result.prepareSearch       = func(wnd, query, plan)->EditBoxCheckResult { return (cast(*HexViewer) wnd).prepareSearch(query, plan) }
    result.collectFileMatches  = func(wnd, source, baseOffset, matches) { (cast(*HexViewer) wnd).collectSearchMatches(source, baseOffset, matches) }
    result.useSearchMatches    = func(wnd, matches) { (cast(*HexViewer) wnd).grid.setSearchMatches(matches) }
    result.isLoading           = func(wnd)->bool { return (cast(*HexViewer) wnd).loadTimer != null }
    result.needsLoadingOverlay = func(wnd)->bool { return (cast(*HexViewer) wnd).loadTimer != null }
    result.retire              = func(wnd)->bool { return (cast(*HexViewer) wnd).retire() }
}
