// GUI10 - the theme inspector.
//
// The other GUI examples show what the toolkit can build; this one shows what the
// toolkit is built out of. Every value of `ThemeColors` and `ThemeMetrics` is listed by
// reflection, so the sheets can never fall behind the struct, and the palettes are put
// side by side because the defect a theme actually ships is almost never a wrong color:
// it is a color one palette forgot to answer.

using Core, Gui, Pixel

const W = 1280
const H = 860

const MaxPages          = 4
const TestFramesPerPage = 30

const RootMargin       = 24.0
const HeaderHeight     = 96.0
const BarHeight        = 34.0
const BarGap           = 10.0
const PageBottomMargin = 46.0
const FilterWidth      = 260.0
const RingsWidth       = 130.0

var app:        Application
var g_Surface:  #null *Surface
var g_View:     #null *Wnd
var g_Title:    #null *Label
var g_SubTitle: #null *Label
var g_Footer:   #null *Label
var g_Filter:   #null *EditBox
var g_Rings:    #null *CheckButton
var g_Sheet:    #null *SheetWnd
var g_Widgets:  #null *WidgetWall

var g_ThemeButtons: Array'(*PushButton)
var g_PageButtons:  Array'(*PushButton)

var g_Variant:   ThemeVariant
var g_Page:      s32
var g_TestFrame: s32

// The three palettes the toolkit ships, followed by the sheet-written example.
//
// A variant is a whole theme, not only its colors: `Theme.setDark` and friends also
// answer for the geometry, which is why the inspector applies them through the theme
// rather than through `theme.colors`.
enum ThemeVariant
{
    Dark
    Light
    SwagDark
    Sheet
}

const ThemeVariantCount = 4

// A theme written as a tweak sheet rather than in code, which is how anyone shipping an
// application writes one. Reading it beside the palettes above is the point of having it
// here: the same thirty-five tokens, the same three hundred parts derived from them, and
// nothing in the toolkit that knows the difference.
const SheetTheme = #include("sepia.tweak")

func variantName(variant: ThemeVariant)->string
{
    switch #complete variant
    {
    case .Dark:     return "Dark"
    case .Light:    return "Light"
    case .SwagDark: return "Swag Dark"
    case .Sheet:    return "Sheet"
    }

    unreachable
}

// Applies `variant` to `theme`, colors and geometry both.
func applyVariant(theme: *Theme, variant: ThemeVariant)
{
    switch #complete variant
    {
    case .Dark:
        theme.setDark()

    case .Light:
        theme.setLight()

    case .SwagDark:
        theme.setSwagDark()

    case .Sheet:

        // A sheet is a delta, so the theme is put back on a known palette before the sheet
        // is read: applied twice in a row, a partial sheet would otherwise compound.
        theme.setLight()
        expect theme.applySheet(cast(string) SheetTheme)
    }
}

// Returns the colors of `variant` without touching the theme on screen.
//
// The sheets that compare palettes need all variants at once, and a palette is a plain
// value, so each one is simply built on the spot.
func variantColors(variant: ThemeVariant)->ThemeColors
{
    var result: retval
    switch #complete variant
    {
    case .Dark:
        result.setDark()

    case .Light:
        result.setLight()

    case .SwagDark:
        result.setSwagDark()

    case .Sheet:
        var theme: Theme
        theme.setLight()
        expect theme.applySheet(cast(string) SheetTheme)
        result = theme.colors
    }

    return result
}

func pageTitle(page: s32)->string
{
    switch page
    {
    case 0: return "Colors"
    case 1: return "Palettes"
    case 2: return "Metrics"
    case 3: return "Widgets"
    }

    unreachable
}

// The command-line name of each palette and each page, in the order of the two enumerations.
const VariantArgs: [ThemeVariantCount] string = ["--dark", "--light", "--swagdark", "--sheet"]
const PageArgs:    [MaxPages] string          = ["--colors", "--palettes", "--metrics", "--widgets"]

// Reads the palette and the page the command line asks the inspector to open on.
//
// Judging a theme means looking at one page of one variant, and there are sixteen such pairs.
// Reached by hand that is sixteen windows to drive by pointer; named on the command line it is
// sixteen launches a script can take a picture of, which is how a change to `apply` is compared
// against the palettes it did not mean to touch.
func readStartupSelection()
{
    for arg in Env.arguments()
    {
        for name, i in VariantArgs where arg == name do
            g_Variant = cast(ThemeVariant) cast(s32) i
        for name, i in PageArgs where arg == name do
            g_Page = cast(s32) i
    }
}

func pageSubtitle(page: s32)->string
{
    switch page
    {
    case 0: return "Every ThemeColors value of the active palette, over the grounds it is drawn on. Alpha shows against the checkerboard."
    case 1: return "The same value across every shipped palette, with the sheet-written example beside them."
    case 2: return "Every ThemeMetrics value of the active theme, in logical pixels."
    case 3: return "Live widgets in every state the palette answers for. Hover and press them to read the hot and pressed colors."
    }

    unreachable
}

func sheetKindOfPage(page: s32)->SheetKind
{
    switch page
    {
    case 0: return .Colors
    case 1: return .Palettes
    case 2: return .Metrics
    }

    return .Colors
}

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

// Marks the button standing for the active palette, and the one standing for the active page.
//
// The selected button takes the default form, which is the one form every palette fills with
// its own accent: the selector then also reports what the accent of the palette it names is.
func updateSelectors()
{
    for btn, idx in g_ThemeButtons
    {
        btn.setForm(cast(s32) idx == cast(s32) g_Variant ? .Default : .Flat)
        btn.invalidate()
    }

    for btn, idx in g_PageButtons
    {
        btn.setForm(cast(s32) idx == g_Page ? .Default : .Flat)
        btn.invalidate()
    }
}

func updateHeader()
{
    g_Title!.setText(Format.toString("GUI10 theme inspector - %", pageTitle(g_Page)))
    g_SubTitle!.setText(pageSubtitle(g_Page))
    g_Footer!.setText(Format.toString("Palette: %. F1 : next page (%/%). F2 : next palette. The filter keeps only the values whose name contains it.", variantName(g_Variant), g_Page + 1, MaxPages))
}

func applyTheme()
{
    applyVariant(app.theme, g_Variant)
    updateSelectors()
    updateHeader()
    app.notifyThemeChanged()
}

func setVariant(variant: ThemeVariant)
{
    if g_Variant == variant do
        return
    g_Variant = variant
    applyTheme()
}

func showPage(page: s32)
{
    g_Page = page

    let widgets = g_Widgets!
    let sheet   = g_Sheet!
    let isSheet = page != 3
    widgets.show(!isSheet)
    sheet.show(isSheet)
    if isSheet do
        sheet.view.setKind(sheetKindOfPage(page))

    updateSelectors()
    updateHeader()
    layoutRootView()
}

func nextPage()
{
    showPage((g_Page + 1) % MaxPages)
}

func layoutRootView()
{
    if !g_View do
        return

    let view         = g_View!
    let rect         = view.clientRect()
    let contentWidth = Math.max(rect.width - 2 * RootMargin, 1.0)

    g_Title!.setPosition({RootMargin, 16, contentWidth, 34})
    g_SubTitle!.setPosition({RootMargin + 2, 52, contentWidth - 4, 36})

    var x = RootMargin
    for btn in g_ThemeButtons
    {
        btn.setPosition({x, HeaderHeight, 118, BarHeight})
        x += 118 + 6
    }

    x = RootMargin
    let barY = HeaderHeight + BarHeight + BarGap
    for btn in g_PageButtons
    {
        btn.setPosition({x, barY, 104, BarHeight})
        x += 104 + 6
    }

    g_Filter!.setPosition({RootMargin + contentWidth - FilterWidth, barY, FilterWidth, BarHeight})
    g_Rings!.setPosition({RootMargin + contentWidth - FilterWidth - RingsWidth - 12, barY, RingsWidth, BarHeight})

    let pageY      = barY + BarHeight + BarGap
    let pageHeight = Math.max(rect.height - pageY - PageBottomMargin, 120.0)
    g_Sheet!.setPosition({RootMargin, pageY, contentWidth, pageHeight})
    g_Widgets!.setPosition({RootMargin, pageY, contentWidth, pageHeight})

    g_Footer!.setPosition({RootMargin, Math.max(rect.height - 34.0, pageY + pageHeight + 4.0), contentWidth, 26})
}

func onRootEvent(view: *Wnd, evt: IEvent)->bool
{
    if evt is ResizeEvent
    {
        layoutRootView()
    }
    elif evt is DestroyEvent
    {
        app.sigFrame.disable()
        g_Surface  = null
        g_View     = null
        g_Title    = null
        g_SubTitle = null
        g_Footer   = null
        g_Filter   = null
        g_Rings    = null
        g_Sheet    = null
        g_Widgets  = null
        g_ThemeButtons.clear()
        g_PageButtons.clear()
    }

    return false
}

func updateTestMode()
{
    if !Env.isSmokeRun() or !g_Surface do
        return

    g_TestFrame += 1
    if g_TestFrame < TestFramesPerPage do
        return

    g_TestFrame = 0

    // A smoke run walks every page of every palette, which is exactly the matrix a
    // reader would step through by hand.
    if g_Page + 1 < MaxPages
    {
        showPage(g_Page + 1)
        return
    }

    if cast(s32) g_Variant + 1 >= ThemeVariantCount
    {
        Env.exit(0)
        return
    }

    showPage(0)
    setVariant(cast(ThemeVariant) (cast(s32) g_Variant + 1))
}

func onFrame(app: *Application)
{
    if !g_Surface do
        return

    if app.keyboard.isKeyJustPressed(.F1) do
        nextPage()
    if app.keyboard.isKeyJustPressed(.F2) do
        setVariant(cast(ThemeVariant) ((cast(s32) g_Variant + 1) % ThemeVariantCount))

    updateTestMode()
}

func createRootView()
{
    let view = g_Surface!.view()
    g_View               = view
    view.backgroundStyle = .View

    let title = Label.create(view, "", {})
    g_Title = title
    setLabelTextStyle(title, .Left, .Center)
    title.style.setFont(view.theme().createDefaultFont(26), .Regular)

    let subTitle = Label.create(view, "", {}, null, .WordWrap | .SecondaryText)
    g_SubTitle = subTitle
    setLabelTextStyle(subTitle, .Left, .Top)

    for i in ThemeVariantCount
    {
        let variant = cast(ThemeVariant) cast(s32) i
        let btn     = PushButton.create(view, variantName(variant), {})
        btn.sigPressed += func|variant|(btn) { setVariant(variant) }
        g_ThemeButtons.add(btn)
    }

    for i in MaxPages
    {
        let page = cast(s32) i
        let btn  = PushButton.create(view, pageTitle(page), {})
        btn.sigPressed += func|page|(btn) { showPage(page) }
        g_PageButtons.add(btn)
    }

    let filter = EditBox.create(view, "", {})
    g_Filter = filter
    filter.setPlaceholder("filter by name")
    filter.setIcon(app.theme.icon(.Search, 16))
    filter.sigTextChanged += func(ed) { g_Sheet!.view.setFilter(ed.text()) }

    // Only one control of a surface can hold the keyboard, so the focus mark is the one state
    // the wall cannot show by standing still. The diagnostic draws every ring at once, which is
    // how the mark is judged against every shape a palette answers for rather than one at a time.
    let rings = CheckButton.create(view, "focus rings", {})
    g_Rings          = rings
    rings.sigChanged += func(box)
    {
        app.options.showFocusRings = box.state == .Checked
        g_View!.invalidate()
    }

    g_Sheet   = SheetWnd.create(view)
    g_Widgets = WidgetWall.create(view)

    let footer = Label.create(view, "", {}, null, .SecondaryText)
    g_Footer = footer
    setLabelTextStyle(footer, .Left, .Center)

    layoutRootView()
    view.hookOnEvent = &onRootEvent
}

#main
{
    let flags   = SurfaceFlags.LargeCaption | SurfaceFlags.MinimizeButton | SurfaceFlags.CloseButton | SurfaceFlags.Border
    let surface = (try app.createSurface(60, 40, W - 46, H - 31, flags))!
    g_Surface = surface
    surface.setTitle("GUI10 theme inspector")
    surface.setIcon(app.theme.icon(ThemeIcons.Picker, 18))
    readStartupSelection()
    createRootView()
    showPage(g_Page)

    app.sigFrame += &onFrame
    if Env.isSmokeRun() do
        app.maxRunFrame = cast(u32) (MaxPages * ThemeVariantCount * TestFramesPerPage + 10)
    surface.show()
    applyTheme()
    app.run()
}
