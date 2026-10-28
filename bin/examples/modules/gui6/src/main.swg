// GUI6 - menus and the commands behind them.
//
// A menu bar, context menus, menus anchored to buttons and the rows a command state computes,
// all routed through one set of commands. The same commands are lens entries under their family,
// so `Ctrl K` reaches every one of them as well as the pages and the appearance; the hint line
// reads the shared state out in mono. `--light` opens the window on Papier, `--page=N` on page N.

using Core, Gui, Pixel

const W        = 1100
const H        = 860
const MaxPages = 4
const TestFramesPerPage = 35

// The page keeps reading margins at its sides, and each section keeps one inset for its label, its
// sentence and its controls, so the section labels stand on the left edge of the title.
const PageMargin      = 48.0
const SectionInset    = 24.0
const SectionGap      = 24.0
const TitleSize       = 34'u32
const TopHeight       = 320.0
const MinBottomHeight = 200.0

const CmdLens         = "gui6.lens"
const CmdNextPage     = "gui6.page.next"
const CmdPreviousPage = "gui6.page.previous"

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

var app:             Application
var g_Surface:       *Surface?
var g_View:          *Wnd?
var g_Title:         *Label?
var g_SubTitle:      *Label?
var g_Tabs:          *Tab?
var g_PageView:      *Wnd?
var g_Lens:          *Lens.View?
var g_Appearance:    *AppearanceButton?
var g_Page:          s32
var g_TestFrame:     s32
var g_Hint:          *HintLine?
var g_StatusLabel:   *Label?
var g_Preview:       *Wnd?
var g_PageMenus:     Array'(*MenuCtrl)
var g_ContextMenu:   *MenuCtrl?
var g_StateMenu:     *MenuCtrl?
var g_DocumentDirty = true
var g_ShowGrid      = true
var g_ShowGuides    = true
var g_ContextPinned: bool
var g_ActionCount:   s32
var g_Mode          = PreviewMode.Detailed
var g_StatusText:    String
var g_Light:         bool

func createText(parent: *Wnd, text: string, rect: Math.Rectangle, flags = LabelFlags.None)->*Label
{
    let label = Label.create(parent, text, rect, null, flags)
    label.setTextAlignment(.Left, .Center)
    return label
}

func createHelpText(parent: *Wnd, text: string, rect: Math.Rectangle)->*Label
{
    let label = createText(parent, text, rect, .WordWrap | .SecondaryText)
    label.setTextVerticalAlignment(.Top)
    return label
}

// Opens a section of a page: its label, the sentence saying what it shows, and room for the
// controls from `y = 88`, all on the same inset.
func createPanel(parent: *Wnd, title, subtitle: string, rect: Math.Rectangle)->*Wnd
{
    let view = Wnd.create'Wnd(parent, rect)
    view.backgroundStyle = .Transparent
    SectionLabel.create(view, title, Math.Rectangle{SectionInset, 0, rect.width - 2 * SectionInset, 20})
    discard createHelpText(view, subtitle, Math.Rectangle{SectionInset, 28, rect.width - 2 * SectionInset, 44})
    return view
}

// Names the control that follows, in the faint ink of a caption.
func createCaption(parent: *Wnd, text: string, x, y, width: f32)
{
    let label = createText(parent, text, Math.Rectangle{x, y, width, 24}, .SecondaryText)
    label.style.addStyleSheetColors("label_TextLight $label_TextFaint")
}

func createActionButton(parent: *Wnd, text: string, rect: Math.Rectangle, id: WndId, icon: ThemeIcons)->*PushButton
{
    let btn = PushButton.create(parent, text, rect, id)
    btn.setIcon(app.theme.icon(icon, 16))
    return btn
}

func currentModeName()->string
{
    switch g_Mode
    {
    case .Compact:  return "compact"
    case .Detailed: return "detailed"
    case .Columns:  return "columns"
    }

    unreachable
}

func boolWord(value: bool)->string => value ? "on" : "off"

func stateSummary()->String
{
    return Format.toString("dirty %  ·  grid %  ·  guides %  ·  mode %  ·  pinned %  ·  commands %",
                           boolWord(g_DocumentDirty),
                           boolWord(g_ShowGrid),
                           boolWord(g_ShowGuides),
                           currentModeName(),
                           boolWord(g_ContextPinned),
                           g_ActionCount)
}

func updateStatusLabel()
{
    g_StatusLabel?.setText(g_StatusText)
}

func setStatus(text: string)
{
    g_StatusText = text
    updateStatusLabel()
    g_Hint?.setReading(stateSummary())

    g_Preview?.invalidate()
    g_PageView?.updateCommandState()
    app.invalidate()
}

func createTrackedPopup(parent: *Wnd)->*MenuCtrl
{
    let menu = MenuCtrl.createPopup(parent, owner: g_View)
    g_PageMenus.add(menu)
    return menu
}

func destroyPageMenus()
{
    for menu in g_PageMenus do
        menu.destroy()

    g_PageMenus.clear()
    g_ContextMenu = null
    g_StateMenu   = null
}

func addDocumentItems(menu: *MenuCtrl)
{
    menu.addItem("New Document", MenuCmd.NewFile, app.theme.icon(.Plus, 16))
    menu.addItem("Open…", MenuCmd.OpenFile, app.theme.icon(.OpenFile, 16))
    menu.addSeparator()
    menu.addItem("Save", MenuCmd.SaveFile, app.theme.icon(.Save, 16))
    menu.addItem("Save As…", MenuCmd.SaveAs, app.theme.icon(.SaveAs, 16))
    menu.addItem("Export Package", MenuCmd.Export, app.theme.icon(.Export, 16))
    menu.addSeparator()
    menu.addItem("Quit", MenuCmd.Quit, app.theme.icon(.Quit, 16))
}

func addEditItems(menu: *MenuCtrl)
{
    menu.addItem("Undo", MenuCmd.Undo, app.theme.icon(.Undo, 16))
    menu.addItem("Redo", MenuCmd.Redo, app.theme.icon(.Redo, 16))
    menu.addSeparator()
    menu.addItem("Cut", MenuCmd.Cut, app.theme.icon(.Cut, 16))
    menu.addItem("Copy", MenuCmd.Copy, app.theme.icon(.Copy, 16))
    menu.addItem("Paste", MenuCmd.Paste, app.theme.icon(.Paste, 16))
    menu.addItem("Duplicate", MenuCmd.Duplicate, app.theme.icon(.Duplicate, 16))
}

func addViewItems(menu: *MenuCtrl)
{
    menu.addItem("Show Grid", MenuCmd.ToggleGrid)
    menu.addItem("Show Guides", MenuCmd.ToggleGuides)
    menu.addSeparator()
    menu.addItem("Compact Cards", MenuCmd.ModeCompact)
    menu.addItem("Detailed Cards", MenuCmd.ModeDetailed)
    menu.addItem("Column Layout", MenuCmd.ModeColumns)
}

func addThemeItems(menu: *MenuCtrl)
{
    menu.addItem("Light Theme", MenuCmd.ThemeLight)
    menu.addItem("Dark Theme", MenuCmd.ThemeDark)
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
    menu.addItem("About Menus", MenuCmd.About, app.theme.icon(.About, 16))
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
    let panel = createPanel(parent,
                            "Command feedback",
                            "The last command chosen is written here; checked and disabled rows follow the same state.",
                            rect)
    let label = createText(panel, g_StatusText, Math.Rectangle{SectionInset, 88, rect.width - 2 * SectionInset, Math.max(rect.height - 88, 1.0)}, .WordWrap)
    label.setTextVerticalAlignment(.Top)
    g_StatusLabel = label
}

func drawWrappedText(painter: *Painter, rect: Math.Rectangle, text: string, font: *Font, color: Color, maxLines = 2'u32)
{
    var richText: RichString = text
    var format:   RichStringFormat
    format.flags        = .WordWrap | .Clip
    format.font.regular = font
    format.palette[0]   = color
    format.maxLines     = maxLines
    painter.drawRichString(rect, &richText, format)
}

// Draws a state as a chip: on the Arc selection ground in Arc when it is on, a hairline ring in the
// soft ink when it is off.
func drawStatePill(painter: *Painter, rect: Math.Rectangle, text: string, active: bool, font: *Font, colors: *ThemeColors)
{
    let corner = g_View!.themeMetrics().corner_Chip
    if active do
        painter.fillRoundRect(rect, corner, corner, colors.selection)
    else do
        painter.drawRoundRect(rect, corner, corner, colors.line, 1)
    painter.drawStringCenter(rect.horzCenter(), rect.vertCenter(), text, font, active ? colors.arc : colors.softText)
}

func onPreviewEvent(view: *Wnd, evt: IEvent)->bool
{
    switch evt
    {
    case PaintEvent as paintEvt:
        let painter   = paintEvt.paintContext.painter
        let rect      = view.clientRect()
        let colors    = view.themeColors()
        let font      = view.theme().createDefaultFont(14)
        let titleFont = view.theme().createDefaultFont(20, .Bold)

        // The state is written on the ground of the page, on the inset of its section.
        let card         = rect
        let contentX     = card.x
        let contentWidth = Math.max(card.width, 1.0)
        painter.drawString(contentX, card.y + 4, "Menu-Driven Workspace", titleFont, colors.text)
        drawWrappedText(painter, Math.Rectangle{contentX, card.y + 42, contentWidth, 42}, g_StatusText, font, colors.softText, 2)

        let pillGap    = 12.0
        let pillHeight = 32.0
        let pillTop    = card.y + 92
        var pillsBottom: f32

        if contentWidth >= 560.0
        {
            let pillWidth = (contentWidth - 3 * pillGap) * 0.25
            drawStatePill(painter,
                          Math.Rectangle{contentX, pillTop, pillWidth, pillHeight},
                          Format.toString("grid %", boolWord(g_ShowGrid)),
                          g_ShowGrid,
                          font,
                          colors)
            drawStatePill(painter,
                          Math.Rectangle{contentX + pillWidth + pillGap, pillTop, pillWidth, pillHeight},
                          Format.toString("guides %", boolWord(g_ShowGuides)),
                          g_ShowGuides,
                          font,
                          colors)
            drawStatePill(painter,
                          Math.Rectangle{contentX + 2 * (pillWidth + pillGap), pillTop, pillWidth, pillHeight},
                          currentModeName(),
                          true,
                          font,
                          colors)
            drawStatePill(painter,
                          Math.Rectangle{contentX + 3 * (pillWidth + pillGap), pillTop, pillWidth, pillHeight},
                          g_DocumentDirty ? "dirty" : "saved",
                          g_DocumentDirty,
                          font,
                          colors)
            pillsBottom = pillTop + pillHeight
        }
        else
        {
            let pillWidth = (contentWidth - pillGap) * 0.5
            let secondX   = contentX + pillWidth + pillGap
            let secondRow = pillTop + pillHeight + 10
            drawStatePill(painter,
                          Math.Rectangle{contentX, pillTop, pillWidth, pillHeight},
                          Format.toString("grid %", boolWord(g_ShowGrid)),
                          g_ShowGrid,
                          font,
                          colors)
            drawStatePill(painter,
                          Math.Rectangle{secondX, pillTop, pillWidth, pillHeight},
                          Format.toString("guides %", boolWord(g_ShowGuides)),
                          g_ShowGuides,
                          font,
                          colors)
            drawStatePill(painter,
                          Math.Rectangle{contentX, secondRow, pillWidth, pillHeight},
                          currentModeName(),
                          true,
                          font,
                          colors)
            drawStatePill(painter,
                          Math.Rectangle{secondX, secondRow, pillWidth, pillHeight},
                          g_DocumentDirty ? "dirty" : "saved",
                          g_DocumentDirty,
                          font,
                          colors)
            pillsBottom = secondRow + pillHeight
        }

        // The count of commands is a measure, written in mono under one hairline.
        let lineY = card.bottom() - 40
        if lineY > pillsBottom + 12
        {
            painter.fillRect(Math.Rectangle{contentX, lineY, contentWidth, 1}, colors.line)
            painter.drawString(contentX, lineY + 14, Format.toString("% commands run", g_ActionCount), view.theme().createDefaultFontFs(12), colors.faintText)
        }
    }

    return false
}

// Creates the painted preview of the shared state in `section`, on its inset.
func createPreview(section: *Wnd)->*Wnd
{
    let rect = section.clientRect()
    let view = Wnd.create'Wnd(section, Math.Rectangle{SectionInset, 88, rect.width - 2 * SectionInset, Math.max(rect.height - 88, 1.0)})
    view.backgroundStyle = .Transparent
    view.hookOnEvent     = &onPreviewEvent
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
        g_ActionCount   += 1
        setStatus("Created a new menu sample document.")

    case MenuCmd.OpenFile:
        g_DocumentDirty = true
        g_ActionCount   += 1
        setStatus("Opened a simulated document from the File menu.")

    case MenuCmd.SaveFile:
        g_DocumentDirty = false
        g_ActionCount   += 1
        setStatus("Saved the current document; Save is now disabled until the next edit.")

    case MenuCmd.SaveAs:
        g_DocumentDirty = false
        g_ActionCount   += 1
        setStatus("Saved a copy through the Save As command.")

    case MenuCmd.Export:
        g_ActionCount += 1
        setStatus("Export command selected from a grouped menu section.")

    case MenuCmd.Quit:
        g_Surface?.destroy()

    case MenuCmd.Undo:
        g_DocumentDirty = false
        g_ActionCount   += 1
        setStatus("Undo consumed the simulated dirty state.")

    case MenuCmd.Redo:
        g_DocumentDirty = true
        g_ActionCount   += 1
        setStatus("Redo restored the simulated dirty state.")

    case MenuCmd.Cut:
        g_DocumentDirty = true
        g_ActionCount   += 1
        setStatus("Cut command selected.")

    case MenuCmd.Copy:
        g_ActionCount += 1
        setStatus("Copy command selected.")

    case MenuCmd.Paste:
        g_DocumentDirty = true
        g_ActionCount   += 1
        setStatus("Paste command selected.")

    case MenuCmd.Duplicate:
        g_DocumentDirty = true
        g_ActionCount   += 1
        setStatus("Duplicate command selected.")

    case MenuCmd.ToggleGrid:
        g_ShowGrid      = not g_ShowGrid
        g_DocumentDirty = true
        g_ActionCount   += 1
        setStatus(Format.toString("Grid visibility is now %.", boolWord(g_ShowGrid)))

    case MenuCmd.ToggleGuides:
        g_ShowGuides    = not g_ShowGuides
        g_DocumentDirty = true
        g_ActionCount   += 1
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

    // The appearance has one owner, which the lens offers too; the menu rows only ask it.
    case MenuCmd.ThemeLight:
        g_ActionCount += 1
        g_Appearance!.setAppearanceTheme(.Light)
        setStatus("Light theme chosen from a menu.")

    case MenuCmd.ThemeDark:
        g_ActionCount += 1
        g_Appearance!.setAppearanceTheme(.Dark)
        setStatus("Dark theme chosen from a menu.")

    case MenuCmd.ContextInspect:
        g_ActionCount += 1
        setStatus("Inspect command selected from the context menu.")

    case MenuCmd.ContextRename:
        g_DocumentDirty = true
        g_ActionCount   += 1
        setStatus("Rename command selected from the context menu.")

    case MenuCmd.ContextPin:
        g_ContextPinned = not g_ContextPinned
        g_ActionCount   += 1
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

// Names a command for the lens, which lists every command of the menus under its family.
func menuCommandName(id: WndId)->string
{
    switch id
    {
    case MenuCmd.NewFile:        return "New Document"
    case MenuCmd.OpenFile:       return "Open…"
    case MenuCmd.SaveFile:       return "Save"
    case MenuCmd.SaveAs:         return "Save As…"
    case MenuCmd.Export:         return "Export Package"
    case MenuCmd.Quit:           return "Quit"
    case MenuCmd.Undo:           return "Undo"
    case MenuCmd.Redo:           return "Redo"
    case MenuCmd.Cut:            return "Cut"
    case MenuCmd.Copy:           return "Copy"
    case MenuCmd.Paste:          return "Paste"
    case MenuCmd.Duplicate:      return "Duplicate"
    case MenuCmd.ToggleGrid:     return "Show Grid"
    case MenuCmd.ToggleGuides:   return "Show Guides"
    case MenuCmd.ModeCompact:    return "Compact Cards"
    case MenuCmd.ModeDetailed:   return "Detailed Cards"
    case MenuCmd.ModeColumns:    return "Column Layout"
    case MenuCmd.ThemeLight:     return "Light Theme"
    case MenuCmd.ThemeDark:      return "Dark Theme"
    case MenuCmd.ContextInspect: return "Inspect"
    case MenuCmd.ContextRename:  return "Rename"
    case MenuCmd.ContextPin:     return "Pin Item"
    case MenuCmd.ContextArchive: return "Archive"
    case MenuCmd.ContextDelete:  return "Delete"
    case MenuCmd.AlignLeft:      return "Align Left"
    case MenuCmd.AlignCenter:    return "Align Center"
    case MenuCmd.AlignRight:     return "Align Right"
    case MenuCmd.About:          return "About Menus"
    }

    return ""
}

// Fills the name and the state of a command of the menus, or answers false for any other.
func computeMenuCommandState(evt: *CommandStateEvent)->bool
{
    let name = menuCommandName(evt.id)
    if name.count == 0 do
        return false
    evt.name = name

    switch evt.id
    {
    case MenuCmd.SaveFile:
        evt.updatedFields |= .Disabled
        evt.disabled      = not g_DocumentDirty

    case MenuCmd.Undo:
        evt.updatedFields |= .Disabled
        evt.disabled      = not g_DocumentDirty

    case MenuCmd.Redo:
        evt.updatedFields |= .Disabled
        evt.disabled      = g_DocumentDirty

    case MenuCmd.ToggleGrid:
        evt.updatedFields |= .Checked
        evt.checked       = g_ShowGrid

    case MenuCmd.ToggleGuides:
        evt.updatedFields |= .Checked
        evt.checked       = g_ShowGuides

    case MenuCmd.ModeCompact:
        evt.updatedFields |= .Checked | .RenderingHint
        evt.renderingHint = .ExclusiveGroup
        evt.checked       = g_Mode == .Compact

    case MenuCmd.ModeDetailed:
        evt.updatedFields |= .Checked | .RenderingHint
        evt.renderingHint = .ExclusiveGroup
        evt.checked       = g_Mode == .Detailed

    case MenuCmd.ModeColumns:
        evt.updatedFields |= .Checked | .RenderingHint
        evt.renderingHint = .ExclusiveGroup
        evt.checked       = g_Mode == .Columns

    case MenuCmd.ThemeLight:
        evt.updatedFields |= .Checked | .RenderingHint
        evt.renderingHint = .ExclusiveGroup
        evt.checked       = app.usesLightTheme()

    case MenuCmd.ThemeDark:
        evt.updatedFields |= .Checked | .RenderingHint
        evt.renderingHint = .ExclusiveGroup
        evt.checked       = not app.usesLightTheme()

    case MenuCmd.ContextPin:
        evt.updatedFields |= .Checked
        evt.checked       = g_ContextPinned

    case MenuCmd.ContextDelete:
        evt.updatedFields |= .Disabled
        evt.disabled      = g_ContextPinned
    }

    return true
}

func getPagePanelLayout(parent: *Wnd)->PagePanelLayout
{
    let rect      = parent.clientRect()
    let width     = Math.max(rect.width, 1.0)
    let halfWidth = (width - SectionGap) * 0.5
    let bottomY   = TopHeight + SectionGap

    var result: #returntype
    result.left   = Math.Rectangle{0, 0, halfWidth, TopHeight}
    result.right  = Math.Rectangle{halfWidth + SectionGap, 0, width - halfWidth - SectionGap, TopHeight}
    result.bottom = Math.Rectangle{0, bottomY, width, Math.max(MinBottomHeight, rect.height - bottomY)}
    return result
}

const PageTitles = ["Menu Bar", "Context Menus", "Command State", "Anchored Popups"]

func pageSubtitle(page: s32)->string
{
    switch page
    {
    case 0: return "A menu bar with grouped rows, glyphs, shortcuts and nested popups."
    case 1: return "A reusable menu opened on a right click or from a button, with a submenu and a destructive row."
    case 2: return "Checked, exclusive and disabled rows, computed from the shared state each time a menu opens."
    case 3: return "Small menus that leave the button they belong to, above or below it."
    }

    unreachable
}

func clearPage()
{
    destroyPageMenus()
    g_StatusLabel = null
    g_Preview     = null
    for child in g_PageView!.children do
        child.destroy()
}

func buildPage()
{
    clearPage()
    g_SubTitle!.setText(pageSubtitle(g_Page))

    let pageView = unwrap g_PageView
    switch g_Page
    {
    case 0:  createMenuBarPage(pageView)
    case 1:  createContextMenuPage(pageView)
    case 2:  createCommandStatePage(pageView)
    case 3:  createAnchoredPopupPage(pageView)
    default: unreachable
    }

    updateStatusLabel()
    pageView.updateCommandState()
    pageView.invalidate()
}

func showPage(page: s32)
{
    g_Page = page
    let tabs = unwrap g_Tabs
    if tabs.selectedIndex != cast(u32, page) do
        tabs.setSelectedIndex(cast(u32, page))
    buildPage()
}

func nextPage()     => showPage((g_Page + 1) % MaxPages)
func previousPage() => showPage((g_Page + MaxPages - 1) % MaxPages)

// Places the header under the window strip, then the page under the tabs, keeping the foot clear
// for the hint line.
func layoutRootView()
{
    if not g_View or not g_PageView do
        return

    let view    = unwrap g_View
    let metrics = view.themeMetrics()
    let rect    = view.clientRect()
    let top     = view.stripInset()
    let width   = Math.max(rect.width - 2 * PageMargin, 1.0)

    let titleHeight = view.theme().createDefaultFont(TitleSize, .Bold).height
    g_Title!.setPosition(Math.Rectangle{PageMargin, top, width, titleHeight})
    g_SubTitle!.setPosition(Math.Rectangle{PageMargin, top + titleHeight + 4, width, 22})

    let tabsY = top + titleHeight + 4 + 22 + 16
    g_Tabs!.setPosition(Math.Rectangle{PageMargin, tabsY, width, metrics.tabBar_FlatHeight})

    let pageY  = tabsY + metrics.tabBar_FlatHeight + 24
    let bottom = rect.height - metrics.hintLine_Bottom - metrics.hintLine_Height - 16
    g_PageView!.setPosition(Math.Rectangle{PageMargin - SectionInset, pageY, width + 2 * SectionInset, Math.max(bottom - pageY, 1.0)})
}

// Answers the lens with the pages, the one shown checked.
func describePages(results: *Lens.Results)
{
    const Family = "Pages"
    let all = Lens.match(results.query, Family).matched
    var section: *Lens.Section?
    for title, index in PageTitles where all or Lens.match(results.query, title).matched
    {
        if not section do
            section = results.addSection(Family)
        with let entry = section.addEntry(title)
        {
            .checked = cast(s32, index) == g_Page
            .run     = func|index|() { showPage(cast(s32, index)) }
        }
    }
}

func onRootEvent(_: *Wnd, evt: IEvent)->bool
{
    switch evt
    {
    case ResizeEvent:
        layoutRootView()
        buildPage()

    case CommandStateEvent as state where state.kind == .Compute:
        switch state.id
        {
        case CmdNextPage:
            state.name = "Next Page"

        case CmdPreviousPage:
            state.name = "Previous Page"

        default:
            if not computeMenuCommandState(state) do
                return false
        }

        state.updatedFields.add(.Name)
        state.accepted = true
        return true

    case CommandEvent as cmd:
        switch cmd.id
        {
        case CmdLens:
            g_Lens!.open()

        case CmdNextPage:
            nextPage()

        case CmdPreviousPage:
            previousPage()

        default:
            if not processMenuCommand(cmd.id) do
                return false
        }

        cmd.accepted = true
        return true

    case DestroyEvent:
        destroyPageMenus()
        app.sigFrame.disable()
        g_Surface, g_View, g_Title, g_SubTitle, g_Tabs, g_PageView, g_Lens, g_Appearance, g_Hint, g_StatusLabel, g_Preview = null
    }

    return false
}

// Walks every page in Encre, then every page in Papier, and opens the lens once in each theme.
func updateTestMode()
{
    if not Env.isSmokeRun() or not g_Surface do
        return

    g_TestFrame += 1
    if g_Page == 0
    {
        if g_TestFrame == TestFramesPerPage / 3 do
            g_Lens!.open("pa")
        elif g_TestFrame == 2 * TestFramesPerPage / 3 do
            g_Lens!.close()
    }

    if g_TestFrame < TestFramesPerPage do
        return

    g_TestFrame = 0
    if g_Page + 1 < MaxPages
    {
        nextPage()
        return
    }

    if g_Light
    {
        Env.exit(0)
        return
    }

    g_Light = true
    g_Appearance!.setAppearanceTheme(.Light)
    showPage(0)
}

func onFrame(_: *Application)
{
    if not g_Surface or not g_View or not g_PageView do
        return

    updateTestMode()
}

func createRootView()
{
    let view = g_Surface!.view()
    g_View               = view
    view.backgroundStyle = .Window
    g_StatusText         = "No command chosen yet."

    with g_Title = Label.create(view, "Menus", {})
    {
        .setTextAlignment(.Left, .Center)
        .style.setFont(view.theme().createDefaultFont(TitleSize, .Bold), .Regular)
    }

    with g_SubTitle = Label.create(view, "", {}, null, .SecondaryText | .Ellipsis)
    {
        .setTextAlignment(.Left, .Center)
    }

    with g_Tabs = Tab.create(view, {})
    {
        .setForms(.Flat, .Flat, .None)
        for title in PageTitles do
            .addItem(title)
        .sigSelectionChanged += func(tab)
        {
            let index = cast(s32, cast(*Tab, tab).selectedIndex)
            if index != g_Page do
                showPage(index)
        }
    }

    with g_PageView = Wnd.create'Wnd(view, {})
    {
        .backgroundStyle = .Transparent
    }

    with g_Hint = HintLine.create(view)
    {
        .setReading(stateSummary())
        .addHint("Ctrl K", "pages, commands, appearance")
        .addHint("F1", "next page")
    }

    // The appearance is a lens entry like every other command; the button only owns the choice.
    with g_Appearance = AppearanceButton.create(unwrap g_Surface)
    {
        .hide()
        .setAppearanceTheme(g_Light ? .Light : .Dark)
    }

    with g_Lens = Lens.View.create(view)
    {
        .addSource(.None, &describePages)
        .addCommands("Go", [CmdNextPage, CmdPreviousPage])
        .addCommands("File", [MenuCmd.NewFile, MenuCmd.OpenFile, MenuCmd.SaveFile, MenuCmd.SaveAs, MenuCmd.Export, MenuCmd.Quit])
        .addCommands("Edit", [MenuCmd.Undo, MenuCmd.Redo, MenuCmd.Cut, MenuCmd.Copy, MenuCmd.Paste, MenuCmd.Duplicate])
        .addCommands("View", [MenuCmd.ToggleGrid, MenuCmd.ToggleGuides, MenuCmd.ModeCompact, MenuCmd.ModeDetailed, MenuCmd.ModeColumns])
        .addCommands("Item", [MenuCmd.ContextInspect, MenuCmd.ContextRename, MenuCmd.ContextPin, MenuCmd.ContextArchive, MenuCmd.ContextDelete,
                              MenuCmd.AlignLeft, MenuCmd.AlignCenter, MenuCmd.AlignRight, MenuCmd.About])
    }

    g_Appearance!.addToLens(unwrap g_Lens)

    view.registerKeyShortcut(.Control, .K, CmdLens)
    view.registerKeyShortcut(.None, .F1, CmdNextPage)
    view.registerKeyShortcut(.Shift, .F1, CmdPreviousPage)
    view.hookOnEvent = &onRootEvent
    layoutRootView()
}

// Reads the theme and the page the command line opens the window on.
func readStartupSelection()
{
    const PagePrefix = "--page="
    for arg in Env.arguments()
    {
        if arg == "--light"
        {
            g_Light = true
        }
        elif Utf8.startsWith(arg, PagePrefix)
        {
            let page = catch StrConv.toS32(arg[PagePrefix.count to])
            g_Page = Math.clamp(page - 1, 0, MaxPages - 1)
        }
    }
}

#main
{
    let surface = try app.createSurface(100, 60, W, H, SurfaceFlags.StandardWindow)
    g_Surface = surface
    surface.setTitle("GUI6 Menus")
    surface.minSize = {900, 720}

    readStartupSelection()
    createRootView()
    showPage(g_Page)

    app.sigFrame += &onFrame
    if Env.isSmokeRun() do
        app.maxRunFrame = cast(u32, 2 * MaxPages * TestFramesPerPage + 20)

    surface.show()
    app.run()
}
