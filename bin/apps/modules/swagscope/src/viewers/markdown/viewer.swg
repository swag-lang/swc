#global internal

using Core, Gui

internal struct MarkdownViewerSettings
{
    themeIndex: u32
    widthIndex: u32 = 1
}

internal var g_MarkdownViewerSettings: MarkdownViewerSettings

// Describes the Markdown viewer to the host.
func markdownViewerPlugin()->Viewer.Plugin
{
    var result: retval
    result.key          = "markdown"
    result.staticName   = "Markdown"
    result.attach       = &registerMarkdownStrings
    result.iconAtlas    = viewerIcons()
    result.iconIndex    = cast(s32) ViewerIcons.Markdown
    result.create       = &createMarkdownViewer
    result.smokeFixture = "comprehensive.md"
    result.addSelectors(".markdown;.md;.mdown;.mdwn;.mkd;.mkdn;.rmd")
    return result
}

internal func markdownViewerStyle(themeIndex, widthIndex: u32)->Markdown.Style
{
    var result = Markdown.Style.theme()
    switch themeIndex
    {
    // The application's own theme and Whitey set their body column flush on both edges. The four
    // themes between them are imported, and each is read with the ragged edge its original has:
    // a justified GitHub page is not a GitHub page.
    case 0:
        result.paragraphAlignment = .Justify

    case 2:
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
        result.maxContentWidth    = 960
        result.horizontalInset    = 52
        result.topInset           = 40
        result.bottomInset        = 48
        result.bodyFontSize       = 19
        result.codeFontSize       = 17
        result.mathFontSize       = 25
        result.heading1FontSize   = 48
        result.heading2FontSize   = 30
        result.heading3FontSize   = 23
        result.heading4FontSize   = 20
        result.heading5FontSize   = 19
        result.heading6FontSize   = 19
        result.lineHeight         = 1.53
        result.headingAlignment   = .Center
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

internal func markdownViewerColors(themeIndex: u32)->string
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

internal func applyMarkdownViewerStyle(view: *Markdown.View, themeIndex, widthIndex: u32, zoomPercent = 100'u32)
{
    var style = markdownViewerStyle(themeIndex, widthIndex)
    let scale = cast(f32) zoomPercent / 100
    style.bodyFontSize     = cast(u32) Math.max(Math.round(cast(f32) style.bodyFontSize * scale), 1)
    style.codeFontSize     = cast(u32) Math.max(Math.round(cast(f32) style.codeFontSize * scale), 1)
    style.mathFontSize     = cast(u32) Math.max(Math.round(cast(f32) style.mathFontSize * scale), 1)
    style.heading1FontSize = cast(u32) Math.max(Math.round(cast(f32) style.heading1FontSize * scale), 1)
    style.heading2FontSize = cast(u32) Math.max(Math.round(cast(f32) style.heading2FontSize * scale), 1)
    style.heading3FontSize = cast(u32) Math.max(Math.round(cast(f32) style.heading3FontSize * scale), 1)
    style.heading4FontSize = cast(u32) Math.max(Math.round(cast(f32) style.heading4FontSize * scale), 1)
    style.heading5FontSize = cast(u32) Math.max(Math.round(cast(f32) style.heading5FontSize * scale), 1)
    style.heading6FontSize = cast(u32) Math.max(Math.round(cast(f32) style.heading6FontSize * scale), 1)
    view.setDocumentThemeColors(markdownViewerColors(themeIndex))
    view.setDocumentStyle(style)
}

internal struct MarkdownZoomButton
{
    using button: IconButton

    #[Swag.Late]
    {
        view:       *Markdown.View
        themeCombo: *ComboBox
        widthCombo: *ComboBox
    }

    zoomPercent: u32 = 100
}

private impl MarkdownZoomButton
{
    mtd applyZoom(percent: u32)
    {
        .zoomPercent = percent
        .setText(Format.toString("% %", percent, "%"))
        applyMarkdownViewerStyle(.view, .themeCombo.selectedIndex, .widthCombo.selectedIndex, percent)
    }

    mtd showZoomMenu()
    {
        let menu = MenuCtrl.createPopup(me, owner: me)
        menu.addItem("75%", "scope.markdown.zoom75")
        menu.addItem("100%", "scope.markdown.zoom100", rightName: "Ctrl+0")
        menu.addItem("125%", "scope.markdown.zoom125")
        menu.addItem("150%", "scope.markdown.zoom150")
        menu.addItem("200%", "scope.markdown.zoom200")
        switch menu.doModal(me, autoDestroy: true) orelse ""
        {
        case "scope.markdown.zoom75":  .applyZoom(75)
        case "scope.markdown.zoom100": .applyZoom(100)
        case "scope.markdown.zoom125": .applyZoom(125)
        case "scope.markdown.zoom150": .applyZoom(150)
        case "scope.markdown.zoom200": .applyZoom(200)
        }
    }

    func create(parent: *Wnd, view: *Markdown.View, themeCombo, widthCombo: *ComboBox)->*MarkdownZoomButton
    {
        let result = Wnd.create'MarkdownZoomButton(parent, null, {0, 0, 96, 32}, "scope.markdown.zoom")
        result.view       = view
        result.themeCombo = themeCombo
        result.widthCombo = widthCombo
        result.dockStyle  = .Center
        result.updateFlags(.CenterContent)
        result.setText("100%")
        result.setArrowPosition(.RightDownward)
        result.setForm(.Rectangle)
        result.style.setFont(result.theme().createDefaultFontFS(11), .Regular)
        result.toolTip    = markdownStrings().ui_ZoomMenu
        result.sigPressed += func(button)
        {
            (cast(*MarkdownZoomButton) button).showZoomMenu()
        }
        return result
    }
}

// Creates the integrated Markdown view.
func createMarkdownViewer(host: Viewer.Host)
{
    let view = Markdown.View.createFile(host.contentParent(), host.fileName(), Markdown.Style.theme())
    if !view.failureReason.isEmpty()
    {
        host.reject(view.failureReason.toString())
        view.destroy()
        return
    }

    let commandGroup = host.createCommandGroup(264)
    let widthCombo   = ComboBox.create(commandGroup, {0, 0, 104, 36})
    widthCombo.dockStyle = .Right
    widthCombo.toolTip   = markdownStrings().ui_TipWidth
    widthCombo.addItem(markdownStrings().ui_Narrow)
    widthCombo.addItem(markdownStrings().ui_Medium)
    widthCombo.addItem(markdownStrings().ui_Wide)
    widthCombo.addItem(markdownStrings().ui_Fluid)
    widthCombo.setSelectedIndex(g_MarkdownViewerSettings.widthIndex, notify: false)

    let themeCombo = ComboBox.create(commandGroup, {0, 0, 148, 36})
    themeCombo.dockStyle = .Right
    themeCombo.margin.z  = 8
    themeCombo.toolTip   = markdownStrings().ui_TipTheme
    themeCombo.addItem(markdownStrings().ui_ThemeApp)
    themeCombo.addItem("GitHub")
    themeCombo.addItem("Newsprint")
    themeCombo.addItem("Night")
    themeCombo.addItem("Pixyll")
    themeCombo.addItem("Whitey")
    themeCombo.setSelectedIndex(g_MarkdownViewerSettings.themeIndex, notify: false)

    let zoomButton = MarkdownZoomButton.create(host.createInfoGroup(96), view, themeCombo, widthCombo)

    let services = host.services()
    if services.reportFailure
    {
        let reportFailure = services.reportFailure!
        view.sigLoadFailed += func|reportFailure|(markdown, reason) { reportFailure(cast(*Wnd) markdown, reason) }
    }

    applyMarkdownViewerStyle(view, g_MarkdownViewerSettings.themeIndex, g_MarkdownViewerSettings.widthIndex)
    host.attachView(view)
    host.setDetails(markdownStrings().ui_Details)
    host.setSearch({
        revealMatch: func(wnd, match, text)->bool { return (cast(*Markdown.View) wnd).revealFileOffset(match.offset, text) },
        matchBounds: func(wnd, match, bounds)->bool
    {
        discard match
        return (cast(*Markdown.View) wnd).searchMatchRect(bounds)
    },
        clear: func(wnd) { (cast(*Markdown.View) wnd).clearSearchHighlight() }})
    host.setLifecycle({isLoading: func(wnd)->bool { return (cast(*Markdown.View) wnd).isLoading() }})
    themeCombo.sigChanged += func|view, widthCombo, zoomButton|(combo, index)
    {
        discard combo
        g_MarkdownViewerSettings.themeIndex = index
        applyMarkdownViewerStyle(view, index, widthCombo.selectedIndex, zoomButton.zoomPercent)
        catch g_App.saveState()
    }
    widthCombo.sigChanged += func|view, themeCombo, zoomButton|(combo, index)
    {
        discard combo
        g_MarkdownViewerSettings.widthIndex = index
        applyMarkdownViewerStyle(view, themeCombo.selectedIndex, index, zoomButton.zoomPercent)
        catch g_App.saveState()
    }
    view.sigLinkActivated += func(markdown, url)
    {
        discard markdown
        Env.openUrl(url)
    }
}
