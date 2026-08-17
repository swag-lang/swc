#global public

using Core, Gui

internal func markdownViewerStyle(themeIndex, widthIndex: u32)->MarkdownStyle
{
    var result = MarkdownStyle.theme()
    switch themeIndex
    {
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
        result.maxContentWidth  = 960
        result.horizontalInset  = 52
        result.topInset         = 40
        result.bottomInset      = 48
        result.bodyFontSize     = 19
        result.codeFontSize     = 17
        result.mathFontSize     = 25
        result.heading1FontSize = 48
        result.heading2FontSize = 30
        result.heading3FontSize = 23
        result.heading4FontSize = 20
        result.heading5FontSize = 19
        result.heading6FontSize = 19
        result.lineHeight       = 1.53
        result.headingAlignment = .Center
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

internal func applyMarkdownViewerStyle(view: *MarkdownView, themeIndex, widthIndex: u32)
{
    view.setDocumentThemeColors(markdownViewerColors(themeIndex))
    view.setDocumentStyle(markdownViewerStyle(themeIndex, widthIndex))
}

// Creates the Markdown view exported through the sFileScope plugin ABI.
func sFileScopePluginCreate(request: const *ViewerRequest, result: *ViewerResult)->bool
{
    if request.apiVersion != ViewerPluginApiVersion do
        return false

    registerMarkdownStrings(request.contentParent.app())

    let commandGroup = Wnd.create'Wnd(request.commandParent, {0, 0, 264, 36})
    commandGroup.backgroundStyle = .Window
    let widthCombo = ComboBox.create(commandGroup, {0, 0, 104, 36})
    widthCombo.dockStyle = .Right
    widthCombo.toolTip   = markdownStrings().ui_TipWidth
    widthCombo.addItem(markdownStrings().ui_Narrow)
    widthCombo.addItem(markdownStrings().ui_Medium)
    widthCombo.addItem(markdownStrings().ui_Wide)
    widthCombo.addItem(markdownStrings().ui_Fluid)
    widthCombo.setSelectedIndex(1, notify: false)

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
    themeCombo.setSelectedIndex(0, notify: false)

    let view = MarkdownView.createFile(request.contentParent, request.fileName, MarkdownStyle.theme())
    applyMarkdownViewerStyle(view, 0, 1)
    result.view        = view
    result.commands    = commandGroup
    result.details     = markdownStrings().ui_Details
    result.revealMatch = func(wnd, offset, text)->bool { return (cast(*MarkdownView) wnd).revealFileOffset(offset, text) }
    themeCombo.sigChanged += func|view, widthCombo|(combo, index)
    {
        discard combo
        applyMarkdownViewerStyle(view, index, widthCombo.selectedIndex)
    }
    widthCombo.sigChanged += func|view, themeCombo|(combo, index)
    {
        discard combo
        applyMarkdownViewerStyle(view, themeCombo.selectedIndex, index)
    }
    view.sigLinkActivated += func(markdown, url)
    {
        discard markdown
        Env.openUrl(url)
    }

    return true
}
