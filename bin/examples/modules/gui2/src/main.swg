using Core, Gui, Pixel

const W                    = 1080
const H                    = 810
const MaxPages             = 8
const TestFramesPerPage    = 35
const RootMargin           = 28.0
const PageTop              = 112.0
const PageBottomMargin     = 58.0
const PanelGap             = 28.0
const TopPanelHeight       = 300.0
const MinBottomPanelHeight = 236.0
const ThemeButtonWidth     = 150.0
const HeaderGap            = 18.0

struct PagePanelLayout
{
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
var g_Progress:    #null *ProgressBar
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
    let label = createText(parent, text, rect, .WordWrap)
    label.labelFlags.add(.LightText)
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
    discard createHelpText(view, subtitle, {16, 36, rect.width - 32, 42})
    return view
}

func createCaption(parent: *Wnd, text: string, x, y, width: f32)
{
    let label = createText(parent, text, {x, y, width, 24})
    label.labelFlags.add(.LightText)
}

func getPagePanelLayout(parent: *Wnd)->PagePanelLayout
{
    let rect         = parent.getClientRect()
    let width        = Math.max(rect.width, 1.0)
    let height       = Math.max(rect.height, TopPanelHeight + PanelGap + MinBottomPanelHeight)
    let halfWidth    = (width - PanelGap) * 0.5
    let topHeight    = Math.min(TopPanelHeight, Math.max(285.0, (height - PanelGap) * 0.52))
    let bottomY      = topHeight + PanelGap
    let bottomHeight = Math.max(MinBottomPanelHeight, height - bottomY)

    var result: retval
    result.left   = {0, 0, halfWidth, topHeight}
    result.right  = {halfWidth + PanelGap, 0, width - halfWidth - PanelGap, topHeight}
    result.bottom = {0, bottomY, width, bottomHeight}
    return result
}

func pageTitle(page: s32)->string
{
    switch page
    {
    case 0: return "PushButton"
    case 1: return "CheckButton"
    case 2: return "RadioButton"
    case 3: return "EditBox"
    case 4: return "Slider"
    case 5: return "ComboBox"
    case 6: return "Tab"
    case 7: return "ProgressBar"
    }

    unreachable
}

func pageSubtitle(page: s32)->string
{
    switch page
    {
    case 0: return "Forms, icons, disabled state and command feedback for push buttons."
    case 1: return "Unchecked, checked, tri-state, right-aligned and disabled check boxes."
    case 2: return "Radio button groups, right alignment and disabled selections."
    case 3: return "Text entry forms, notes, icons, numeric modes, clear button and read-only fields."
    case 4: return "Horizontal, range, stepped, vertical and disabled sliders."
    case 5: return "Select, editable, rich text, separators, constrained popups and disabled combos."
    case 6: return "Flat, round, button and push-button tab presentations with real child views."
    case 7: return "Finite, infinite, disabled and frame-driven progress indicators."
    }

    unreachable
}

func updateHeader()
{
    let title    = notnull g_Title
    let subTitle = notnull g_SubTitle
    let footer   = notnull g_Footer
    title.setText(Format.toString("GUI2 widget showcase - %", pageTitle(g_Page)))
    subTitle.setText(pageSubtitle(g_Page))
    footer.setText(Format.toString("F1 : next page (%/%). Pages : buttons, checks, radios, edits, sliders, combos, tabs, progress.", g_Page + 1, MaxPages))
}

func updateThemeButton()
{
    let btn = g_ThemeButton
    if !btn do
        return

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

func toggleTheme(btn: *Button)
{
    g_DarkTheme = !g_DarkTheme
    applyTheme()
}

func clearPage()
{
    g_Progress = null
    let pageView = notnull g_PageView
    for child in pageView.childs
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
    case 0:  createPushButtonPage(notnull g_PageView)
    case 1:  createCheckButtonPage(notnull g_PageView)
    case 2:  createRadioButtonPage(notnull g_PageView)
    case 3:  createEditBoxPage(notnull g_PageView)
    case 4:  createSliderPage(notnull g_PageView)
    case 5:  createComboBoxPage(notnull g_PageView)
    case 6:  createTabPage(notnull g_PageView)
    case 7:  createProgressBarPage(notnull g_PageView)
    default: unreachable
    }

    let pv = notnull g_PageView
    pv.invalidate()
}

func layoutRootView()
{
    if !g_View or !g_PageView do
        return

    let view     = notnull g_View
    let pageView = notnull g_PageView

    let rect         = view.getClientRect()
    let contentWidth = Math.max(rect.width - 2 * RootMargin, 1.0)
    let pageHeight   = Math.max(rect.height - PageTop - PageBottomMargin, TopPanelHeight + PanelGap + MinBottomPanelHeight)
    let footerY      = Math.max(rect.height - 42.0, PageTop + pageHeight + 6.0)

    let titleWidth = Math.max(contentWidth - ThemeButtonWidth - HeaderGap, 1.0)

    let title       = notnull g_Title
    let themeButton = notnull g_ThemeButton
    let subTitle    = notnull g_SubTitle
    let footer      = notnull g_Footer
    title.setPosition({RootMargin, 18, titleWidth, 34})
    themeButton.setPosition({RootMargin + titleWidth + HeaderGap, 18, ThemeButtonWidth, 34})
    subTitle.setPosition({RootMargin + 2, 56, contentWidth - 4, 42})
    pageView.setPosition({RootMargin, PageTop, contentWidth, pageHeight})
    footer.setPosition({RootMargin, footerY, contentWidth, 28})
}

func onRootEvent(view: *Wnd, evt: IEvent)->bool
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
        g_Progress    = null
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

    let view     = notnull g_View
    let pageView = notnull g_PageView

    let focus = view.getFocus()
    if !focus or focus == g_View do
        return true

    return !pageView.isParentOf(notnull focus)
}

func onFrame(app: *Application)
{
    if !g_Surface or !g_View or !g_PageView do
        return

    if app.keyb.isKeyJustPressed(.F1) do
        nextPage()

    let progress = g_Progress
    if progress
    {
        let value = progress.progression + app.getDt() * 0.35
        progress.setProgression(value > 1 ? 0 : value)
    }

    updateTestMode()
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
    themeButton.icon       = app.theme.getIcon24(ThemeIcons24.Picker, 18)
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
    let flags = SurfaceFlags.BigCaption | SurfaceFlags.MinimizeBtn | SurfaceFlags.CloseBtn | SurfaceFlags.Border
    let surface = notnull (try app.createSurface(100, 100, W - 46, H - 31, flags))
    g_Surface = surface
    surface.setTitle("GUI2 widget showcase")
    surface.setIcon(app.theme.getIcon24(ThemeIcons24.Options, 18))

    createRootView()
    buildPage()

    app.sigFrame += &onFrame
    if Env.hasArg("swag.test") do
        app.maxRunFrame = cast(u32) MaxPages * cast(u32) TestFramesPerPage + 10

    surface.show()
    applyTheme()
    app.run()
}
