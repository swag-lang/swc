using Core, Gui, Pixel

const W = 1320
const H = 940
const MaxPages = 5
const TestFramesPerPage = 35
const RootMargin = 24.0
const PageTop = 112.0
const PageBottomMargin = 58.0
const PanelGap = 24.0
const TopPanelHeight = 440.0
const MinBottomPanelHeight = 260.0
const ThemeButtonWidth = 152.0
const HeaderGap = 18.0

struct PagePanelLayout
{
    left:   Math.Rectangle
    right:  Math.Rectangle
    bottom: Math.Rectangle
}

var app: Application
var g_Surface: #null *Surface
var g_View: #null *Wnd
var g_Title: #null *Label
var g_SubTitle: #null *Label
var g_ThemeButton: #null *PushButton
var g_PageView: #null *Wnd
var g_Footer: #null *Label
var g_Page: s32
var g_TestFrame: s32
var g_DarkTheme: bool
var g_Color: Color = Argb.CornflowerBlue

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

func createCaption(parent: *Wnd, text: string, x, y, width: f32)
{
    let label = createText(parent, text, {x, y, width, 22})
    label.labelFlags.add(.LightText)
}

func getPagePanelLayout(parent: *Wnd)->PagePanelLayout
{
    let rect = parent.getClientRect()
    let width = Math.max(rect.width, 1.0)
    let height = Math.max(rect.height, TopPanelHeight + PanelGap + MinBottomPanelHeight)
    let halfWidth = (width - PanelGap) * 0.5
    let topHeight = Math.min(TopPanelHeight, Math.max(400.0, (height - PanelGap) * 0.62))
    let bottomY = topHeight + PanelGap
    let bottomHeight = Math.max(MinBottomPanelHeight, height - bottomY)

    var result: retval
    result.left = {0, 0, halfWidth, topHeight}
    result.right = {halfWidth + PanelGap, 0, width - halfWidth - PanelGap, topHeight}
    result.bottom = {0, bottomY, width, bottomHeight}
    return result
}

func pageTitle(page: s32)->string
{
    switch page
    {
    case 0:
        return "Composite"
    case 1:
        return "HSL modes"
    case 2:
        return "RGB modes"
    case 3:
        return "Palettes"
    case 4:
        return "Preview"
    }

    unreachable
}

func pageSubtitle(page: s32)->string
{
    switch page
    {
    case 0:
        return "ColorPickerCtrl variants, with and without alpha, plus shared quick palettes and a live preview."
    case 1:
        return "Low-level ColorPicker HSL planes and hue, saturation, lightness and alpha bars."
    case 2:
        return "RGB channel planes and red, green, blue sliders in horizontal and vertical forms."
    case 3:
        return "PalettePicker ramps for hue families, luminance, saturation, alpha and named color sets."
    case 4:
        return "Derived colors, contrast decisions, alpha compositing and selected-color rendering."
    }

    unreachable
}

func colorSummary()->String
{
    let hsl = g_Color.toHsl()
    return Format.toString("#%{X08}  A:% R:% G:% B:%  H:% S:% L:%", g_Color.argb, g_Color.a, g_Color.r, g_Color.g, g_Color.b, cast(s32) (hsl.h * 360), cast(s32) (hsl.s * 100), cast(s32) (hsl.l * 100))
}

func updateHeader()
{
    g_Title.setText(Format.toString("GUI5 color widgets - %", pageTitle(g_Page)))
    g_SubTitle.setText(pageSubtitle(g_Page))
    g_Footer.setText(Format.toString("F1 : next page (%/%). Selected %", g_Page + 1, MaxPages, colorSummary()))
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

func setSelectedColor(color: Color, source: string)
{
    g_Color = color
    updateHeader()
    if g_PageView do
        g_PageView.invalidate()
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
    var pal: retval
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
    picker.boxSize = 30
    picker.boxMargin = 6
    addPaletteColors(picker, makePickerPalette())
    picker.sigChanged += func|title, keepAlpha|(palette)
    {
        selectPaletteColor(palette, title, keepAlpha)
    }
    return picker
}

func createModePicker(parent: *Wnd, title: string, rect: Math.Rectangle, mode: ColorPickerMode)->*ColorPicker
{
    // Narrow pickers (vertical bars) still need a readable caption width.
    createCaption(parent, title, rect.x, rect.y - 28, Math.max(rect.width, 64.0))
    let picker = ColorPicker.create(parent, rect)
    picker.setMode(mode)
    picker.setColor(g_Color)
    picker.sigChanged += func(picker)
    {
        setSelectedColor(picker.getColor(), "ColorPicker")
    }
    return picker
}

func createPaletteRamp(parent: *Wnd, title: string, rect: Math.Rectangle, mode: s32, base: Color, keepAlpha = true)->*PalettePicker
{
    createCaption(parent, title, rect.x, rect.y - 28, rect.width)
    let picker = PalettePicker.create(parent, rect)
    picker.boxSize = 29
    picker.boxMargin = 5

    switch mode
    {
    case 0:
        picker.addHueColors(10, 0.86, 0.52)
        picker.addHueColors(10, 0.54, 0.36)
    case 1:
        picker.addLumColors(12, base)
        picker.addColor(Argb.Black)
        picker.addColor(Argb.White)
    case 2:
        picker.addSatColors(12, base)
        picker.addColor(base.getComplementary())
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

    picker.sigChanged += func|title, keepAlpha|(palette)
    {
        selectPaletteColor(palette, title, keepAlpha)
    }

    return picker
}

func drawWrappedText(painter: *Painter, rect: Math.Rectangle, text: string, font: *Font, color: Color, maxLines = 1'u32)
{
    var richText: RichString = text
    var format: RichStringFormat
    format.flags = .WordWrap | .Clip
    format.font.regular = font
    format.palette[0] = color
    format.maxLines = maxLines
    painter.drawRichString(rect, &richText, format)
}

func drawSwatch(painter: *Painter, rect: Math.Rectangle, label: string, color: Color, font: *Font, colors: *ThemeColors)
{
    if color.a != 255 do
        painter.fillRoundRect(rect, 10, 10, Brush.createHatch(.CheckBoardLarge, colors.colorPicker_BackAlpha))
    painter.fillRoundRect(rect, 10, 10, color)
    painter.drawRoundRect(rect, 10, 10, Color.fromArgb(84'u8, Argb.Black), 1)
    painter.drawString(rect.x, rect.bottom() + 8, label, font, colors.label_TextLight)
}

func drawLiveCard(painter: *Painter, rect: Math.Rectangle, colors: *ThemeColors)
{
    let titleFont = g_View.getTheme().createDefaultFont(24, .Bold)
    let bodyFont = g_View.getTheme().createDefaultFont(14)
    let textColor = g_Color.getContrasting()
    let accent = g_Color.getComplementary()

    painter.fillRoundRect(rect, 22, 22, Brush.createHatch(.CheckBoardLarge, colors.colorPicker_BackAlpha))
    painter.fillRoundRect(rect, 22, 22, g_Color)
    painter.drawRoundRect(rect, 22, 22, Color.fromArgb(96'u8, Argb.Black), 2)

    let tag = Math.Rectangle{rect.x + 24, rect.y + 24, 118, 32}
    painter.fillRoundRect(tag, 16, 16, accent.withAlpha(220'u8))
    painter.drawStringCenter(tag.horzCenter(), tag.vertCenter(), "accent", bodyFont, accent.getContrasting())

    painter.drawString(rect.x + 24, rect.y + 82, "Live swatch", titleFont, textColor)
    drawWrappedText(painter, {rect.x + 24, rect.y + 118, rect.width - 48, 48}, "Every picker and palette page feeds this shared selected color.", bodyFont, textColor.withAlpha(220'u8), 2)

    let lineY = rect.bottom() - 48
    painter.drawLine(rect.x + 24, lineY, rect.right() - 24, lineY, textColor.withAlpha(90'u8), 1)
    painter.drawString(rect.x + 24, lineY + 14, Format.toString("#%{X08}", g_Color.argb), bodyFont, textColor.withAlpha(225'u8))
}

// Lay labelled swatches in a single horizontal row that fits `rect`. Used by the
// short, wide bottom panels where a tall card would overlap or clip.
func drawColorRow(painter: *Painter, rect: Math.Rectangle, font: *Font, colors: *ThemeColors, names: Array'(string), cols: Array'Color)
{
    let n = Math.max(cast(f32) cols.count, 1.0)
    let pad = 16.0
    let sw = Math.max((rect.width - pad * (n + 1)) / n, 40.0)
    let sh = Math.max(rect.height - 34, 24.0)
    for c, i in cols
    {
        let x = rect.x + pad + cast(f32) i * (sw + pad)
        drawSwatch(painter, {x, rect.y + 6, sw, sh}, names[i], c, font, colors)
    }
}

func onLivePreviewEvent(view: *Wnd, evt: IEvent)->bool
{
    switch evt
    {
    case PaintEvent as paintEvt:
        let painter = paintEvt.bc.painter
        let rect = view.getClientRect()
        let colors = view.getThemeColors()
        let font = view.getTheme().createDefaultFont(14)

        painter.fillRect(rect, colors.view_Bk)

        // Tall panel: full live card plus a derived-swatch row. Short/wide panel:
        // a single fitted swatch row (the card needs room it does not have here).
        if rect.height >= 300
        {
            let card = Math.Rectangle{24, 24, Math.max(rect.width - 48, 1.0), Math.max(rect.height - 116, 120.0)}
            drawLiveCard(painter, card, colors)

            let y = card.bottom() + 28
            let width = Math.max((rect.width - 96) / 4, 70.0)
            drawSwatch(painter, {24, y, width, 40}, "lighter", Color.getLighter(g_Color, 0.34), font, colors)
            drawSwatch(painter, {24 + width + 16, y, width, 40}, "darker", Color.getDarker(g_Color, 0.34), font, colors)
            drawSwatch(painter, {24 + (width + 16) * 2, y, width, 40}, "complement", g_Color.getComplementary(), font, colors)
            drawSwatch(painter, {24 + (width + 16) * 3, y, width, 40}, "muted", g_Color.adjustSaturation(-0.55), font, colors)
        }
        else
        {
            var names: Array'(string)
            var cols:  Array'Color
            names.add("selected");   cols.add(g_Color)
            names.add("lighter");    cols.add(Color.getLighter(g_Color, 0.34))
            names.add("darker");     cols.add(Color.getDarker(g_Color, 0.34))
            names.add("complement"); cols.add(g_Color.getComplementary())
            names.add("muted");      cols.add(g_Color.adjustSaturation(-0.55))
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
        let painter = paintEvt.bc.painter
        let rect = view.getClientRect()
        let colors = view.getThemeColors()
        let font = view.getTheme().createDefaultFont(14)

        painter.fillRect(rect, colors.view_Bk)

        var names: Array'(string)
        var cols:  Array'Color
        names.add("selected");   cols.add(g_Color)
        names.add("analog -30"); cols.add(g_Color.rotateHue(-30))
        names.add("analog +30"); cols.add(g_Color.rotateHue(30))
        names.add("triad +120"); cols.add(g_Color.rotateHue(120))
        names.add("triad -120"); cols.add(g_Color.rotateHue(-120))
        names.add("gray");       cols.add(g_Color.getGrayscale())

        // Two rows of three when there is height for it, otherwise a single fitted
        // row so the bottom row is never clipped.
        if rect.height >= 220
        {
            let pad = 16.0
            let cellW = Math.max((rect.width - pad * 4) / 3, 88.0)
            let cellH = Math.max((rect.height - pad * 3 - 48) / 2, 50.0)
            for c, i in cols
            {
                let col = cast(f32) (i % 3)
                let row = cast(f32) (i / 3)
                let x = rect.x + pad + col * (cellW + pad)
                let y = rect.y + pad + row * (cellH + 24 + pad)
                drawSwatch(painter, {x, y, cellW, cellH}, names[i], c, font, colors)
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
        let painter = paintEvt.bc.painter
        let rect = view.getClientRect()
        let colors = view.getThemeColors()
        let font = view.getTheme().createDefaultFont(14)
        let titleFont = view.getTheme().createDefaultFont(18, .Bold)

        painter.fillRect(rect, colors.view_Bk)

        let left = Math.Rectangle{24, 28, Math.max((rect.width - 72) * 0.5, 120.0), Math.max(rect.height - 56, 80.0)}
        let right = Math.Rectangle{left.right() + 24, 28, left.width, left.height}
        let text = g_Color.getContrasting()

        // Fit the body text to whatever height the card actually has.
        let bodyTop = 50.0
        let lines = cast(u32) Math.max((left.height - bodyTop) / 18.0, 1.0)

        painter.fillRoundRect(left, 18, 18, g_Color)
        painter.drawRoundRect(left, 18, 18, Color.fromArgb(80'u8, Argb.Black), 1)
        painter.drawString(left.x + 24, left.y + 20, "Contrast pick", titleFont, text)
        drawWrappedText(painter, {left.x + 24, left.y + bodyTop, left.width - 48, left.height - bodyTop - 12}, "Foreground uses Color.getContrasting() on the selected color.", font, text.withAlpha(220'u8), lines)

        painter.fillRoundRect(right, 18, 18, Brush.createHatch(.CheckBoardLarge, colors.colorPicker_BackAlpha))
        painter.fillRoundRect(right, 18, 18, g_Color.withAlpha(145'u8))
        painter.drawRoundRect(right, 18, 18, Color.fromArgb(80'u8, Argb.Black), 1)
        painter.drawString(right.x + 24, right.y + 20, "Alpha sample", titleFont, text)
        drawWrappedText(painter, {right.x + 24, right.y + bodyTop, right.width - 48, right.height - bodyTop - 12}, "The checkerboard makes semi-transparent selections visible.", font, text.withAlpha(220'u8), lines)
    }

    return false
}

func createPreview(parent: *Wnd, rect: Math.Rectangle, hook: func(view: *Wnd, evt: IEvent)->bool)->*Wnd
{
    let view = Wnd.create'Wnd(parent, rect)
    view.hookOnEvent = hook
    return view
}

func clearPage()
{
    for child in g_PageView.childs do
        child.destroy()
}

func buildPage()
{
    clearPage()
    updateHeader()

    switch g_Page
    {
    case 0:
        createCompositePage(assume g_PageView)
    case 1:
        createHslModesPage(assume g_PageView)
    case 2:
        createRgbModesPage(assume g_PageView)
    case 3:
        createPalettesPage(assume g_PageView)
    case 4:
        createPreviewPage(assume g_PageView)
    default:
        unreachable
    }

    g_PageView.invalidate()
}

func layoutRootView()
{
    if !g_View or !g_PageView do
        return

    let rect = g_View.getClientRect()
    let contentWidth = Math.max(rect.width - 2 * RootMargin, 1.0)
    let pageHeight = Math.max(rect.height - PageTop - PageBottomMargin, TopPanelHeight + PanelGap + MinBottomPanelHeight)
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
    if evt is ResizeEvent
    {
        layoutRootView()
        buildPage()
    }
    elif evt is DestroyEvent
    {
        app.sigFrame.disable()
        g_Surface = null
        g_View = null
        g_Title = null
        g_SubTitle = null
        g_ThemeButton = null
        g_PageView = null
        g_Footer = null
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

    updateTestMode()
}

func createRootView()
{
    g_View = g_Surface.getView()
    g_View.backgroundStyle = .View

    g_Title = Label.create(assume g_View, "", {})
    setLabelTextStyle(assume g_Title, .Left, .Center)
    g_Title.style.setFont(g_View.getTheme().createDefaultFont(28), .Regular)

    g_SubTitle = Label.create(assume g_View, "", {}, null, .WordWrap | .LightText)
    setLabelTextStyle(assume g_SubTitle, .Left, .Top)

    g_ThemeButton = PushButton.create(assume g_View, "", {})
    g_ThemeButton.form = .Flat
    g_ThemeButton.icon = app.theme.getIcon24(ThemeIcons24.Picker, 18)
    g_ThemeButton.sigPressed += &toggleTheme

    g_PageView = Wnd.create'Wnd(assume g_View, {})
    g_PageView.backgroundStyle = .Transparent

    g_Footer = Label.create(assume g_View, "", {})
    setLabelTextStyle(assume g_Footer, .Left, .Center)
    g_Footer.labelFlags.add(.LightText)

    layoutRootView()
    g_View.hookOnEvent = &onRootEvent
}

#main
{
    let flags = SurfaceFlags.BigCaption | SurfaceFlags.MinimizeBtn | SurfaceFlags.CloseBtn | SurfaceFlags.Border
    g_Surface = try app.createSurface(100, 50, W - 46, H - 31, flags)
    g_Surface.setTitle("GUI5 color widgets")
    g_Surface.setIcon(app.theme.getIcon24(ThemeIcons24.Picker, 18))

    createRootView()
    buildPage()

    app.sigFrame += &onFrame
    if Env.hasArg("swag.test") do
        app.maxRunFrame = cast(u32) MaxPages * cast(u32) TestFramesPerPage + 10

    g_Surface.show()
    applyTheme()
    app.run()
}
