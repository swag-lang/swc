#global public

using Core, Gui

private const ViewerPluginApiVersion = 4'u32

private func markdownViewerStyle(themeIndex, widthIndex: u32)->MarkdownStyle
{
    var result = MarkdownStyle.theme()
    switch themeIndex
    {
    case 1:
        result.bodyFontSize = 17
        result.codeFontSize = 15
        result.topInset     = 46
        result.bottomInset  = 46

    case 2:
        result.bodyFontSize    = 14
        result.codeFontSize    = 13
        result.horizontalInset = 32
        result.topInset        = 28
        result.bottomInset     = 28
    }

    switch widthIndex
    {
    case 0: result.maxContentWidth = 680
    case 2: result.maxContentWidth = 1_100
    case 3:
        result.maxContentWidth = 100_000
        result.horizontalInset = 24
    }

    return result
}

private func applyMarkdownViewerStyle(view: *MarkdownView, themeIndex, widthIndex: u32)
{
    view.style.clearStyleSheetColors()
    if themeIndex == 1 do
        view.style.addStyleSheetColors("view_Bk $wnd_Bk")
    view.setDocumentStyle(markdownViewerStyle(themeIndex, widthIndex))
}

// Creates the Markdown view exported through the sFileScope plugin ABI.
func sFileScopePluginCreate(contentParent, commandParent: *Wnd, fileName: string, apiVersion: u32, commands: *#null *Wnd, details: *String, revealMatch: *#null func||(*Wnd, u64, string)->bool)->#null *Wnd
{
    if apiVersion != ViewerPluginApiVersion do
        return null

    let commandGroup = Wnd.create'Wnd(commandParent, {0, 0, 244, 36})
    commandGroup.backgroundStyle = .Window
    let widthCombo = ComboBox.create(commandGroup, {0, 0, 104, 36})
    widthCombo.dockStyle = .Right
    widthCombo.toolTip   = "Reading width"
    widthCombo.addItem("Narrow")
    widthCombo.addItem("Medium")
    widthCombo.addItem("Wide")
    widthCombo.addItem("Fluid")
    widthCombo.setSelectedIndex(1, notify: false)

    let themeCombo = ComboBox.create(commandGroup, {0, 0, 128, 36})
    themeCombo.dockStyle = .Right
    themeCombo.margin.z  = 8
    themeCombo.toolTip   = "Markdown appearance"
    themeCombo.addItem("Reader")
    themeCombo.addItem("Paper")
    themeCombo.addItem("Compact")
    themeCombo.setSelectedIndex(0, notify: false)

    commands[] = commandGroup
    details[]  = "Markdown · UTF-8 · streamed"
    let view = MarkdownView.createFile(contentParent, fileName, MarkdownStyle.theme())
    revealMatch[] = func(wnd, offset, text)->bool { return (cast(*MarkdownView) wnd).revealFileOffset(offset, text) }
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
    return view
}
