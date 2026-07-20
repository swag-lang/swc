using Core, Gui, Pixel

const W = 1240
const H = 820
const MaxPages = 4
const TestFramesPerPage = 35
const RootMargin = 24.0
const PageTop = 112.0
const PageBottomMargin = 58.0
const ThemeButtonWidth = 152.0
const HeaderGap = 18.0

struct PageLayout
{
    full:   Math.Rectangle
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
var g_Page: s32
var g_TestFrame: s32
var g_DarkTheme: bool

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

func createPane(parent: *Wnd, title, text: string)->*FrameWnd
{
    let frame = Wnd.create'FrameWnd(parent, {})
    frame.setFrameForm(.Round)
    frame.setFrameFlags(.Zero, .Borders)

    let view = frame.createView'Wnd()
    discard createText(view, title, {12, 8, 220, 22})
    discard createHelpText(view, text, {12, 34, 220, 120})
    return frame
}

func refreshLayoutTree(wnd: *Wnd)
{
    if !wnd do
        return

    wnd.sendResizeEvent()
    wnd.applyLayout()
    for child in wnd.childs do
        refreshLayoutTree(child)
    wnd.invalidate()
}

func createChip(parent: *Wnd, text: string, icon: ThemeIcons24 = .Options)->*PushButton
{
    let btn = PushButton.create(parent, text, {0, 0, 118, 32})
    btn.form = .Flat
    btn.icon = app.theme.getIcon24(icon, 16)
    return btn
}

func getPageLayout(parent: *Wnd)->PageLayout
{
    let rect = parent.getClientRect()
    let gap = 20.0
    let bottomH = Math.max(190.0, rect.height * 0.32)
    let topH = Math.max(rect.height - bottomH - gap, 260.0)
    let halfW = (rect.width - gap) * 0.5

    var result: retval
    result.full = {0, 0, rect.width, rect.height}
    result.left = {0, 0, halfW, topH}
    result.right = {halfW + gap, 0, rect.width - halfW - gap, topH}
    result.bottom = {0, topH + gap, rect.width, rect.height - topH - gap}
    return result
}

func pageTitle(page: s32)->string
{
    switch page
    {
    case 0:
        return "Nested splitters"
    case 1:
        return "Stack layouts"
    case 2:
        return "Grid and wrap"
    case 3:
        return "Docking constraints"
    }

    unreachable
}

func pageSubtitle(page: s32)->string
{
    switch page
    {
    case 0:
        return "Resizable panes with nested horizontal and vertical splitters, minimum sizes and preserved side panels."
    case 1:
        return "Top, left, fitted and centered stacks arranging ordinary controls inside pane-sized regions."
    case 2:
        return "A spanning grid paired with a wrapping tile strip to show fixed cells and adaptive rows."
    case 3:
        return "Docking, margins, min/max sizes and anchors sharing the same parent rectangle."
    }

    unreachable
}

func updateHeader()
{
    g_Title.setText(Format.toString("GUI7 layout showcase - %", pageTitle(g_Page)))
    g_SubTitle.setText(pageSubtitle(g_Page))
    g_Footer.setText(Format.toString("F1 : next page (%/%). Resize the window or drag split bars.", g_Page + 1, MaxPages))
}

func updateThemeButton()
{
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

func clearPage()
{
    for child in g_PageView.childs do
        child.destroy()
}

func buildPage()
{
    clearPage()
    updateHeader()

    switch g_Page
    {
    case 0:
        createSplitterPage(g_PageView)
    case 1:
        createStackPage(g_PageView)
    case 2:
        createGridWrapPage(g_PageView)
    case 3:
        createConstraintsPage(g_PageView)
    default:
        unreachable
    }

    refreshLayoutTree(g_PageView)
    g_PageView.invalidate()
}

func layoutRootView()
{
    if !g_View or !g_PageView do
        return

    let rect = g_View.getClientRect()
    let contentWidth = Math.max(rect.width - 2 * RootMargin, 1.0)
    let pageHeight = Math.max(rect.height - PageTop - PageBottomMargin, 360.0)
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

func onFrame(app: #nonull *Application)
{
    if !g_Surface or !g_View or !g_PageView do
        return

    if app.keyb.isKeyJustPressed(.F1) do
        nextPage()

    updateTestMode()
}

func onRootEvent(_view: *Wnd, evt: IEvent)->bool
{
    if evt is ResizeEvent
    {
        layoutRootView()
        buildPage()
        return true
    }
    elif evt is DestroyEvent
    {
        app.sigFrame.disable()
        g_Surface     = null
        g_View        = null
        g_Title       = null
        g_SubTitle    = null
        g_ThemeButton = null
        g_PageView    = null
        g_Footer      = null
        return true
    }

    return false
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
    g_ThemeButton.icon = app.theme.getIcon24(.Picker, 18)
    g_ThemeButton.sigPressed += &toggleTheme

    g_PageView = Wnd.create'Wnd(g_View, {})
    g_PageView.backgroundStyle = .Transparent

    g_Footer = Label.create(g_View, "", {})
    setLabelTextStyle(g_Footer, .Left, .Center)
    g_Footer.labelFlags.add(.LightText)

    layoutRootView()
    g_View.hookOnEvent = &onRootEvent
}

#main
{
    let flags = SurfaceFlags.BigCaption | SurfaceFlags.MinimizeBtn | SurfaceFlags.CloseBtn | SurfaceFlags.Border | SurfaceFlags.Sizeable
    g_Surface = try app.createSurface(120, 90, W - 46, H - 31, flags)
    g_Surface.setTitle("GUI7 layout showcase")
    g_Surface.setIcon(app.theme.getIcon24(.Sort, 18))

    createRootView()
    buildPage()

    app.sigFrame += &onFrame
    if Env.hasArg("swag.test") do
        app.maxRunFrame = cast(u32) MaxPages * cast(u32) TestFramesPerPage + 10

    g_Surface.show()
    applyTheme()
    app.run()
}
