#global internal
#global namespace Viewers.Xlsx

using Core, Gui

// Offers sheet values before the generic ZIP package structure.
func viewerPlugin()->Viewer.Plugin
{
    with var result: #returntype
    {
        .key          = "xlsx"
        .staticName   = "Workbook"
        .resolveName  = func()->string => texts().ui_Name
        .attach       = &registerTexts
        .iconAtlas    = viewerIcons()
        .iconIndex    = cast(s32, ViewerIcons.Xlsx)
        .create       = &createViewer
        .smokeFixture = "viewer.xlsx"
        .addSelectors(".xlsx")
    }

    return result
}

struct Panel
{
    using wnd: Wnd

    properties:     Package.DocumentProperties     // What the package says of the document, once read.
    propertiesRead: bool

    workbook:         Workbook
    load:             Viewer.BackgroundLoad'Workbook
    services:         Viewer.HostServices
    view:             *HtmlView?
    grid:             *Grid?
    gridHost:         *Wnd?
    selection:        Address
    textMode:         bool
    showHiddenRanges: bool
    sheet:            u64 = Swag.U64.Max
    visible:          Array'u64
    showHidden:       bool

    late
    {
        status:         *Label
        previousButton: *IconButton
        nextButton:     *IconButton
        sheetLabel:     *Label
        outline:        *DocumentOutline
    }
}

private impl IWnd for Panel
{
    mtd impl onTaskEvent(evt: *TaskEvent)
    {
        if not .load.claim(evt)
        {
            evt.accepted = false
            return
        }

        let failure = .load.finish(&.workbook)
        if not failure.isEmpty()
        {
            .services.failed(me, failure)
            return
        }

        .sheet = .workbook.activeSheet
        .publishSheets()
        .services.loadingChanged(me)
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        evt.accepted = .handleKey(evt)
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged and not .workbook.sheets.isEmpty() do
            .publishSheets()
        .wnd.IWnd.onNotifyEvent(evt)
    }
}

private impl Panel
{
    internal mtd retire()->bool => .load.retire()

    mtd refreshNavigation()
    {
        var position = Swag.U64.Max
        for index, ordinal in .visible where index == .sheet do
            position = ordinal
        .previousButton.enable(position < .visible.count and position > 0)
        .nextButton.enable(position < .visible.count and position + 1 < .visible.count)
        .sheetLabel.setText(Viewer.pageText(position, .visible.count))
        .previousButton.toolTip = texts().ui_Previous
        .nextButton.toolTip     = texts().ui_Next
        if .sheet < .workbook.sheets.count
        {
            var details = .workbook.sheets[.sheet].details()
            if .grid and .grid.hasSelection do
                details += Format.toString(" · %", .grid.selected.label())
            .services.showDetails(me, details)
        }
        else
        {
            .services.showDetails(me, .workbook.details())
        }
    }

    mtd publishSheets()
    {
        .visible.clear()
        var headings: Array'DocumentHeading
        for page, index in .workbook.sheets where .showHidden or not page.hidden
        {
            .visible.add(index)
            let name = page.hidden ? Format.toString(texts().ui_Hidden, page.name) : page.name
            headings.add(DocumentHeading{name, 1, index})
        }

        // Publishing can reset the list selection. Choose the sheet after the rows exist.
        .outline.publish(headings.toSlice())
        var target = Swag.U64.Max
        for index in .visible where index == .sheet do
            target = index
        if target == Swag.U64.Max and not .visible.isEmpty() do
            target = .visible[0]
        if target == Swag.U64.Max
        {
            .sheet = target
            .clearSheet()

            .status.setText(texts().ui_AllHidden)
            .status.show()
            .applyLayout()
        }
        else
        {
            .showSheet(target)
        }

        .refreshNavigation()
    }

    internal mtd showSheet(index: u64)
    {
        if index >= .workbook.sheets.count or (.workbook.sheets[index].hidden and not .showHidden) do
            return
        if index != .sheet or (not .view and not .grid)
        {
            .sheet = index
            .buildSheet()
        }

        for row, position in .outline.rows where cast(u64, row.userData0) == index + 1
        {
            if .outline.list.selectedLine() != row do
                .outline.list.selectLine(cast(u32, position))
            break
        }

        .refreshNavigation()
    }

    mtd clearSheet()
    {
        .view?.hide()
        .view?.destroy()
        .view = null
        .gridHost?.hide()
        .gridHost?.destroy()
        .gridHost = null
        .grid     = null
    }

    mtd buildSheet(preserveSelection = false)
    {
        let address = preserveSelection ? .selection : Address{}
        .clearSheet()
        let sheet = &.workbook.sheets[.sheet]
        if .textMode
        {
            var style = HtmlStyle.theme()
            style.maxContentWidth = 680
            with .view = HtmlView.createText(me, sheet.readingHtml(.showHiddenRanges), style)
            {
                .dockStyle = .Center
                .margin    = {.themeMetrics().floating_Inset, 0, .themeMetrics().floating_Inset, 0}
            }
        }
        else
        {
            let inset = .themeMetrics().floating_Inset
            with .gridHost = Wnd.create'Wnd(me, "scope.xlsx.grid")
            {
                .dockStyle       = .Center
                .backgroundStyle = .Transparent
                .margin          = {inset, .stripInset() + inset, inset, .themeMetrics().miniBar_ButtonSize + 2 * inset}
            }

            with let title = Label.create(.gridHost, sheet.name, {0, 0, 0, 40}, null, .Ellipsis)
            {
                .dockStyle = .Top
                .setTextAlignment(.Left, .Top)
                .style.setFont(.theme().createDefaultFont(24, .Bold), .Regular)
            }

            .grid = Grid.create(.gridHost, sheet, &.workbook.styles, .showHiddenRanges)
            .grid.selectAddress(address)
            .selection        = .grid.selected
            .grid.sigSelected += func|view = me|(_)
            {
                if view.grid do
                    view.selection = view.grid.selected
                view.refreshNavigation()
            }
        }

        .status.hide()
        .applyLayout()
        .refreshNavigation()
    }

    internal mtd setTextMode(enabled: bool)
    {
        if .textMode == enabled do
            return
        .textMode = enabled
        if .sheet < .workbook.sheets.count do
            .buildSheet(true)
    }

    internal mtd setHiddenRanges(enabled: bool)
    {
        if .showHiddenRanges == enabled do
            return
        .showHiddenRanges = enabled
        if .sheet < .workbook.sheets.count do
            .buildSheet(true)
    }

    internal mtd turn(direction: s32)
    {
        for index, position in .visible where index == .sheet
        {
            if direction < 0 and position > 0 do
                .showSheet(.visible[position - 1])
            elif direction > 0 and position + 1 < .visible.count do
                .showSheet(.visible[position + 1])
            return
        }
    }

    internal mtd setShowHidden(enabled: bool)
    {
        if .showHidden == enabled do
            return
        .showHidden = enabled
        .publishSheets()
    }

    mtd handleKey(key: const *KeyEvent)->bool
    {
        if key.kind != .Pressed do
            return false
        let direction = Viewer.pageKeyDirection(key)
        if not direction do
            return false
        .turn(direction)
        return true
    }

    // Shows the cell at `address` of the sheet in view in the grid, selected and in view.
    internal mtd revealCell(address: Address)
    {
        if .textMode do
            .setTextMode(false)
        .grid?.selectAddress(address)
    }

    // Answers `:` and a cell address, as `B12`, with that cell of the sheet in view; any other
    // query with the commands of the workbook.
    mtd describeLens(entries: *Viewer.LensEntries)
    {
        if entries.results.prefix == .Line
        {
            var typed = String.from(Latin1.trim(entries.query.toString()))
            typed.makeUpper()
            let address = catch Address.parse(typed.toString()) { return; }
            if .sheet >= .workbook.sheets.count do
                return
            let entry = entries.add(Format.toString(texts().ui_GoToCell, address.label()), .GoTo, func|view = me, address|() { view.revealCell(address) })
            if entry do
                entry.lead = address.label()
            return
        }

        entries.add(texts().ui_Previous, .ChevronLeft, func|view = me|() { view.turn(-1) }, disabled: not .previousButton.isEnabled(), defaultKey: {modifiers: .Control, key: .PageUp}, bindId: "scope.xlsx.previous")
        entries.add(texts().ui_Next, .ChevronRight, func|view = me|() { view.turn(1) }, disabled: not .nextButton.isEnabled(), defaultKey: {modifiers: .Control, key: .PageDown}, bindId: "scope.xlsx.next")
        if .workbook.hiddenSheets do
            entries.add(texts().ui_ShowHidden, .File, func|view = me|() { view.setShowHidden(not view.showHidden) }, checked: .showHidden, bindId: "scope.xlsx.showHidden")
        entries.add(texts().ui_Grid, .File, func|view = me|() { view.setTextMode(false) }, checked: not .textMode, bindId: "scope.xlsx.grid")
        entries.add(texts().ui_ReadText, .Wrap, func|view = me|() { view.setTextMode(true) }, checked: .textMode, bindId: "scope.xlsx.readText")
        if .grid do
            entries.add(texts().ui_CopyCell, .Copy, func|view = me|() { view.grid?.copy() }, disabled: not .grid.hasSelection, defaultKey: {modifiers: .Control, key: .C}, bindId: "scope.xlsx.copyCell")
        if .sheet < .workbook.sheets.count and .workbook.sheets[.sheet].hiddenRanges do
            entries.add(texts().ui_HiddenRanges, .File, func|view = me|() { view.setHiddenRanges(not view.showHiddenRanges) }, checked: .showHiddenRanges, bindId: "scope.xlsx.hiddenRanges")
    }

    func create(host: Viewer.Host)->*Panel
    {
        with let result = Wnd.create'Panel(host.contentParent(), "scope.xlsx")
        {
            .backgroundStyle = .View
            .focusPolicy     = .Tab
            .services        = host.services()
        }

        let controls = host.createCommandGroup(Viewer.pageControlWidth(result.themeMetrics()))
        with result.previousButton = Viewer.createPageStep(controls, -1)
        {
            .sigPressed += func|view = result|(_) { view.turn(-1) }
        }

        result.sheetLabel = Viewer.createPageLabel(controls)
        with result.nextButton = Viewer.createPageStep(controls, 1)
        {
            .sigPressed += func|view = result|(_) { view.turn(1) }
        }

        with result.status = Label.create(result, texts().ui_Preparing, {}, null, .WordWrap)
        {
            .dockStyle       = .Center
            .backgroundStyle = .View
            .setTextAlignment(.Center, .Center)
        }

        result.hookOnChildEvent = func|result|(_, evt)
        {
            if evt is KeyEvent as key do
                return result.handleKey(key)
            return false
        }

        result.refreshNavigation()
        result.applyLayout()
        return result
    }
}

func createViewer(host: Viewer.Host)
{
    createWorkbookViewer(host, &Workbook.load)
}

impl Panel
{
    // Describes the document in the information sheet with what its package says of it, read
    // once, the first time the sheet asks.
    internal mtd describeInformation(sheet: *InfoSheet)
    {
        if not .propertiesRead and not .load.fileName.isEmpty()
        {
            .properties     = Package.DocumentProperties.read(.load.fileName)
            .propertiesRead = true
        }

        var data: MediaInfoData
        .properties.describe(&data)
        data.describe(sheet)
    }
}

func createWorkbookViewer(host: Viewer.Host, loader: func(string)->Workbook fail)
{
    let view = Panel.create(host)
    host.attachView(view)
    host.setInformation(func|view|(sheet) { view.describeInformation(sheet) })
    view.outline = DocumentOutline.create(host)
    view.outline.sigSelected += func|view|(_, index) { view.showSheet(index) }
    host.setLensSource(func|view|(entries) { view.describeLens(entries) })
    view.load.start(host.fileName(), loader, view)
    host.setLifecycle(Viewer.loadLifecycle(view))
}
