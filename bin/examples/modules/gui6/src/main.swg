using Core, Gui, Pixel

const W = 1240
const H = 820
const MaxPages = 4
const TestFramesPerPage = 35
const RootMargin = 24.0
const PageTop = 112.0
const PageBottomMargin = 58.0
const PanelGap = 24.0
const TopPanelHeight = 360.0
const MinBottomPanelHeight = 220.0
const ThemeButtonWidth = 152.0
const HeaderGap = 18.0

struct MenuCmd
{
    newCmdId("NewFile")
    newCmdId("OpenFile")
    newCmdId("SaveFile")
    newCmdId("SaveAs")
    newCmdId("Export")
    newCmdId("Quit")

    newCmdId("Undo")
    newCmdId("Redo")
    newCmdId("Cut")
    newCmdId("Copy")
    newCmdId("Paste")
    newCmdId("Duplicate")

    newCmdId("ToggleGrid")
    newCmdId("ToggleGuides")
    newCmdId("ModeCompact")
    newCmdId("ModeDetailed")
    newCmdId("ModeColumns")
    newCmdId("ThemeLight")
    newCmdId("ThemeDark")

    newCmdId("ContextInspect")
    newCmdId("ContextRename")
    newCmdId("ContextPin")
    newCmdId("ContextArchive")
    newCmdId("ContextDelete")
    newCmdId("AlignLeft")
    newCmdId("AlignCenter")
    newCmdId("AlignRight")
    newCmdId("About")
}

enum PreviewMode
{
    Compact
    Detailed
    Columns
}

struct PagePanelLayout
{
    left:   Math.Rectangle
    right:  Math.Rectangle
    bottom: Math.Rectangle
}

var app: Application
var g_Surface: *Surface
var g_View: *Wnd
var g_Title: *Label
var g_SubTitle: *Label
var g_ThemeButton: *PushButton
var g_PageView: *Wnd
var g_Footer: *Label
var g_StatusLabel: *Label
var g_Preview: *Wnd
var g_PageMenus: Array'(*MenuCtrl)
var g_ContextMenu: *MenuCtrl
var g_StateMenu: *MenuCtrl
var g_Page: s32
var g_TestFrame: s32
var g_DarkTheme: bool
var g_DocumentDirty = true
var g_ShowGrid = true
var g_ShowGuides = true
var g_ContextPinned: bool
var g_ActionCount: s32
var g_Mode = PreviewMode.Detailed
var g_StatusText: String

func setLabelTextStyle(label: *Label, horizontal = StringHorzAlignment.Left, vertical = StringVertAlignment.Center)
{
    label.horzAlignmentText = horizontal
    label.vertAlignmentText = vertical
}

func createText(parent: *Wnd, text: string, rect: Math.Rectangle, flags = LabelFlags.Zero)->*Label
{
    let label = Label.create(parent, text, rect, null, flags)
    setLabelTextStyle(label, .Left, .Center)
    return label
}

func createHelpText(parent: *Wnd, text: string, rect: Math.Rectangle)->*Label
{
    let label = createText(parent, text, rect, .WordWrap | .LightText)
    label.vertAlignmentText = .Top
    return label
}

func createPanel(parent: *Wnd, title, subtitle: string, rect: Math.Rectangle)->*Wnd
{
    let frame = Wnd.create'FrameWnd(parent, rect)
    frame.setFrameForm(.Round)
    frame.setFrameFlags(.Borders)

    let view = frame.createView'Wnd()
    discard createText(view, title, {16, 10, rect.width - 32, 24})
    discard createHelpText(view, subtitle, {16, 36, rect.width - 32, 44})
    return view
}

func createCaption(parent: *Wnd, text: string, x, y, width: f32)
{
    let label = createText(parent, text, {x, y, width, 22})
    label.labelFlags.add(.LightText)
}

func createActionButton(parent: *Wnd, text: string, rect: Math.Rectangle, id: WndId, icon: ThemeIcons24)->*PushButton
{
    let btn = PushButton.create(parent, text, rect, id)
    btn.icon = app.theme.getIcon24(icon, 18)
    return btn
}

func getPagePanelLayout(parent: *Wnd)->PagePanelLayout
{
    let rect = parent.getClientRect()
    let width = Math.max(rect.width, 1.0)
    let height = Math.max(rect.height, TopPanelHeight + PanelGap + MinBottomPanelHeight)
    let halfWidth = (width - PanelGap) * 0.5
    let topHeight = Math.min(TopPanelHeight, Math.max(330.0, (height - PanelGap) * 0.58))
    let bottomY = topHeight + PanelGap
    let bottomHeight = Math.max(MinBottomPanelHeight, height - bottomY)

    var result: retval
    result.left = {0, 0, halfWidth, topHeight}
    result.right = {halfWidth + PanelGap, 0, width - halfWidth - PanelGap, topHeight}
    result.bottom = {0, bottomY, width, bottomHeight}
    return result
}

func pageTitle(page: s32)->string
{
    switch page
    {
    case 0:
        return "Menu bar"
    case 1:
        return "Context menus"
    case 2:
        return "Command state"
    case 3:
        return "Anchored popups"
    }

    unreachable
}

func pageSubtitle(page: s32)->string
{
    switch page
    {
    case 0:
        return "A desktop-style menu bar with grouped items, icons, shortcuts and nested popups."
    case 1:
        return "Reusable right-click menus with separators, submenus and destructive commands."
    case 2:
        return "Checked, radio-style and disabled rows driven by CommandStateEvent."
    case 3:
        return "Small menus anchored to buttons, suitable for compact toolbars and split-button flows."
    }

    unreachable
}

func currentModeName()->string
{
    switch g_Mode
    {
    case Compact:
        return "compact"
    case Detailed:
        return "detailed"
    case Columns:
        return "columns"
    }

    unreachable
}

func boolWord(value: bool)->string
{
    return value ? "on" : "off"
}

func stateSummary()->String
{
    return Format.toString("Dirty: %    Grid: %    Guides: %    Mode: %    Pinned: %    Commands: %", boolWord(g_DocumentDirty), boolWord(g_ShowGrid), boolWord(g_ShowGuides), currentModeName(), boolWord(g_ContextPinned), g_ActionCount)
}

func updateHeader()
{
    g_Title.setText(Format.toString("GUI6 menu showcase - %", pageTitle(g_Page)))
    g_SubTitle.setText(pageSubtitle(g_Page))
    g_Footer.setText(Format.toString("F1/right/down : next, left/up : previous (%/%). %", g_Page + 1, MaxPages, stateSummary()))
}

func updateStatusLabel()
{
    if g_StatusLabel do
        g_StatusLabel.setText(g_StatusText)
}

func setStatus(text: string)
{
    g_StatusText = text
    updateStatusLabel()
    updateHeader()

    if g_Preview do
        g_Preview.invalidate()
    if g_PageView do
        g_PageView.updateCommandState()
    app.invalidate()
}

func updateThemeButton()
{
    if !g_ThemeButton do
        return

    if g_DarkTheme do
        g_ThemeButton.name = "White theme"
    else do
        g_ThemeButton.name = "Black theme"
    g_ThemeButton.invalidate()
}

func applyTheme()
{
    if g_DarkTheme do
        app.theme.colors.setDark()
    else do
        app.theme.colors.setLight()

    updateThemeButton()
    app.themeHasChanged()
}

func toggleTheme(_btn: *Button)
{
    g_DarkTheme = !g_DarkTheme
    applyTheme()
}

func createTrackedPopup(parent: *Wnd)->*MenuCtrl
{
    let menu = MenuCtrl.createPopup(parent, owner: g_View)
    g_PageMenus.add(menu)
    return menu
}

func destroyPageMenus()
{
    foreach menu in g_PageMenus where menu do
        menu.destroy()

    g_PageMenus.clear()
    g_ContextMenu = null
    g_StateMenu = null
}

func addDocumentItems(menu: *MenuCtrl)
{
    menu.addItem("New document", MenuCmd.NewFile, app.theme.getIcon24(.Plus, 18))
    menu.addItem("Open...", MenuCmd.OpenFile, app.theme.getIcon24(.OpenFile, 18))
    menu.addSeparator()
    menu.addItem("Save", MenuCmd.SaveFile, app.theme.getIcon24(.Save, 18))
    menu.addItem("Save as...", MenuCmd.SaveAs, app.theme.getIcon24(.SaveAs, 18))
    menu.addItem("Export package", MenuCmd.Export, app.theme.getIcon24(.Export, 18))
    menu.addSeparator()
    menu.addItem("Quit", MenuCmd.Quit, app.theme.getIcon24(.Quit, 18))
}

func addEditItems(menu: *MenuCtrl)
{
    menu.addItem("Undo", MenuCmd.Undo, app.theme.getIcon24(.Undo, 18))
    menu.addItem("Redo", MenuCmd.Redo, app.theme.getIcon24(.Redo, 18))
    menu.addSeparator()
    menu.addItem("Cut", MenuCmd.Cut, app.theme.getIcon24(.Cut, 18))
    menu.addItem("Copy", MenuCmd.Copy, app.theme.getIcon24(.Copy, 18))
    menu.addItem("Paste", MenuCmd.Paste, app.theme.getIcon24(.Paste, 18))
    menu.addItem("Duplicate", MenuCmd.Duplicate, app.theme.getIcon24(.Duplicate, 18))
}

func addViewItems(menu: *MenuCtrl)
{
    menu.addItem("Show grid", MenuCmd.ToggleGrid)
    menu.addItem("Show guides", MenuCmd.ToggleGuides)
    menu.addSeparator()
    menu.addItem("Compact cards", MenuCmd.ModeCompact)
    menu.addItem("Detailed cards", MenuCmd.ModeDetailed)
    menu.addItem("Column layout", MenuCmd.ModeColumns)
}

func addThemeItems(menu: *MenuCtrl)
{
    menu.addItem("Light theme", MenuCmd.ThemeLight)
    menu.addItem("Dark theme", MenuCmd.ThemeDark)
}

func createFileMenu(parent: *Wnd)->*MenuCtrl
{
    let menu = createTrackedPopup(parent)
    addDocumentItems(menu)
    return menu
}

func createEditMenu(parent: *Wnd)->*MenuCtrl
{
    let menu = createTrackedPopup(parent)
    addEditItems(menu)
    return menu
}

func createViewMenu(parent: *Wnd)->*MenuCtrl
{
    let menu = createTrackedPopup(parent)
    addViewItems(menu)
    return menu
}

func createOptionsMenu(parent: *Wnd)->*MenuCtrl
{
    let menu = createTrackedPopup(parent)
    addThemeItems(menu)
    menu.addSeparator()
    menu.addItem("About menus", MenuCmd.About, app.theme.getIcon24(.About, 18))
    return menu
}

func createMainMenuBar(parent: *Wnd, rect: Math.Rectangle)->*MenuCtrl
{
    let bar = MenuCtrl.createBar(parent, rect, owner: g_View)
    bar.addPopup("File", createFileMenu(parent))
    bar.addPopup("Edit", createEditMenu(parent))
    bar.addPopup("View", createViewMenu(parent))
    bar.addPopup("Options", createOptionsMenu(parent))
    return bar
}

func createStatusPanel(parent: *Wnd, rect: Math.Rectangle)
{
    let panel = createPanel(parent, "Command feedback", "The last selected menu item is reflected here while checked and disabled rows update from shared state.", rect)
    g_StatusLabel = createHelpText(panel, g_StatusText, {20, 92, rect.width - 40, rect.height - 112})
}

func drawWrappedText(painter: *Painter, rect: Math.Rectangle, text: string, font: *Font, color: Color, maxLines = 2'u32)
{
    var richText: RichString = text
    var format: RichStringFormat
    format.flags = .WordWrap | .Clip
    format.font.regular = font
    format.palette[0] = color
    format.maxLines = maxLines
    painter.drawRichString(rect, &richText, format)
}

func drawStatePill(painter: *Painter, rect: Math.Rectangle, text: string, active: bool, font: *Font, colors: *ThemeColors)
{
    let fill = active ? Argb.CornflowerBlue : colors.view_Bk
    let textColor = active ? Argb.White : colors.label_Text
    painter.fillRoundRect(rect, 16, 16, fill)
    painter.drawRoundRect(rect, 16, 16, active ? Argb.CornflowerBlue : colors.frameWnd_Border, 1)
    painter.drawStringCenter(rect.horzCenter(), rect.vertCenter(), text, font, textColor)
}

func onPreviewEvent(view: *Wnd, evt: IEvent)->bool
{
    switch evt
    {
    case PaintEvent as paintEvt:
        let painter = paintEvt.bc.painter
        let rect = view.getClientRect()
        let colors = view.getThemeColors()
        let font = view.getTheme().createDefaultFont(14)
        let titleFont = view.getTheme().createDefaultFont(20, .Bold)

        painter.fillRect(rect, colors.view_Bk)
        let card = Math.Rectangle{24, 24, Math.max(rect.width - 48, 1.0), Math.max(rect.height - 48, 1.0)}
        painter.fillRoundRect(card, 20, 20, Color.fromArgb(255, 246, 248, 250))
        painter.drawRoundRect(card, 20, 20, Color.fromArgb(70'u8, Argb.Black), 1)

        painter.drawString(card.x + 24, card.y + 22, "Menu-driven workspace", titleFont, Argb.DarkSlateGray)
        drawWrappedText(painter, {card.x + 24, card.y + 60, card.width - 48, 44}, g_StatusText, font, Argb.DimGray, 2)

        let y = card.y + 126
        drawStatePill(painter, {card.x + 24, y, 112, 34}, Format.toString("grid %", boolWord(g_ShowGrid)), g_ShowGrid, font, colors)
        drawStatePill(painter, {card.x + 150, y, 124, 34}, Format.toString("guides %", boolWord(g_ShowGuides)), g_ShowGuides, font, colors)
        drawStatePill(painter, {card.x + 288, y, 132, 34}, currentModeName(), true, font, colors)
        drawStatePill(painter, {card.x + 434, y, 112, 34}, g_DocumentDirty ? "dirty" : "saved", g_DocumentDirty, font, colors)

        let lineY = card.bottom() - 52
        painter.drawLine(card.x + 24, lineY, card.right() - 24, lineY, Color.fromArgb(60'u8, Argb.Black), 1)
        painter.drawString(card.x + 24, lineY + 16, stateSummary(), font, Argb.DimGray)
    }

    return false
}

func createPreview(parent: *Wnd, rect: Math.Rectangle)->*Wnd
{
    let view = Wnd.create'Wnd(parent, rect)
    view.hookOnEvent = &onPreviewEvent
    return view
}

func setMode(mode: PreviewMode)
{
    g_Mode = mode
    g_DocumentDirty = true
    setStatus(Format.toString("Preview mode changed to %.", currentModeName()))
}

func processMenuCommand(id: WndId)->bool
{
    switch id
    {
    case MenuCmd.NewFile:
        g_DocumentDirty = true
        g_ActionCount += 1
        setStatus("Created a new menu sample document.")
    case MenuCmd.OpenFile:
        g_DocumentDirty = true
        g_ActionCount += 1
        setStatus("Opened a simulated document from the File menu.")
    case MenuCmd.SaveFile:
        g_DocumentDirty = false
        g_ActionCount += 1
        setStatus("Saved the current document; Save is now disabled until the next edit.")
    case MenuCmd.SaveAs:
        g_DocumentDirty = false
        g_ActionCount += 1
        setStatus("Saved a copy through the Save As command.")
    case MenuCmd.Export:
        g_ActionCount += 1
        setStatus("Export command selected from a grouped menu section.")
    case MenuCmd.Quit:
        if g_Surface do
            g_Surface.destroy()

    case MenuCmd.Undo:
        g_DocumentDirty = false
        g_ActionCount += 1
        setStatus("Undo consumed the simulated dirty state.")
    case MenuCmd.Redo:
        g_DocumentDirty = true
        g_ActionCount += 1
        setStatus("Redo restored the simulated dirty state.")
    case MenuCmd.Cut:
        g_DocumentDirty = true
        g_ActionCount += 1
        setStatus("Cut command selected.")
    case MenuCmd.Copy:
        g_ActionCount += 1
        setStatus("Copy command selected.")
    case MenuCmd.Paste:
        g_DocumentDirty = true
        g_ActionCount += 1
        setStatus("Paste command selected.")
    case MenuCmd.Duplicate:
        g_DocumentDirty = true
        g_ActionCount += 1
        setStatus("Duplicate command selected.")

    case MenuCmd.ToggleGrid:
        g_ShowGrid = !g_ShowGrid
        g_DocumentDirty = true
        g_ActionCount += 1
        setStatus(Format.toString("Grid visibility is now %.", boolWord(g_ShowGrid)))
    case MenuCmd.ToggleGuides:
        g_ShowGuides = !g_ShowGuides
        g_DocumentDirty = true
        g_ActionCount += 1
        setStatus(Format.toString("Guide visibility is now %.", boolWord(g_ShowGuides)))
    case MenuCmd.ModeCompact:
        g_ActionCount += 1
        setMode(.Compact)
    case MenuCmd.ModeDetailed:
        g_ActionCount += 1
        setMode(.Detailed)
    case MenuCmd.ModeColumns:
        g_ActionCount += 1
        setMode(.Columns)
    case MenuCmd.ThemeLight:
        g_DarkTheme = false
        g_ActionCount += 1
        applyTheme()
        setStatus("Light theme selected from a menu.")
    case MenuCmd.ThemeDark:
        g_DarkTheme = true
        g_ActionCount += 1
        applyTheme()
        setStatus("Dark theme selected from a menu.")

    case MenuCmd.ContextInspect:
        g_ActionCount += 1
        setStatus("Inspect command selected from the context menu.")
    case MenuCmd.ContextRename:
        g_DocumentDirty = true
        g_ActionCount += 1
        setStatus("Rename command selected from the context menu.")
    case MenuCmd.ContextPin:
        g_ContextPinned = !g_ContextPinned
        g_ActionCount += 1
        setStatus(Format.toString("Context item pinned state is now %.", boolWord(g_ContextPinned)))
    case MenuCmd.ContextArchive:
        g_ActionCount += 1
        setStatus("Archive command selected.")
    case MenuCmd.ContextDelete:
        g_ActionCount += 1
        setStatus("Delete command selected; destructive entries can live in their own group.")
    case MenuCmd.AlignLeft:
        g_ActionCount += 1
        setStatus("Aligned context selection left.")
    case MenuCmd.AlignCenter:
        g_ActionCount += 1
        setStatus("Aligned context selection center.")
    case MenuCmd.AlignRight:
        g_ActionCount += 1
        setStatus("Aligned context selection right.")
    case MenuCmd.About:
        g_ActionCount += 1
        setStatus("Menus support bars, popup menus, submenus, check marks, radio groups, shortcuts and command state.")
    default:
        return false
    }

    return true
}

func computeMenuCommandState(evt: *CommandStateEvent)->bool
{
    switch evt.id
    {
    case MenuCmd.SaveFile:
        evt.setFlags |= .Disabled
        evt.disabled = !g_DocumentDirty
    case MenuCmd.Undo:
        evt.setFlags |= .Disabled
        evt.disabled = !g_DocumentDirty
    case MenuCmd.Redo:
        evt.setFlags |= .Disabled
        evt.disabled = g_DocumentDirty
    case MenuCmd.ToggleGrid:
        evt.setFlags |= .Checked
        evt.checked = g_ShowGrid
    case MenuCmd.ToggleGuides:
        evt.setFlags |= .Checked
        evt.checked = g_ShowGuides
    case MenuCmd.ModeCompact:
        evt.setFlags |= .Checked | .RenderingHint
        evt.renderingHint = .ExclusiveGroup
        evt.checked = g_Mode == .Compact
    case MenuCmd.ModeDetailed:
        evt.setFlags |= .Checked | .RenderingHint
        evt.renderingHint = .ExclusiveGroup
        evt.checked = g_Mode == .Detailed
    case MenuCmd.ModeColumns:
        evt.setFlags |= .Checked | .RenderingHint
        evt.renderingHint = .ExclusiveGroup
        evt.checked = g_Mode == .Columns
    case MenuCmd.ThemeLight:
        evt.setFlags |= .Checked | .RenderingHint
        evt.renderingHint = .ExclusiveGroup
        evt.checked = !g_DarkTheme
    case MenuCmd.ThemeDark:
        evt.setFlags |= .Checked | .RenderingHint
        evt.renderingHint = .ExclusiveGroup
        evt.checked = g_DarkTheme
    case MenuCmd.ContextPin:
        evt.setFlags |= .Checked
        evt.checked = g_ContextPinned
    case MenuCmd.ContextDelete:
        evt.setFlags |= .Disabled
        evt.disabled = g_ContextPinned
    default:
        return false
    }

    return true
}

func onRootEvent(_view: *Wnd, evt: IEvent)->bool
{
    if let cmd = evt as CommandEvent
    {
        if processMenuCommand(cmd.id)
        {
            cmd.accepted = true
            return true
        }
    }
    elif let state = evt as CommandStateEvent where state.kind == .ComputeCommandState
    {
        if computeMenuCommandState(state)
        {
            state.accepted = true
            return true
        }
    }
    elif evt is ResizeEvent
    {
        layoutRootView()
        buildPage()
        return true
    }
    elif evt is DestroyEvent
    {
        destroyPageMenus()
        app.sigFrame.disable()
        g_Surface     = null
        g_View        = null
        g_Title       = null
        g_SubTitle    = null
        g_ThemeButton = null
        g_PageView    = null
        g_Footer      = null
        g_StatusLabel = null
        g_Preview     = null
        return true
    }

    return false
}

func clearPage()
{
    destroyPageMenus()
    g_StatusLabel = null
    g_Preview = null

    foreach child in g_PageView.childs do
        child.destroy()
}

func buildPage()
{
    clearPage()
    updateHeader()

    switch g_Page
    {
    case 0:
        createMenuBarPage(g_PageView)
    case 1:
        createContextMenuPage(g_PageView)
    case 2:
        createCommandStatePage(g_PageView)
    case 3:
        createAnchoredPopupPage(g_PageView)
    default:
        unreachable
    }

    updateStatusLabel()
    g_PageView.updateCommandState()
    g_PageView.invalidate()
}

func layoutRootView()
{
    if !g_View or !g_PageView do
        return

    let rect = g_View.getClientRect()
    let contentWidth = Math.max(rect.width - 2 * RootMargin, 1.0)
    let pageHeight = Math.max(rect.height - PageTop - PageBottomMargin, TopPanelHeight + PanelGap + MinBottomPanelHeight)
    let footerY = Math.max(rect.height - 42.0, PageTop + pageHeight + 6.0)
    let titleWidth = Math.max(contentWidth - ThemeButtonWidth - HeaderGap, 1.0)

    g_Title.setPosition({RootMargin, 18, titleWidth, 34})
    g_ThemeButton.setPosition({RootMargin + titleWidth + HeaderGap, 18, ThemeButtonWidth, 34})
    g_SubTitle.setPosition({RootMargin + 2, 56, contentWidth - 4, 42})
    g_PageView.setPosition({RootMargin, PageTop, contentWidth, pageHeight})
    g_Footer.setPosition({RootMargin, footerY, contentWidth, 28})
}

func nextPage()
{
    g_Page = (g_Page + 1) % MaxPages
    buildPage()
}

func previousPage()
{
    g_Page -= 1
    if g_Page < 0 do
        g_Page = MaxPages - 1
    buildPage()
}

func updateTestMode()
{
    if !Env.hasArg("swag.test") or !g_Surface do
        return

    g_TestFrame += 1
    if g_TestFrame < TestFramesPerPage do
        return

    g_TestFrame = 0
    if g_Page + 1 >= MaxPages
    {
        Env.exit(0)
        return
    }

    nextPage()
}

func canUsePageArrows()->bool
{
    if !g_View or !g_PageView do
        return false

    let focus = g_View.getFocus()
    if !focus or focus == g_View do
        return true

    return !g_PageView.isParentOf(focus)
}

func onFrame(app: *Application)
{
    if !g_Surface or !g_View or !g_PageView do
        return

    if app.keyb.isKeyJustPressed(.F1) do
        nextPage()
    elif canUsePageArrows()
    {
        if app.keyb.isKeyJustPressed(.Right) or app.keyb.isKeyJustPressed(.Down) do
            nextPage()
        elif app.keyb.isKeyJustPressed(.Left) or app.keyb.isKeyJustPressed(.Up) do
            previousPage()
    }

    updateTestMode()
}

func registerMenuShortcuts()
{
    g_View.registerKeyShortcut(.Control, .N, MenuCmd.NewFile)
    g_View.registerKeyShortcut(.Control, .O, MenuCmd.OpenFile)
    g_View.registerKeyShortcut(.Control, .S, MenuCmd.SaveFile)
    g_View.registerKeyShortcut(.CtrlShift, .S, MenuCmd.SaveAs)
    g_View.registerKeyShortcut(.Control, .Z, MenuCmd.Undo)
    g_View.registerKeyShortcut(.Control, .Y, MenuCmd.Redo)
    g_View.registerKeyShortcut(.Control, .X, MenuCmd.Cut)
    g_View.registerKeyShortcut(.Control, .C, MenuCmd.Copy)
    g_View.registerKeyShortcut(.Control, .V, MenuCmd.Paste)
    g_View.registerKeyShortcut(.Control, .G, MenuCmd.ToggleGrid)
    g_View.registerKeyShortcut(.CtrlShift, .G, MenuCmd.ToggleGuides)
}

func createRootView()
{
    g_View = g_Surface.getView()
    g_View.backgroundStyle = .View

    g_Title = Label.create(g_View, "", {})
    setLabelTextStyle(g_Title, .Left, .Center)
    g_Title.style.setFont(g_View.getTheme().createDefaultFont(28), .Regular)

    g_SubTitle = Label.create(g_View, "", {}, null, .WordWrap | .LightText)
    setLabelTextStyle(g_SubTitle, .Left, .Top)

    g_ThemeButton = PushButton.create(g_View, "", {})
    g_ThemeButton.form = .Flat
    g_ThemeButton.icon = app.theme.getIcon24(ThemeIcons24.Picker, 18)
    g_ThemeButton.sigPressed += &toggleTheme

    g_PageView = Wnd.create'Wnd(g_View, {})
    g_PageView.backgroundStyle = .Transparent

    g_Footer = Label.create(g_View, "", {})
    setLabelTextStyle(g_Footer, .Left, .Center)
    g_Footer.labelFlags.add(.LightText)

    registerMenuShortcuts()
    layoutRootView()
    g_View.hookOnEvent = &onRootEvent
}

#main
{
    let flags = SurfaceFlags.BigCaption | SurfaceFlags.MinimizeBtn | SurfaceFlags.CloseBtn | SurfaceFlags.Border
    g_Surface = try app.createSurface(100, 80, W, H, flags)
    g_Surface.setTitle("GUI6 menu showcase")
    g_Surface.setIcon(app.theme.getIcon24(ThemeIcons24.More, 18))
    g_StatusText = "Open a menu or use shortcuts to exercise command dispatch."

    createRootView()
    buildPage()

    app.sigFrame += &onFrame
    if Env.hasArg("swag.test") do
        app.maxRunFrame = cast(u32) MaxPages * cast(u32) TestFramesPerPage + 10

    g_Surface.show()
    applyTheme()
    app.run()
}
