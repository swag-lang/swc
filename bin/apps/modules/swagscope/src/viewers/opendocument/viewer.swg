#global internal
#global namespace Viewers.OpenDocument

using Core, Core.Errors, Gui

// Describes OpenDocument text, spreadsheet, presentation, and drawing files to the host.
func viewerPlugin()->Viewer.Plugin
{
    with var result: retval
    {
        .key          = "opendocument"
        .resolveName  = func()->string => texts().ui_Name
        .attach       = &registerTexts
        .iconAtlas    = viewerIcons()
        .iconIndex    = cast(s32, ViewerIcons.OpenDocument)
        .create       = &createViewer
        .smokeFixture = "viewer.odt"
        .addSelectors(".odt;.ott;.fodt;.ods;.ots;.fods;.odp;.otp;.fodp;.odg;.otg;.fodg")
    }

    return result
}

private const PageComboWidth = 224.0

// Shows an OpenDocument file on the reader surface of its kind, decoding it away from the GUI thread.
struct Panel
{
    using wnd: Wnd

    late
    {
        html:      *HtmlView
        table:     *Table.Panel
        commands:  *Wnd
        pageCombo: *ComboBox
        info:      *Wnd
        zoomLabel: *IconButton
    }

    document:      Content
    outline:       *DocumentOutline?
    sheetIndex:    u64
    slideIndex:    u64
    zoomPercent:   u32 = 100
    load:          Viewer.BackgroundLoad'Content
    services:      Viewer.HostServices
    failureReason: String
}

private impl IWnd for Panel
{
    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer != .load.timer
        {
            evt.accepted = false
            return
        }

        if not .load.poll() do
            return

        .failureReason = .load.finish(&.document)
        if not .failureReason.isEmpty()
        {
            .services.failed(me, .failureReason)
            return
        }

        .publishDocument()
        .reportDocumentDetails()
        .services.loadingChanged(me)
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged and not .load.isPending() and .failureReason.isEmpty()
        {
            .fillPageChoices()
            .zoomLabel.toolTip = texts().ui_ZoomMenu
            .reportDocumentDetails()
        }

        .wnd.IWnd.onNotifyEvent(evt)
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind != .Pressed
        {
            evt.accepted = false
            return
        }

        if Viewer.isZoomKey(evt) and .document.kind != .Spreadsheet do
            .setZoom(Viewer.zoomAfterKey(evt, .zoomPercent))
        elif evt.modifiers != .None or not .navigatePagedDocument(evt.key) do
            evt.accepted = false
    }
}

private impl Panel
{
    mtd applyZoom()
    {
        if .html == null do
            return
        var style = HtmlStyle.theme()
        style.bodyFontSize = cast(u32, Math.max(Math.round(16.0 * cast(f32, .zoomPercent) / 100), 1))
        style.codeFontSize = cast(u32, Math.max(Math.round(14.0 * cast(f32, .zoomPercent) / 100), 1))
        .html.setDocumentStyle(style)
    }

    internal mtd setZoom(percent: u32)
    {
        .zoomPercent = Viewer.clampZoom(percent)
        .applyZoom()
        .zoomLabel.setText(Viewer.zoomText(.zoomPercent))
    }

    mtd showZoomMenu()
    {
        let percent = Viewer.pickZoom(me, .zoomLabel, .zoomPercent)
        if percent do
            .setZoom(percent)
    }

    mtd refreshZoomChrome()
    {
        let visible = .document.kind != .Spreadsheet
        .info.show(visible)
        if visible do
            .setZoom(.zoomPercent)
        .services.chromeChanged(me)
    }

    mtd kindName()->string
    {
        switch #complete .document.kind
        {
        case .Text:         return texts().ui_Text
        case .Spreadsheet:  return texts().ui_Spreadsheet
        case .Presentation: return texts().ui_Presentation
        case .Drawing:      return texts().ui_Drawing
        }
    }

    mtd documentDetails(details: string)->String
    {
        if .document.metadata.title.isEmpty() do
            return details
        return Format.toString("% · %", details, .document.metadata.title)
    }

    mtd reportDocumentDetails()
    {
        if .document.kind == .Spreadsheet and .sheetIndex < .document.sheets.count
        {
            .services.showDetails(me, .documentDetails(Format.toString(texts().ui_DetailsSheet, .sheetName(.sheetIndex))))
            return
        }

        if (.document.kind == .Presentation or .document.kind == .Drawing) and .slideIndex < .document.slides.count
        {
            let details = .document.kind == .Presentation ? texts().ui_DetailsSlide : texts().ui_DetailsPage
            .services.showDetails(me, .documentDetails(Format.toString(details, .slideName(.slideIndex))))
            return
        }

        .services.showDetails(me, .documentDetails(Format.toString(texts().ui_Details, .kindName())))
    }

    // Returns the source name of a sheet, or a numbered label when the sheet has none.
    mtd sheetName(index: u64)->String
    {
        let name = .document.sheets[index].name
        if not name.isEmpty() do
            return name
        return Format.toString(texts().ui_Sheet, index + 1)
    }

    // Returns the source name of a slide or drawing page, or a numbered label when it has none.
    mtd slideName(index: u64)->String
    {
        let name = .document.slides[index].name
        if not name.isEmpty() do
            return name
        return Format.toString(.document.kind == .Drawing ? texts().ui_Page : texts().ui_Slide, index + 1)
    }

    mtd fillPageChoices()
    {
        .pageCombo.clear()

        var count:  u64
        var active: u64
        switch .document.kind
        {
        case .Spreadsheet:
            .pageCombo.toolTip = texts().ui_TipSheet
            count  = .document.sheets.count
            active = .sheetIndex
            for index in count do
                .pageCombo.addItem(.sheetName(index))

        case .Presentation:
            .pageCombo.toolTip = texts().ui_TipSlide
            count  = .document.slides.count
            active = .slideIndex
            for index in count do
                .pageCombo.addItem(.slideName(index))

        case .Drawing:
            .pageCombo.toolTip = texts().ui_TipPage
            count  = .document.slides.count
            active = .slideIndex
            for index in count do
                .pageCombo.addItem(.slideName(index))

        case .Text:
            count = 0
        }

        if count do
            .pageCombo.setSelectedIndex(cast(u32, active), notify: false)
        let hasChoices = count > 1
        .pageCombo.show(hasChoices)
        .commands.show(hasChoices)
        .services.chromeChanged(me)
    }

    mtd showSheet(index: u64, clearSearch: bool)->bool
    {
        if index >= .document.sheets.count or .table == null do
            return false
        if index == .sheetIndex
        {
            if clearSearch do
                .table.clearSearch()
            return true
        }

        .document.sheets[.sheetIndex].table = #move .table.document
        .table.destroy()
        .sheetIndex      = index
        .table           = Table.Panel.createDocument(me, #move .document.sheets[index].table)
        .table.dockStyle = .Center
        .pageCombo.setSelectedIndex(cast(u32, index), notify: false)
        if clearSearch do
            .table.clearSearch()
        .applyLayout()
        .setInitialFocus(.table)
        .reportDocumentDetails()
        return true
    }

    // Creates the reading surface for generated markup, whose activated links open in the system browser.
    mtd createHtmlView(markup: string)
    {
        .html = HtmlView.createText(me, markup)
        .html.dockStyle = .Center
        .applyZoom()
        .html.sigLinkActivated += func(?, url)
        {
            Env.openUrl(url)
        }
    }

    mtd showSlide(index: u64, clearSearch: bool)->bool
    {
        if index >= .document.slides.count do
            return false
        if index == .slideIndex and .html != null
        {
            if clearSearch do
                .html.clearSearch()
            return true
        }

        if .html != null do
            .html.destroy()
        .slideIndex = index
        .createHtmlView(.document.slides[index].html)
        .pageCombo.setSelectedIndex(cast(u32, index), notify: false)
        if clearSearch do
            .html.clearSearch()
        .applyLayout()
        .setInitialFocus(.html)
        .reportDocumentDetails()
        return true
    }

    // Preserves the ordinary document-reader keys without stealing scroll keys from text documents.
    mtd navigatePagedDocument(key: Input.Key)->bool
    {
        if .document.kind != .Presentation and .document.kind != .Drawing do
            return false

        switch key
        {
        case .Left, .PageUp where .slideIndex: return .showSlide(.slideIndex - 1, true)
        case .Right, .PageDown where .slideIndex + 1 < .document.slides.count: return .showSlide(.slideIndex + 1, true)
        case .Home where .slideIndex: return .showSlide(0, true)
        case .End where .slideIndex + 1 < .document.slides.count: return .showSlide(.document.slides.count - 1, true)
        }

        return false
    }

    mtd showPage(index: u64, clearSearch: bool)->bool
    {
        switch #complete .document.kind
        {
        case .Spreadsheet:  return .showSheet(index, clearSearch)
        case .Presentation: return .showSlide(index, clearSearch)
        case .Drawing:      return .showSlide(index, clearSearch)
        case .Text:         return false
        }
    }

    mtd collectTableMatches(document: const *Table.Document, sheetIndex: u64, text: string, options: Viewer.SearchOptions, result: *Array'Viewer.SearchMatch)
    {
        for row, rowIndex in document.rows
        {
            for cell, column in row.cells do
                Viewer.collectTextMatches(cell.toString(), text, options, sheetIndex, (rowIndex << 32) | column, 0, result)
        }
    }

    mtd collectSpreadsheetMatches(text: string, options: Viewer.SearchOptions, result: *Array'Viewer.SearchMatch)
    {
        for &sheet, index in .document.sheets
        {
            if index == .sheetIndex and .table != null do
                .collectTableMatches(&.table.document, index, text, options, result)
            else do
                .collectTableMatches(&sheet.table, index, text, options, result)
        }
    }

    mtd collectPresentationMatches(text: string, options: Viewer.SearchOptions, result: *Array'Viewer.SearchMatch)
    {
        for slide, index in .document.slides do
            Viewer.collectTextMatches(slide.html, text, options, index, 0, 0, result)
    }

    mtd publishDocument()
    {
        if .document.kind == .Spreadsheet
        {
            .table = Table.Panel.createDocument(me, #move .document.sheets[0].table)
            .table.dockStyle = .Center
            .fillPageChoices()
            .setInitialFocus(.table)
        }
        elif .document.kind == .Presentation or .document.kind == .Drawing
        {
            .fillPageChoices()
            discard .showSlide(0, false)
        }
        else
        {
            .createHtmlView(.document.html)
            .setInitialFocus(.html)
        }

        if .outline
        {
            if .document.kind == .Text
            {
                .outline.bindHtml(.html)
            }
            else
            {
                .outline.clear()
                if .document.kind == .Spreadsheet
                {
                    for sheet, index in .document.sheets do
                        .outline.add(sheet.name, 1, index)
                }
                else
                {
                    for slide, index in .document.slides do
                        .outline.add(slide.name, 1, index)
                }

                .outline.refresh()
                .outline.sigSelected += func|view = me|(?, index) { discard view.showPage(index, true) }
            }
        }

        .refreshZoomChrome()
        .applyLayout()
    }

    mtd collectMatches(text: string, options: Viewer.SearchOptions, result: *Array'Viewer.SearchMatch)
    {
        if .document.kind == .Spreadsheet
        {
            if .table != null do
                .collectSpreadsheetMatches(text, options, result)
            return
        }

        if .document.kind == .Presentation or .document.kind == .Drawing
        {
            .collectPresentationMatches(text, options, result)
            return
        }

        if .html != null do
            Viewer.collectTextMatches(.document.html, text, options, 0, 0, 0, result)
    }

    mtd revealMatch(match: Viewer.SearchMatch, text: string)->bool
    {
        if .document.kind == .Spreadsheet
        {
            if not .showSheet(match.major, false) do
                return false
            var tableMatch = match
            tableMatch.major = match.minor >> 32
            tableMatch.minor = match.minor & 0xFFFF_FFFF'u64
            return .table.revealMatch(tableMatch, text)
        }

        if .document.kind == .Presentation or .document.kind == .Drawing
        {
            if not .showSlide(match.major, false) do
                return false
            return .html.revealFileOffset(match.offset, text)
        }

        if .html == null do
            return false
        return .html.revealFileOffset(match.offset, text)
    }

    mtd searchBounds(result: *Math.Rectangle)->bool
    {
        if .document.kind == .Spreadsheet
        {
            if .table == null do
                return false
            return .table.searchBounds(result)
        }

        if .html == null do
            return false
        return .html.searchMatchRect(result)
    }

    mtd clearSearch()
    {
        if .document.kind == .Spreadsheet
        {
            if .table != null do
                .table.clearSearch()
            return
        }

        if .html != null do
            .html.clearSearch()
    }

    mtd retire()->bool
    {
        return .load.retire()
    }

    func create(host: Viewer.Host)->*Panel
    {
        let services = host.services()

        with let result = Wnd.create'Panel(host.contentParent(), "scope.opendocument")
        {
            .backgroundStyle = .View
            .services        = services
        }

        result.createZoomButton(host)
        result.hookOnChildEvent = func|view = result|(?, evt)
        {
            switch evt
            {
            case KeyEvent as keyEvt where Viewer.isZoomKey(keyEvt) and view.document.kind != .Spreadsheet:
                view.setZoom(Viewer.zoomAfterKey(keyEvt, view.zoomPercent))
                return true

            case KeyEvent as keyEvt where keyEvt.kind == .Pressed and keyEvt.modifiers == .None:
                return view.navigatePagedDocument(keyEvt.key)

            default:
                return false
            }
        }

        result.createPageSelector(host)
        result.load.startPolled(result, host.fileName(), &loadContent)
        return result
    }

    // Creates the reading-zoom button, hidden until a document that can zoom is published.
    mtd createZoomButton(host: Viewer.Host)
    {
        .info = host.createInfoGroup(Viewer.ZoomSlotWidth)
        .info.hide()
        .zoomLabel = Viewer.createZoomButton(me.info, "scope.opendocument.zoom", texts().ui_ZoomMenu)
        .zoomLabel.sigPressed += func|view = me|(?) { view.showZoomMenu() }
    }

    // Creates the sheet, slide, or page selector, hidden until a document offers several.
    mtd createPageSelector(host: Viewer.Host)
    {
        .commands = host.createCommandGroup(PageComboWidth)
        .commands.hide()
        with .pageCombo = ComboBox.create(me.commands, {0, 0, PageComboWidth, 36})
        {
            .dockStyle = .Left
            .hide()
            .toolTip    = texts().ui_TipSheet
            .sigChanged += func|view = me|(?, index) { discard view.showPage(index, true) }
        }
    }
}

// Creates the integrated reader for OpenDocument files.
func createViewer(host: Viewer.Host)
{
    let view = Panel.create(host)
    view.outline = DocumentOutline.create(host)
    host.attachView(view)
    host.setDetails(texts().ui_Name)

    host.setSearch(Viewer.searchApi(view))

    host.setLifecycle(Viewer.loadLifecycle(view))
}
