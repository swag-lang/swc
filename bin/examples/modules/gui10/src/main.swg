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

const MaxPages = 5
const TestFramesPerPage = 30

// The page keeps reading margins at its sides; the header stands under the window strip.
const PageMargin  = 48.0
const TitleSize   = 34'u32
const FilterWidth = 240.0
const RingsWidth  = 130.0
const BarGap      = 16.0

const CmdLens        = "gui10.lens"
const CmdNextPage    = "gui10.page.next"
const CmdNextPalette = "gui10.palette.next"

var app:        Application
var g_Surface:  *Surface?
var g_View:     *Wnd?
var g_Title:    *Label?
var g_SubTitle: *Label?
var g_Tabs:     *Tab?
var g_Variants: *Tab?
var g_Filter:   *EditBox?
var g_Rings:    *CheckButton?
var g_Sheet:    *SheetWnd?
var g_Widgets:  *WidgetWall?
var g_Stage:    *ComponentStage?
var g_Lens:     *Lens.View?

var g_Variant:   ThemeVariant
var g_Page:      s32
var g_TestFrame: s32

// The two themes the toolkit ships, Encre and Papier, followed by the sheet-written example.
//
// A variant is applied through the theme rather than through `theme.colors`, because a sheet
// can answer for metrics and atlas tiles as well as for colors.
enum ThemeVariant
{
    Dark
    Light
    Sheet
}

const ThemeVariantCount = 3

// A theme written as a tweak sheet rather than in code, which is how anyone shipping an
// application writes one. Reading it beside the palettes above is the point of having it
// here: the same thirty-five tokens, the same three hundred parts derived from them, and
// nothing in the toolkit that knows the difference.
const SheetTheme = #include("sepia.tweak")

func variantName(variant: ThemeVariant)->string
{
    switch #complete variant
    {
    case .Dark:  return "Encre"
    case .Light: return "Papier"
    case .Sheet: return "Sepia sheet"
    }
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

    case .Sheet:

        // A sheet is a delta, so the theme is put back on a known palette before the sheet
        // is read: applied twice in a row, a partial sheet would otherwise compound.
        theme.setLight()
        expect theme.applySheet(cast(string, SheetTheme))
    }
}

// Returns the colors of `variant` without touching the theme on screen.
//
// The sheets that compare palettes need all variants at once, and a palette is a plain
// value, so each one is simply built on the spot.
func variantColors(variant: ThemeVariant)->ThemeColors
{
    var result: #returntype
    switch #complete variant
    {
    case .Dark:
        result.setDark()

    case .Light:
        result.setLight()

    case .Sheet:
        var theme: Theme
        theme.setLight()
        expect theme.applySheet(cast(string, SheetTheme))
        result = theme.colors
    }

    return result
}

const PageTitles: [MaxPages] string = ["Colors", "Palettes", "Metrics", "Widgets", "Components"]

// The command-line name of each palette and each page, in the order of the two enumerations.
const VariantArgs: [ThemeVariantCount] string = ["--dark", "--light", "--sheet"]
const PageArgs:    [MaxPages] string = ["--colors", "--palettes", "--metrics", "--widgets", "--components"]

// Reads the palette and the page the command line asks the inspector to open on.
//
// Judging a theme means looking at one page of one variant, and there are twelve such pairs.
// Reached by hand that is twelve windows to drive by pointer; named on the command line it is
// twelve launches a script can take a picture of, which is how a change to `apply` is compared
// against the palettes it did not mean to touch.
func readStartupSelection()
{
    for arg in Env.arguments()
    {
        for name, i in VariantArgs where arg == name do
            g_Variant = cast(ThemeVariant, cast(s32, i))
        for name, i in PageArgs where arg == name do
            g_Page = cast(s32, i)
    }
}

func pageSubtitle(page: s32)->string
{
    switch page
    {
    case 0: return "Every ThemeColors value of the active palette, over the grounds it is drawn on. Alpha shows against the checkerboard."
    case 1: return "The same value in Encre and in Papier, with the sheet-written example beside them."
    case 2: return "Every ThemeMetrics value of the active theme, in logical pixels."
    case 3: return "Live widgets in every state the palette answers for. Hover and press them to read the hot and pressed colors."
    case 4: return "The floating components over a piece of work: dock, mini-bar, inspector, hint line. I shows the sheet; Ctrl K on the stage opens its lens."
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

// Marks the tab of the active palette and the tab of the active page.
func updateSelectors()
{
    let variant = cast(u32, cast(s32, g_Variant))
    if g_Variants!.selectedIndex != variant do
        g_Variants!.setSelectedIndex(variant)
    if g_Tabs!.selectedIndex != cast(u32, g_Page) do
        g_Tabs!.setSelectedIndex(cast(u32, g_Page))
}

func updateHeader()
{
    g_SubTitle!.setText(pageSubtitle(g_Page))
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

    let widgets = unwrap g_Widgets
    let sheet   = unwrap g_Sheet
    let stage   = unwrap g_Stage
    let isSheet = page < 3
    widgets.show(page == 3)
    stage.show(page == 4)
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

// Places the header under the window strip: the title with the palettes at its right, then the
// pages as text tabs with the focus-ring switch and the filter at their right, then the page,
// keeping the foot clear for the hint line.
func layoutRootView()
{
    if not g_View do
        return

    let view    = unwrap g_View
    let metrics = view.themeMetrics()
    let rect    = view.clientRect()
    let top     = view.stripInset()
    let width   = Math.max(rect.width - 2 * PageMargin, 1.0)

    let titleHeight = view.theme().createDefaultFont(TitleSize, .Bold).height
    g_Title!.setPosition(Math.Rectangle{PageMargin, top, width, titleHeight})
    g_SubTitle!.setPosition(Math.Rectangle{PageMargin, top + titleHeight + 4, width, 22})

    let variantsWidth = 330.0
    g_Variants!.setPosition(Math.Rectangle{PageMargin + width - variantsWidth, top + (titleHeight - metrics.tabBar_RoundHeight) * 0.5, variantsWidth, metrics.tabBar_RoundHeight})

    let barY = top + titleHeight + 4 + 22 + 16
    g_Tabs!.setPosition(Math.Rectangle{PageMargin, barY, width, metrics.tabBar_FlatHeight})
    let fieldY = barY + (metrics.tabBar_FlatHeight - metrics.editBox_Height) * 0.5 - 4
    g_Filter!.setPosition(Math.Rectangle{PageMargin + width - FilterWidth, fieldY, FilterWidth, metrics.editBox_Height})
    g_Rings!.setPosition(Math.Rectangle{PageMargin + width - FilterWidth - RingsWidth - BarGap, fieldY, RingsWidth, metrics.editBox_Height})

    let pageY      = barY + metrics.tabBar_FlatHeight + BarGap
    let bottom     = rect.height - metrics.hintLine_Bottom - metrics.hintLine_Height - 16
    let pageHeight = Math.max(bottom - pageY, 120.0)
    g_Sheet!.setPosition(Math.Rectangle{PageMargin, pageY, width, pageHeight})
    g_Widgets!.setPosition(Math.Rectangle{PageMargin, pageY, width, pageHeight})
    g_Stage!.setPosition(Math.Rectangle{PageMargin, pageY, width, pageHeight})
}

// Answers the lens with the pages and the palettes, the ones shown checked.
func describeChoices(results: *Lens.Results)
{
    const PagesFamily = "Pages"
    var section: *Lens.Section?
    for title, index in PageTitles where Lens.match(results.query, PagesFamily).matched or Lens.match(results.query, title).matched
    {
        if not section do
            section = results.addSection(PagesFamily)
        with let entry = section.addEntry(title)
        {
            .checked = cast(s32, index) == g_Page
            .run     = func|index|() { showPage(cast(s32, index)) }
        }
    }

    const PalettesFamily = "Palettes"
    section = null
    for i in ThemeVariantCount
    {
        let variant = cast(ThemeVariant, cast(s32, i))
        let name    = variantName(variant)
        if not Lens.match(results.query, PalettesFamily).matched and not Lens.match(results.query, name).matched do
            continue
        if not section do
            section = results.addSection(PalettesFamily)
        with let entry = section.addEntry(name)
        {
            .checked = variant == g_Variant
            .run     = func|variant|() { setVariant(variant) }
        }
    }
}

func nextVariant() => setVariant(cast(ThemeVariant, ((cast(s32, g_Variant) + 1) % ThemeVariantCount)))

func onRootEvent(_: *Wnd, evt: IEvent)->bool
{
    switch evt
    {
    case ResizeEvent:
        layoutRootView()

    case CommandStateEvent as state where state.kind == .Compute:
        switch state.id
        {
        case CmdNextPage:    state.name = "Next Page"
        case CmdNextPalette: state.name = "Next Palette"
        default: return false
        }

        state.updatedFields.add(.Name)
        state.accepted = true
        return true

    case CommandEvent as cmd:
        switch cmd.id
        {
        case CmdLens:        g_Lens!.open()
        case CmdNextPage:    nextPage()
        case CmdNextPalette: nextVariant()
        default:             return false
        }

        cmd.accepted = true
        return true

    case DestroyEvent:
        app.sigFrame.disable()
        g_Surface, g_View, g_Title, g_SubTitle, g_Tabs, g_Variants, g_Filter, g_Rings, g_Sheet, g_Widgets, g_Stage, g_Lens = null
    }

    return false
}

func updateTestMode()
{
    if not Env.isSmokeRun() or not g_Surface do
        return

    g_TestFrame += 1

    // The lens is exercised on its page: it opens a third of the way through and closes before
    // the page turns.
    if g_Page == 4
    {
        if g_TestFrame == TestFramesPerPage / 3 do
            g_Stage!.lens.open("t")
        elif g_TestFrame == 2 * TestFramesPerPage / 3 do
            g_Stage!.lens.close()
    }

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

    if cast(s32, g_Variant) + 1 >= ThemeVariantCount
    {
        Env.exit(0)
        return
    }

    showPage(0)
    setVariant(cast(ThemeVariant, (cast(s32, g_Variant) + 1)))
}

func onFrame(_: *Application)
{
    if not g_Surface do
        return
    updateTestMode()
}

func createRootView()
{
    let view = g_Surface!.view()
    g_View = view
    view.backgroundStyle = .Window

    with g_Title = Label.create(view, "Theme", {})
    {
        .setTextAlignment(.Left, .Center)
        .style.setFont(view.theme().createDefaultFont(TitleSize, .Bold), .Regular)
    }

    with g_SubTitle = Label.create(view, "", {}, null, .SecondaryText | .Ellipsis)
    {
        .setTextAlignment(.Left, .Center)
    }

    // The palette is a choice among three, so it is a group of segments beside the title.
    with g_Variants = Tab.create(view, {})
    {
        .setForms(.Round, .Round, .None)
        .setLayout(.Equal)
        for i in ThemeVariantCount do
            .addItem(variantName(cast(ThemeVariant, cast(s32, i))))
        .sigSelectionChanged += func(tab) { setVariant(cast(ThemeVariant, cast(s32, cast(*Tab, tab).selectedIndex))) }
    }

    with g_Tabs = Tab.create(view, {})
    {
        .setForms(.Flat, .Flat, .None)
        .setLayout(.Content)
        for title in PageTitles do
            .addItem(title)
        .sigSelectionChanged += func(tab)
        {
            let index = cast(s32, cast(*Tab, tab).selectedIndex)
            if index != g_Page do
                showPage(index)
        }
    }

    with g_Filter = EditBox.create(view, "", {})
    {
        .setPlaceholder("Filter by name")
        .setIcon(app.theme.icon(.Search, 16))
        .sigTextChanged += func(ed) { g_Sheet!.view.setFilter(ed.text()) }
    }

    // Only one control of a surface can hold the keyboard, so the focus mark is the one state
    // the wall cannot show by standing still. The diagnostic draws every ring at once, which is
    // how the mark is judged against every shape a palette answers for rather than one at a time.
    with g_Rings = CheckButton.create(view, "Focus rings", {})
    {
        .sigChanged += func(box)
        {
            app.options.showFocusRings = box.state == .Checked
            g_View!.invalidate()
        }
    }

    g_Sheet   = SheetWnd.create(view)
    g_Widgets = WidgetWall.create(view)
    g_Stage   = ComponentStage.create(view)

    with let hint = HintLine.create(view)
    {
        .addHint("Ctrl K", "pages, palettes")
        .addHint("F1", "next page")
        .addHint("F2", "next palette")
    }

    with g_Lens = Lens.View.create(view)
    {
        .addSource(.None, &describeChoices)
        .addCommands("Go", [CmdNextPage, CmdNextPalette])
    }

    view.registerKeyShortcut(.Control, .K, CmdLens)
    view.registerKeyShortcut(.None, .F1, CmdNextPage)
    view.registerKeyShortcut(.None, .F2, CmdNextPalette)
    view.hookOnEvent = &onRootEvent
    layoutRootView()
}

#main
{
    let surface = try app.createSurface(60, 40, W, H, SurfaceFlags.StandardWindow)
    g_Surface = surface
    surface.setTitle("GUI10 Theme")
    surface.minSize = {1000, 700}
    readStartupSelection()
    createRootView()
    showPage(g_Page)

    app.sigFrame += &onFrame
    if Env.isSmokeRun() do
        app.maxRunFrame = cast(u32, (MaxPages * ThemeVariantCount * TestFramesPerPage + 10))
    surface.show()
    applyTheme()
    app.run()
}
