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

    workbook:   Workbook
    load:       Viewer.BackgroundLoad'Workbook
    services:   Viewer.HostServices
    view:       *HtmlView?
    sheet:      u64 = Swag.U64.Max
    visible:    Array'u64
    showHidden: bool

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
        if .sheet < .workbook.sheets.count do
            .services.showDetails(me, .workbook.sheets[.sheet].details())
        else do
            .services.showDetails(me, .workbook.details())
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
            .view?.hide()
            .view?.destroy()
            .view = null
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
        if index != .sheet or not .view
        {
            .sheet = index
            .view?.hide()
            .view?.destroy()
            var style = HtmlStyle.theme()
            style.maxContentWidth = 680
            with .view = HtmlView.createText(me, .workbook.sheets[index].html, style)
            {
                .dockStyle = .Center
                .margin    = {.themeMetrics().floating_Inset, 0, .themeMetrics().floating_Inset, 0}
            }

            .status.hide()
            .applyLayout()
        }

        for row, position in .outline.rows where cast(u64, row.userData0) == index + 1
        {
            if .outline.list.selectedLine() != row do
                .outline.list.selectLine(cast(u32, position))
            break
        }

        .refreshNavigation()
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

    mtd describeLens(entries: *Viewer.LensEntries)
    {
        entries.add(texts().ui_Previous, .ChevronLeft, func|view = me|() { view.turn(-1) }, disabled: not .previousButton.isEnabled(), shortcut: Input.formatKeyShortcut(.Control, .PageUp))
        entries.add(texts().ui_Next, .ChevronRight, func|view = me|() { view.turn(1) }, disabled: not .nextButton.isEnabled(), shortcut: Input.formatKeyShortcut(.Control, .PageDown))
        if .workbook.hiddenSheets do
            entries.add(texts().ui_ShowHidden, .File, func|view = me|() { view.setShowHidden(not view.showHidden) }, checked: .showHidden)
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
    let view = Panel.create(host)
    host.attachView(view)
    view.outline = DocumentOutline.create(host)
    view.outline.sigSelected += func|view|(_, index) { view.showSheet(index) }
    host.setLensSource(func|view|(entries) { view.describeLens(entries) })
    view.load.start(host.fileName(), &Workbook.load, view)
    host.setLifecycle(Viewer.loadLifecycle(view))
}
