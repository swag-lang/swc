using Core, Gui, Pixel

const W                 = 1080
const H                 = 750
const MaxPages          = 4
const TestFramesPerPage = 35
const RootMargin        = 24.0
const PageTop           = 92.0
const PageBottomMargin  = 44.0
const ThemeButtonWidth  = 152.0
const HeaderGap         = 18.0

struct PageLayout
{
    full:   Math.Rectangle
    left:   Math.Rectangle
    right:  Math.Rectangle
    bottom: Math.Rectangle
}

var app:           Application
var g_Surface:     #null *Surface
var g_View:        #null *Wnd
var g_Title:       #null *Label
var g_SubTitle:    #null *Label
var g_ThemeButton: #null *PushButton
var g_PageView:    #null *Wnd
var g_Footer:      #null *Label
var g_Page:        s32
var g_TestFrame:   s32
var g_DarkTheme:   bool

func setLabelTextStyle(label: *Label, horizontal = StringHorzAlignment.Left, vertical = StringVertAlignment.Center)
{
    label.setTextAlignment(horizontal, vertical)
}

func createText(parent: *Wnd, text: string, rect: Math.Rectangle, flags = LabelFlags.None)->*Label
{
    let label = Label.create(parent, text, rect, null, flags)
    setLabelTextStyle(label, .Left, .Center)
    return label
}

func createHelpText(parent: *Wnd, text: string, rect: Math.Rectangle)->*Label
{
    let label = createText(parent, text, rect, .WordWrap | .SecondaryText)
    label.setTextVerticalAlignment(.Top)
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
    frame.setFrameFlags(.None, .Borders)

    let view = frame.createView'Wnd()
    discard createText(view, title, {12, 8, 220, 22})
    discard createHelpText(view, text, {12, 34, 220, 120})
    return frame
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
    let gap     = 20.0
    let bottomH = Math.max(190.0, rect.height * 0.32)
    let topH    = Math.max(rect.height - bottomH - gap, 260.0)
    let halfW   = (rect.width - gap) * 0.5

    var result: retval
    result.full   = {0, 0, rect.width, rect.height}
    result.left   = {0, 0, halfW, topH}
    result.right  = {halfW + gap, 0, rect.width - halfW - gap, topH}
    result.bottom = {0, topH + gap, rect.width, rect.height - topH - gap}
    return result
}

func pageTitle(page: s32)->string
{
    switch page
    {
    case 0: return "Nested splitters"
    case 1: return "Stack layouts"
    case 2: return "Grid and wrap"
    case 3: return "Docking constraints"
    }

    unreachable
}

func pageSubtitle(page: s32)->string
{
    switch page
    {
    case 0: return "Resizable panes with nested horizontal and vertical splitters, minimum sizes and preserved side panels."
    case 1: return "Top, left, fitted and centered stacks arranging ordinary controls inside pane-sized regions."
    case 2: return "A spanning grid paired with a wrapping tile strip to show fixed cells and adaptive rows."
    case 3: return "Docking, margins, min/max sizes and anchors sharing the same parent rectangle."
    }

    unreachable
}

func updateHeader()
{
    let title    = g_Title!
    let subTitle = g_SubTitle!
    let footer   = g_Footer!
    title.setText(Format.toString("GUI7 layout showcase - %", pageTitle(g_Page)))
    subTitle.setText(pageSubtitle(g_Page))
    footer.setText(Format.toString("F1 : next page (%/%). Resize the window or drag split bars.", g_Page + 1, MaxPages))
}

func updateThemeButton()
{
    let btn = g_ThemeButton!
    if g_DarkTheme do
        btn.name = "White theme"
    else do
        btn.name = "Black theme"
    btn.invalidate()
}

func applyTheme()
{
    if g_DarkTheme do
        app.theme.colors.setDark()
    else do
        app.theme.colors.setLight()

    updateThemeButton()
    app.notifyThemeChanged()
}

func toggleTheme(_btn: *Button)
{
    g_DarkTheme = !g_DarkTheme
    applyTheme()
}

func clearPage()
{
    let pageView0 = g_PageView!
    for child in pageView0.children
    {
        let c = child!
        c.destroy()
    }
}

func buildPage()
{
    clearPage()
    updateHeader()

    switch g_Page
    {
    case 0:  createSplitterPage(g_PageView!)
    case 1:  createStackPage(g_PageView!)
    case 2:  createGridWrapPage(g_PageView!)
    case 3:  createConstraintsPage(g_PageView!)
    default: unreachable
    }

    refreshLayoutTree(g_PageView!)
    let pv = g_PageView!
    pv.invalidate()
}

func layoutRootView()
{
    if !g_View or !g_PageView do
        return

    let view     = g_View!
    let pageView = g_PageView!

    let rect         = view.clientRect()
    let contentWidth = Math.max(rect.width - 2 * RootMargin, 1.0)
    let pageHeight   = Math.max(rect.height - PageTop - PageBottomMargin, 360.0)
    let footerY      = Math.max(rect.height - 42.0, PageTop + pageHeight + 6.0)
    let titleWidth   = Math.max(contentWidth - ThemeButtonWidth - HeaderGap, 1.0)

    let title2      = g_Title!
    let themeButton = g_ThemeButton!
    let subTitle2   = g_SubTitle!
    let footer2     = g_Footer!
    title2.setPosition({RootMargin, 18, titleWidth, 34})
    themeButton.setPosition({RootMargin + titleWidth + HeaderGap, 18, ThemeButtonWidth, 34})
    subTitle2.setPosition({RootMargin + 2, 56, contentWidth - 4, 42})
    pageView.setPosition({RootMargin, PageTop, contentWidth, pageHeight})
    footer2.setPosition({RootMargin, footerY, contentWidth, 28})
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
    if !Env.isSmokeRun() or !g_Surface do
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

    let view2     = g_View!
    let pageView2 = g_PageView!

    let focus = view2.focusedWindow()
    if !focus or focus == g_View do
        return true

    return !pageView2.isAncestorOf(focus!)
}

func onFrame(app: *Application)
{
    if !g_Surface or !g_View or !g_PageView do
        return

    if app.keyboard.isKeyJustPressed(.F1) do
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
    let view = g_Surface!.view()
    g_View               = view
    view.backgroundStyle = .View

    let title = Label.create(view, "", {})
    g_Title = title
    setLabelTextStyle(title, .Left, .Center)
    title.style.setFont(view.theme().createDefaultFont(28), .Regular)

    let subTitle = Label.create(view, "", {}, null, .WordWrap | .SecondaryText)
    g_SubTitle = subTitle
    setLabelTextStyle(subTitle, .Left, .Top)

    let themeButton = PushButton.create(view, "", {})
    g_ThemeButton = themeButton
    themeButton.setForm(.Flat)
    themeButton.setIcon(app.theme.icon(.Picker, 18))
    themeButton.sigPressed += &toggleTheme

    let pageView = Wnd.create'Wnd(view, {})
    g_PageView               = pageView
    pageView.backgroundStyle = .Transparent

    let footer = Label.create(view, "", {})
    g_Footer = footer
    setLabelTextStyle(footer, .Left, .Center)
    footer.updateFlags(.SecondaryText)

    layoutRootView()
    view.hookOnEvent = &onRootEvent
}

#main
{
    let flags   = SurfaceFlags.LargeCaption | SurfaceFlags.MinimizeButton | SurfaceFlags.CloseButton | SurfaceFlags.Border | SurfaceFlags.Resizable
    let surface = (try app.createSurface(120, 90, W - 46, H - 31, flags))!
    g_Surface = surface
    surface.setTitle("GUI7 layout showcase")
    surface.setIcon(app.theme.icon(.Sort, 18))

    createRootView()
    buildPage()

    app.sigFrame += &onFrame
    if Env.isSmokeRun() do
        app.maxRunFrame = cast(u32) MaxPages * cast(u32) TestFramesPerPage + 10

    surface.show()
    applyTheme()
    app.run()
}
