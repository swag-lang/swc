// GUI4 - the property control.
//
// One `PropertiesCtrl` edits several cards at once from a reflected struct: nested categories,
// `Heading`, `Gap` and `HelpBox` decorators, conditional fields, validation and a custom editor
// registered for a type. Each page shows the control in one of its four layouts; the segments
// over the preview choose how many cards it edits. `Ctrl K` opens the lens, which reaches every
// layout and the appearance. `--light` opens the window on Papier, `--page=N` on page N.

using Core, Gui, Pixel
using Properties

const W        = 1360
const H        = 900
const MaxPages = 4
const TestFramesPerPage = 60

// The page keeps reading margins at its sides, and each section keeps one inset for its label, its
// sentence and its controls, so the section labels stand on the left edge of the title.
const PageMargin      = 48.0
const SectionInset    = 24.0
const SectionGap      = 24.0
const TitleSize       = 34'u32
const TopHeight       = 240.0
const MinBottomHeight = 232.0

const CmdLens         = "gui4.lens"
const CmdNextPage     = "gui4.page.next"
const CmdPreviousPage = "gui4.page.previous"

const InspectorWidth = 560.0
const NumCards       = 3

// ---------------------------------------------------------------------------
// Data. A single struct edited several instances at a time (multi-selection),
// organised with nested category subgroups and the Heading / Gap / HelpBox
// decorators — all declared right in the struct.
// ---------------------------------------------------------------------------

enum CardShape
{
    Card
    Banner
    Pill
}

enum ShadowKind
{
    None
    Soft
    Hard
}

#[Swag.EnumFlags]
enum CardBadge
{
    #[Description("Draw a small accent dot in the corner.")]
    Accent

    #[Description("Draw an outline ring around the card.")]
    Ring

    #[Description("Draw a small state tag in the upper right.")]
    Tag
}

// A tiny value type given a bespoke editor through the registry (see RatingEditor).
#[Swag.Using(Gui.Properties)]
struct Rating
{
    value: s32 = 3
}

#[Swag.Using(Gui.Properties)]
struct SceneCard
{
    #[Name("Label"), Description("Caption drawn on the card.")]
    label: String

    // Transform group, with a nested "Advanced" subgroup ("Transform/Advanced").
    #[Category("Transform"), Description("Offset from the slot center.")]
    offset: Math.Point = {0, 0}

    #[SliderMinMax(0.5, 1.8), Description("Uniform scale factor.")]
    scale: f32 = 1.0

    #[Category("Transform/Advanced"), SliderMinMax(0.2, 1.0), Description("Overall opacity.")]
    opacity: f32 = 1.0

    // Style group: opens with a HelpBox note, then later a Gap + Heading "Shadow" sub-divider.
    #[Category("Style"), HelpBox("These settings control how the card is drawn."), Description("Overall shape."), RecalcLayout]
    shape: CardShape = CardShape.Card

    #[Properties.Opaque, Description("Fill color. The editor uses the ColorPicker popup.")]
    fill: Color = Argb.CornflowerBlue

    #[SliderMinMax(0, 42), Description("Corner radius (card & banner shapes).")]
    radius: f32 = 16

    #[SliderMinMax(0, 1), Description("0 = glossy highlight, 1 = fully matte.")]
    roughness: f32 = 0.4

    #[Gap(14), Heading("Shadow"), Description("Cast a drop shadow under the card."), RecalcLayout]
    castShadow: bool = true

    #[Description("Shadow softness. Disabled when the shadow is off.")]
    shadowKind: ShadowKind = ShadowKind.Soft

    // A second nested subgroup: "Style/Advanced".
    #[Category("Style/Advanced"), Description("Optional badges drawn on the card.")]
    badges: CardBadge = CardBadge.Accent | CardBadge.Tag

    #[Name("Rating"), Description("Custom editor registered for the Rating type (click a pip).")]
    quality: Rating = {4}
}

impl IPropertyNotify for SceneCard
{
    // Conditional enable: radius is meaningless for a pill, shadow softness only when shadows are on.
    mtd impl isItemEnabled(_: *Properties, item: *PropertiesItem)->bool
    {
        switch item.typeValue.name
        {
        case #nameof(SceneCard.radius):     return .shape != CardShape.Pill
        case #nameof(SceneCard.shadowKind): return .castShadow
        }

        return true
    }

    // Per-field validation, surfaced by the grid as a critical ring or a caution message.
    mtd impl validateItem(_: *Properties, item: *PropertiesItem)->PropValidationResult
    {
        switch item.typeValue.name
        {
        case #nameof(SceneCard.label):
            if .label.isEmpty() do
                return {.Error, "A label is required."}

        case #nameof(SceneCard.scale):
            if .scale >= 1.6 do
                return {.Warning, "Large cards may overflow their slot."}
        }

        return {}
    }
}

struct PagePanelLayout
{
    left:   Math.Rectangle
    right:  Math.Rectangle
    bottom: Math.Rectangle
}

var app:           Application
var g_Surface:     *Surface?
var g_View:        *Wnd?
var g_Title:       *Label?
var g_SubTitle:    *Label?
var g_Tabs:        *Tab?
var g_PageView:    *Wnd?
var g_Lens:        *Lens.View?
var g_Appearance:  *AppearanceButton?
var g_Page:        s32
var g_TestFrame:   s32
var g_Hint:        *HintLine?
var g_StatusText:  String
var g_Cards:       [NumCards] SceneCard
var g_CardCount:   s32 = 2
var g_DisplayMode: PropertiesKind = .Grid
var g_Filter:      String
var g_ObjHost:     *Wnd?
var g_PropCtrl:    *PropertiesCtrl?
var g_Props:       *Properties?
var g_Preview:     *Wnd?
var g_CountTabs:   *Tab?
var g_Light:       bool

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

func initCard(c: *SceneCard,
              label: string,
              argb: u32,
              shape: CardShape,
              scale,
              radius,
              roughness,
              opacity: f32,
              shadow: bool,
              shadowKind: ShadowKind,
              badges: CardBadge)
{
    c.label      = label
    c.fill       = Color.fromArgb(argb)
    c.shape      = shape
    c.scale      = scale
    c.radius     = radius
    c.roughness  = roughness
    c.opacity    = opacity
    c.castShadow = shadow
    c.shadowKind = shadowKind
    c.badges     = badges
}

func initDemoData()
{
    // Deliberately different values so a multi-selection shows shared fields and "mixed" fields.
    initCard(&g_Cards[0],
             label: "Alpha",
             argb: 0xFF6495ED,
             shape: .Card,
             scale: 1.0,
             radius: 16,
             roughness: 0.30,
             opacity: 1.00,
             shadow: true,
             shadowKind: .Soft,
             badges: CardBadge.Accent | CardBadge.Tag)
    initCard(&g_Cards[1],
             label: "Beta",
             argb: 0xFFE2725B,
             shape: .Banner,
             scale: 1.3,
             radius: 10,
             roughness: 0.60,
             opacity: 0.85,
             shadow: false,
             shadowKind: .None,
             badges: CardBadge.Ring)
    initCard(&g_Cards[2],
             label: "Gamma",
             argb: 0xFF66BB6A,
             shape: .Pill,
             scale: 0.9,
             radius: 24,
             roughness: 0.15,
             opacity: 1.00,
             shadow: true,
             shadowKind: .Hard,
             badges: CardBadge.Accent)

    g_StatusText = "no change yet"
}

// ---------------------------------------------------------------------------
// The single inspector page: one property control (multi-selection) + preview
// ---------------------------------------------------------------------------

func displayModeFromIndex(idx: u32)->PropertiesKind
{
    switch idx
    {
    case 0: return .Grid
    case 1: return .Condensed
    case 2: return .List
    case 3: return .Panel
    }

    return .Grid
}

// (Re)create the property control bound to the first g_CardCount cards, in the current display mode.
// Changing the mode or the count rebinds the instance set, so we recreate the widget (like the old
// multi-selection page did on a count change).
func rebuildInspector()
{
    let objHost = g_ObjHost
    if not objHost do
        return

    g_PropCtrl?.destroy()

    let ctrl  = PropertiesCtrl.create(objHost, kind: g_DisplayMode, flags: .SearchBar)
    let props = ctrl.properties
    g_PropCtrl     = ctrl
    g_Props        = props
    ctrl.dockStyle = .Center
    props.setEditorWidth(320)
    if props.isGridLike() do
        props.setNameColumnWidth(190)

    var bases: Array'(*u8)
    for i in g_CardCount do
        bases.add(cast(*u8, &g_Cards[i]))
    props.addStructMulti(SceneCard,
                         bases.toSlice(),
                         Format.toString("Editing % card%", g_CardCount, g_CardCount > 1 ? "s" : ""))

    if not g_Filter.isEmpty() do
        ctrl.search.setText(g_Filter.toString())

    ctrl.search.sigTextChanged += func(fil)
    {
        g_Filter = fil.text()
    }

    props.sigValueChanged += func(_, item)
    {
        updateStatus(item)
        g_Preview?.invalidate()
    }

    objHost.applyLayout()
}

func setCardCount(count: s32)
{
    if g_CardCount == count do
        return
    g_CardCount = count
    g_CountTabs?.setSelectedIndex(cast(u32, count - 1))
    rebuildInspector()
    g_Preview?.invalidate()
}

// Lays the page out in two sections: the property control at the left, in the layout the page
// names, and the preview of the cards at the right with the number of cards it edits.
func createInspectorPage(parent: *Wnd)
{
    g_DisplayMode = displayModeFromIndex(cast(u32, g_Page))

    let rect  = parent.clientRect()
    let leftW = Math.min(InspectorWidth + 2 * SectionInset, rect.width * 0.55)
    let left  = createPanel(parent,
                            "Properties",
                            "One control edits the cards chosen at the right at once; a field they disagree on reads as mixed.",
                            Math.Rectangle{0, 0, leftW, rect.height})
    let objHost = Wnd.create'Wnd(left, Math.Rectangle{SectionInset, 88, leftW - 2 * SectionInset, Math.max(rect.height - 88, 1.0)})
    g_ObjHost = objHost
    rebuildInspector()

    let rightX = leftW + SectionGap
    let right  = createPanel(parent,
                             "Preview",
                             "Each card is one edited instance; the ones ringed in Arc are bound to the control.",
                             Math.Rectangle{rightX, 0, Math.max(rect.width - rightX, 1.0), rect.height})

    // How many cards the control edits is a choice among three, so it is a group of segments.
    with g_CountTabs = Tab.create(right, Math.Rectangle{SectionInset, 88, 300, right.themeMetrics().tabBar_RoundHeight})
    {
        .setForms(.Round, .Round, .None)
        .setLayout(.Equal)
        .addItem("1 Card")
        .addItem("2 Cards")
        .addItem("3 Cards")
        .setSelectedIndex(cast(u32, g_CardCount - 1))
        .sigSelectionChanged += func(tab) { setCardCount(cast(s32, cast(*Tab, tab).selectedIndex) + 1) }
    }

    let preview = Wnd.create'Wnd(right, Math.Rectangle{0, 136, right.position.width, Math.max(rect.height - 136, 1.0)})
    preview.backgroundStyle = .Transparent
    preview.hookOnEvent     = &onPreviewEvent
    g_Preview = preview
}

// ---------------------------------------------------------------------------
// Preview: the NumCards cards drawn in vertical slots, the first g_CardCount selected.
// ---------------------------------------------------------------------------

func cardRadius(card: *SceneCard, h: f32)->f32
{
    switch card.shape
    {
    case .Card:   return card.radius
    case .Banner: return Math.min(card.radius, 12)
    case .Pill:   return h * 0.5
    }

    return card.radius
}

func drawCard(painter: *Painter, slot: Math.Rectangle, card: *SceneCard, selected: bool)
{
    painter.setParams(.Antialiased)

    let a    = cast(u8, (Math.clamp(card.opacity, 0.0, 1.0) * 255))
    let w    = Math.min(320.0 * card.scale, slot.width - 40)
    let h    = Math.min(120.0 * card.scale, slot.height - 22)
    let cx   = slot.horzCenter() + cast(f32, card.offset.x)
    let cy   = slot.vertCenter() + cast(f32, card.offset.y)
    let body = Math.Rectangle{cx - w * 0.5, cy - h * 0.5, w, h}
    let rad  = cardRadius(card, h)

    if card.castShadow and card.shadowKind != .None
    {
        let off = card.shadowKind == .Soft ? 14.0'f32 : 7.0'f32
        let sa  = card.shadowKind == .Soft ? 45.0'f32 : 90.0'f32
        let sh  = Math.Rectangle{body.x + off, body.y + off, body.width, body.height}
        painter.fillRoundRect(sh, rad, rad, Color.fromArgb(cast(u8, (sa * card.opacity)), Argb.Black))
    }

    painter.fillRoundRect(body, rad, rad, card.fill.withAlpha(a))

    // Gloss on the upper half: stronger as roughness drops.
    let gloss = Math.clamp(1.0 - card.roughness, 0.0, 1.0)
    if gloss > 0.02
    {
        var hi = body
        hi.height *= 0.5
        painter.fillRoundRect(hi, rad, rad, Color.fromArgb(cast(u8, (gloss * 90 * card.opacity)), Argb.White))
    }

    if card.badges & CardBadge.Ring do
        painter.drawRoundRect(body, rad, rad, Color.lerpRgb(card.fill, Argb.White, 0.5).withAlpha(a), 2.0)
    if card.badges & CardBadge.Accent do
        painter.fillCircle(body.x + 20, body.y + 20, 6, Color.fromArgb(Argb.Orange).withAlpha(a))
    if card.badges & CardBadge.Tag
    {
        let tag = Math.Rectangle{body.right() - 62, body.y + 14, 48, 22}
        painter.fillRoundRect(tag, 11, 11, Color.fromArgb(cast(u8, (200.0 * card.opacity)), Argb.Black))
    }

    // A card bound to the control is chosen, so it is ringed in Arc.
    if selected
    {
        let corner = g_View!.themeMetrics().corner_Floating
        let sel    = Math.Rectangle{slot.x + 6, slot.y + 4, slot.width - 12, slot.height - 8}
        painter.drawRoundRect(sel, corner, corner, g_View!.themeColors().arc, 2.0)
    }

    let font = g_View!.theme().createDefaultFont(15, .Bold)
    let tcol = Color.lerpRgb(card.fill, Argb.Black, 0.72).withAlpha(a)
    painter.drawStringCenter(body.horzCenter(), body.vertCenter(), card.label.toString(), font, tcol)
}

func onPreviewEvent(view: *Wnd, evt: IEvent)->bool
{
    switch evt
    {
    case PaintEvent as paintEvt:
        let painter = paintEvt.paintContext.painter
        let rect    = view.clientRect()

        const TopReserve = 0.0
        const Gap        = 16.0
        let avail = Math.max(rect.height - TopReserve - Gap, 1.0)
        let slotH = (avail - cast(f32, (NumCards - 1)) * Gap) / cast(f32, NumCards)
        var y     = rect.y + TopReserve
        for i in NumCards
        {
            let slot = Math.Rectangle{rect.x + Gap, y, rect.width - 2 * Gap, slotH}
            drawCard(painter, slot, &g_Cards[i], cast(s32, i) < g_CardCount)
            y += slotH + Gap
        }
    }

    return false
}

// ---------------------------------------------------------------------------
// Custom editor for the Rating type (registered globally at #init).
// ---------------------------------------------------------------------------

const RatingMax     = 5
const RatingPipSize = 28'f32

struct RatingEditor {}

impl IPropertyEditor for RatingEditor
{
    mtd impl canEdit(type: typeinfo?)->bool => type == Rating

    mtd impl construct(list: *Properties, value: Swag.TypeValue, data: [*] u8?, parent: *PropertiesItem?)->*PropertiesItem
    {
        let item   = list.addItem(value, data, parent)
        let rating = cast(*Rating?, data)
        let prop   = list

        let line = Wnd.create'Wnd(item.line,
                                  Math.Rectangle{0, 0, RatingMax * RatingPipSize, list.themeMetrics().editBox_Height})
        line.maxSize.x = RatingMax * RatingPipSize
        if list.isGridLike() do
            line.dockStyle = .CenterKeepSizeVert
        else do
            line.anchorStyle = .Right

        for i in RatingMax
        {
            let idx      = cast(s32, i)
            with let btn = IconButton.create(line, {}, Math.Rectangle{0, 0, RatingPipSize, item.line.position.height})
            {
                .dockStyle = .Left
                .updateFlags(.Flat)
                .sigPressed += func|prop, item, rating, idx|(_)
                {
                    let rat = unwrap rating
                    rat.value = rat.value == idx + 1 ? idx : idx + 1
                    prop.commitItemChange(item)
                }

                // A pip that is on is chosen, so it is Arc; one that is off is a stronger rule.
                .iconPainter = func|rating, idx, line|(_, bc, pos, _)
                {
                    bc.painter.setParams(.Antialiased)
                    let on  = idx < rating!.value
                    let col = on ? line.themeColors().arc : line.themeColors().strongLine
                    let rad = Math.min(pos.width, pos.height) * 0.28
                    bc.painter.fillCircle(pos.horzCenter(), pos.vertCenter(), rad, col)
                }
            }
        }

        item.sigRefresh += func|line|(_)
        {
            for c in line.children do
                c.invalidate()
        }

        return item
    }
}

#init
{
    Properties.registerEditor'(RatingEditor)()
}

// Writes the last change in the hint line.
func updateStatus(item: *PropertiesItem?)
{
    if item == null do
        return

    // Owned: 'RichString.plainText' returns a 'String' whose view would dangle once
    // the temporary is dropped at the end of the statement.
    var name: String = item.typeValue.name
    if name == "" and (item.label != null) do
        name = RichString.plainText(item.label.text())
    if name == "" do
        name = "section"

    g_StatusText = Format.toString("last change: %", name)
    g_Hint?.setReading(g_StatusText)
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

const PageTitles = ["Grid", "Condensed", "List", "Panel"]

func pageSubtitle(page: s32)->string
{
    switch page
    {
    case 0: return "A name column and a value column, with sections that fold."
    case 1: return "Rows of 26 with values as text; the editor opens on a click."
    case 2: return "Each setting stacks its label, its help and its editor."
    case 3: return "Self-labelled controls under section labels."
    }

    unreachable
}

func clearPage()
{
    g_ObjHost, g_PropCtrl, g_Props, g_Preview, g_CountTabs = null
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
    case 0:  createInspectorPage(pageView)
    case 1:  createInspectorPage(pageView)
    case 2:  createInspectorPage(pageView)
    case 3:  createInspectorPage(pageView)
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
    const Family = "Layouts"
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
        g_Surface, g_View, g_Title, g_SubTitle, g_Tabs, g_PageView, g_Lens, g_Appearance, g_Hint, g_ObjHost, g_PropCtrl, g_Props, g_Preview, g_CountTabs = null
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

    // A smoke run edits one, two and three cards in turn on every layout.
    if Env.isSmokeRun() and g_TestFrame == TestFramesPerPage / 2 do
        setCardCount(g_CardCount % NumCards + 1)

    updateTestMode()
}

func createRootView()
{
    let view = g_Surface!.view()
    g_View = view
    view.backgroundStyle = .Window

    with g_Title = Label.create(view, "Properties", {})
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

    with g_Hint = HintLine.create(view)
    {
        .setReading(g_StatusText)
        .addHint("Ctrl K", "layouts, appearance")
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
    surface.setTitle("GUI4 Properties")
    surface.minSize = {1100, 720}

    readStartupSelection()
    initDemoData()
    createRootView()
    showPage(g_Page)

    app.sigFrame += &onFrame
    if Env.isSmokeRun() do
        app.maxRunFrame = cast(u32, 2 * MaxPages * TestFramesPerPage + 20)

    surface.show()
    app.run()
}
