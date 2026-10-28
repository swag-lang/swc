// GUI7 - layout.
//
// Splitters, stacks, grids, wrapping and docking, each on a page of its own. The regions a layout
// arranges stand on the raised ground, so the arrangement reads without a frame around every
// pane. The pages are text tabs under the title; `Ctrl K` opens the lens, which reaches every page
// and the appearance. Resize the window or drag a splitter to watch the layouts answer.
// `--light` opens the window on Papier, `--page=N` on page N.

using Core, Gui, Pixel

const W        = 1100
const H        = 820
const MaxPages = 4
const TestFramesPerPage = 35

// The page keeps reading margins at its sides, and each section keeps one inset for its label, its
// sentence and its controls, so the section labels stand on the left edge of the title.
const PageMargin      = 48.0
const SectionInset    = 24.0
const SectionGap      = 24.0
const TitleSize       = 34'u32
const TopHeight       = 260.0
const MinBottomHeight = 190.0

const CmdLens         = "gui7.lens"
const CmdNextPage     = "gui7.page.next"
const CmdPreviousPage = "gui7.page.previous"

struct PageLayout
{
    full:   Math.Rectangle
    left:   Math.Rectangle
    right:  Math.Rectangle
    bottom: Math.Rectangle
}

var app:          Application
var g_Surface:    *Surface?
var g_View:       *Wnd?
var g_Title:      *Label?
var g_SubTitle:   *Label?
var g_Tabs:       *Tab?
var g_PageView:   *Wnd?
var g_Lens:       *Lens.View?
var g_Appearance: *AppearanceButton?
var g_Page:       s32
var g_TestFrame:  s32
var g_Light:      bool

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

// Lays the raised ground under a region a layout arranges, on the control corner, so the
// arrangement reads without a frame around each region.
func raiseRegion(wnd: *Wnd)
{
    wnd.backgroundStyle = .Transparent
    wnd.hookOnEvent     = &onRaisedEvent
}

func onRaisedEvent(wnd: *Wnd, evt: IEvent)->bool
{
    if evt is PaintEvent as paint where paint.kind == .Content
    {
        let corner = wnd.themeMetrics().corner_Control
        paint.paintContext.painter.fillRoundRect(wnd.clientRect(), corner, corner, wnd.themeColors().raised)
    }

    return false
}

// Creates a region a layout arranges: the raised ground, its name and a sentence about it.
func createPane(parent: *Wnd, title, text: string)->*Wnd
{
    let pane = Wnd.create'Wnd(parent, {})
    raiseRegion(pane)
    discard createText(pane, title, {16, 12, 220, 22})
    discard createHelpText(pane, text, {16, 38, 220, 120})
    return pane
}

func refreshLayoutTree(wnd: *Wnd)
{
    wnd.sendResizeEvent()
    wnd.applyLayout()
    for child in wnd.children do
        refreshLayoutTree(child)
    wnd.invalidate()
}

func createChip(parent: *Wnd, text: string, icon: ThemeIcons = .Options)->*PushButton
{
    let btn = PushButton.create(parent, text, {0, 0, 118, 32})
    btn.setForm(.Flat)
    btn.setIcon(app.theme.icon(icon, 16))
    return btn
}

func getPageLayout(parent: *Wnd)->PageLayout
{
    let rect    = parent.clientRect()
    let bottomH = Math.max(MinBottomHeight, rect.height * 0.32)
    let topH    = Math.max(rect.height - bottomH - SectionGap, TopHeight)
    let halfW   = (rect.width - SectionGap) * 0.5

    var result: #returntype
    result.full   = Math.Rectangle{0, 0, rect.width, rect.height}
    result.left   = Math.Rectangle{0, 0, halfW, topH}
    result.right  = Math.Rectangle{halfW + SectionGap, 0, rect.width - halfW - SectionGap, topH}
    result.bottom = Math.Rectangle{0, topH + SectionGap, rect.width, rect.height - topH - SectionGap}
    return result
}

const PageTitles = ["Splitters", "Stacks", "Grid and Wrap", "Docking"]

func pageSubtitle(page: s32)->string
{
    switch page
    {
    case 0: return "Nested horizontal and vertical splitters, with minimum sizes and side panes that keep their width."
    case 1: return "Top, fitted and centred stacks arranging ordinary controls."
    case 2: return "A grid whose cells span rows and columns, beside tiles that wrap as the room narrows."
    case 3: return "Docking, margins, minimum and maximum sizes, and anchors sharing one parent rectangle."
    }

    unreachable
}

func clearPage()
{
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
    case 0:  createSplitterPage(pageView)
    case 1:  createStackPage(pageView)
    case 2:  createGridWrapPage(pageView)
    case 3:  createConstraintsPage(pageView)
    default: unreachable
    }

    refreshLayoutTree(pageView)
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
        case CmdNextPage:     state.name = "Next Page"
        case CmdPreviousPage: state.name = "Previous Page"
        default: return false
        }

        state.updatedFields.add(.Name)
        state.accepted = true
        return true

    case CommandEvent as cmd:
        switch cmd.id
        {
        case CmdLens:         g_Lens!.open()
        case CmdNextPage:     nextPage()
        case CmdPreviousPage: previousPage()
        default:              return false
        }

        cmd.accepted = true
        return true

    case DestroyEvent:
        app.sigFrame.disable()
        g_Surface, g_View, g_Title, g_SubTitle, g_Tabs, g_PageView, g_Lens, g_Appearance = null
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
    g_View = view
    view.backgroundStyle = .Window

    with g_Title = Label.create(view, "Layout", {})
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

    with let hint = HintLine.create(view)
    {
        .addHint("Ctrl K", "pages, appearance")
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
    surface.setTitle("GUI7 Layout")
    surface.minSize = {900, 680}

    readStartupSelection()
    createRootView()
    showPage(g_Page)

    app.sigFrame += &onFrame
    if Env.isSmokeRun() do
        app.maxRunFrame = cast(u32, 2 * MaxPages * TestFramesPerPage + 20)

    surface.show()
    app.run()
}
