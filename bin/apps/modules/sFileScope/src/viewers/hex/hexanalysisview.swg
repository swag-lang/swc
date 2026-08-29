#global internal

using Core, Pixel, Gui

const HexAnalysisPanelWidth     = 368.0
const HexAnalysisHeaderHeight   = 28.0
const HexAnalysisLabelHeight    = 24.0
const HexAnalysisMetricsHeight  = 42.0
const HexAnalysisHistogramSize  = 184.0
const HexAnalysisHistogramInset = 8.0
const HexAnalysisHistogramGap   = 2.0

// A 16x16 byte map. Each cell keeps its hexadecimal position, while the alternate theme tone
// carries frequency; empty cells remain on the panel ground.
struct HexHistogramView
{
    using wnd: Wnd

    histogram: [256] u64
    total:     u64
    maximum:   u64
    hovered = Swag.U32.Max

    sigByteChanged: SigArray'func||(*HexHistogramView, u32)
}

private impl HexHistogramView
{
    mtd geometry()->{origin: Math.Point, pitch, cell: f32}
    {
        let client    = .clientRect()
        let available = Math.max(Math.min(client.width, client.height) - HexAnalysisHistogramInset * 2, 16)
        let pitch     = Math.floor(available / 16)
        let extent    = pitch * 16
        var result: retval
        result.origin = {client.horzCenter() - extent * 0.5, client.vertCenter() - extent * 0.5}
        result.pitch  = pitch
        result.cell   = Math.max(pitch - HexAnalysisHistogramGap, 1)
        return result
    }

    mtd byteAt(point: Math.Point)->u32
    {
        let geometry = .geometry()
        let x        = point.x - geometry.origin.x
        let y        = point.y - geometry.origin.y
        if x < 0 or y < 0 or x >= geometry.pitch * 16 or y >= geometry.pitch * 16 do
            return Swag.U32.Max
        return cast(u32) (y / geometry.pitch) * 16 + cast(u32) (x / geometry.pitch)
    }
}

private impl IWnd for HexHistogramView
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
            let strength = count and .maximum ? 0.12'f32 + 0.80'f32 * Math.sqrt(cast(f32) count / cast(f32) .maximum) : 0
            let color    = Color.lerp(colors.wnd_Bk, alternate, strength)
            let box      = Math.Rectangle{geometry.origin.x + cast(f32) column * geometry.pitch, geometry.origin.y + cast(f32) row * geometry.pitch, geometry.cell, geometry.cell}
            painter.fillRoundRect(box, corner, corner, color)
            if value == .hovered do
                painter.drawRoundRect(box, corner, corner, colors.hilight, 1)
        }
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        var next = Swag.U32.Max
        if evt.kind == .Move or evt.kind == .Enter do
            next = .byteAt(.surfaceToLocal(evt.surfacePos))
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

impl HexHistogramView
{
    func create(parent: *Wnd)->*HexHistogramView
    {
        let result = Wnd.create'HexHistogramView(parent, {0, 0, 0, HexAnalysisHistogramSize})
        result.dockStyle       = .Top
        result.backgroundStyle = .Transparent
        return result
    }

    mtd setResult(result: const *HexAnalysisResult)
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
struct HexAnalysisView
{
    using wnd: Wnd

    #[Swag.Late]
    {
        titleLabel:    *Label
        analyzeButton: *IconButton
        cancelButton:  *IconButton
        closeButton:   *IconButton
        scopeLabel:    *Label
        metricsLabel:  *Label
        histogram:     *HexHistogramView
        byteLabel:     *Label
        stringsLabel:  *Label
        stringsList:   *ListCtrl
    }

    result:       HexAnalysisResult
    offsetDigits: u64 = 8
    selection:    bool

    sigAnalyze:  SigArray'func||(*HexAnalysisView)
    sigCancel:   SigArray'func||(*HexAnalysisView)
    sigClose:    SigArray'func||(*HexAnalysisView)
    sigNavigate: SigArray'func||(*HexAnalysisView, u64, u64)
}

private impl HexAnalysisView
{
    mtd offsetText(offset: u64)->String
    {
        var bytes: Array'u8
        appendHexDigits(&bytes, offset, .offsetDigits)
        return String.from(@mkstring(bytes.buffer!, bytes.count))
    }

    mtd scopeText(range: HexAnalysisRange)->String
    {
        if .selection do
            return Format.toString(hexStrings().ui_AnalysisSelection, .offsetText(range.offset), StrConv.toDisplaySize(range.length))
        return Format.toString(hexStrings().ui_AnalysisFile, StrConv.toDisplaySize(range.length))
    }

    mtd stringKind(kind: HexAnalysisStringKind)->string
    {
        switch kind
        {
        case .Ascii:       return hexStrings().ui_AnalysisAscii
        case .Utf16Little: return hexStrings().ui_AnalysisUtf16Little
        case .Utf16Big:    return hexStrings().ui_AnalysisUtf16Big
        }
    }

    mtd updateByteDetail(value: u32)
    {
        if value == Swag.U32.Max or !.result.scanned
        {
            .byteLabel.setText(hexStrings().ui_AnalysisByteHint)
            return
        }

        let count = .result.histogram[value]
        let share = cast(f64) count * 100 / cast(f64) .result.scanned
        .byteLabel.setText(Format.toString(hexStrings().ui_AnalysisByte, value, count, share))
    }

    mtd fillStringLine(line: *ListLine, index: u32)
    {
        if index >= .result.strings.count do
            return
        let value = &.result.strings[index]
        line.setItem(0, .offsetText(value.offset).toString())
        line.setItem(1, .stringKind(value.kind))
        line.setItem(2, value.text.toString())
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

    mtd refreshResultText()
    {
        .scopeLabel.setText(.scopeText(.result.range).toString())
        if !.result.failureReason.isEmpty() do
            .metricsLabel.setText(.result.failureReason.toString())
        elif .result.cancelled do
            .metricsLabel.setText(Format.toString(hexStrings().ui_AnalysisCancelled, StrConv.toDisplaySize(.result.scanned)))
        elif .result.scanned
        {
            let zero      = cast(f64) .result.zeroCount * 100 / cast(f64) .result.scanned
            let printable = cast(f64) .result.printableCount * 100 / cast(f64) .result.scanned
            .metricsLabel.setText(Format.toString(hexStrings().ui_AnalysisMetrics, .result.entropy, zero, printable))
        }
        else do
            .metricsLabel.setText(hexStrings().ui_AnalysisNoBytes)

        if .result.stringsTruncated do
            .stringsLabel.setText(Format.toString(hexStrings().ui_AnalysisStringsLimited, .result.strings.count))
        else do
            .stringsLabel.setText(Format.toString(hexStrings().ui_AnalysisStringsCount, .result.strings.count))
    }
}

impl HexAnalysisView
{
    mtd begin(range: HexAnalysisRange, selection: bool, offsetDigits: u64)
    {
        .selection    = selection
        .offsetDigits = offsetDigits
        .result       = {}
        .result.range = range
        .scopeLabel.setText(.scopeText(range).toString())
        .metricsLabel.setText(Format.toString(hexStrings().ui_AnalysisProgress, 0'f64))
        .histogram.clear()
        .byteLabel.setText(hexStrings().ui_AnalysisByteHint)
        .stringsLabel.setText(hexStrings().ui_AnalysisStrings)
        .stringsList.setVirtualCount(0)
        .analyzeButton.hide()
        .cancelButton.show()
    }

    mtd setProgress(processed: u64)
    {
        let percent = .result.range.length ? cast(f64) processed * 100 / cast(f64) .result.range.length : 100
        .metricsLabel.setText(Format.toString(hexStrings().ui_AnalysisProgress, percent))
    }

    mtd publish(result: *HexAnalysisResult)
    {
        .result = #move result[]
        .refreshResultText()
        .histogram.setResult(&.result)
        .updateByteDetail(Swag.U32.Max)
        .stringsList.setVirtualCount(cast(u32) .result.strings.count)
        .cancelButton.hide()
        .analyzeButton.show()
        .invalidate()
    }

    mtd retranslate()
    {
        .titleLabel.setText(hexStrings().ui_Analysis)
        .analyzeButton.toolTip             = hexStrings().ui_AnalysisRun
        .cancelButton.toolTip              = hexStrings().ui_AnalysisCancel
        .closeButton.toolTip               = hexStrings().ui_AnalysisClose
        .stringsList.header.itemAt(0).name = hexStrings().ui_AnalysisOffset
        .stringsList.header.itemAt(1).name = hexStrings().ui_AnalysisEncoding
        .stringsList.header.itemAt(2).name = hexStrings().ui_AnalysisText
        .stringsList.header.invalidate()
        if .result.range.length or .result.scanned or .result.cancelled or !.result.failureReason.isEmpty()
        {
            .refreshResultText()
            .updateByteDetail(.histogram.hovered)
        }
    }

    func create(parent: *Wnd)->*HexAnalysisView
    {
        let result = Wnd.create'HexAnalysisView(parent, {0, 0, HexAnalysisPanelWidth, 0})
        result.dockStyle       = .Right
        result.backgroundStyle = .Panel
        result.padding         = {12, 8, 12, 8}

        with let header = Wnd.create'Wnd(result, {0, 0, 0, HexAnalysisHeaderHeight})
        {
            .dockStyle       = .Top
            .backgroundStyle = .Transparent
        }

        with result.closeButton = IconButton.create(header, result.theme().icon(.WndClose, 16), {0, 0, 24, 24})
        {
            .dockStyle  = .Right
            .toolTip    = hexStrings().ui_AnalysisClose
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.sigClose.call(view)
            }
        }

        with result.cancelButton = IconButton.create(header, result.theme().icon(.Stop, 16), {0, 0, 24, 24})
        {
            .dockStyle = .Right
            .toolTip   = hexStrings().ui_AnalysisCancel
            .hide()
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.sigCancel.call(view)
            }
        }

        with result.analyzeButton = IconButton.create(header, result.theme().icon(.Play, 16), {0, 0, 24, 24})
        {
            .dockStyle  = .Right
            .toolTip    = hexStrings().ui_AnalysisRun
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.sigAnalyze.call(view)
            }
        }

        with result.titleLabel = Label.create(header, hexStrings().ui_Analysis, {0, 0, 0, HexAnalysisHeaderHeight})
        {
            .dockStyle = .Center
            .style.setFont(result.theme().createDefaultFont(13, .Bold), .Regular)
            .setTextAlignment(.Left, .Center)
        }

        with result.scopeLabel = Label.create(result, "", {0, 0, 0, HexAnalysisLabelHeight}, null, .SecondaryText | .Ellipsis)
        {
            .dockStyle = .Top
            .style.setFont(result.theme().createDefaultFontFS(12), .Regular)
            .setTextAlignment(.Left, .OpticalCenter)
        }

        with result.metricsLabel = Label.create(result, "", {0, 0, 0, HexAnalysisMetricsHeight}, null, .SecondaryText | .WordWrap)
        {
            .dockStyle = .Top
            .style.setFont(result.theme().createDefaultFontFS(12), .Regular)
            .setTextAlignment(.Left, .OpticalCenter)
        }

        result.histogram                = HexHistogramView.create(result)
        result.histogram.sigByteChanged += func|view = result|(histogram, value)
        {
            discard histogram
            view.updateByteDetail(value)
        }

        with result.byteLabel = Label.create(result, hexStrings().ui_AnalysisByteHint, {0, 0, 0, HexAnalysisLabelHeight}, null, .SecondaryText | .Ellipsis)
        {
            .dockStyle = .Top
            .style.setFont(result.theme().createDefaultFontFS(12), .Regular)
            .setTextAlignment(.Left, .OpticalCenter)
        }

        with result.stringsLabel = Label.create(result, hexStrings().ui_AnalysisStrings, {0, 0, 0, HexAnalysisLabelHeight}, null, .SecondaryText | .Ellipsis)
        {
            .dockStyle = .Top
            .setTextAlignment(.Left, .OpticalCenter)
        }

        with result.stringsList = ListCtrl.createMultiColumns(result)
        {
            .dockStyle                = .Center
            .backgroundStyle          = .Transparent
            .listView.backgroundStyle = .Transparent
            .style.setFont(result.theme().createDefaultFontFS(result.themeMetrics().defaultFixedFontSize), .Regular)
            .setSelectionMode(.Single)
            .setFirstColumnIconMargin(false)
            .updateFlags(.HotTrack | .Ellipsis)
            .scrollWnd.updateFlags(.DisableHorizontal)
            .header.form = .Transparent
            .header.updateFlags(remove: .Clickable | .Separators)
            .addColumn(hexStrings().ui_AnalysisOffset, 82)
            .addColumn(hexStrings().ui_AnalysisEncoding, 78)
            .addColumn(hexStrings().ui_AnalysisText, 150)
            .onFillVirtualLine   = &fillHexAnalysisStringLine
            .sigSelectionChanged += func|view = result|(list) { view.navigateSelection(list) }
        }

        result.applyLayout()
        return result
    }
}

private func fillHexAnalysisStringLine(list: *ListCtrl, line: #null *ListLine, index: u32)
{
    if line do
        (cast(*HexAnalysisView) list.parent!).fillStringLine(line!, index)
}
