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
    const NavigationHistoryLimit = 64'u64

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

// Converts one IEEE-754 binary16 value to binary32 without relying on host-specific half types.
func float16ToFloat(value: u16)->f32
{
    let sign     = cast(u32, value & 0x8000'u16) << 16
    let exponent = (value >> 10) & 0x1F'u16
    var fraction = cast(u32, value & 0x03FF'u16)
    var bits     = sign
    if exponent == 0
    {
        if fraction
        {
            var exponent32 = 113'u32
            while (fraction & 0x400) == 0
            {
                fraction <<= 1
                exponent32 -= 1
            }
            fraction &= 0x3FF
            bits |= exponent32 << 23 | fraction << 13
        }
    }
    elif exponent == 0x1F
    {
        bits |= 0x7F800000 | fraction << 13
    }
    else
    {
        bits |= (cast(u32, exponent) + 112) << 23 | fraction << 13
    }

    return cast #bit (f32, bits)
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
        goToButton:        *IconButton
        copyBytesButton:   *IconButton
        copyFormatsButton: *IconButton
        analysisButton:    *IconButton
        optionsButton:     *IconButton
        analysisView:      *AnalysisView
        grid:              *GridView
        tabs:              *StructureTabs
        inspector:         *FloatingPanel
        inspectorView:     *InspectorView
    }

    zoomLabel: *IconButton?
    built:     bool     // Whether every part the page places exists.

    // How the bytes are laid out and read, as the options chose it.
    rowWidthIndex:   u32      // Zero fits the window; otherwise 8, 16, 32 or 64 bytes per row.
    valueWidthIndex: u32      // One, two, four or eight bytes per value.
    formatIndex:     u32      // Hexadecimal, unsigned, signed, or float for the wide values.
    bigEndian:       bool     // Whether multi-byte values read their most significant byte first.

    searchPattern:     SearchPattern
    bookmarkOffset:    u64
    hasBookmark:       bool     // One session-local byte offset; set after the lens stores it.
    baseAddress:       u64      // Virtual address mapped to file offset zero for Go To expressions.
    navigationHistory: Array'u64
    navigationIndex:   u64 = Swag.U64.Max
    navigatingHistory: bool
    analysis:          AnalysisOperation
    analysisTimer:     *Timer?     // Refreshes the progress of a running analysis.
    fileName:          String
    details:           String
    structure:         Structure     // What the binary readers recognized; the tabs and the inspector read it.
    load:              Viewer.BackgroundLoad'Loaded
    services:          Viewer.HostServices
    failureReason:     String
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
        .goToButton.enable(.grid.doc.fileSize != 0)
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
    // Adds an explicit destination to the bounded offset history, preserving the current position
    // as a return point and dropping any forward branch after a new visit.
    private mtd recordNavigation(offset, from: u64)
    {
        if .navigatingHistory or offset >= .grid.doc.fileSize do
            return

        if not .navigationHistory.count
        {
            .navigationHistory.add(from)
            .navigationIndex = 0
        }
        elif .navigationIndex < .navigationHistory.count and .navigationHistory[.navigationIndex] != from
        {
            .navigationHistory.resize(.navigationIndex + 1)
            .navigationHistory.add(from)
            .navigationIndex = .navigationHistory.count - 1
        }

        if .navigationIndex < .navigationHistory.count and .navigationHistory[.navigationIndex] == offset do
            return
        if .navigationIndex != Swag.U64.Max and .navigationIndex + 1 < .navigationHistory.count do
            .navigationHistory.resize(.navigationIndex + 1)
        .navigationHistory.add(offset)
        .navigationIndex = .navigationHistory.count - 1

        if .navigationHistory.count > NavigationHistoryLimit
        {
            .navigationHistory.remove(0, .navigationHistory.count - NavigationHistoryLimit)
            .navigationIndex = .navigationHistory.count - 1
        }
    }

    // Reveals an explicit destination and optionally selects its byte range.
    private mtd navigateTo(offset, length: u64, selectRange = false)->bool
    {
        if offset >= .grid.doc.fileSize do
            return false
        let previous = .grid.caret
        if selectRange
        {
            .grid.selectRange(offset, length)
        }
        elif length
        {
            if not .grid.revealRange(offset, length) do
                return false
        }
        else
        {
            .grid.moveCaret(offset, false, center: true)
        }

        .recordNavigation(offset, previous)
        .grid.setFocus()
        return true
    }

    // Returns to a preceding or following explicit byte offset.
    mtd navigateHistory(direction: s32)->bool
    {
        if .navigationIndex == Swag.U64.Max do
            return false
        let next = cast(s64, .navigationIndex) + direction
        if next < 0 or next >= cast(s64, .navigationHistory.count) do
            return false
        .navigatingHistory = true
        defer .navigatingHistory = false
        .navigationIndex = cast(u64, next)
        .grid.moveCaret(.navigationHistory[.navigationIndex], false, center: true)
        .grid.setFocus()
        return true
    }

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
        result.selection = .grid.hasSelection()
        result.range     = result.selection ?
                           AnalysisRange{.grid.selectionStart(), .grid.selectionLength()} :
                           AnalysisRange{0, .grid.doc.fileSize}
        return result
    }

    // Shows the analysis panel and analyzes the selection, or the whole file when only the caret is set.
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
        .analysis.start(.fileName, range, me, .analysisView.algorithms)
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
        .goToButton.toolTip        = texts().ui_GoTo
        .copyBytesButton.toolTip   = texts().ui_CopyBytes
        .copyFormatsButton.toolTip = texts().ui_CopyFormats
        .optionsButton.toolTip     = appStrings().ui_Options
        .analysisButton.toolTip    = texts().ui_AnalysisTip
        .analysisView.retranslate()
        .grid.invalidate()
        .refreshInspector()
    }

    // Gives the lens the commands, the options and the zoom of the byte view.
    mtd describeLens(entries: *Viewer.LensEntries)
    {
        // `:` and an offset, in the grammar of Go to Offset, go there.
        if entries.results.prefix == .Line
        {
            let target = parseFileOffset(entries.query.toString(), .grid.caret, .grid.doc.fileSize, .baseAddress, .bookmarkOffset, true)
            if target != Swag.U64.Max
            {
                let value = formatDigits(target, .grid.offsetDigits)
                entries.add(Viewer.jumpRowText(appStrings().lens_GoToOffset, value.toString(), entries.query.toString()), .GoTo, func|view = me, target|() { discard view.navigateTo(target, 0) })
            }

            return
        }

        // The commands of the context menu, so none of them needs a right click.
        let strings      = texts()
        let hasSelection = .grid.hasSelection()
        let bounded      = .grid.selectionLength() > CopyLimit
        let limit        = StrConv.toDisplaySize(CopyLimit)
        entries.add(strings.ui_GoTo, .GoTo, func|view = me|() { view.grid.promptGoToOffset() }, disabled: not .grid.doc.fileSize, defaultKey: {modifiers: .Control, key: .G}, bindId: "scope.hex.goTo")
        entries.add(strings.ui_SetBaseAddress, .Settings, func|view = me|() { view.promptBaseAddress() }, bindId: "scope.hex.setBaseAddress")
        let canGoBack    = .navigationIndex != Swag.U64.Max and .navigationIndex > 0
        let canGoForward = .navigationIndex != Swag.U64.Max and .navigationIndex + 1 < .navigationHistory.count
        entries.add(strings.ui_Back, .ChevronLeft, func|view = me|() { discard view.navigateHistory(-1) }, disabled: not canGoBack, defaultKey: {modifiers: .Alt, key: .Left}, bindId: "scope.hex.back")
        entries.add(strings.ui_Forward, .ChevronRight, func|view = me|() { discard view.navigateHistory(1) }, disabled: not canGoForward, defaultKey: {modifiers: .Alt, key: .Right}, bindId: "scope.hex.forward")
        entries.add(bounded ? Format.toString(strings.ui_CopyBytesMax, limit) : String.from(strings.ui_CopyBytes), .Copy, func|view = me|() { view.grid.copySelection(.Bytes) }, disabled: not hasSelection, defaultKey: {modifiers: .Control, key: .C}, bindId: "scope.hex.copyBytes")
        entries.add(bounded ? Format.toString(strings.ui_CopyTextMax, limit) : String.from(strings.ui_CopyText), .Copy, func|view = me|() { view.grid.copySelection(.Text) }, disabled: not hasSelection, bindId: "scope.hex.copyText")
        entries.add(bounded ? Format.toString(strings.ui_CopyDumpMax, limit) : String.from(strings.ui_CopyDump), .Copy, func|view = me|() { view.grid.copySelection(.Dump) }, disabled: not hasSelection, bindId: "scope.hex.copyDump")
        entries.add(Format.toString(strings.ui_CopyOffset, offsetHex(.grid.caret)), .Copy, func|view = me|() { Clipboard.setString(offsetHex(view.grid.caret)) }, disabled: not .grid.doc.fileSize, bindId: "scope.hex.copyOffset")
        entries.add(strings.ui_CopyValue, .Copy, func|view = me|() { Clipboard.setString(view.inspectorView.headline) }, disabled: .inspectorView.headline.isEmpty(), bindId: "scope.hex.copyValue")
        for reading in .inspectorView.readings
        {
            let title = Format.toString(strings.ui_CopyReading, reading.label)
            let value = reading.value.toString()
            entries.add(title, .Copy, func|value|() { Clipboard.setString(value) }, disabled: reading.value.isEmpty())
        }
        entries.add(strings.ui_SelectAll, .SelectAll, func|view = me|() { view.grid.selectAll() }, disabled: not .grid.doc.fileSize, defaultKey: {modifiers: .Control, key: .A}, bindId: "scope.hex.selectAll")
        entries.add(strings.ui_SetBookmark, .GoTo, func|view = me|() { view.bookmarkOffset = view.grid.caret; view.grid.bookmarkOffset = view.bookmarkOffset; view.hasBookmark = true }, disabled: not .grid.doc.fileSize, defaultKey: {modifiers: Input.KeyModifiers.Control | .Shift, key: .B}, bindId: "scope.hex.setBookmark")
        if .hasBookmark
        {
            let bookmark = .bookmarkOffset
            let address  = offsetHex(bookmark)
            entries.add(Format.toString(strings.ui_GoToBookmark, address), .GoTo, func|view = me, bookmark|() { discard view.navigateTo(bookmark, 0) }, disabled: bookmark >= .grid.doc.fileSize, defaultKey: {modifiers: Input.KeyModifiers.Control | .Alt, key: .B}, bindId: "scope.hex.goToBookmark")
        }

        entries.add(appStrings().cmd_Options, .Settings, func|view = me|() { view.showOptions() }, bindId: "scope.hex.options")

        // The zoom keys step the size of the bytes within the grid's own bounds rather than the
        // shared ones, so only actual size is the shared row.
        entries.add(appStrings().cmd_ZoomIn, .ZoomIn, func|view = me|() { view.grid.adjustFontSize(1) }, disabled: .grid.fontSize >= MaxFontSize, defaultKey: {modifiers: .Control, key: .OemPlus}, bindId: "scope.hex.zoomIn")
        entries.add(appStrings().cmd_ZoomOut, .ZoomOut, func|view = me|() { view.grid.adjustFontSize(-1) }, disabled: .grid.fontSize <= MinFontSize, defaultKey: {modifiers: .Control, key: .OemMinus}, bindId: "scope.hex.zoomOut")
        entries.addZoom(.Reset, .zoomPercent(), func|view = me|() { view.grid.resetFontSize() })
        entries.add(appStrings().cmd_ZoomMenu, .ZoomLevels, func|view = me|() { view.showZoomMenu() }, bindId: "scope.hex.zoomMenu")

        // Each copied checksum names its algorithm and the half-open byte range it covers.
        let result = &.analysisView.result
        if result.hasDigests
        {
            if result.algorithms.crc32 do entries.add(strings.ui_AnalysisCopyCrc32, .Copy, func|view = me|() { Clipboard.setString(view.analysisView.result.digestCopyText("CRC-32", view.analysisView.result.crc32Text())) }, bindId: "scope.hex.analysisCopyCrc32")
            if result.algorithms.crc64 do entries.add(strings.ui_AnalysisCopyCrc64, .Copy, func|view = me|() { Clipboard.setString(view.analysisView.result.digestCopyText("CRC-64/ECMA-182", view.analysisView.result.crc64Text())) }, bindId: "scope.hex.analysisCopyCrc64")
            if result.algorithms.md5 do entries.add(strings.ui_AnalysisCopyMd5, .Copy, func|view = me|() { Clipboard.setString(view.analysisView.result.digestCopyText("MD5", view.analysisView.result.md5Text())) }, bindId: "scope.hex.analysisCopyMd5")
            if result.algorithms.sha1 do entries.add(strings.ui_AnalysisCopySha1, .Copy, func|view = me|() { Clipboard.setString(view.analysisView.result.digestCopyText("SHA-1", view.analysisView.result.sha1Text())) }, bindId: "scope.hex.analysisCopySha1")
            if result.algorithms.sha256 do entries.add(strings.ui_AnalysisCopySha256, .Copy, func|view = me|() { Clipboard.setString(view.analysisView.result.digestCopyText("SHA-256", view.analysisView.result.sha256Text())) }, bindId: "scope.hex.analysisCopySha256")
            if result.algorithms.sha512 do entries.add(strings.ui_AnalysisCopySha512, .Copy, func|view = me|() { Clipboard.setString(view.analysisView.result.digestCopyText("SHA-512", view.analysisView.result.sha512Text())) }, bindId: "scope.hex.analysisCopySha512")
            if result.algorithms.blake2s do entries.add(strings.ui_AnalysisCopyBlake2s, .Copy, func|view = me|() { Clipboard.setString(view.analysisView.result.digestCopyText("BLAKE2s-256", view.analysisView.result.blake2sText())) }, bindId: "scope.hex.analysisCopyBlake2s")
            if result.algorithms.blake2b do entries.add(strings.ui_AnalysisCopyBlake2b, .Copy, func|view = me|() { Clipboard.setString(view.analysisView.result.digestCopyText("BLAKE2b-512", view.analysisView.result.blake2bText())) }, bindId: "scope.hex.analysisCopyBlake2b")
        }
    }

    // Opens how the bytes are laid out and read: row width, value width, representation, byte order.
    mtd showOptions()
    {
        let sheet = OptionSheet.View.create(.optionsButton, func|view = me|(page) { view.describeOptions(page) }, owner: me)
        sheet.doModal(.optionsButton, autoDestroy: true)
    }

    mtd describeOptions(page: *OptionSheet.Page)
    {
        let strings = texts()
        page.addLink(strings.ui_RowWidth,
                     rowWidthName(.rowWidthIndex),
                     func|view = me|(rows)
                     {
                         for index in RowWidthCount do
                             rows.addChoice(rowWidthName(index), index == view.rowWidthIndex, func|view, index|() { view.setRowWidth(index) })
                     },
                     icon: .theme().icon(.FitWidth, themeRowIconSize(.themeMetrics())))

        page.addLink(strings.ui_ValueWidth,
                     valueWidthName(.valueWidthIndex),
                     func|view = me|(widths)
                     {
                         for index in 4'u32 do
                             widths.addChoice(valueWidthName(index), index == view.valueWidthIndex, func|view, index|() { view.setValueWidth(index) })
                     },
                     icon: .theme().icon(.ActualSize, themeRowIconSize(.themeMetrics())))

        page.addLink(strings.ui_Representation,
                     formatName(.formatIndex),
                     func|view = me|(formats)
                     {
                         for index in view.formatCount() do
                             formats.addChoice(formatName(index), index == view.formatIndex, func|view, index|() { view.setFormat(index) })
                     },
                     icon: .theme().icon(.FileCode, themeRowIconSize(.themeMetrics())))

        page.addLink(strings.ui_ByteOrder,
                     .bigEndian ? strings.ui_EndianBig : strings.ui_EndianLittle,
                     func|view = me|(orders)
                     {
                         orders.addChoice(texts().ui_EndianLittle, not view.bigEndian, func|view|() { view.setBigEndian(false) })
                         orders.addChoice(texts().ui_EndianBig, view.bigEndian, func|view|() { view.setBigEndian(true) })
                     },
                     icon: .theme().icon(.Sort, themeRowIconSize(.themeMetrics())))
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

    // Offers the two alternate bounded clipboard spellings beside the direct Copy Bytes action.
    private mtd showCopyFormatsMenu()
    {
        if not .grid.hasSelection() do
            return

        with let menu = MenuCtrl.createPopup(.grid, owner: .grid)
        {
            .addItem(Action.CopyText)
            .addItem(Action.CopyDump)
        }

        discard menu.doModal(.copyFormatsButton, autoDestroy: true)
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
        discard .navigateTo(tab.offset, tab.length, selectRange: true)
    }

    // Shows what the caret stands on: the floating inspector, the tab of its structure, and the
    // reading line under the grid.
    mtd refreshInspector()
    {
        .tabs.follow(.grid.caret)

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

        if not .grid.doc.fileSize
        {
            .refreshDetails()
            return
        }
        let caret     = .grid.caret
        let bytes     = .grid.doc.read(caret, Math.min(8'u64, .grid.doc.fileSize - caret))
        let bigEndian = .readingBigEndian()
        if bytes.isEmpty()
        {
            .refreshDetails()
            return
        }

        .describeValue(caret, bigEndian)
        .describeReadings(bytes.toSlice(), bigEndian)
        .describeFields(caret)
        .refreshDetails()
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
                view.headline = Viewer.groupThousands(readScalar(bytes.toSlice(), bigEndian))
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
            view.headline = Viewer.groupThousands(formatScalar(grouping, readScalar(bytes.toSlice(), bigEndian)))
        else do
            view.headline = String.from("--")
        view.caption = Format.toString(texts().ui_InspectorAt, kind, .offsetText(start))
    }

    // Lists the bytes under the caret in the readings a reader reaches for most: a byte, a short,
    // a signed and an unsigned word in both orders, and a float.
    private mtd describeReadings(bytes: const [..] u8, bigEndian: bool)
    {
        let view = .inspectorView
        view.readings.add({"u8", Viewer.groupThousands(cast(u64, bytes[0])), false})
        if bytes.count >= 2
        {
            let value = readScalar(bytes[until 2], bigEndian)
            view.readings.add({"u16", Viewer.groupThousands(value), false})
            view.readings.add({texts().ui_InspectorFloat16,
                               Format.toString("%{g4}", float16ToFloat(cast(u16, value))), false})
        }

        if bytes.count < 4 do
            return
        let word  = readScalar(bytes[until 4], bigEndian)
        let other = readScalar(bytes[until 4], not bigEndian)
        view.readings.add({"s32", Viewer.groupThousands(Format.toString("%", signedScalar(word, 4))), false})
        view.readings.add({bigEndian ? "u32 LE" : "u32 BE", Viewer.groupThousands(other), false})
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
            line.value  = Viewer.groupThousands(row.value)
            line.strong = rows[index] == field
            if not row.detail.isEmpty() do
                line.value = Format.toString("% · %", line.value, row.detail)
            .inspectorView.fields.add(#move line)
        }
    }

    // Writes the caret, selection, active value, and percentage to the reading line. The host adds
    // the file size and keeps the complete string as the line's tooltip.
    mtd refreshDetails()
    {
        let fileSize = .grid.doc.fileSize
        let percent = fileSize > 1 ? cast(f64, .grid.caret) * 100 / cast(f64, fileSize - 1) : 0'f64
        let hexCaret = Format.toString("0x%{X}", .grid.caret)
        let decimalCaret = Format.toString("%", .grid.caret)
        var value = .inspectorView.headline.isEmpty() ? String.from("—") : .inspectorView.headline
        value.replace(" ", "")
        if .grid.hasSelection()
        {
            .details = Format.toString(texts().ui_DetailsSelection,
                                       percent,
                                       value,
                                       Format.toString("0x%{X}", .grid.selectionStart()),
                                       Format.toString("0x%{X}", .grid.selectionEnd()),
                                       Format.toString("%", .grid.selectionStart()),
                                       Format.toString("%", .grid.selectionEnd()),
                                       Format.toString("%", .grid.selectionLength()),
                                       Format.toString("0x%{X}", .grid.selectionLength()),
                                       hexCaret,
                                       decimalCaret)
        }
        else
        {
            .details = Format.toString(texts().ui_DetailsCaret, percent, value, hexCaret, decimalCaret)
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
        let trimmed = Latin1.trim(query)
        let selectionScoped = Utf8.startsWith(trimmed, "selection:", .Latin1NoCase)
        let patternQuery = selectionScoped ? Latin1.trim(cast(string, trimmed[10 to])) : query
        if selectionScoped
        {
            if Utf8.startsWith(patternQuery, "range:", .Latin1NoCase)
            {
                result.error = texts().ui_SearchRangeInvalid
                return .InvalidVisible
            }
            if not .grid.hasSelection()
            {
                result.error = texts().ui_SearchSelectionRequired
                return .InvalidVisible
            }
            if not patternQuery.count do
                return .Incomplete
            result.byteRange = {offset: .grid.selectionStart(), length: .grid.selectionLength()}
        }

        var parsed = parseSearch(patternQuery, .grid.grouping, .grid.bigEndian)
        switch #complete parsed.state
        {
        case .Incomplete:
            return .Incomplete

        case .Invalid:
            if parsed.error == .Range
            {
                result.error = texts().ui_SearchRangeInvalid
            }
            else
            {
                result.error = parsed.error == .Value ? texts().ui_SearchValueError : texts().ui_SearchPatternError
            }
            return .InvalidVisible

        case .Valid:
            if parsed.hasByteRange
            {
                if parsed.rangeLength == 0 or not Viewer.isByteRangeInBounds(.grid.doc.fileSize, parsed.rangeOffset, parsed.rangeLength)
                {
                    result.error = texts().ui_SearchRangeInvalid
                    return .InvalidVisible
                }
                result.byteRange = {offset: parsed.rangeOffset, length: parsed.rangeLength}
            }
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
        return .navigateTo(offset, length)
    }
}

impl Panel
{
    // Keeps the configured virtual base address available to every Go To entry point.
    mtd setBaseAddress(address: u64)
    {
        .baseAddress = address
        .grid.baseAddress = address
    }

    // Asks for the virtual address that maps to file offset zero; entering zero clears it.
    mtd promptBaseAddress()
    {
        let current = Format.toString("0x%{X}", .baseAddress)
        with var options: EditDlgOptions
        {
            .title   = texts().ui_SetBaseAddress
            .message = texts().ui_BaseAddressMessage
            .text    = current
        }

        let dialog = EditDlg.createSingleLine(unwrap .surface, options)
        if dialog.doModal() != Dialog.BtnOk do
            return

        let address = parseFileOffset(dialog.text(), 0, Swag.U64.Max)
        if address != Swag.U64.Max do
            .setBaseAddress(address)
    }

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

        let actions = host.createActionGroup(themeActionButtonSize(result.themeMetrics()))
        actions.dockStyle = .Right
        actions.margin.z  = 12

        with result.goToButton = Viewer.createActionButton(actions, .GoTo)
        {
            .toolTip = texts().ui_GoTo
            .enable(false)
            .sigPressed += func|view = result|(_)
            {
                view.grid.promptGoToOffset()
            }
        }

        with result.copyBytesButton = Viewer.createActionButton(actions, .Copy)
        {
            .toolTip = texts().ui_CopyBytes
            .enable(false)
            .sigPressed += func|view = result|(_)
            {
                view.grid.copySelection(.Bytes)
            }
        }

        with result.copyFormatsButton = Viewer.createActionDropDown(actions, .Copy)
        {
            .toolTip = texts().ui_CopyFormats
            .enable(false)
            .setArrowPosition(.RightUpward)
            .sigPressed += func|view = result|(_)
            {
                view.showCopyFormatsMenu()
            }
        }

        result.createAnalysisPanel(host)
        result.createReadingControls(host)
        result.createTabs()
        result.createGrid()
        result.createInspector()

        result.built = true
        result.layoutPage()
        result.applyLayout()
        result.grid.refreshLayout()
        result.refreshInspector()
        result.refreshZoom()
        result.load.start(host.fileName(), &loadDocument, result)
        return result
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
                discard view.navigateTo(offset, length)
                view.refreshInspector()
            }
        }
    }

    // Creates the options of the layout and reading of the bytes, and the zoom, at the right of
    // the reading line.
    private mtd createReadingControls(host: Viewer.Host)
    {
        let info = host.createInfoGroup(Viewer.InfoOptionsWidth + Viewer.ZoomSlotWidth)
        with .optionsButton = Viewer.createInfoOptionsButton(info)
        {
            .sigPressed += func|view = me|(_) { view.showOptions() }
        }

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
            .baseAddress    = me.baseAddress
            .bookmarkOffset = me.hasBookmark ? me.bookmarkOffset : Swag.U64.Max
            .sigGoToOffset += func|view = me|(_, offset)
            {
                view.recordNavigation(offset, view.grid.caret)
            }

            .sigCaretChanged += func|view = me|(_)
            {
                view.refreshInspector()
                view.copyBytesButton.enable(view.grid.hasSelection())
                view.copyFormatsButton.enable(view.grid.hasSelection())
            }

            .sigZoomChanged += func|view = me|(_)
            {
                view.refreshZoom()
            }
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

// Writes `offset` as a hexadecimal address a reader pastes into another tool: `0x` and eight
// digits, sixteen past four gigabytes.
func offsetHex(offset: u64)->String => offset > Swag.U32.Max ? Format.toString("0x%{X016}", offset) : Format.toString("0x%{X08}", offset)

// Creates the integrated hexadecimal view.
func createViewer(host: Viewer.Host)
{
    let view = Panel.create(host)

    host.attachView(view)
    host.setDetails(view.details)

    // The caret offset and the selection are readings of the foot of the document, not of the
    // file: the sheet keeps the file's own readings only.
    host.setInformation(func(_) {})

    with var search: Viewer.SearchApi
    {
        .revealMatch        = func|view|(match, _) => view.navigateTo(match.offset, match.length)
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
