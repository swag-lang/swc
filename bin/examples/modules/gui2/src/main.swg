using Core, Gui, Pixel

const W = 1080
const H = 720
const MaxPages = 8
const TestFramesPerPage = 35

var app: Application
var g_Surface: *Surface
var g_View: *Wnd
var g_Title: *Label
var g_SubTitle: *Label
var g_PageView: *Wnd
var g_Footer: *Label
var g_Page: s32
var g_TestFrame: s32
var g_Progress: *ProgressBar

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

func pageTitle(page: s32)->string
{
    switch page
    {
    case 0:
        return "PushButton"
    case 1:
        return "CheckButton"
    case 2:
        return "RadioButton"
    case 3:
        return "EditBox"
    case 4:
        return "Slider"
    case 5:
        return "ComboBox"
    case 6:
        return "Tab"
    case 7:
        return "ProgressBar"
    }

    unreachable
}

func pageSubtitle(page: s32)->string
{
    switch page
    {
    case 0:
        return "Forms, icons, disabled state and command feedback for push buttons."
    case 1:
        return "Unchecked, checked, tri-state, right-aligned and disabled check boxes."
    case 2:
        return "Radio button groups, right alignment and disabled selections."
    case 3:
        return "Text entry forms, notes, icons, numeric modes, clear button and read-only fields."
    case 4:
        return "Horizontal, range, stepped, vertical and disabled sliders."
    case 5:
        return "Select, editable, rich text, separators, constrained popups and disabled combos."
    case 6:
        return "Flat, round, button and push-button tab presentations with real child views."
    case 7:
        return "Finite, infinite, disabled and frame-driven progress indicators."
    }

    unreachable
}

func updateHeader()
{
    g_Title.setText(Format.toString("GUI2 widget showcase - %", pageTitle(g_Page)))
    g_SubTitle.setText(pageSubtitle(g_Page))
    g_Footer.setText(Format.toString("F1 : next page (%/%). Pages : buttons, checks, radios, edits, sliders, combos, tabs, progress.", g_Page + 1, MaxPages))
}

func clearPage()
{
    g_Progress = null
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
        createPushButtonPage(g_PageView)
    case 1:
        createCheckButtonPage(g_PageView)
    case 2:
        createRadioButtonPage(g_PageView)
    case 3:
        createEditBoxPage(g_PageView)
    case 4:
        createSliderPage(g_PageView)
    case 5:
        createComboBoxPage(g_PageView)
    case 6:
        createTabPage(g_PageView)
    case 7:
        createProgressBarPage(g_PageView)
    default:
        unreachable
    }

    g_PageView.invalidate()
}

func nextPage()
{
    g_Page = (g_Page + 1) % MaxPages
    buildPage()
}

func updateTestMode()
{
    if !Env.hasArg("swag.test") do
        return

    g_TestFrame += 1
    if g_TestFrame < TestFramesPerPage do
        return

    g_TestFrame = 0
    if g_Page + 1 >= MaxPages do
        Env.exit(0)

    nextPage()
}

func onFrame(app: *Application)
{
    if app.keyb.isKeyJustPressed(.F1) do
        nextPage()

    if g_Progress
    {
        let value = g_Progress.progression + app.getDt() * 0.35
        g_Progress.setProgression(value > 1 ? 0 : value)
    }

    updateTestMode()
}

func createRootView()
{
    g_View = g_Surface.getView()
    g_View.backgroundStyle = .View

    g_Title = Label.create(g_View, "", {28, 18, W - 56, 34})
    setLabelTextStyle(g_Title, .Left, .Center)
    g_Title.style.setFont(g_View.getTheme().createDefaultFont(28), .Regular)

    g_SubTitle = Label.create(g_View, "", {30, 56, W - 60, 42}, null, .WordWrap | .LightText)
    setLabelTextStyle(g_SubTitle, .Left, .Top)

    g_PageView = Wnd.create'Wnd(g_View, {28, 112, W - 56, H - 170})
    g_PageView.backgroundStyle = .Transparent

    g_Footer = Label.create(g_View, "", {28, H - 42, W - 56, 28})
    setLabelTextStyle(g_Footer, .Left, .Center)
    g_Footer.labelFlags.add(.LightText)
}

#main
{
    let flags = SurfaceFlags.BigCaption | SurfaceFlags.MinimizeBtn | SurfaceFlags.CloseBtn | SurfaceFlags.Border
    g_Surface = try app.createSurface(100, 100, W, H, flags)
    g_Surface.setTitle("GUI2 widget showcase")
    g_Surface.setIcon(app.theme.getIcon24(ThemeIcons24.Options, 18))

    createRootView()
    buildPage()

    app.sigFrame += &onFrame
    if Env.hasArg("swag.test") do
        app.maxRunFrame = cast(u32) MaxPages * cast(u32) TestFramesPerPage + 10

    g_Surface.show()
    app.theme.colors.setLight()
    app.themeHasChanged()
    app.run()
}
