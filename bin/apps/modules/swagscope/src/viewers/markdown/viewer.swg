#global internal
#global namespace Viewers.MarkdownText

using Core, Gui

// Reading preferences of the Markdown viewer, kept across files and persisted by the window.
struct ViewerSettings
{
    #[Properties.Name("Document Theme")]
    themeIndex:  u32           // Document appearance, in the order of the appearance selector.
    #[Properties.Name("Reading Width")]
    widthIndex:  u32 = 1       // Reading measure, in the order of the width selector.
    #[Properties.Name("Zoom"), Properties.MinMax(25, 400), Properties.Unit("%")]
    zoomPercent: u32 = 100     // Document zoom.
}

impl ViewerSettings
{
    // Brings preferences read back from a saved state into the ranges the selectors offer.
    mtd sanitize()
    {
        .themeIndex  = Math.min(.themeIndex, 5)
        .widthIndex  = Math.min(.widthIndex, 3)
        .zoomPercent = Viewer.clampZoom(.zoomPercent)
    }
}

var g_ViewerSettings: ViewerSettings

private func addViewerOptions(grid: *PropertiesCtrl, section: string) => grid.addStruct(g_ViewerSettings, section)

// Describes the Markdown viewer to the host.
func viewerPlugin()->Viewer.Plugin
{
    with var result: #returntype
    {
        .key             = "markdown"
        .staticName      = "Markdown"
        .attach          = &registerTexts
        .iconAtlas       = viewerIcons()
        .iconIndex       = cast(s32, ViewerIcons.Markdown)
        .create          = &createViewer
        .options         = &addViewerOptions
        .textual         = true
        .showReadingLine = false
        .smokeFixture    = "comprehensive.md"
        .addSelectors(".markdown;.md;.mdown;.mdwn;.mkd;.mkdn;.rmd")
    }

    return result
}

// Returns the document style of one appearance at one reading measure.
func viewerStyle(themeIndex, widthIndex: u32)->Markdown.Style
{
    var result = Markdown.Style.theme()
    if themeIndex
    {
        result.codeTypeFaces        = systemFaces(["Consolas", "Menlo", "Monaco"])
        result.blockMargins         = {16, 16}
        result.bodyLineHeight       = 25.6
        result.codeLineHeight       = 22.4
        result.headingTopSpacing    = [16, 16, 16, 16, 16, 16]
        result.headingBottomSpacing = [16, 16, 16, 16, 16, 16]
        result.horizontalInset      = 30
        result.topInset             = 36
        result.bottomInset          = 100
        result.imageAlignment       = .Center
        result.quotePadding         = {19, 0, 15, 0}
        result.quoteRuleWidth       = 4
        result.quoteRuleInset       = 0
        result.quoteRuleColor       = .Border
    }

    switch themeIndex
    {
    // The application's own theme and Whitey set their body column flush on both edges. The four
    // themes between them follow Typora's ragged paragraph edges.
    case 0:
        result.maxContentWidth    = 640
        result.paragraphAlignment = .Justify

    case 1:
        result.bodyTypeFaces      = systemFaces(["Open Sans", "Clear Sans", "Helvetica Neue", "Helvetica", "Arial"])
        result.maxContentWidth    = 800
        result.topInset           = 30
        result.blockMargins       = {12.8, 12.8}
        result.headingLineHeights = [43.2, 34.3, 34.32, 28, 22.4, 22.4]
        result.headingRuleWidths  = [-1, -1, 0, 0, 0, 0]

    case 2:
        result.bodyTypeFaces        = systemFaces(["PT Serif", "Times New Roman", "Times"])
        result.maxContentWidth      = 580
        result.heading1FontSize     = 30
        result.heading2FontSize     = 21
        result.heading3FontSize     = 21
        result.heading4FontSize     = 18
        result.lineHeight           = 1.5
        result.bodyLineHeight       = 24
        result.blockMargins         = {16, 24}
        result.headingFontStyles    = [.Bold, .Bold, .Regular, .Bold, .Bold, .Bold]
        result.headingTopSpacing    = [60, 48, 48, 48, 16, 16]
        result.headingBottomSpacing = [45, 32, 32, 27, 24, 24]
        result.headingLineHeights   = [48, 24.15, 24.15, 24, 24, 24]
        result.headingRuleWidths    = [-1, 0, 0, 0, 0, 0]
        result.headingRuleColor     = .Text
        result.headingRulePadding   = [24.375, 0, 0, 0, 0, 0]
        result.quotePadding         = {21, 0, 0, 0}
        result.quoteRuleWidth       = 5
        result.quoteIndent          = 32
        result.quoteFontStyle       = .Italic
        result.quoteRuleColor       = .Text

    case 3:
        result.bodyTypeFaces        = systemFaces(["Helvetica Neue", "Helvetica", "Arial"])
        result.headingTypeFaces     = systemFaces(["Lucida Grande", "Corbel"])
        result.maxContentWidth      = 854
        result.heading1FontSize     = 40
        result.heading2FontSize     = 26
        result.heading3FontSize     = 19
        result.heading4FontSize     = 18
        result.heading6FontSize     = 15
        result.lineHeight           = 1.625
        result.bodyLineHeight       = 26
        result.headingFontStyles    = [.Regular, .Bold, .Bold, .Regular, .Bold, .Regular]
        result.headingTopSpacing    = [0, 0, 0, 0, 0, 0]
        result.headingBottomSpacing = [24, 24, 24, 24, 24, 12]
        result.headingLineHeights   = [44, 30, 24, 22, 20, 16]
        result.quotePadding         = {32, 0, 0, 0}
        result.quoteIndent          = 30
        result.quoteRuleWidth       = 2

    case 4:
        result.bodyTypeFaces        = systemFaces(["Merriweather", "PT Serif", "Georgia", "Times New Roman"])
        result.headingTypeFaces     = systemFaces(["Lato", "Helvetica Neue", "Helvetica", "Arial"])
        result.codeTypeFaces        = systemFaces(["Menlo", "Monaco", "Courier New"])
        result.maxContentWidth      = 854
        result.bodyFontSize         = 20
        result.codeFontSize         = 16
        result.mathFontSize         = 24
        result.heading1FontSize     = 52
        result.heading2FontSize     = 37
        result.heading3FontSize     = 26
        result.heading4FontSize     = 21
        result.heading5FontSize     = 18
        result.heading6FontSize     = 18
        result.lineHeight           = 1.8
        result.bodyLineHeight       = 36
        result.headingTopSpacing    = [52, 37, 26, 21, 18, 18]
        result.headingBottomSpacing = [26, 18, 13, 10, 9, 9]
        result.headingLineHeights   = [62.4, 44.4, 31.2, 25.2, 21.6, 21.6]
        result.quotePadding         = {32, 27, 27, 27}
        result.quoteRuleWidth       = 5
        result.quoteFontStyle       = .Italic
        result.quoteRuleColor       = .RichText

    case 5:
        result.bodyTypeFaces          = systemFaces(["Vollkorn", "Palatino", "Times", "Times New Roman"])
        result.headingFontStyles      = [.Regular, .Regular, .Italic, .Bold, .Bold, .Bold]
        result.headingTopSpacing      = [91, 68, 91, 19, 19, 19]
        result.headingBottomSpacing   = [19, 19, 19, 19, 19, 19]
        result.maxContentWidth        = 900
        result.topInset               = 40
        result.bottomInset            = 48
        result.bodyFontSize           = 19
        result.codeFontSize           = 17
        result.mathFontSize           = 25
        result.heading1FontSize       = 57
        result.heading2FontSize       = 34
        result.heading3FontSize       = 30
        result.heading4FontSize       = 27
        result.heading5FontSize       = 23
        result.heading6FontSize       = 19
        result.lineHeight             = 1.53
        result.bodyLineHeight         = 29.07
        result.codeLineHeight         = 26.16
        result.blockMargins           = {0, 19}
        result.headingLineHeights     = [87.21, 52.02, 45.9, 41.31, 35.19, 29.07]
        result.headingRuleWidths      = [0, 100, 0, 0, 0, 0]
        result.headingRuleColor       = .Text
        result.quotePadding           = {20, 0, 0, 0}
        result.quoteIndent            = 19
        result.quoteRuleWidth         = 1
        result.headingAlignment       = .Center
        result.headingAlignmentLevels = 3
        result.imageAlignment         = .Center
        result.paragraphAlignment     = .Justify
    }

    switch widthIndex
    {
    case 0:
        result.maxContentWidth = themeIndex == 0 ? 560 : 680

    case 2:
        result.maxContentWidth = 1_100

    case 3:
        result.maxContentWidth = 100_000
        result.horizontalInset = 24
    }

    return result
}

// The theme-sheet colors of the imported appearances, one color per line.
private
{
    const GitHubColors = """view_Bk              0xFFFFFFFF
                            label_Text           0xFF333333
                            label_TextLight      0xFF666666
                            label_TextFaint      0xFF777777
                            edit_Bk              0xFFF8F8F8
                            edit_Border          0xFFDFE2E5
                            edit_SelectedBk      0xFFCCE5FF
                            url_Text             0xFF4183C4
                            url_HotText          0xFF2B6DA8
                            richColor1           0xFF777777
                            scrollBar_Bk         0xFFFFFFFF
                            scrollBar_HotBk      0xFFF5F5F5
                            scrollBar_Box        0xFFC5C5C5
                            scrollBar_HotBox     0xFFA5A5A5
                            scrollBar_PressedBox 0xFF888888"""

    const NewsprintColors = """view_Bk              0xFFF3F2EE
                               label_Text           0xFF1F0909
                               label_TextLight      0xFF656565
                               label_TextFaint      0xFF656565
                               edit_Bk              0xFFDADADA
                               edit_Border          0xFFC5C5C5
                               edit_SelectedBk      0xFFBBCBD2
                               url_Text             0xFF065588
                               url_HotText          0xFF043A5D
                               richColor1           0xFFBABABA
                               scrollBar_Bk         0xFFF3F2EE
                               scrollBar_HotBk      0xFFE8E6E0
                               scrollBar_Box        0xFFBAB6AE
                               scrollBar_HotBox     0xFF8F8980
                               scrollBar_PressedBox 0xFF6F6961"""

    const NightColors = """view_Bk              0xFF363B40
                           label_Text           0xFFB8BFC6
                           label_TextLight      0xFF9CA4AC
                           label_TextFaint      0xFF8E969E
                           edit_Bk              0xFF333333
                           edit_Border          0xFF474D54
                           edit_SelectedBk      0xFF4A6073
                           url_Text             0xFF6DC1E7
                           url_HotText          0xFFA3D5FE
                           richColor1           0xFFDEDEDE
                           scrollBar_Bk         0xFF363B40
                           scrollBar_HotBk      0xFF3D4349
                           scrollBar_Box        0xFF596169
                           scrollBar_HotBox     0xFF707A84
                           scrollBar_PressedBox 0xFF89949F"""

    const PixyllColors = """view_Bk              0xFFFFFFFF
                            label_Text           0xFF333333
                            label_TextLight      0xFF666666
                            label_TextFaint      0xFF7A7A7A
                            edit_Bk              0xFFF8F8F8
                            edit_Border          0xFFD8D8D8
                            edit_SelectedBk      0xFFDDE7F2
                            url_Text             0xFF463F5C
                            url_HotText          0xFF6A6086
                            richColor1           0xFF7A7A7A
                            scrollBar_Bk         0xFFFFFFFF
                            scrollBar_HotBk      0xFFF4F4F4
                            scrollBar_Box        0xFFC6C6C6
                            scrollBar_HotBox     0xFFA6A6A6
                            scrollBar_PressedBox 0xFF8A8A8A"""

    const WhiteyColors = """view_Bk              0xFFFEFEFE
                            label_Text           0xFF333333
                            label_TextLight      0xFF666666
                            label_TextFaint      0xFF777777
                            edit_Bk              0xFFFFFFFF
                            edit_Border          0xFFDDDDDD
                            edit_SelectedBk      0xFFD9EAF5
                            url_Text             0xFF2484C1
                            url_HotText          0xFF17618F
                            richColor1           0xFF777777
                            scrollBar_Bk         0xFFFEFEFE
                            scrollBar_HotBk      0xFFF3F3F3
                            scrollBar_Box        0xFFC8C8C8
                            scrollBar_HotBox     0xFFA8A8A8
                            scrollBar_PressedBox 0xFF8B8B8B"""
}

// Returns the theme-sheet colors of one appearance, or nothing for the application's own.
func viewerColors(themeIndex: u32)->String
{
    var colors: string
    switch themeIndex
    {
    case 0:  return {}
    case 2:  colors = NewsprintColors
    case 3:  colors = NightColors
    case 4:  colors = PixyllColors
    case 5:  colors = WhiteyColors
    default: colors = GitHubColors
    }

    // Document-owned navigation uses the same ink and ground as its paragraphs.
    const NavigationColors = """text                       $label_Text
                               softText                   $label_TextLight
                               faintText                  $label_TextFaint
                               line                       $edit_Border
                               arc                        $url_Text
                               ground                     $view_Bk
                               listItem_Text              $label_Text
                               listItem_SelectedText      $label_Text
                               listItem_FocusSelectedText $label_Text
                               listItem_SelectedBk        $edit_SelectedBk
                               listItem_FocusSelectedBk   $edit_SelectedBk
                               listItem_HotBk             $edit_SelectedBk
                               edit_Text                  $label_Text
                               edit_Note                  $label_TextFaint
                               edit_Caret                 $label_Text
                               edit_FocusBorder           $label_Text
                               edit_FocusBk               $view_Bk
                               edit_HotBk                 $view_Bk
                               edit_HotBorder             $label_TextLight
                               btnIcon_Icon               $label_TextFaint
                               btnIcon_HotIcon            $label_Text"""
    return Format.toString("%\n%", colors, NavigationColors)
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
    style.bodyLineHeight   *= scale
    style.codeLineHeight   *= scale
    style.quotePadding     *= scale
    style.quoteRuleWidth   *= scale
    style.quoteRuleInset   *= scale
    style.quoteIndent      *= scale
    style.topInset         *= scale
    style.bottomInset      *= scale
    if style.blockMargins.x >= 0 and style.blockMargins.y >= 0 do
        style.blockMargins *= scale
    for &height in style.headingLineHeights do
        height[] *= scale
    for &width in style.headingRuleWidths where width[] > 0 do
        width[] *= scale
    for &padding in style.headingRulePadding do
        padding[] *= scale
    for &spacing in style.headingTopSpacing do
        spacing[] = cast(u32, Math.round(cast(f32, spacing[]) * scale))
    for &spacing in style.headingBottomSpacing do
        spacing[] = cast(u32, Math.round(cast(f32, spacing[]) * scale))
    if applyColors do
        view.setDocumentThemeColors(viewerColors(themeIndex))
    view.setDocumentStyle(style)
}

// The zoom menu of the Markdown viewer, which also owns the viewer's background statistics and
// outline, since the document view itself is a standard [[Gui.Markdown.View]].
struct ZoomButton
{
    using button: IconButton

    late view: *Markdown.View

    zoomPercent:    u32 = 100
    statisticsLoad: Viewer.BackgroundLoad'TextStatistics
    statistics:     TextStatistics
    hasStatistics:  bool
    services:       Viewer.HostServices
    outline:        *DocumentOutline?
}

impl IWnd for ZoomButton
{
    mtd impl onTaskEvent(evt: *TaskEvent)
    {
        if not .statisticsLoad.claim(evt) do
            return
        let error = .statisticsLoad.finish(&.statistics)
        .hasStatistics = error.isEmpty()
        .reportStatistics()
    }
}

impl ZoomButton
{
    mtd reportStatistics()
    {
        .outline?.setReadingColors(viewerColors(g_ViewerSettings.themeIndex))
        if not .hasStatistics
        {
            .services.showDetails(.view, texts().ui_Details)
            return
        }

        let texts      = texts()
        let lines      = .statistics.lines == 1 ? String.from(texts.ui_OneLine) : Format.toString(texts.ui_Lines, .statistics.lines)
        let words      = .statistics.words == 1 ? String.from(texts.ui_OneWord) : Format.toString(texts.ui_Words, .statistics.words)
        let characters = .statistics.characters == 1 ? String.from(texts.ui_OneCharacter) : Format.toString(texts.ui_Characters, .statistics.characters)
        .services.showDetails(.view, Format.toString("% · % · % · %", texts.ui_Details, lines, words, characters))
    }

    mtd retire()->bool
    {
        if .outline and not .outline.retire() do
            return false

        // Totals that arrive while the view retires have nobody left to show them to.
        return .statisticsLoad.retire()
    }

    mtd applyZoom(percent: u32)
    {
        let bounded = Viewer.clampZoom(percent)
        if .zoomPercent == bounded do
            return
        .zoomPercent = bounded
        .setText(Viewer.zoomText(bounded))
        applyViewerStyle(.view, g_ViewerSettings.themeIndex, g_ViewerSettings.widthIndex, bounded, applyColors: false)

        // The window saves preferences on navigation and close, outside wheel handling.
        g_ViewerSettings.zoomPercent = bounded
    }

    // The page shows no line of readings, so the menu takes the place of the lens.
    mtd showZoomMenu()
    {
        let percent = Viewer.pickZoom(.view, Lens.followUpPoint(.view, 0), .AnchorTopCenter, .zoomPercent)
        if percent do
            .applyZoom(percent)
    }

    // Creates the zoom menu of `view` at the persisted zoom, in the persisted measure and appearance.
    func create(parent: *Wnd, view: *Markdown.View)->*ZoomButton
    {
        with let result = Wnd.create'ZoomButton(parent, null, {0, 0, Viewer.ZoomButtonWidth, 32}, "scope.markdown.zoom")
        {
            .view        = view
            .dockStyle   = .Center
            .margin      = {Viewer.ZoomButtonInset, 0, Viewer.ZoomButtonInset, 0}
            .zoomPercent = Viewer.clampZoom(g_ViewerSettings.zoomPercent)
            .toolTip     = texts().ui_ZoomMenu
            .updateFlags(.CenterContent)
            .setText(Viewer.zoomText(.zoomPercent))
            .setArrowPosition(.RightDownward)
            .setForm(.Rectangle)
            .style.setFont(result.theme().createDefaultFontFs(11), .Regular)
            .sigPressed += func(button) { button.showZoomMenu() }
        }

        return result
    }
}

// Names one reading measure, in the order of [[ViewerSettings.widthIndex]].
func widthName(index: u32)->string
{
    switch index
    {
    case 0:  return texts().ui_Narrow
    case 1:  return texts().ui_Medium
    case 2:  return texts().ui_Wide
    default: return texts().ui_Fluid
    }
}

// Names one appearance, in the order of [[ViewerSettings.themeIndex]].
//
// Only the application's own appearance is translated: the others are the names their styles are
// known by.
func themeName(index: u32)->string
{
    const Names = ["GitHub", "Newsprint", "Night", "Pixyll", "Whitey"]
    return index ? Names[Math.min(index - 1, Names.count - 1)] : texts().ui_ThemeApp
}

const WidthCount = 4'u32
const ThemeCount = 6'u32

// Opens how the document reads: its measure and its appearance. Both choices are remembered, and
// the keyboard goes back to the document, where the reader was.
//
// The page shows no line of readings, so the sheet takes the place of the lens.
func showOptions(anchor: *Wnd, view: *Markdown.View, zoom: *ZoomButton)
{
    let sheet = OptionSheet.View.create(anchor, func|view, zoom|(page) { describeOptions(page, view, zoom) }, owner: view)
    sheet.doModal(Lens.followUpPoint(view, view.themeMetrics().optionSheet_Width), autoDestroy: true)
    view.setFocus()
}

func describeOptions(page: *OptionSheet.Page, view: *Markdown.View, zoom: *ZoomButton)
{
    page.addLink(texts().ui_Width, widthName(g_ViewerSettings.widthIndex), func|view, zoom|(widths)
    {
        for index in WidthCount
        {
            widths.addChoice(widthName(index), index == g_ViewerSettings.widthIndex, func|view, zoom, index|()
            {
                g_ViewerSettings.widthIndex = index
                applyViewerStyle(view, g_ViewerSettings.themeIndex, index, zoom.zoomPercent, applyColors: false)
                catch g_App.saveState()
            })
        }
    })

    page.addLink(texts().ui_Theme, themeName(g_ViewerSettings.themeIndex), func|view, zoom|(themes)
    {
        for index in ThemeCount
        {
            themes.addChoice(themeName(index), index == g_ViewerSettings.themeIndex, func|view, zoom, index|()
            {
                g_ViewerSettings.themeIndex = index
                applyViewerStyle(view, index, g_ViewerSettings.widthIndex, zoom.zoomPercent)
                zoom.reportStatistics()
                catch g_App.saveState()
            })
        }
    })
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

    let actionGroup = host.createActionGroup(themeDropDownButtonWidth(view.themeMetrics()))
    actionGroup.dockStyle = .Right
    actionGroup.margin.z  = 12
    let optionsButton = Viewer.createOptionsButton(actionGroup)
    optionsButton.dockStyle = .Right
    optionsButton.setArrowPosition(.RightDownward)

    with let zoomButton = ZoomButton.create(host.createInfoGroup(Viewer.ZoomSlotWidth), view)
    {
        .outline = DocumentOutline.create(host, floatingSurface: false)
        .outline.bindMarkdown(view, host.fileName())
        .outline.startMarkdown()
    }

    optionsButton.sigPressed += func|view, zoomButton|(button)
    {
        showOptions(button, view, zoomButton)
    }

    host.setLensSource(func|view, zoomButton|(entries)
    {
        entries.addZoom(.In, zoomButton.zoomPercent, func|zoomButton, percent = Viewer.zoomTarget(.In, zoomButton.zoomPercent)|() { zoomButton.applyZoom(percent) })
        entries.addZoom(.Out, zoomButton.zoomPercent, func|zoomButton, percent = Viewer.zoomTarget(.Out, zoomButton.zoomPercent)|() { zoomButton.applyZoom(percent) })
        entries.addZoom(.Reset, zoomButton.zoomPercent, func|zoomButton, percent = Viewer.zoomTarget(.Reset, zoomButton.zoomPercent)|() { zoomButton.applyZoom(percent) })
        entries.add(appStrings().cmd_ZoomMenu, func|zoomButton|() { zoomButton.showZoomMenu() })
        entries.add(appStrings().cmd_Options, func|view, zoomButton|() { showOptions(view, view, zoomButton) })
    })

    view.hookOnEvent = func|optionsButton, zoomButton|(_, evt)
    {
        switch evt
        {
        case KeyEvent as key where Viewer.isZoomKey(key):
            zoomButton.applyZoom(Viewer.zoomAfterKey(key, zoomButton.zoomPercent))
            return true

        case MouseEvent as mouse where mouse.kind == .Wheel and mouse.modifiers.has(.Control):
            if mouse.delta.y > 0 do
                zoomButton.applyZoom(Viewer.zoomIn(zoomButton.zoomPercent))
            elif mouse.delta.y < 0 do
                zoomButton.applyZoom(Viewer.zoomOut(zoomButton.zoomPercent))
            return true

        case NotifyEvent as notification where notification.kind == .LanguageChanged:
            optionsButton.toolTip = appStrings().ui_Options
            zoomButton.toolTip    = texts().ui_ZoomMenu
            zoomButton.reportStatistics()
        }

        return false
    }

    let services = host.services()
    if services.reportFailure
    {
        let reportFailure: Viewer.ReportFailure = services.reportFailure
        view.sigLoadFailed += func|reportFailure|(markdown, reason) { reportFailure(markdown, reason) }
    }

    applyViewerStyle(view, g_ViewerSettings.themeIndex, g_ViewerSettings.widthIndex, zoomButton.zoomPercent)
    host.attachView(view)
    host.setDetails(texts().ui_Details)

    with var search: Viewer.SearchApi
    {
        .revealMatch = func|view|(match, text)->bool => view.revealFileOffset(match.offset, text)
        .matchBounds = func|view|(_, bounds)->bool => view.searchMatchRect(bounds)
        .clear       = func|view|() => view.clearSearchHighlight()
    }

    host.setSearch(search)

    view.userData       = zoomButton
    zoomButton.services = services
    zoomButton.statisticsLoad.start(host.fileName(), &TextStatisticsCounter.loadUtf8, zoomButton)

    with var lifecycle: Viewer.LifecycleApi
    {
        .isLoading = func|view|()->bool => view.isLoading()
        .retire    = func|view|()->bool => cast(*ZoomButton, unwrap view.userData).retire()
    }

    host.setLifecycle(lifecycle)

    view.sigLinkActivated += func(_, url)
    {
        Env.openUrl(url)
    }
}
