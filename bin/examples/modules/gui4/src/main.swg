using Core, Gui, Pixel
using Properties

const W = 1600
const H = 1000
const RootMargin = 24.0
const PageTop = 104.0
const PageBottomMargin = 50.0
const SplitGap = 24.0
const InspectorWidth = 660.0
const ThemeButtonWidth = 152.0
const HeaderGap = 18.0
const NumCards = 3

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

    #[SliderMinMax(0.5, 1.8), EditSize(280), Description("Uniform scale factor.")]
    scale: f32 = 1.0

    #[Category("Transform/Advanced"), SliderMinMax(0.2, 1.0), EditSize(280), Description("Overall opacity.")]
    opacity: f32 = 1.0

    // Style group: opens with a HelpBox note, then later a Gap + Heading "Shadow" sub-divider.
    #[Category("Style"), HelpBox("These settings control how the card is drawn."), Description("Overall shape."), RecalcLayout]
    shape: CardShape = CardShape.Card

    #[Properties.Opaque, Description("Fill color. The editor uses the ColorPicker popup.")]
    fill: Color = Argb.CornflowerBlue

    #[SliderMinMax(0, 42), EditSize(280), Description("Corner radius (card & banner shapes).")]
    radius: f32 = 16

    #[SliderMinMax(0, 1), EditSize(280), Description("0 = glossy highlight, 1 = fully matte.")]
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
    mtd impl isItemEnabled(_list: *Properties, item: *PropertiesItem)->bool
    {
        switch item.typeValue.name
        {
        case #nameof(SceneCard.radius):
            return .shape != CardShape.Pill
        case #nameof(SceneCard.shadowKind):
            return .castShadow
        }

        return true
    }

    // Per-field validation, surfaced by the grid as an accent bar + tooltip.
    mtd impl validateItem(_list: *Properties, item: *PropertiesItem)->PropValidationResult
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

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

var app: Application
var g_Surface: *Surface
var g_View: *Wnd
var g_Title: *Label
var g_SubTitle: *Label
var g_ThemeButton: *PushButton
var g_PageView: *Wnd
var g_Footer: *Label
var g_DarkTheme: bool
var g_StatusText: String

var g_Cards: [NumCards] SceneCard
var g_CardCount: s32 = 2
var g_DisplayMode: PropertiesKind = .Grid
var g_Filter: String

var g_ObjHost: *Wnd
var g_Props: *Properties
var g_Preview: *Wnd
var g_DisplayCombo: *ComboBox
var g_CountCombo: *ComboBox

var g_TestFrame: s32
var g_TestStep: s32

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

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

func createPanel(parent: *Wnd, title, subtitle: string, rect: Math.Rectangle)->*FrameWnd
{
    let frame = Wnd.create'FrameWnd(parent, rect)
    frame.setFrameForm(.Round)
    frame.setFrameFlags(.Borders)

    let view = frame.createView'Wnd()
    discard createText(view, title, {16, 10, rect.width - 32, 24})
    let help = createText(view, subtitle, {16, 36, rect.width - 32, 42}, .WordWrap | .LightText)
    help.vertAlignmentText = .Top
    return frame
}

func updateThemeButton()
{
    if !g_ThemeButton do
        return
    g_ThemeButton.name = g_DarkTheme ? "White theme" : "Black theme"
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

func initCard(c: *SceneCard, label: string, argb: u32, shape: CardShape, scale, radius, roughness, opacity: f32, shadow: bool, sk: ShadowKind, badges: CardBadge)
{
    c.label      = label
    c.fill       = Color.fromArgb(argb)
    c.shape      = shape
    c.scale      = scale
    c.radius     = radius
    c.roughness  = roughness
    c.opacity    = opacity
    c.castShadow = shadow
    c.shadowKind = sk
    c.badges     = badges
}

func initDemoData()
{
    // Deliberately different values so a multi-selection shows shared fields and "mixed" fields.
    initCard(&g_Cards[0], "Alpha", 0xFF6495ED, .Card,   1.0, 16, 0.30, 1.00, true,  .Soft, CardBadge.Accent | CardBadge.Tag)
    initCard(&g_Cards[1], "Beta",  0xFFE2725B, .Banner, 1.3, 10, 0.60, 0.85, false, .None, CardBadge.Ring)
    initCard(&g_Cards[2], "Gamma", 0xFF66BB6A, .Pill,   0.9, 24, 0.15, 1.00, true,  .Hard, CardBadge.Accent)

    g_StatusText = "Pick a display mode, edit 1-3 cards at once; a field that differs shows as mixed."
}

// ---------------------------------------------------------------------------
// The single inspector page: one property control (multi-selection) + preview
// ---------------------------------------------------------------------------

func displayModeIndex(kind: PropertiesKind)->u32
{
    switch kind
    {
    case Grid:      return 0
    case Condensed: return 1
    case List:      return 2
    }
    return 0
}

func displayModeFromIndex(idx: u32)->PropertiesKind
{
    switch idx
    {
    case 0: return .Grid
    case 1: return .Condensed
    case 2: return .List
    }
    return .Grid
}

// (Re)create the property control bound to the first g_CardCount cards, in the current display mode.
// Changing the mode or the count rebinds the instance set, so we recreate the widget (like the old
// multi-selection page did on a count change).
func rebuildInspector()
{
    if !g_ObjHost do
        return

    if g_Props do
        g_Props.destroy()

    g_Props           = Properties.create(g_ObjHost, {}, g_DisplayMode)
    g_Props.dockStyle = .Center
    g_Props.sizeEditValue = 320
    if g_Props.isGridLike() do
        g_Props.setColumnSize(190)

    var bases: Array'(*u8)
    for i in g_CardCount do
        bases.add(cast(*u8) &g_Cards[i])
    g_Props.addStructMulti(SceneCard, bases.toSlice(), Format.toString("Editing % card%", g_CardCount, g_CardCount > 1 ? "s" : ""))

    if !g_Filter.isEmpty() do
        g_Props.setStringFilter(g_Filter.toString())

    g_Props.sigChanged += func(_list, item)
    {
        updateStatus(item)
        if g_Preview do
            g_Preview.invalidate()
    }

    g_ObjHost.applyLayout()
}

func setDisplayMode(kind: PropertiesKind)
{
    if g_DisplayMode == kind do
        return
    g_DisplayMode = kind
    rebuildInspector()
}

func setCardCount(count: s32)
{
    if g_CardCount == count do
        return
    g_CardCount = count
    rebuildInspector()
    if g_Preview do
        g_Preview.invalidate()
}

func createInspectorPage(parent: *Wnd)
{
    // Left column: a control row (display mode + edited count), a search box, then the grid.
    g_ObjHost           = Wnd.create'Wnd(parent, {0, 0, InspectorWidth, 10})
    g_ObjHost.dockStyle = .Left
    g_ObjHost.margin.z  = SplitGap

    let controls        = Wnd.create'Wnd(g_ObjHost, {0, 0, 0, 44})
    controls.dockStyle  = .Top
    controls.margin.w   = 8

    discard createText(controls, "Display:", {0, 0, 60, 44})
    with g_DisplayCombo = ComboBox.create(controls, {62, 8, 170, 28})
    {
        .addItem("Normal")
        .addItem("Condensed")
        .addItem("List")
        .selectItem(displayModeIndex(g_DisplayMode))          // before the handler -> no spurious rebuild
        .sigChanged += func(_cb, idx) { setDisplayMode(displayModeFromIndex(idx)); }
    }

    discard createText(controls, "Edit:", {252, 0, 40, 44})
    with g_CountCombo = ComboBox.create(controls, {294, 8, 150, 28})
    {
        .addItem("1 card")
        .addItem("2 cards")
        .addItem("3 cards")
        .selectItem(cast(u32) (g_CardCount - 1))
        .sigChanged += func(_cb, idx) { setCardCount(cast(s32) idx + 1); }
    }

    with let search = EditBox.create(g_ObjHost, "")
    {
        .icon      = parent.getTheme().getIcon24(ThemeIcons24.Search, 18)
        .dockStyle = .Top
        .setNote("Search")
        .margin.w  = 8
        .editBoxFlags.add(.ClearButton)
        .sigChanged += func(fil)
        {
            g_Filter = fil.text
            if g_Props do
                g_Props.setStringFilter(fil.text)
        }
    }

    rebuildInspector()

    let frame = createPanel(parent, "Live preview", "Each card is one edited instance; the highlighted ones are bound to the grid, so editing a field writes them all.", {})
    frame.dockStyle = .Center
    g_Preview = frame.view
    g_Preview.hookOnEvent = &onPreviewEvent
}

// ---------------------------------------------------------------------------
// Preview: the NumCards cards drawn in vertical slots, the first g_CardCount selected.
// ---------------------------------------------------------------------------

func cardRadius(card: *SceneCard, h: f32)->f32
{
    switch card.shape
    {
    case Card:   return card.radius
    case Banner: return Math.min(card.radius, 12)
    case Pill:   return h * 0.5
    }
    return card.radius
}

func drawCard(painter: *Painter, slot: Math.Rectangle, card: *SceneCard, selected: bool)
{
    painter.setParams(.Antialiased)

    let a = cast(u8) (Math.clamp(card.opacity, 0.0, 1.0) * 255)
    let w = Math.min(320.0 * card.scale, slot.width - 40)
    let h = Math.min(120.0 * card.scale, slot.height - 22)
    let cx = slot.horzCenter() + cast(f32) card.offset.x
    let cy = slot.vertCenter() + cast(f32) card.offset.y
    let body = Math.Rectangle{cx - w * 0.5, cy - h * 0.5, w, h}
    let rad = cardRadius(card, h)

    if card.castShadow and card.shadowKind != .None
    {
        let off = card.shadowKind == .Soft ? 14.0'f32 : 7.0'f32
        let sa  = card.shadowKind == .Soft ? 45.0'f32 : 90.0'f32
        let sh  = Math.Rectangle{body.x + off, body.y + off, body.width, body.height}
        painter.fillRoundRect(sh, rad, rad, Color.fromArgb(cast(u8) (sa * card.opacity), Argb.Black))
    }

    painter.fillRoundRect(body, rad, rad, card.fill.withAlpha(a))

    // Gloss on the upper half: stronger as roughness drops.
    let gloss = Math.clamp(1.0 - card.roughness, 0.0, 1.0)
    if gloss > 0.02
    {
        var hi = body
        hi.height *= 0.5
        painter.fillRoundRect(hi, rad, rad, Color.fromArgb(cast(u8) (gloss * 90 * card.opacity), Argb.White))
    }

    if card.badges & CardBadge.Ring do
        painter.drawRoundRect(body, rad, rad, Color.getBlendKeepAlpha(card.fill, Argb.White, 0.5).withAlpha(a), 2.0)
    if card.badges & CardBadge.Accent do
        painter.fillCircle(body.x + 20, body.y + 20, 6, Color.fromArgb(Argb.Orange).withAlpha(a))
    if card.badges & CardBadge.Tag
    {
        let tag = Math.Rectangle{body.right() - 62, body.y + 14, 48, 22}
        painter.fillRoundRect(tag, 11, 11, Color.fromArgb(cast(u8) (200.0 * card.opacity), Argb.Black))
    }

    if selected
    {
        let sel = Math.Rectangle{slot.x + 6, slot.y + 4, slot.width - 12, slot.height - 8}
        painter.drawRoundRect(sel, 12, 12, g_View.getThemeColors().prop_FocusBorder, 2.0)
    }

    let font = g_View.getTheme().createDefaultFont(15, .Bold)
    let tcol = Color.getBlendKeepAlpha(card.fill, Argb.Black, 0.72).withAlpha(a)
    painter.drawStringCenter(body.horzCenter(), body.vertCenter(), card.label.toString(), font, tcol)
}

func onPreviewEvent(view: *Wnd, evt: IEvent)->bool
{
    switch evt
    {
    case PaintEvent as paintEvt:
        let painter = paintEvt.bc.painter
        let rect    = view.getClientRect()
        painter.fillRect(rect, view.getThemeColors().view_Bk)

        const TopReserve = 72.0
        const Gap        = 16.0
        let avail = Math.max(rect.height - TopReserve - Gap, 1.0)
        let slotH = (avail - cast(f32) (NumCards - 1) * Gap) / cast(f32) NumCards
        var y     = rect.y + TopReserve
        for i in NumCards
        {
            let slot = Math.Rectangle{rect.x + Gap, y, rect.width - 2 * Gap, slotH}
            drawCard(painter, slot, &g_Cards[i], cast(s32) i < g_CardCount)
            y += slotH + Gap
        }
    }

    return false
}

// ---------------------------------------------------------------------------
// Custom editor for the Rating type (registered globally at #init).
// ---------------------------------------------------------------------------

const RatingMax = 5
const RatingPipSize = 28'f32

struct RatingEditor {}

impl IPropertyEditor for RatingEditor
{
    mtd impl canEdit(type: typeinfo)->bool
    {
        return type == Rating
    }

    mtd impl construct(list: *Properties, value: Swag.TypeValue, data: [*] u8, parent: *PropertiesItem)->*PropertiesItem
    {
        let item   = list.addItem(value, data, parent)
        let rating = cast(*Rating) data
        let prop   = list

        let line = Wnd.create'Wnd(item.line, {0, 0, RatingMax * RatingPipSize, list.getThemeMetrics().editBox_Height})
        line.maxSize.x = RatingMax * RatingPipSize
        if list.isGridLike() do
            line.dockStyle = .CenterKeepSizeVert
        else do
            line.anchorStyle = .X

        for i in RatingMax
        {
            let idx = cast(s32) i
            with let btn = IconButton.create(line, {}, {0, 0, RatingPipSize, item.line.position.height})
            {
                .dockStyle = .Left
                .iconBtnFlags.add(.Flat)
                .sigPressed += func|prop, item, rating, idx|(b)
                {
                    rating.value = rating.value == idx + 1 ? idx : idx + 1
                    prop.hasChanged(item)
                }
                .sigPaintIcon = func|rating, idx|(b, bc, pos, paintFlags)
                {
                    bc.painter.setParams(.Antialiased)
                    let on  = idx < rating.value
                    let col = on ? Argb.Goldenrod : Color.fromArgb(70'u8, Argb.Gray)
                    let rad = Math.min(pos.width, pos.height) * 0.28
                    bc.painter.fillCircle(pos.horzCenter(), pos.vertCenter(), rad, col)
                }
            }
        }

        item.sigRefresh += func|line|(item)
        {
            foreach c in line.childs do
                c.invalidate()
        }

        return item
    }
}

#init
{
    Properties.registerEditor'(RatingEditor)()
}

// ---------------------------------------------------------------------------
// Root view / app
// ---------------------------------------------------------------------------

func updateStatus(item: *PropertiesItem)
{
    var name = item.typeValue.name
    if name == "" and item.label do
        name = RichString.getNaked(item.label.getText())
    if name == "" do
        name = "section"

    g_StatusText = Format.toString("Last change: %.", name)
    updateHeader()
}

func updateHeader()
{
    g_Title.setText("GUI4 property control inspector")
    g_SubTitle.setText("One property control edits several cards at once (multi-selection). The card struct uses nested category subgroups plus Heading / Gap / HelpBox decorators; the combo switches the display mode.")
    g_Footer.setText(Format.toString("Grouping, decorators, multi-selection and live preview in one grid. %", g_StatusText))
}

func layoutRootView()
{
    if !g_View or !g_PageView do
        return

    let rect = g_View.getClientRect()
    let contentWidth = Math.max(rect.width - 2 * RootMargin, 1.0)
    let pageHeight = Math.max(rect.height - PageTop - PageBottomMargin, 1.0)
    let footerY = Math.max(rect.height - 42.0, PageTop + pageHeight + 6.0)
    let titleWidth = Math.max(contentWidth - ThemeButtonWidth - HeaderGap, 1.0)

    g_Title.setPosition({RootMargin, 18, titleWidth, 34})
    g_ThemeButton.setPosition({RootMargin + titleWidth + HeaderGap, 18, ThemeButtonWidth, 34})
    g_SubTitle.setPosition({RootMargin + 2, 56, contentWidth - 4, 42})
    g_PageView.setPosition({RootMargin, PageTop, contentWidth, pageHeight})
    g_Footer.setPosition({RootMargin, footerY, contentWidth, 28})
}

func onRootEvent(_view: *Wnd, evt: IEvent)->bool
{
    switch evt
    {
    case ResizeEvent:
        layoutRootView()

    case DestroyEvent:
        app.sigFrame.disable()
        g_Surface      = null
        g_View         = null
        g_Title        = null
        g_SubTitle     = null
        g_ThemeButton  = null
        g_PageView     = null
        g_Footer       = null
        g_ObjHost      = null
        g_Props        = null
        g_Preview      = null
        g_DisplayCombo = null
        g_CountCombo   = null
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

// In test mode, cycle the display mode and the edited-card count through the combos (driving the
// real rebuild path), then quit after a fixed number of frames.
func updateTestMode()
{
    if !Env.hasArg("swag.test") or !g_Surface do
        return

    g_TestFrame += 1
    if g_TestFrame % 24 == 0 and g_DisplayCombo and g_CountCombo
    {
        g_TestStep += 1
        g_DisplayCombo.selectItem(cast(u32) (g_TestStep % 3))
        g_CountCombo.selectItem(cast(u32) ((g_TestStep / 3) % 3))
    }

    if g_TestFrame >= 200 do
        Env.exit(0)
}

func onFrame(_app: *Application)
{
    updateTestMode()
}

#main
{
    initDemoData()

    let flags = SurfaceFlags.BigCaption | SurfaceFlags.MinimizeBtn | SurfaceFlags.CloseBtn | SurfaceFlags.Border
    g_Surface = try app.createSurface(100, 100, W - 46, H - 31, flags)
    g_Surface.setTitle("GUI4 property control inspector")
    g_Surface.setIcon(app.theme.getIcon24(ThemeIcons24.Options, 18))

    createRootView()
    createInspectorPage(g_PageView)
    updateHeader()
    applyTheme()

    app.sigFrame += &onFrame
    if Env.hasArg("swag.test") do
        app.maxRunFrame = 240

    g_Surface.show()
    app.run()
}
