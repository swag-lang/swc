#global internal
#global namespace Viewers.Hex

using Core, Pixel, Gui

// Map of the 256 byte values, shaded by how often each occurs.
//
// The 16x16 cells keep their hexadecimal position, high nibble by row and low nibble by column,
// while the alternate theme tone carries frequency; empty cells remain on the panel ground.
struct HistogramView
{
    using wnd: Wnd

    histogram: [256] u64
    total:     u64
    maximum:   u64
    hovered:   u32 = Swag.U32.Max     // Byte value under the pointer, or `Swag.U32.Max` for none.

    sigByteChanged: SigArray'func||(*HistogramView, u32)     // Emitted with the new hovered value.
}

private impl HistogramView
{
    mtd geometry()->{origin: Math.Point, pitch, cell: f32}
    {
        let client    = .clientRect()
        let available = Math.max(Math.min(client.width, client.height) - Inset * 2, 16)
        let pitch     = Math.floor(available / 16)
        let extent    = pitch * 16
        var result: retval
        result.origin = {client.horzCenter() - extent * 0.5, client.vertCenter() - extent * 0.5}
        result.pitch  = pitch
        result.cell   = Math.max(pitch - Gap, 1)
        return result
    }

    mtd byteAt(point: Math.Point)->u32
    {
        let geometry = .geometry()
        let x        = point.x - geometry.origin.x
        let y        = point.y - geometry.origin.y
        if x < 0 or y < 0 or x >= geometry.pitch * 16 or y >= geometry.pitch * 16 do
            return Swag.U32.Max
        return cast(u32, y / geometry.pitch) * 16 + cast(u32, x / geometry.pitch)
    }
}

private impl IWnd for HistogramView
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter   = evt.paintContext.painter
        let colors    = .themeColors()
        let alternate = .theme().palette.alternate.mark
        let corner    = .themeRects().btnIcon_RoundSquareBk.radius
        let geometry  = .geometry()
        for value in 256'u32
        {
            let row      = value / 16
            let column   = value % 16
            let count    = .histogram[value]
            let strength = count and .maximum ? 0.12'f32 + 0.80'f32 * Math.sqrt(cast(f32, count) / cast(f32, .maximum)) : 0
            let color    = Color.lerp(colors.wnd_Bk, alternate, strength)
            let box      = Math.Rectangle{geometry.origin.x + cast(f32, column) * geometry.pitch, geometry.origin.y + cast(f32, row) * geometry.pitch, geometry.cell, geometry.cell}
            painter.fillRoundRect(box, corner, corner, color)
            if value == .hovered do
                painter.drawRoundRect(box, corner, corner, colors.hilight, 1)
        }
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        var next = Swag.U32.Max
        if evt.kind == .Move or evt.kind == .Enter
        {
            next = .byteAt(.surfaceToLocal(evt.surfacePos))
        }
        elif evt.kind != .Leave
        {
            evt.accepted = false
            return
        }

        if next == .hovered do
            return
        .hovered = next
        .sigByteChanged.call(me, next)
        .invalidate()
    }
}

impl HistogramView
{
    // The square the 16x16 map fills, the margin around it, and the gap between its cells.
    const Size  = 184.0
    const Inset = 8.0
    const Gap   = 2.0

    func create(parent: *Wnd)->*HistogramView
    {
        with let result = Wnd.create'HistogramView(parent, {0, 0, 0, Size})
        {
            .dockStyle       = .Top
            .backgroundStyle = .Transparent
        }

        return result
    }

    mtd setResult(result: const *AnalysisResult)
    {
        .histogram = result.histogram
        .total     = result.scanned
        .maximum   = 0
        for count in .histogram do
            .maximum = Math.max(.maximum, count)
        .hovered = Swag.U32.Max
        .invalidate()
    }

    mtd clear()
    {
        for i in 256 do
            .histogram[i] = 0
        .total   = 0
        .maximum = 0
        .hovered = Swag.U32.Max
        .invalidate()
    }
}

// Right-side findings panel. It owns one bounded result and returns every inferred string to its
// exact byte range when selected.
struct AnalysisView
{
    using wnd: Wnd

    late
    {
        titleLabel:    *Label
        analyzeButton: *IconButton
        cancelButton:  *IconButton
        closeButton:   *IconButton
        scopeLabel:    *Label
        metricsLabel:  *Label
        histogram:     *HistogramView
        byteLabel:     *Label
        stringsLabel:  *Label
        stringsList:   *ListCtrl
    }

    result:       AnalysisResult
    offsetDigits: u64 = 8
    selection:    bool

    sigAnalyze:  SigArray'func||(*AnalysisView)
    sigCancel:   SigArray'func||(*AnalysisView)
    sigClose:    SigArray'func||(*AnalysisView)
    sigNavigate: SigArray'func||(*AnalysisView, u64, u64)
}

private impl AnalysisView
{
    mtd offsetText(offset: u64)->String => formatDigits(offset, .offsetDigits)

    mtd scopeText(range: AnalysisRange)->String
    {
        if .selection do
            return Format.toString(texts().ui_AnalysisSelection, .offsetText(range.offset), StrConv.toDisplaySize(range.length))
        return Format.toString(texts().ui_AnalysisFile, StrConv.toDisplaySize(range.length))
    }

    mtd encodingName(kind: AnalysisStringKind)->string
    {
        switch #complete kind
        {
        case .Ascii:       return texts().ui_AnalysisAscii
        case .Utf16Little: return texts().ui_AnalysisUtf16Little
        case .Utf16Big:    return texts().ui_AnalysisUtf16Big
        }
    }

    mtd updateByteDetail(value: u32)
    {
        if value == Swag.U32.Max or not .result.scanned
        {
            .byteLabel.setText(texts().ui_AnalysisByteHint)
            return
        }

        let count = .result.histogram[value]
        let share = cast(f64, count) * 100 / cast(f64, .result.scanned)
        .byteLabel.setText(Format.toString(texts().ui_AnalysisByte, value, count, share))
    }

    mtd fillStringLine(line: *ListLine, index: u32)
    {
        if index >= .result.strings.count do
            return
        let value = &.result.strings[index]
        line.setItem(0, .offsetText(value.offset))
        line.setItem(1, .encodingName(value.kind))
        line.setItem(2, value.text)
    }

    mtd navigateSelection(list: *ListCtrl)
    {
        for index in list.lineCount() where list.isLineSelected(index)
        {
            if index >= .result.strings.count do
                return
            let value = &.result.strings[index]
            .sigNavigate.call(me, value.offset, value.length)
            return
        }
    }

    // Shows the analysis outcome: the failure, the amount scanned before a cancellation, or the
    // entropy and the share of zero and printable bytes, then the strings count.
    mtd refreshResultText()
    {
        .scopeLabel.setText(.scopeText(.result.range))
        if not .result.failureReason.isEmpty()
        {
            .metricsLabel.setText(.result.failureReason)
        }
        elif .result.cancelled
        {
            .metricsLabel.setText(Format.toString(texts().ui_AnalysisCancelled, StrConv.toDisplaySize(.result.scanned)))
        }
        elif .result.scanned
        {
            let zero      = cast(f64, .result.zeroCount) * 100 / cast(f64, .result.scanned)
            let printable = cast(f64, .result.printableCount) * 100 / cast(f64, .result.scanned)
            .metricsLabel.setText(Format.toString(texts().ui_AnalysisMetrics, .result.entropy, zero, printable))
        }
        else
        {
            .metricsLabel.setText(texts().ui_AnalysisNoBytes)
        }

        if .result.stringsTruncated do
            .stringsLabel.setText(Format.toString(texts().ui_AnalysisStringsLimited, .result.strings.count))
        else do
            .stringsLabel.setText(Format.toString(texts().ui_AnalysisStringsCount, .result.strings.count))
    }

    // Creates the title row and its run, stop, and close actions.
    mtd createHeader()
    {
        let compactSize = themeCompactButtonSize(.themeMetrics())
        let rowIconSize = themeRowIconSize(.themeMetrics())

        with let header = Wnd.create'Wnd(me, {0, 0, 0, compactSize})
        {
            .dockStyle       = .Top
            .backgroundStyle = .Transparent
        }

        with .closeButton = IconButton.create(header, .theme().icon(.WndClose, rowIconSize), {0, 0, compactSize, compactSize})
        {
            .dockStyle  = .Right
            .toolTip    = texts().ui_AnalysisClose
            .sigPressed += func|view = me|(_) { view.sigClose.call(view) }
        }

        with .cancelButton = IconButton.create(header, .theme().icon(.Stop, rowIconSize), {0, 0, compactSize, compactSize})
        {
            .dockStyle = .Right
            .toolTip   = texts().ui_AnalysisCancel
            .hide()
            .sigPressed += func|view = me|(_) { view.sigCancel.call(view) }
        }

        with .analyzeButton = IconButton.create(header, .theme().icon(.Play, rowIconSize), {0, 0, compactSize, compactSize})
        {
            .dockStyle  = .Right
            .toolTip    = texts().ui_AnalysisRun
            .sigPressed += func|view = me|(_) { view.sigAnalyze.call(view) }
        }

        with .titleLabel = Label.create(header, texts().ui_Analysis, {0, 0, 0, compactSize})
        {
            .dockStyle = .Center
            .style.setFont(me.theme().createDefaultFont(13, .Bold), .Regular)
            .setTextAlignment(.Left, .Center)
        }
    }

    // Creates the list of inferred strings, where selecting a line navigates to its bytes.
    mtd createStringsList()
    {
        with .stringsList = ListCtrl.createMultiColumns(me)
        {
            .dockStyle       = .Center
            .backgroundStyle = .Transparent
            .listView.backgroundStyle = .Transparent
            .style.setFont(me.theme().createDefaultFontFs(me.themeMetrics().defaultFixedFontSize), .Regular)
            .setSelectionMode(.Single)
            .setFirstColumnIconMargin(false)
            .updateFlags(.HotTrack | .Ellipsis)
            .scrollWnd.updateFlags(.DisableHorizontal)
            .header.form = .Transparent
            .header.updateFlags(remove: .Clickable | .Separators)
            .addColumn(texts().ui_AnalysisOffset, 82)
            .addColumn(texts().ui_AnalysisEncoding, 78)
            .addColumn(texts().ui_AnalysisText, 150)
            .onFillVirtualLine   = &fillAnalysisStringLine
            .sigSelectionChanged += func|view = me|(list) { view.navigateSelection(list) }
        }
    }
}

impl AnalysisView
{
    // Width of the analysis panel, and the heights of its section labels and metrics row.
    const PanelWidth    = 368.0
    const LabelHeight   = 24.0
    const MetricsHeight = 42.0

    // Clears the panel for a new analysis of `range`, and shows its cancel action.
    //
    // `selection` says whether `range` comes from a selection rather than the whole file, and
    // `offsetDigits` is the width the grid writes offsets with.
    mtd begin(range: AnalysisRange, selection: bool, offsetDigits: u64)
    {
        .selection    = selection
        .offsetDigits = offsetDigits
        .result       = {}
        .result.range = range
        .scopeLabel.setText(.scopeText(range))
        .metricsLabel.setText(Format.toString(texts().ui_AnalysisProgress, 0'f64))
        .histogram.clear()
        .byteLabel.setText(texts().ui_AnalysisByteHint)
        .stringsLabel.setText(texts().ui_AnalysisStrings)
        .stringsList.setVirtualCount(0)
        .analyzeButton.hide()
        .cancelButton.show()
    }

    // Shows the share of the range `processed` bytes represent.
    mtd setProgress(processed: u64)
    {
        let percent = .result.range.length ? cast(f64, processed) * 100 / cast(f64, .result.range.length) : 100
        .metricsLabel.setText(Format.toString(texts().ui_AnalysisProgress, percent))
    }

    // Takes over `result` and shows it, restoring the run action.
    mtd publish(result: *AnalysisResult)
    {
        .result = #move result[]
        .refreshResultText()
        .histogram.setResult(&.result)
        .updateByteDetail(Swag.U32.Max)
        .stringsList.setVirtualCount(cast(u32, .result.strings.count))
        .cancelButton.hide()
        .analyzeButton.show()
        .invalidate()
    }

    mtd retranslate()
    {
        .titleLabel.setText(texts().ui_Analysis)
        .analyzeButton.toolTip             = texts().ui_AnalysisRun
        .cancelButton.toolTip              = texts().ui_AnalysisCancel
        .closeButton.toolTip               = texts().ui_AnalysisClose
        .stringsList.header.itemAt(0).name = texts().ui_AnalysisOffset
        .stringsList.header.itemAt(1).name = texts().ui_AnalysisEncoding
        .stringsList.header.itemAt(2).name = texts().ui_AnalysisText
        .stringsList.header.invalidate()
        if .result.range.length or
           .result.scanned or
           .result.cancelled or
           not .result.failureReason.isEmpty()
        {
            .refreshResultText()
            .updateByteDetail(.histogram.hovered)
        }
    }

    // Builds the analysis panel: header, scope and metrics lines, the byte histogram with the
    // detail of the hovered byte, and the list of strings found.
    func create(parent: *Wnd)->*AnalysisView
    {
        with let result = Wnd.create'AnalysisView(parent)
        {
            .dockStyle       = .Center
            .backgroundStyle = .Transparent
            .padding         = {12, 8, 12, 8}
        }

        result.createHeader()

        with result.scopeLabel = Label.create(result, "", {0, 0, 0, LabelHeight}, null, .SecondaryText | .Ellipsis)
        {
            .dockStyle = .Top
            .style.setFont(result.theme().createDefaultFontFs(12), .Regular)
            .setTextAlignment(.Left, .OpticalCenter)
        }

        with result.metricsLabel = Label.create(result, "", {0, 0, 0, MetricsHeight}, null, .SecondaryText | .WordWrap)
        {
            .dockStyle = .Top
            .style.setFont(result.theme().createDefaultFontFs(12), .Regular)
            .setTextAlignment(.Left, .OpticalCenter)
        }

        with result.histogram = HistogramView.create(result)
        {
            .sigByteChanged += func|view = result|(_, value) { view.updateByteDetail(value) }
        }

        with result.byteLabel = Label.create(result, texts().ui_AnalysisByteHint, {0, 0, 0, LabelHeight}, null, .SecondaryText | .Ellipsis)
        {
            .dockStyle = .Top
            .style.setFont(result.theme().createDefaultFontFs(12), .Regular)
            .setTextAlignment(.Left, .OpticalCenter)
        }

        with result.stringsLabel = Label.create(result, texts().ui_AnalysisStrings, {0, 0, 0, LabelHeight}, null, .SecondaryText | .Ellipsis)
        {
            .dockStyle = .Top
            .setTextAlignment(.Left, .OpticalCenter)
        }

        result.createStringsList()
        result.applyLayout()
        return result
    }
}

// Fills one line of the virtual strings list from the panel that owns the list.
private func fillAnalysisStringLine(list: *ListCtrl, line: *ListLine?, index: u32)
{
    if line do
        assume cast(*AnalysisView, list.parent).fillStringLine(line, index)
}
