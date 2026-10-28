// GUI5 - the colour widgets.
//
// `ColorPickerCtrl`, the planes and bars of `ColorPicker`, and `PalettePicker` all write one
// selected colour, which the previews derive from and the hint line reads out in mono. The pages
// are text tabs under the title; `Ctrl K` opens the lens, which reaches every page and the
// appearance. `--light` opens the window on Papier, `--page=N` on page N.

using Core, Gui, Pixel

const W        = 1240
const H        = 920
const MaxPages = 5
const TestFramesPerPage = 35

// The page keeps reading margins at its sides, and each section keeps one inset for its label, its
// sentence and its controls, so the section labels stand on the left edge of the title.
const PageMargin      = 48.0
const SectionInset    = 24.0
const SectionGap      = 24.0
const TitleSize       = 34'u32
const TopHeight       = 424.0
const MinBottomHeight = 200.0

const CmdLens         = "gui5.lens"
const CmdNextPage     = "gui5.page.next"
const CmdPreviousPage = "gui5.page.previous"

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
var g_Hint:       *HintLine?
var g_Color:      Color = Argb.CornflowerBlue
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

func colorSummary()->String
{
    let hsl = g_Color.toHsl()
    return Format.toString("#%{X08}  A:% R:% G:% B:%  H:% S:% L:%",
                           g_Color.argb,
                           g_Color.a,
                           g_Color.r,
                           g_Color.g,
                           g_Color.b,
                           cast(s32, (hsl.h * 360)),
                           cast(s32, (hsl.s * 100)),
                           cast(s32, (hsl.l * 100)))
}

func setSelectedColor(color: Color, _: string)
{
    g_Color = color
    g_Hint?.setReading(colorSummary())
    g_PageView?.invalidate()
    app.invalidate()
}

func selectPaletteColor(palette: *PalettePicker, source: string, keepAlpha = true)
{
    var color = palette.selectedColor
    if keepAlpha and color.a and g_Color.a do
        color.a = g_Color.a
    setSelectedColor(color, source)
}

func makePickerPalette()->Array'Color
{
    var pal: #returntype
    pal.add(Argb.CornflowerBlue)
    pal.add(Argb.DeepSkyBlue)
    pal.add(Argb.MediumSeaGreen)
    pal.add(Argb.Goldenrod)
    pal.add(Argb.Tomato)
    pal.add(Argb.Crimson)
    pal.add(Argb.MediumPurple)
    pal.add(Argb.DarkSlateGray)
    pal.add(Color.fromArgb(128'u8, Argb.DeepSkyBlue))
    return pal
}

func addPaletteColors(picker: *PalettePicker, colors: Array'Color)
{
    for color in colors do
        picker.addColor(color)
}

func createQuickPalette(parent: *Wnd, rect: Math.Rectangle, title: string, keepAlpha = true)->*PalettePicker
{
    createCaption(parent, title, rect.x, rect.y - 28, rect.width)
    let picker = PalettePicker.create(parent, rect)
    picker.setItemMetrics(30, 6)
    addPaletteColors(picker, makePickerPalette())
    picker.sigSelectionChanged += func|title, keepAlpha|(palette) { selectPaletteColor(palette, title, keepAlpha) }
    return picker
}

func createModePicker(parent: *Wnd, title: string, rect: Math.Rectangle, mode: ColorPickerMode)->*ColorPicker
{
    // Narrow pickers (vertical bars) still need a readable caption width.
    createCaption(parent, title, rect.x, rect.y - 28, Math.max(rect.width, 64.0))
    let picker = ColorPicker.create(parent, rect)
    picker.setMode(mode)
    picker.setColor(g_Color)
    picker.sigColorChanged += func(picker) { setSelectedColor(picker.color(), "ColorPicker") }
    return picker
}

func createPaletteRamp(parent: *Wnd, title: string, rect: Math.Rectangle, mode: s32, base: Color, keepAlpha = true)->*PalettePicker
{
    createCaption(parent, title, rect.x, rect.y - 28, rect.width)
    let picker = PalettePicker.create(parent, rect)
    picker.setItemMetrics(29, 5)

    switch mode
    {
    case 0:
        picker.addHueRamp(10, 0.86, 0.52)
        picker.addHueRamp(10, 0.54, 0.36)

    case 1:
        picker.addLightnessRamp(12, base)
        picker.addColor(Argb.Black)
        picker.addColor(Argb.White)

    case 2:
        picker.addSaturationRamp(12, base)
        picker.addColor(base.complementary())
        picker.addColor(base.adjustSaturation(-0.70))

    case 3:
        picker.addColor(base.withAlpha(20'u8))
        picker.addColor(base.withAlpha(48'u8))
        picker.addColor(base.withAlpha(84'u8))
        picker.addColor(base.withAlpha(128'u8))
        picker.addColor(base.withAlpha(180'u8))
        picker.addColor(base.withAlpha(230'u8))
        picker.addColor(base.withAlpha(255'u8))
    }

    picker.sigSelectionChanged += func|title, keepAlpha|(palette) { selectPaletteColor(palette, title, keepAlpha) }

    return picker
}

func drawWrappedText(painter: *Painter, rect: Math.Rectangle, text: string, font: *Font, color: Color, maxLines = 1'u32)
{
    var richText: RichString = text
    var format:   RichStringFormat
    format.flags        = .WordWrap | .Clip
    format.font.regular = font
    format.palette[0]   = color
    format.maxLines     = maxLines
    painter.drawRichString(rect, &richText, format)
}

// Draws a swatch on the chip corner with its hairline ring, and its name under it in the faint ink.
func drawSwatch(painter: *Painter, rect: Math.Rectangle, label: string, color: Color, font: *Font, colors: *ThemeColors)
{
    let corner = g_View!.themeMetrics().corner_Chip
    if color.a != 255 do
        painter.fillRoundRect(rect, corner, corner, Brush.createHatch(.CheckBoardLarge, colors.colorPicker_BackAlpha))
    painter.fillRoundRect(rect, corner, corner, color)
    painter.drawRoundRect(rect, corner, corner, colors.line, 1)
    painter.drawString(rect.x, rect.bottom() + 8, label, font, colors.faintText)
}

func drawLiveCard(painter: *Painter, rect: Math.Rectangle, colors: *ThemeColors)
{
    let view      = unwrap g_View
    let corner    = view.themeMetrics().corner_Floating
    let chip      = view.themeMetrics().corner_Chip
    let titleFont = view.theme().createDefaultFont(24, .Bold)
    let bodyFont  = view.theme().createDefaultFont(14)
    let textColor = g_Color.contrasting()
    let accent    = g_Color.complementary()

    painter.fillRoundRect(rect, corner, corner, Brush.createHatch(.CheckBoardLarge, colors.colorPicker_BackAlpha))
    painter.fillRoundRect(rect, corner, corner, g_Color)
    painter.drawRoundRect(rect, corner, corner, colors.line, 1)

    let tag = Math.Rectangle{rect.x + 24, rect.y + 24, 118, 32}
    painter.fillRoundRect(tag, chip, chip, accent.withAlpha(220'u8))
    painter.drawStringCenter(tag.horzCenter(), tag.vertCenter(), "accent", bodyFont, accent.contrasting())

    painter.drawString(rect.x + 24, rect.y + 82, "Live swatch", titleFont, textColor)
    drawWrappedText(painter,
                    Math.Rectangle{rect.x + 24, rect.y + 118, rect.width - 48, 48},
                    "Every picker and palette page feeds this shared selected color.",
                    bodyFont,
                    textColor.withAlpha(220'u8),
                    2)

    let lineY = rect.bottom() - 48
    painter.drawLine(rect.x + 24, lineY, rect.right() - 24, lineY, textColor.withAlpha(90'u8), 1)
    painter.drawString(rect.x + 24, lineY + 14, Format.toString("#%{X08}", g_Color.argb), bodyFont, textColor.withAlpha(225'u8))
}

// Lay labelled swatches in a single horizontal row that fits `rect`. Used by the
// short, wide bottom panels where a tall card would overlap or clip.
func drawColorRow(painter: *Painter, rect: Math.Rectangle, font: *Font, colors: *ThemeColors, names: Array'(string), cols: Array'Color)
{
    let n   = Math.max(cast(f32, cols.count), 1.0)
    let pad = 16.0
    let sw  = Math.max((rect.width - pad * (n + 1)) / n, 40.0)
    let sh  = Math.max(rect.height - 34, 24.0)
    for c, i in cols
    {
        let x = rect.x + pad + cast(f32, i) * (sw + pad)
        drawSwatch(painter, Math.Rectangle{x, rect.y + 6, sw, sh}, names[i], c, font, colors)
    }
}

func onLivePreviewEvent(view: *Wnd, evt: IEvent)->bool
{
    switch evt
    {
    case PaintEvent as paintEvt:
        let painter = paintEvt.paintContext.painter
        let rect    = view.clientRect()
        let colors  = view.themeColors()
        let font    = view.theme().createDefaultFont(14)

        // Tall panel: full live card plus a derived-swatch row. Short/wide panel:
        // a single fitted swatch row (the card needs room it does not have here).
        if rect.height >= 300
        {
            let card = Math.Rectangle{24, 24, Math.max(rect.width - 48, 1.0), Math.max(rect.height - 116, 120.0)}
            drawLiveCard(painter, card, colors)

            let y     = card.bottom() + 28
            let width = Math.max((rect.width - 96) / 4, 70.0)
            drawSwatch(painter,
                       Math.Rectangle{24, y, width, 40},
                       "lighter",
                       Color.lighter(g_Color, 0.34),
                       font,
                       colors)
            drawSwatch(painter,
                       Math.Rectangle{24 + width + 16, y, width, 40},
                       "darker",
                       Color.darker(g_Color, 0.34),
                       font,
                       colors)
            drawSwatch(painter,
                       Math.Rectangle{24 + (width + 16) * 2, y, width, 40},
                       "complement",
                       g_Color.complementary(),
                       font,
                       colors)
            drawSwatch(painter,
                       Math.Rectangle{24 + (width + 16) * 3, y, width, 40},
                       "muted",
                       g_Color.adjustSaturation(-0.55),
                       font,
                       colors)
        }
        else
        {
            var names: Array'(string)
            var cols:  Array'Color
            names.add("selected")
            cols.add(g_Color)
            names.add("lighter")
            cols.add(Color.lighter(g_Color, 0.34))
            names.add("darker")
            cols.add(Color.darker(g_Color, 0.34))
            names.add("complement")
            cols.add(g_Color.complementary())
            names.add("muted")
            cols.add(g_Color.adjustSaturation(-0.55))
            drawColorRow(painter, rect, font, colors, names, cols)
        }
    }

    return false
}

func onDerivedPreviewEvent(view: *Wnd, evt: IEvent)->bool
{
    switch evt
    {
    case PaintEvent as paintEvt:
        let painter = paintEvt.paintContext.painter
        let rect    = view.clientRect()
        let colors  = view.themeColors()
        let font    = view.theme().createDefaultFont(14)

        var names: Array'(string)
        var cols:  Array'Color
        names.add("selected")
        cols.add(g_Color)
        names.add("analog -30")
        cols.add(g_Color.rotateHue(-30))
        names.add("analog +30")
        cols.add(g_Color.rotateHue(30))
        names.add("triad +120")
        cols.add(g_Color.rotateHue(120))
        names.add("triad -120")
        cols.add(g_Color.rotateHue(-120))
        names.add("gray")
        cols.add(g_Color.grayscale())

        // Two rows of three when there is height for it, otherwise a single fitted
        // row so the bottom row is never clipped.
        if rect.height >= 220
        {
            let pad   = 16.0
            let cellW = Math.max((rect.width - pad * 4) / 3, 88.0)
            let cellH = Math.max((rect.height - pad * 3 - 48) / 2, 50.0)
            for c, i in cols
            {
                let col = cast(f32, (i % 3))
                let row = cast(f32, (i / 3))
                let x   = rect.x + pad + col * (cellW + pad)
                let y   = rect.y + pad + row * (cellH + 24 + pad)
                drawSwatch(painter, Math.Rectangle{x, y, cellW, cellH}, names[i], c, font, colors)
            }
        }
        else
        {
            drawColorRow(painter, rect, font, colors, names, cols)
        }
    }

    return false
}

func onContrastPreviewEvent(view: *Wnd, evt: IEvent)->bool
{
    switch evt
    {
    case PaintEvent as paintEvt:
        let painter   = paintEvt.paintContext.painter
        let rect      = view.clientRect()
        let colors    = view.themeColors()
        let font      = view.theme().createDefaultFont(14)
        let titleFont = view.theme().createDefaultFont(18, .Bold)
        let corner    = view.themeMetrics().corner_Floating

        let left = Math.Rectangle{
            24,
            28,
            Math.max((rect.width - 72) * 0.5, 120.0),
            Math.max(rect.height - 56, 80.0)}
        let right = Math.Rectangle{left.right() + 24, 28, left.width, left.height}
        let text  = g_Color.contrasting()

        // Fit the body text to whatever height the card actually has.
        let bodyTop = 50.0
        let lines   = cast(u32, Math.max((left.height - bodyTop) / 18.0, 1.0))

        painter.fillRoundRect(left, corner, corner, g_Color)
        painter.drawRoundRect(left, corner, corner, colors.line, 1)
        painter.drawString(left.x + 24, left.y + 20, "Contrast pick", titleFont, text)
        drawWrappedText(painter,
                        Math.Rectangle{left.x + 24, left.y + bodyTop, left.width - 48, left.height - bodyTop - 12},
                        "Foreground uses Color.contrasting() on the selected color.",
                        font,
                        text.withAlpha(220'u8),
                        lines)

        painter.fillRoundRect(right, corner, corner, Brush.createHatch(.CheckBoardLarge, colors.colorPicker_BackAlpha))
        painter.fillRoundRect(right, corner, corner, g_Color.withAlpha(145'u8))
        painter.drawRoundRect(right, corner, corner, colors.line, 1)
        painter.drawString(right.x + 24, right.y + 20, "Alpha sample", titleFont, text)
        drawWrappedText(painter,
                        Math.Rectangle{right.x + 24, right.y + bodyTop, right.width - 48, right.height - bodyTop - 12},
                        "The checkerboard makes semi-transparent selections visible.",
                        font,
                        text.withAlpha(220'u8),
                        lines)
    }

    return false
}

// Creates a painted preview in `section`, on its inset from the line the controls start on.
func createPreview(section: *Wnd, hook: func(view: *Wnd, evt: IEvent)->bool)->*Wnd
{
    let rect = section.clientRect()
    let view = Wnd.create'Wnd(section, Math.Rectangle{SectionInset - 16, 80, rect.width - 2 * SectionInset + 32, Math.max(rect.height - 80, 1.0)})
    view.backgroundStyle = .Transparent
    view.hookOnEvent     = hook
    return view
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

const PageTitles = ["Composite", "HSL", "RGB", "Palettes", "Preview"]

func pageSubtitle(page: s32)->string
{
    switch page
    {
    case 0: return "ColorPickerCtrl with and without alpha, quick palettes, and a live preview of the selection."
    case 1: return "The HSL planes of ColorPicker, and its hue, saturation, lightness and alpha bars."
    case 2: return "RGB channel planes, and red, green and blue bars in both orientations."
    case 3: return "PalettePicker ramps for hue families, lightness, saturation and alpha, and designed sets."
    case 4: return "Derived colours, contrast decisions and alpha compositing of the selection."
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
    case 0:  createCompositePage(pageView)
    case 1:  createHslModesPage(pageView)
    case 2:  createRgbModesPage(pageView)
    case 3:  createPalettesPage(pageView)
    case 4:  createPreviewPage(pageView)
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

    case DestroyEvent:
        app.sigFrame.disable()
        g_Surface, g_View, g_Title, g_SubTitle, g_Tabs, g_PageView, g_Lens, g_Appearance, g_Hint = null
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

    updateTestMode()
}

func createRootView()
{
    let view = g_Surface!.view()
    g_View = view
    view.backgroundStyle = .Window

    with g_Title = Label.create(view, "Colours", {})
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
        .setReading(colorSummary())
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
    surface.setTitle("GUI5 Colours")
    surface.minSize = {1000, 760}

    readStartupSelection()
    createRootView()
    showPage(g_Page)

    app.sigFrame += &onFrame
    if Env.isSmokeRun() do
        app.maxRunFrame = cast(u32, 2 * MaxPages * TestFramesPerPage + 20)

    surface.show()
    app.run()
}
