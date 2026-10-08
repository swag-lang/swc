#global internal
#global namespace Viewers.MarkdownText

using Core, Gui

// Reading preferences of the Markdown viewer, kept across files and persisted by the window.
struct ViewerSettings
{
    themeIndex:  u32           // Document appearance, in the order of the appearance selector.
    widthIndex:  u32 = 1       // Reading measure, in the order of the width selector.
    zoomPercent: u32 = 100     // Document zoom.
}

impl ViewerSettings
{
    // Brings preferences read back from a saved state into the ranges the selectors offer.
    mtd sanitize()
    {
        .themeIndex  = Math.min(.themeIndex, 5)
        .widthIndex  = Math.min(.widthIndex, 3)
        .zoomPercent = Math.clamp(.zoomPercent, 50'u32, 300'u32)
    }
}

var g_ViewerSettings: ViewerSettings

// Describes the Markdown viewer to the host.
func viewerPlugin()->Viewer.Plugin
{
    with var result: retval
    {
        .key          = "markdown"
        .staticName   = "Markdown"
        .attach       = &registerTexts
        .iconAtlas    = viewerIcons()
        .iconIndex    = cast(s32, ViewerIcons.Markdown)
        .create       = &createViewer
        .textual      = true
        .smokeFixture = "comprehensive.md"
        .addSelectors(".markdown;.md;.mdown;.mdwn;.mkd;.mkdn;.rmd")
    }

    return result
}

// Returns the document style of one appearance at one reading measure.
func viewerStyle(themeIndex, widthIndex: u32)->Markdown.Style
{
    var result = Markdown.Style.theme()
    if themeIndex do
        result.codeTypeFaces = systemFaces(["Consolas", "Menlo", "Monaco"])
    switch themeIndex
    {
    // The application's own theme and Whitey set their body column flush on both edges. The four
    // themes between them are imported, and each is read with the ragged edge its original has:
    // a justified GitHub page is not a GitHub page.
    case 0:
        result.paragraphAlignment = .Justify

    case 1:
        result.bodyTypeFaces = systemFaces(["Open Sans", "Clear Sans", "Helvetica Neue", "Helvetica", "Arial"])

    case 2:
        result.bodyTypeFaces    = systemFaces(["PT Serif", "Times New Roman", "Times"])
        result.maxContentWidth  = 640
        result.horizontalInset  = 40
        result.topInset         = 48
        result.bottomInset      = 48
        result.heading1FontSize = 30
        result.heading2FontSize = 21
        result.heading3FontSize = 21
        result.heading4FontSize = 18
        result.lineHeight       = 1.5

    case 3:
        result.bodyTypeFaces    = systemFaces(["Helvetica Neue", "Helvetica", "Arial"])
        result.headingTypeFaces = systemFaces(["Lucida Grande", "Corbel"])
        result.maxContentWidth  = 914
        result.horizontalInset  = 48
        result.topInset         = 42
        result.bottomInset      = 48
        result.heading1FontSize = 40
        result.heading2FontSize = 26
        result.heading3FontSize = 19
        result.heading4FontSize = 18
        result.heading6FontSize = 15
        result.lineHeight       = 1.625

    case 4:
        result.bodyTypeFaces    = systemFaces(["Merriweather", "PT Serif", "Georgia", "Times New Roman"])
        result.headingTypeFaces = systemFaces(["Lato", "Helvetica Neue", "Helvetica", "Arial"])
        result.codeTypeFaces    = systemFaces(["Menlo", "Monaco", "Courier New"])
        result.maxContentWidth  = 914
        result.horizontalInset  = 48
        result.topInset         = 32
        result.bottomInset      = 56
        result.bodyFontSize     = 18
        result.codeFontSize     = 16
        result.mathFontSize     = 24
        result.heading1FontSize = 42
        result.heading2FontSize = 30
        result.heading3FontSize = 24
        result.heading4FontSize = 20
        result.heading5FontSize = 18
        result.heading6FontSize = 18
        result.lineHeight       = 1.8

    case 5:
        result.bodyTypeFaces      = systemFaces(["Vollkorn", "Palatino", "Palatino Linotype", "Times", "Times New Roman"])
        result.headingFontStyles  = [.Regular, .Regular, .Italic, .Bold, .Bold, .Bold]
        result.maxContentWidth    = 960
        result.horizontalInset    = 52
        result.topInset           = 40
        result.bottomInset        = 48
        result.bodyFontSize       = 19
        result.codeFontSize       = 17
        result.mathFontSize       = 25
        result.heading1FontSize   = 57
        result.heading2FontSize   = 30
        result.heading3FontSize   = 23
        result.heading4FontSize   = 20
        result.heading5FontSize   = 19
        result.heading6FontSize   = 19
        result.lineHeight         = 1.53
        result.headingAlignment   = .Center
        result.imageAlignment     = .Center
        result.paragraphAlignment = .Justify
    }

    switch widthIndex
    {
    case 0:
        result.maxContentWidth = 680

    case 2:
        result.maxContentWidth = 1_100

    case 3:
        result.maxContentWidth = 100_000
        result.horizontalInset = 24
    }

    return result
}

// Returns the theme-sheet colors of one appearance, or nothing for the application's own.
func viewerColors(themeIndex: u32)->string
{
    switch themeIndex
    {
    case 0:  return ""
    case 2:  return "view_Bk 0xFFF3F2EE\nlabel_Text 0xFF1F0909\nlabel_TextLight 0xFF656565\nlabel_TextFaint 0xFF656565\nedit_Bk 0xFFDADADA\nedit_Border 0xFFC5C5C5\nedit_SelectedBk 0xFFBBCBD2\nurl_Text 0xFF065588\nurl_HotText 0xFF043A5D\nrichColor1 0xFFBABABA\nscrollBar_Bk 0xFFF3F2EE\nscrollBar_HotBk 0xFFE8E6E0\nscrollBar_Box 0xFFBAB6AE\nscrollBar_HotBox 0xFF8F8980\nscrollBar_PressedBox 0xFF6F6961"
    case 3:  return "view_Bk 0xFF363B40\nlabel_Text 0xFFB8BFC6\nlabel_TextLight 0xFF9CA4AC\nlabel_TextFaint 0xFF8E969E\nedit_Bk 0xFF333333\nedit_Border 0xFF474D54\nedit_SelectedBk 0xFF4A6073\nurl_Text 0xFF6DC1E7\nurl_HotText 0xFFA3D5FE\nrichColor1 0xFFDEDEDE\nscrollBar_Bk 0xFF363B40\nscrollBar_HotBk 0xFF3D4349\nscrollBar_Box 0xFF596169\nscrollBar_HotBox 0xFF707A84\nscrollBar_PressedBox 0xFF89949F"
    case 4:  return "view_Bk 0xFFFFFFFF\nlabel_Text 0xFF333333\nlabel_TextLight 0xFF666666\nlabel_TextFaint 0xFF7A7A7A\nedit_Bk 0xFFF8F8F8\nedit_Border 0xFFD8D8D8\nedit_SelectedBk 0xFFDDE7F2\nurl_Text 0xFF463F5C\nurl_HotText 0xFF6A6086\nrichColor1 0xFF7A7A7A\nscrollBar_Bk 0xFFFFFFFF\nscrollBar_HotBk 0xFFF4F4F4\nscrollBar_Box 0xFFC6C6C6\nscrollBar_HotBox 0xFFA6A6A6\nscrollBar_PressedBox 0xFF8A8A8A"
    case 5:  return "view_Bk 0xFFFEFEFE\nlabel_Text 0xFF333333\nlabel_TextLight 0xFF666666\nlabel_TextFaint 0xFF777777\nedit_Bk 0xFFFFFFFF\nedit_Border 0xFFDDDDDD\nedit_SelectedBk 0xFFD9EAF5\nurl_Text 0xFF2484C1\nurl_HotText 0xFF17618F\nrichColor1 0xFF777777\nscrollBar_Bk 0xFFFEFEFE\nscrollBar_HotBk 0xFFF3F3F3\nscrollBar_Box 0xFFC8C8C8\nscrollBar_HotBox 0xFFA8A8A8\nscrollBar_PressedBox 0xFF8B8B8B"
    default: return "view_Bk 0xFFFFFFFF\nlabel_Text 0xFF333333\nlabel_TextLight 0xFF666666\nlabel_TextFaint 0xFF777777\nedit_Bk 0xFFF8F8F8\nedit_Border 0xFFDFE2E5\nedit_SelectedBk 0xFFCCE5FF\nurl_Text 0xFF4183C4\nurl_HotText 0xFF2B6DA8\nrichColor1 0xFF777777\nscrollBar_Bk 0xFFFFFFFF\nscrollBar_HotBk 0xFFF5F5F5\nscrollBar_Box 0xFFC5C5C5\nscrollBar_HotBox 0xFFA5A5A5\nscrollBar_PressedBox 0xFF888888"
    }
}

// Styles `view` with one appearance and reading measure, scaled by `zoomPercent`.
//
// `applyColors` is false when only the measure or the zoom changed, so the colors already applied stay.
func applyViewerStyle(view: *Markdown.View, themeIndex, widthIndex: u32, zoomPercent = 100'u32, applyColors = true)
{
    var style = viewerStyle(themeIndex, widthIndex)
    let scale = cast(f32, zoomPercent) / 100
    style.bodyFontSize     = cast(u32, Math.max(Math.round(cast(f32, style.bodyFontSize) * scale), 1))
    style.codeFontSize     = cast(u32, Math.max(Math.round(cast(f32, style.codeFontSize) * scale), 1))
    style.mathFontSize     = cast(u32, Math.max(Math.round(cast(f32, style.mathFontSize) * scale), 1))
    style.heading1FontSize = cast(u32, Math.max(Math.round(cast(f32, style.heading1FontSize) * scale), 1))
    style.heading2FontSize = cast(u32, Math.max(Math.round(cast(f32, style.heading2FontSize) * scale), 1))
    style.heading3FontSize = cast(u32, Math.max(Math.round(cast(f32, style.heading3FontSize) * scale), 1))
    style.heading4FontSize = cast(u32, Math.max(Math.round(cast(f32, style.heading4FontSize) * scale), 1))
    style.heading5FontSize = cast(u32, Math.max(Math.round(cast(f32, style.heading5FontSize) * scale), 1))
    style.heading6FontSize = cast(u32, Math.max(Math.round(cast(f32, style.heading6FontSize) * scale), 1))
    if applyColors do
        view.setDocumentThemeColors(viewerColors(themeIndex))
    view.setDocumentStyle(style)
}

// The zoom menu of the Markdown viewer, which also owns the viewer's background statistics and
// outline, since the document view itself is a standard [[Gui.Markdown.View]].
struct ZoomButton
{
    using button: IconButton

    late
    {
        view:       *Markdown.View
        themeCombo: *ComboBox
        widthCombo: *ComboBox
    }

    zoomPercent:     u32 = 100
    statisticsLoad:  Viewer.BackgroundLoad'TextStatistics
    statistics:      TextStatistics
    statisticsTimer: *Timer?
    hasStatistics:   bool
    reportDetails:   Viewer.ReportDetails?
    outline:         *DocumentOutline?
}

impl IWnd for ZoomButton
{
    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer != .statisticsTimer or not .statisticsLoad.isDone() do
            return
        .removeTimer(evt.timer)
        .statisticsTimer = null
        let error = .statisticsLoad.finish(&.statistics)
        .hasStatistics = error.isEmpty()
        .reportStatistics()
    }
}

impl ZoomButton
{
    mtd reportStatistics()
    {
        if not .reportDetails do
            return
        if not .hasStatistics
        {
            .reportDetails(.view, texts().ui_Details)
            return
        }

        let texts = texts()
        let lines = .statistics.lines == 1 ? String.from(texts.ui_OneLine) : Format.toString(texts.ui_Lines, .statistics.lines)
        let words = .statistics.words == 1 ? String.from(texts.ui_OneWord) : Format.toString(texts.ui_Words, .statistics.words)
        .reportDetails(.view, Format.toString("% · % · %", texts.ui_Details, lines, words))
    }

    mtd retire()->bool
    {
        if .outline and not .outline.retire() do
            return false
        if .statisticsTimer
        {
            .removeTimer(.statisticsTimer)
            .statisticsTimer = null
        }

        return .statisticsLoad.retire()
    }

    mtd applyZoom(percent: u32)
    {
        let bounded = Math.clamp(percent, 50'u32, 300'u32)
        if .zoomPercent == bounded do
            return
        .zoomPercent = bounded
        .setText(Format.toString("% %", bounded, "%"))
        applyViewerStyle(.view, .themeCombo.selectedIndex, .widthCombo.selectedIndex, bounded, applyColors: false)

        // The window saves preferences on navigation and close, outside wheel handling.
        g_ViewerSettings.zoomPercent = bounded
    }

    mtd showZoomMenu()
    {
        let menu = MenuCtrl.createPopup(me, owner: me)
        menu.addItem("75%", "scope.markdown.zoom75", checked: .zoomPercent == 75)
        menu.addItem("100%", "scope.markdown.zoom100", checked: .zoomPercent == 100)
        menu.addItem("125%", "scope.markdown.zoom125", checked: .zoomPercent == 125)
        menu.addItem("150%", "scope.markdown.zoom150", checked: .zoomPercent == 150)
        menu.addItem("200%", "scope.markdown.zoom200", checked: .zoomPercent == 200)
        switch menu.doModal(me, autoDestroy: true) orelse ""
        {
        case "scope.markdown.zoom75":  .applyZoom(75)
        case "scope.markdown.zoom100": .applyZoom(100)
        case "scope.markdown.zoom125": .applyZoom(125)
        case "scope.markdown.zoom150": .applyZoom(150)
        case "scope.markdown.zoom200": .applyZoom(200)
        }
    }

    // Creates the zoom menu of `view` at the persisted zoom; both selectors restyle the same view.
    func create(parent: *Wnd, view: *Markdown.View, themeCombo, widthCombo: *ComboBox)->*ZoomButton
    {
        with let result = Wnd.create'ZoomButton(parent, null, {0, 0, ViewerZoomButtonWidth, 32}, "scope.markdown.zoom")
        {
            .view        = view
            .themeCombo  = themeCombo
            .widthCombo  = widthCombo
            .dockStyle   = .Center
            .margin      = {ViewerInfoControlInset, 0, ViewerInfoControlInset, 0}
            .zoomPercent = Math.clamp(g_ViewerSettings.zoomPercent, 50'u32, 300'u32)
            .updateFlags(.CenterContent)
            .setText(Format.toString("% %", .zoomPercent, "%"))
            .setArrowPosition(.RightDownward)
            .setForm(.Rectangle)
            .style.setFont(result.theme().createDefaultFontFs(11), .Regular)
            .toolTip    = texts().ui_ZoomMenu
            .sigPressed += func(button) { assume cast(*ZoomButton, button).showZoomMenu() }
        }

        return result
    }
}

// Adds the reading measures to `combo`, in the order of [[ViewerSettings.widthIndex]].
private func addWidths(combo: *ComboBox)
{
    combo.addItem(texts().ui_Narrow)
    combo.addItem(texts().ui_Medium)
    combo.addItem(texts().ui_Wide)
    combo.addItem(texts().ui_Fluid)
}

// Adds the appearances to `combo`, in the order of [[ViewerSettings.themeIndex]].
//
// Only the application's own appearance is translated: the others are the names their styles are
// known by.
private func addThemes(combo: *ComboBox)
{
    combo.addItem(texts().ui_ThemeApp)
    for name in ["GitHub", "Newsprint", "Night", "Pixyll", "Whitey"] do
        combo.addItem(name)
}

// Creates the integrated Markdown view.
func createViewer(host: Viewer.Host)
{
    let view = Markdown.View.createFile(host.contentParent(), host.fileName(), Markdown.Style.theme())
    if not view.failureReason.isEmpty()
    {
        host.reject(view.failureReason)
        view.destroy()
        return
    }

    let commandGroup = host.createCommandGroup(264)

    with let widthCombo = ComboBox.create(commandGroup, {0, 0, 104, 36})
    {
        .dockStyle = .Right
        .toolTip   = texts().ui_TipWidth
        addWidths(widthCombo)
        .setSelectedIndex(g_ViewerSettings.widthIndex, notify: false)
    }

    with let themeCombo = ComboBox.create(commandGroup, {0, 0, 148, 36})
    {
        .dockStyle = .Right
        .margin.z  = 8
        .toolTip   = texts().ui_TipTheme
        addThemes(themeCombo)
        .setSelectedIndex(g_ViewerSettings.themeIndex, notify: false)
    }

    with let zoomButton = ZoomButton.create(host.createInfoGroup(ViewerZoomSlotWidth), view, themeCombo, widthCombo)
    {
        .outline = DocumentOutline.create(host)
        .outline.bindMarkdown(view, host.fileName())
    }

    view.hookOnEvent = func|widthCombo, themeCombo, zoomButton|(?, evt)
    {
        switch evt
        {
        case KeyEvent as key where key.kind == .Pressed and key.modifiers.has(.Control):
            switch key.key
            {
            case .Add, .OemPlus:       zoomButton.applyZoom(zoomButton.zoomPercent + 25)
            case .Subtract, .OemMinus: zoomButton.applyZoom(zoomButton.zoomPercent > 50 ? zoomButton.zoomPercent - 25 : 50)
            case .D0:                  zoomButton.applyZoom(100)
            default:                   return false
            }

            return true

        case MouseEvent as mouse where mouse.kind == .Wheel and mouse.modifiers.has(.Control):
            if mouse.delta.y > 0 do
                zoomButton.applyZoom(zoomButton.zoomPercent + 25)
            elif mouse.delta.y < 0 do
                zoomButton.applyZoom(zoomButton.zoomPercent > 50 ? zoomButton.zoomPercent - 25 : 50)
            return true

        case NotifyEvent as notification where notification.kind == .LanguageChanged:
            let widthIndex = widthCombo.selectedIndex
            let themeIndex = themeCombo.selectedIndex
            widthCombo.clear()
            addWidths(widthCombo)
            widthCombo.setSelectedIndex(widthIndex, notify: false)
            widthCombo.toolTip = texts().ui_TipWidth
            themeCombo.clear()
            addThemes(themeCombo)
            themeCombo.setSelectedIndex(themeIndex, notify: false)
            themeCombo.toolTip = texts().ui_TipTheme
            zoomButton.toolTip = texts().ui_ZoomMenu
            zoomButton.reportStatistics()
        }

        return false
    }

    let services = host.services()
    if services.reportFailure
    {
        let reportFailure: Viewer.ReportFailure = services.reportFailure
        view.sigLoadFailed += func|reportFailure|(markdown, reason) { reportFailure(cast(*Wnd, markdown), reason) }
    }

    applyViewerStyle(view, g_ViewerSettings.themeIndex, g_ViewerSettings.widthIndex, zoomButton.zoomPercent)
    host.attachView(view)
    host.setDetails(texts().ui_Details)

    with var search: Viewer.SearchApi
    {
        .revealMatch = func|view|(match, text)->bool => view.revealFileOffset(match.offset, text)
        .matchBounds = func|view|(?, bounds)->bool => view.searchMatchRect(bounds)
        .clear       = func|view|() => view.clearSearchHighlight()
    }

    host.setSearch(search)

    view.userData = zoomButton
    zoomButton.reportDetails = services.reportDetails
    zoomButton.statisticsLoad.start(host.fileName(), &TextStatisticsCounter.loadUtf8)
    zoomButton.statisticsTimer = zoomButton.addTimer(Viewer.BackgroundPollInterval)

    with var lifecycle: Viewer.LifecycleApi
    {
        .isLoading = func|view|()->bool => view.isLoading()
        .retire    = func|view|()->bool => cast(*ZoomButton, view.userData!).retire()
    }

    host.setLifecycle(lifecycle)

    themeCombo.sigChanged += func|view, widthCombo, zoomButton|(?, index)
    {
        g_ViewerSettings.themeIndex = index
        applyViewerStyle(view, index, widthCombo.selectedIndex, zoomButton.zoomPercent)
        catch g_App.saveState()
    }

    widthCombo.sigChanged += func|view, themeCombo, zoomButton|(?, index)
    {
        g_ViewerSettings.widthIndex = index
        applyViewerStyle(view, themeCombo.selectedIndex, index, zoomButton.zoomPercent, applyColors: false)
        catch g_App.saveState()
    }

    view.sigLinkActivated += func(?, url)
    {
        Env.openUrl(url)
    }
}
