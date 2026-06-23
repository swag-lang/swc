using Core, Gui, Pixel

const W = 1320
const H = 860
const MaxPages = 4
const TestFramesPerPage = 40
const RootMargin = 24.0
const PageTop = 116.0
const PageBottomMargin = 58.0
const PanelGap = 24.0
const TopPanelHeight = 300.0
const MinBottomPanelHeight = 230.0
const ThemeButtonWidth = 152.0
const HeaderGap = 18.0

const SourcePageLexer = #include("page.lexer.swg")
const SourcePageStyles = #include("page.styles.swg")
const SourcePageModes = #include("page.modes.swg")
const SourcePageWorkspace = #include("page.workspace.swg")

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
var g_Page: s32
var g_TestFrame: s32
var g_DarkTheme: bool
var g_LexerSwag: RichEditLexerSwag

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
    let label = createText(parent, text, rect, .WordWrap)
    label.labelFlags.add(.LightText)
    label.vertAlignmentText = .Top
    return label
}

func createCaption(parent: *Wnd, text: string, x, y, width: f32)
{
    let label = createText(parent, text, {x, y, width, 24})
    label.labelFlags.add(.LightText)
}

func createPanel(parent: *Wnd, title, subtitle: string, rect: Math.Rectangle)->*Wnd
{
    let frame = Wnd.create'FrameWnd(parent, rect)
    frame.setFrameForm(.Round)
    frame.setFrameFlags(.Borders)

    let view = frame.createView'Wnd()
    discard createText(view, title, {16, 10, rect.width - 32, 24})
    discard createHelpText(view, subtitle, {16, 36, rect.width - 32, 42})
    return view
}

func getPagePanelLayout(parent: *Wnd)->PagePanelLayout
{
    let rect         = parent.getClientRect()
    let width        = Math.max(rect.width, 1.0)
    let height       = Math.max(rect.height, TopPanelHeight + PanelGap + MinBottomPanelHeight)
    let halfWidth    = (width - PanelGap) * 0.5
    let topHeight    = Math.min(TopPanelHeight, Math.max(250.0, (height - PanelGap) * 0.5))
    let bottomY      = topHeight + PanelGap
    let bottomHeight = Math.max(MinBottomPanelHeight, height - bottomY)

    var result: retval
    result.left   = {0, 0, halfWidth, topHeight}
    result.right  = {halfWidth + PanelGap, 0, width - halfWidth - PanelGap, topHeight}
    result.bottom = {0, bottomY, width, bottomHeight}
    return result
}

func getFullPageRect(parent: *Wnd)->Math.Rectangle
{
    let rect = parent.getClientRect()
    return {0, 0, Math.max(rect.width, 1.0), Math.max(rect.height, 1.0)}
}

func pageTitle(page: s32)->string
{
    switch page
    {
    case 0:
        return "Lexer"
    case 1:
        return "Styles"
    case 2:
        return "Modes"
    case 3:
        return "Workspace"
    }

    unreachable
}

func pageSubtitle(page: s32)->string
{
    switch page
    {
    case 0:
        return "Swag highlighting, margins, wrapping and visible blanks in large editors."
    case 1:
        return "Manual rich spans, inline emphasis and log-like styling without leaving the control."
    case 2:
        return "RichEditCtrl versus Edit form, read-only states and mixed flag combinations."
    case 3:
        return "A richer composition inspired by the wnd sample: split panes, notes and code side by side."
    }

    unreachable
}

func updateHeader()
{
    g_Title.setText(Format.toString("GUI3 rich edit showcase - %", pageTitle(g_Page)))
    g_SubTitle.setText(pageSubtitle(g_Page))
    g_Footer.setText(Format.toString("F1/right/down : next, left/up : previous (%/%). Pages : lexer, styles, modes, workspace.", g_Page + 1, MaxPages))
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

func createDemoEditor(parent: *Wnd, rect: Math.Rectangle, flags: RichEditFlags, form = RichEditForm.RichEditCtrl)->*RichEditCtrl
{
    let ed = RichEditCtrl.create(parent, rect)
    ed.setFrameForm(.Round)
    ed.setFrameFlags(.FocusBorder)
    ed.setForm(form)
    ed.setRichEdFlags(flags)
    return ed
}

func createCodeEditor(parent: *Wnd, rect: Math.Rectangle, text: string, flags = RichEditFlags.ShowFocusSel | .CurLineBorder | .TabToSpaces)->*RichEditCtrl
{
    let ed = createDemoEditor(parent, rect, flags)
    ed.setLexer(cast(IRichEditLexer) g_LexerSwag)
    ed.marginLeft  = 18
    ed.marginRight = 24
    ed.setText(text)
    return ed
}

func createDocumentEditor(parent: *Wnd, rect: Math.Rectangle, text: string, flags = RichEditFlags.ShowFocusSel | .WordWrap, form = RichEditForm.Edit)->*RichEditCtrl
{
    let ed = createDemoEditor(parent, rect, flags, form)
    ed.marginLeft  = 18
    ed.marginRight = 18
    ed.lineSpacing = 1
    ed.setText(text)
    return ed
}

func clearPage()
{
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
        createLexerPage(g_PageView)
    case 1:
        createStylesPage(g_PageView)
    case 2:
        createModesPage(g_PageView)
    case 3:
        createWorkspacePage(g_PageView)
    default:
        unreachable
    }

    g_PageView.invalidate()
}

func layoutRootView()
{
    if !g_View or !g_PageView do
        return

    let rect         = g_View.getClientRect()
    let contentWidth = Math.max(rect.width - 2 * RootMargin, 1.0)
    let pageHeight   = Math.max(rect.height - PageTop - PageBottomMargin, TopPanelHeight + PanelGap + MinBottomPanelHeight)
    let footerY      = Math.max(rect.height - 42.0, PageTop + pageHeight + 6.0)
    let titleWidth   = Math.max(contentWidth - ThemeButtonWidth - HeaderGap, 1.0)

    g_Title.setPosition({RootMargin, 18, titleWidth, 34})
    g_ThemeButton.setPosition({RootMargin + titleWidth + HeaderGap, 18, ThemeButtonWidth, 34})
    g_SubTitle.setPosition({RootMargin + 2, 56, contentWidth - 4, 42})
    g_PageView.setPosition({RootMargin, PageTop, contentWidth, pageHeight})
    g_Footer.setPosition({RootMargin, footerY, contentWidth, 28})
}

func onRootEvent(_view: *Wnd, evt: IEvent)->bool
{
    if evt is ResizeEvent
    {
        layoutRootView()
        buildPage()
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
    }

    return false
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

    layoutRootView()
    g_View.hookOnEvent = &onRootEvent
}

#main
{
    let flags = SurfaceFlags.BigCaption | SurfaceFlags.MinimizeBtn | SurfaceFlags.CloseBtn | SurfaceFlags.Border
    g_Surface = try app.createSurface(100, 100, W - 46, H - 31, flags)
    g_Surface.setTitle("GUI3 rich edit showcase")
    g_Surface.setIcon(app.theme.getIcon24(ThemeIcons24.Edit, 18))

    createRootView()
    buildPage()

    app.sigFrame += &onFrame
    if Env.hasArg("swag.test") do
        app.maxRunFrame = cast(u32) MaxPages * cast(u32) TestFramesPerPage + 10

    g_Surface.show()
    applyTheme()
    app.run()
}
