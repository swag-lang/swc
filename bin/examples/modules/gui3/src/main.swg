// GUI3 - the rich editor, from code to prose.
//
// One control, `RichEditCtrl`, carries a Swag listing with its lexer, styled spans, a log and a
// page of notes. Each page sets editors in sections under the title; `Ctrl K` opens the lens,
// which reaches every page and the appearance. The styled spans take their colours from the
// theme, so the page is set again when the appearance changes. `--light` opens the window on
// Papier, `--page=N` on page N.

using Core, Gui, Pixel

const W        = 1140
const H        = 880
const MaxPages = 4
const TestFramesPerPage = 40

// The page keeps reading margins at its sides, and each section keeps one inset for its label, its
// sentence and its controls, so the section labels stand on the left edge of the title.
const PageMargin      = 48.0
const SectionInset    = 24.0
const SectionGap      = 24.0
const TitleSize       = 34'u32
const TopHeight       = 300.0
const MinBottomHeight = 232.0

const CmdLens         = "gui3.lens"
const CmdNextPage     = "gui3.page.next"
const CmdPreviousPage = "gui3.page.previous"

const SourcePageLexer     = #include("page.lexer.swg")
const SourcePageStyles    = #include("page.styles.swg")
const SourcePageModes     = #include("page.modes.swg")
const SourcePageWorkspace = #include("page.workspace.swg")

struct PagePanelLayout
{
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
var g_LexerSwag:  RichEditLexerSwag
var g_Restyle:    bool
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

func getFullPageRect(parent: *Wnd)->Math.Rectangle
{
    let rect = parent.clientRect()
    return Math.Rectangle{0, 0, Math.max(rect.width, 1.0), Math.max(rect.height, 1.0)}
}

// Returns the rectangle the editor of a section takes: the section's inset, from the line the
// controls start on to the foot of the section.
func editorRect(section: *Wnd)->Math.Rectangle
{
    let rect = section.clientRect()
    return Math.Rectangle{SectionInset, 88, rect.width - 2 * SectionInset, Math.max(rect.height - 88, 1.0)}
}

func createDemoEditor(parent: *Wnd, rect: Math.Rectangle, flags: RichEditFlags, form = RichEditForm.RichEditCtrl)->*RichEditCtrl
{
    let ed = RichEditCtrl.create(parent, rect)
    ed.setFrameForm(.Round)
    ed.setFrameFlags(.FocusBorder)
    ed.setForm(form)
    ed.setFlags(flags)
    return ed
}

func createCodeEditor(parent: *Wnd,
                      rect: Math.Rectangle,
                      text: string,
                      flags = RichEditFlags.ShowFocusSel | .CurLineBorder | .TabToSpaces)->*RichEditCtrl
{
    let ed = createDemoEditor(parent, rect, flags)
    ed.setLexer(g_LexerSwag)
    ed.marginLeft  = 18
    ed.marginRight = 24
    ed.setText(text)
    return ed
}

func createDocumentEditor(parent: *Wnd,
                          rect: Math.Rectangle,
                          text: string,
                          flags = RichEditFlags.ShowFocusSel | .WordWrap,
                          form = RichEditForm.Edit)->*RichEditCtrl
{
    let ed = createDemoEditor(parent, rect, flags, form)
    ed.marginLeft  = 18
    ed.marginRight = 18
    ed.lineSpacing = 1
    ed.setText(text)
    return ed
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

const PageTitles = ["Lexer", "Styles", "Modes", "Workspace"]

func pageSubtitle(page: s32)->string
{
    switch page
    {
    case 0: return "Swag highlighting, margins, wrapping and visible blanks, on the sources of this example."
    case 1: return "Styled spans, inline emphasis and a log, each colour taken from the theme."
    case 2: return "The code form beside the edit form, read-only editors and combined flags."
    case 3: return "Split panes holding code, notes and a read-only preview side by side."
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
    case 0:  createLexerPage(pageView)
    case 1:  createStylesPage(pageView)
    case 2:  createModesPage(pageView)
    case 3:  createWorkspacePage(pageView)
    default: unreachable
    }

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

    // The styled spans are written in the colours of the theme, so a new theme sets the page again.
    case NotifyEvent as notify where notify.kind == .ThemeChanged:
        g_Restyle = true

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

    // A theme change is noted while the tree is notified, and the page is set again on the next frame.
    if g_Restyle
    {
        g_Restyle = false
        buildPage()
    }

    updateTestMode()
}

func createRootView()
{
    let view = g_Surface!.view()
    g_View = view
    view.backgroundStyle = .Window

    with g_Title = Label.create(view, "Rich Edit", {})
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
    surface.setTitle("GUI3 Rich Edit")
    surface.minSize = {900, 700}

    readStartupSelection()
    createRootView()
    showPage(g_Page)

    app.sigFrame += &onFrame
    if Env.isSmokeRun() do
        app.maxRunFrame = cast(u32, 2 * MaxPages * TestFramesPerPage + 20)

    surface.show()
    app.run()
}
