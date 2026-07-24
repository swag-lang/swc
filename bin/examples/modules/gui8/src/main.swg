using Core, Gui, Pixel

const W                 = 1240
const H                 = 820
const MaxPages          = 4
const TestFramesPerPage = 35
const RootMargin        = 24.0
const PageTop           = 112.0
const PageBottomMargin  = 58.0
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

func sampleIcon(index: s32, size = 16'f32)->Icon
{
    switch index % 8
    {
    case 0:  return app.theme.getIcon24(.Search, size)
    case 1:  return app.theme.getIcon24(.OpenFile, size)
    case 2:  return app.theme.getIcon24(.Edit, size)
    case 3:  return app.theme.getIcon24(.Filter, size)
    case 4:  return app.theme.getIcon24(.Options, size)
    case 5:  return app.theme.getIcon24(.Download, size)
    case 6:  return app.theme.getIcon24(.Link, size)
    default: return app.theme.getIcon24(.Sort, size)
    }
}

func addListFlags(list: *ListCtrl)
{
    list.listFlags.add(.AlternateLines)
    list.listFlags.add(.HorzLines)
    list.listFlags.add(.VertLines)
}

func getPageLayout(parent: *Wnd)->PageLayout
{
    let rect = parent.getClientRect()
    let gap = 20.0
    let bottomH = Math.max(190.0, rect.height * 0.31)
    let topH = Math.max(rect.height - bottomH - gap, 260.0)
    let halfW = (rect.width - gap) * 0.5

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
    case 0: return "Lists"
    case 1: return "Columns"
    case 2: return "Trees"
    case 3: return "Headers"
    }

    unreachable
}

func pageSubtitle(page: s32)->string
{
    switch page
    {
    case 0: return "Simple, checkable and virtual ListCtrl configurations with selection and scrolling."
    case 1: return "Multi-column ListCtrl pages with clickable headers, icons, sorted columns and grid lines."
    case 2: return "Tree-shaped ListCtrl data with expanded branches, nested rows and multi-column metadata."
    case 3: return "Standalone Header controls with sizing constraints, sort marks and matching list headers."
    }

    unreachable
}

func updateHeader()
{
    let title    = notnull g_Title
    let subTitle = notnull g_SubTitle
    let footer   = notnull g_Footer
    title.setText(Format.toString("GUI8 list showcase - %", pageTitle(g_Page)))
    subTitle.setText(pageSubtitle(g_Page))
    footer.setText(Format.toString("F1 : next page (%/%). Resize the window to stress list and header layout.", g_Page + 1, MaxPages))
}

func updateThemeButton()
{
    let btn = notnull g_ThemeButton
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
    app.themeHasChanged()
}

func toggleTheme(_btn: *Button)
{
    g_DarkTheme = !g_DarkTheme
    applyTheme()
}

func clearPage()
{
    let pageView0 = notnull g_PageView
    for child in pageView0.childs
    {
        let c = notnull child
        c.destroy()
    }
}

func buildPage()
{
    clearPage()
    updateHeader()

    switch g_Page
    {
    case 0:  createListsPage(notnull g_PageView)
    case 1:  createColumnsPage(notnull g_PageView)
    case 2:  createTreesPage(notnull g_PageView)
    case 3:  createHeadersPage(notnull g_PageView)
    default: unreachable
    }

    refreshLayoutTree(notnull g_PageView)
    let pv = notnull g_PageView
    pv.invalidate()
}

func layoutRootView()
{
    if !g_View or !g_PageView do
        return

    let view     = notnull g_View
    let pageView = notnull g_PageView

    let rect = view.getClientRect()
    let contentWidth = Math.max(rect.width - 2 * RootMargin, 1.0)
    let pageHeight = Math.max(rect.height - PageTop - PageBottomMargin, 360.0)
    let footerY = Math.max(rect.height - 42.0, PageTop + pageHeight + 6.0)
    let titleWidth = Math.max(contentWidth - ThemeButtonWidth - HeaderGap, 1.0)

    let title2      = notnull g_Title
    let themeButton = notnull g_ThemeButton
    let subTitle2   = notnull g_SubTitle
    let footer2     = notnull g_Footer
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

    let view2     = notnull g_View
    let pageView2 = notnull g_PageView

    let focus = view2.getFocus()
    if !focus or focus == g_View do
        return true

    return !pageView2.isParentOf(notnull focus)
}

func onFrame(app: *Application)
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
    let view = (notnull g_Surface).getView()
    g_View               = view
    view.backgroundStyle = .View

    let title = Label.create(view, "", {})
    g_Title = title
    setLabelTextStyle(title, .Left, .Center)
    title.style.setFont(view.getTheme().createDefaultFont(28), .Regular)

    let subTitle = Label.create(view, "", {}, null, .WordWrap | .LightText)
    g_SubTitle = subTitle
    setLabelTextStyle(subTitle, .Left, .Top)

    let themeButton = PushButton.create(view, "", {})
    g_ThemeButton          = themeButton
    themeButton.form       = .Flat
    themeButton.icon       = app.theme.getIcon24(.Picker, 18)
    themeButton.sigPressed += &toggleTheme

    let pageView = Wnd.create'Wnd(view, {})
    g_PageView               = pageView
    pageView.backgroundStyle = .Transparent

    let footer = Label.create(view, "", {})
    g_Footer = footer
    setLabelTextStyle(footer, .Left, .Center)
    footer.labelFlags.add(.LightText)

    layoutRootView()
    view.hookOnEvent = &onRootEvent
}

#main
{
    let flags = SurfaceFlags.BigCaption | SurfaceFlags.MinimizeBtn | SurfaceFlags.CloseBtn | SurfaceFlags.Border | SurfaceFlags.Sizeable
    let surface = notnull (try app.createSurface(120, 90, W - 46, H - 31, flags))
    g_Surface = surface
    surface.setTitle("GUI8 list showcase")
    surface.setIcon(app.theme.getIcon24(.Sort, 18))

    createRootView()
    buildPage()

    app.sigFrame += &onFrame
    if Env.hasArg("swag.test") do
        app.maxRunFrame = cast(u32) MaxPages * cast(u32) TestFramesPerPage + 10

    surface.show()
    applyTheme()
    app.run()
}
