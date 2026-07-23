using Core, Pixel, Win32

const W                 = 980
const H                 = 720
const MaxPages          = 11
const TestFramesPerPage = 30
const PanelHeaderHeight = 76.0

const FixedWindowStyle = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_CLIPSIBLINGS | WS_CLIPCHILDREN

var g_Window:   Env.Window
var g_Renderer: Pixel.RenderOgl
var g_Painter:  Pixel.Painter
var g_RC:       Pixel.RenderingContext
var g_Keyboard: Input.Keyboard

var g_FontPath:     String
var g_FontBytes:    Array'u8
var g_TypeFace:     #null *Pixel.TypeFace
var g_TitleFont:    #null *Pixel.Font
var g_OutlineFont:  #null *Pixel.Font
var g_SubTitleFont: #null *Pixel.Font
var g_LabelFont:    #null *Pixel.Font
var g_HelpFont:     #null *Pixel.Font
var g_FillTexture:  Texture
var g_TileTexture:  Texture
var g_OutlineText:  LinePathList

var g_Page:      s32
var g_TestFrame: s32

func fontPath(fileName: string, loc = #callerlocation)->String
{
    let srcPath = Path.getDirectoryName(loc.fileName)
    return Path.combine(Path.combine(srcPath, "data"), fileName)
}

func loadFonts() throw
{
    g_FontPath = fontPath("segoeui.ttf")
    let path   = g_FontPath.toString()
    g_FontBytes    = File.readAllBytes(path)
    g_TypeFace     = TypeFace.create(path, g_FontBytes.toSlice())
    g_TitleFont    = Font.create(notnull g_TypeFace, 34)
    g_OutlineFont  = Font.create(notnull g_TypeFace, 84)
    g_SubTitleFont = Font.create(notnull g_TypeFace, 18)
    g_LabelFont    = Font.create(notnull g_TypeFace, 16)
    g_HelpFont     = Font.create(notnull g_TypeFace, 14)
}

func buildFillBrushImage()->Image
{
    var img = Image.create(96, 96, .RGBA8)
    for y in img.height
    {
        var pix = img.pixels.buffer + y * img.width8
        for x in img.width
        {
            if ((x / 12 + y / 12) & 1) == 0
            {
                pix[0] = 255
                pix[1] = 182
                pix[2] = 76
                pix[3] = 255
            }
            else
            {
                pix[0] = 34
                pix[1] = 122
                pix[2] = 255
                pix[3] = 255
            }

            if (x - y + img.width * 2) % 24 < 4
            {
                pix[0] = 255
                pix[1] = 248
                pix[2] = 228
            }

            pix += img.bpp8
        }
    }

    return img
}

func buildTileBrushImage()->Image
{
    var img = Image.create(48, 48, .RGBA8)
    for y in img.height
    {
        var pix = img.pixels.buffer + y * img.width8
        for x in img.width
        {
            if ((x / 8 + y / 8) & 1) == 0
            {
                pix[0] = 252
                pix[1] = 238
                pix[2] = 193
                pix[3] = 255
            }
            else
            {
                pix[0] = 120
                pix[1] = 64
                pix[2] = 40
                pix[3] = 255
            }

            if x % 8 == 0 or y % 8 == 0
            {
                pix[0] = 26
                pix[1] = 26
                pix[2] = 26
            }

            pix += img.bpp8
        }
    }

    return img
}

func loadBrushTextures()
{
    // Keep the showcase self-contained by generating brush textures on the fly.
    g_FillTexture = g_Renderer.addImage(buildFillBrushImage())
    g_TileTexture = g_Renderer.addImage(buildTileBrushImage())
}

func loadTextShowcase()
{
    assume g_TypeFace.getStringOutline(&g_OutlineText, "PIXEL", 84)
}

func insetRect(rect: Math.Rectangle, left, top, right, bottom: f32)->Math.Rectangle
{
    var result = rect
    result.x      += left
    result.y      += top
    result.width  -= left + right
    result.height -= top + bottom
    return result
}

func nextPage()
{
    g_Page = (g_Page + 1) % MaxPages
}

func isAnchorCap(cap: LineCapStyle)->bool
{
    return cap == .ArrowAnchor or cap == .ArrowAnchor2 or cap == .SquareAnchor or cap == .RoundAnchor
}

func drawPageHeader(painter: *Pixel.Painter, title, subtitle: string)
{
    painter.drawString(28, 22, title, notnull g_TitleFont, Argb.MidnightBlue)
    drawWrappedText(painter, {30, 62, W - 60, 38}, subtitle, notnull g_SubTitleFont, Argb.DimGray)
}

func drawFooter(painter: *Pixel.Painter)
{
    let pageText = Format.toString("F1 : next page (%/%). Pages : caps, joins, transparency, polygons, brushes, gradients, text, compositing, render targets, text effects, layers.", g_Page + 1, MaxPages)
    painter.drawString(28, H - 26, pageText, notnull g_HelpFont, Argb.DimGray)
}

func drawPanel(painter: *Pixel.Painter, rect: Math.Rectangle, title, subtitle: string)->Math.Rectangle
{
    painter.fillRoundRect(rect.x, rect.y, rect.width, rect.height, 18, 18, Argb.White)
    painter.drawRoundRect(rect.x, rect.y, rect.width, rect.height, 18, 18, Color.fromArgb(96, Argb.SlateGray), 2)
    painter.drawString(rect.x + 18, rect.y + 12, title, notnull g_SubTitleFont, Argb.DarkSlateBlue)
    drawWrappedText(painter, {rect.x + 18, rect.y + 36, rect.width - 36, PanelHeaderHeight - 40}, subtitle, notnull g_HelpFont, Argb.Gray)
    return insetRect(rect, 18, PanelHeaderHeight, 18, 18)
}

func drawWrappedText(painter: *Pixel.Painter, rect: Math.Rectangle, text: string, font: *Pixel.Font, color: Color)
{
    var richText: RichString = text
    var format:   RichStringFormat
    format.font.regular = font
    format.palette[0]   = color
    format.lineGap      = 0
    format.flags        = .WordWrap | .Clip
    painter.drawRichString(rect, &richText, format)
}

func drawClosedOutline(painter: *Pixel.Painter, points: [..] Math.Vector2, pen: Pen)
{
    if @countof(points) < 2 do
        return

    var path: LinePath
    path.start(points[0].x, points[0].y)
    for pt in points where @index do
        path.lineTo(pt.x, pt.y)
    path.close()
    painter.drawPath(&path, pen)
}

func makeStarPolygon(cx, cy, outer, inner: f32, branches: s32)->Array'Math.Vector2
{
    var result: retval
    let total = branches * 2
    for i in total
    {
        var radius = inner
        if (i & 1) == 0 do
            radius = outer
        let angle = -Math.ConstF32.Pi * 0.5 + cast(f32) i * (Math.ConstF32.TwoPi / cast(f32) total)
        result.add(Math.Vector2{cx + Math.cos(angle) * radius, cy + Math.sin(angle) * radius})
    }

    return result
}

func makeHexPolygon(cx, cy, radius: f32)->Array'Math.Vector2
{
    var result: retval
    for i in 6
    {
        let angle = Math.ConstF32.Pi / 6 + cast(f32) i * (Math.ConstF32.TwoPi / 6)
        result.add(Math.Vector2{cx + Math.cos(angle) * radius, cy + Math.sin(angle) * radius})
    }

    return result
}

func makeArrowPolygon(rect: Math.Rectangle)->Array'Math.Vector2
{
    var result: retval
    let left   = rect.x + 22
    let top    = rect.y + 26
    let right  = rect.right() - 26
    let bottom = rect.bottom() - 24
    let midY   = rect.vertCenter()
    let stemX  = left + rect.width * 0.42

    result.add(Math.Vector2{left, midY - 34})
    result.add(Math.Vector2{stemX, midY - 34})
    result.add(Math.Vector2{stemX, top})
    result.add(Math.Vector2{right, midY})
    result.add(Math.Vector2{stemX, bottom})
    result.add(Math.Vector2{stemX, midY + 34})
    result.add(Math.Vector2{left, midY + 34})
    result.add(Math.Vector2{left + 28, midY})
    return result
}

func makeTransparencyPath(rect: Math.Rectangle, variant: s32)->LinePath
{
    var path: retval
    let left  = rect.x
    let top   = rect.y
    let right = rect.right()
    let bot   = rect.bottom()

    switch variant
    {
    case 0:
        path.start(left + 34, bot - 74)
        path.lineTo(left + rect.width * 0.20, top + 38)
        path.lineTo(left + rect.width * 0.44, bot - 28)
        path.lineTo(left + rect.width * 0.68, top + 54)
        path.lineTo(right - 36, top + rect.height * 0.45)

    case 1:
        path.start(left + 90, top + 52)
        path.lineTo(left + rect.width * 0.32, bot - 52)
        path.lineTo(left + rect.width * 0.54, top + 92)
        path.lineTo(left + rect.width * 0.76, bot - 70)
        path.lineTo(right - 86, top + 58)

    case 2:
        path.start(left + 48, top + rect.height * 0.48)
        path.lineTo(left + rect.width * 0.24, top + 26)
        path.lineTo(left + rect.width * 0.48, bot - 16)
        path.lineTo(left + rect.width * 0.74, top + 84)
        path.lineTo(right - 44, bot - 86)
    }

    return path
}

func makeBlobPath(rect: Math.Rectangle)->LinePath
{
    var path: retval
    let left  = rect.x
    let top   = rect.y
    let width = rect.width
    let height = rect.height

    path.start(left + width * 0.311, top + height * 0.464)
    path.bezierTo(left + width * 0.450, top + height * 0.100, left + width * 0.320, top + height * 0.180, left + width * 0.385, top + height * 0.057)
    path.bezierTo(left + width * 0.676, top + height * 0.446, left + width * 0.534, top + height * 0.162, left + width * 0.671, top + height * 0.218)
    path.bezierTo(left + width * 0.545, top + height * 0.933, left + width * 0.689, top + height * 0.680, left + width * 0.624, top + height * 0.995)
    path.bezierTo(left + width * 0.311, top + height * 0.464, left + width * 0.468, top + height * 0.971, left + width * 0.320, top + height * 0.810)
    path.close()
    return path
}

func drawScene(painter: *Pixel.Painter)
{
    painter.clear(Argb.WhiteSmoke)
    painter.setParams(.Antialiased)

    switch g_Page
    {
    case 0:
        drawCapsPage(painter)
    case 1:
        drawJoinsPage(painter)
    case 2:
        drawTransparencyPage(painter)
    case 3:
        drawPolygonsPage(painter)
    case 4:
        drawBrushesPage(painter)
    case 5:
        drawGradientsPage(painter)
    case 6:
        drawTextPage(painter)
    case 7:
        drawCompositingPage(painter)
    case 8:
        drawRenderTargetPage(painter)
    case 9:
        drawTextEffectsPage(painter)
    case 10:
        drawLayerPipelinePage(painter)
    default:
        unreachable
    }

    drawFooter(painter)
}

func display()
{
    g_Renderer.begin(g_RC)
    g_Painter.begin()
    drawScene(&g_Painter)
    g_Painter.end()
    g_Renderer.draw(&g_Painter)
    g_Renderer.end()
}

func onResize(_window: *Env.Window, width, height: s32)
{
    g_RC.width  = width
    g_RC.height = height
}

func updateShortcuts()
{
    g_Keyboard.update()
    if g_Keyboard.isKeyJustPressed(Input.Key.F1) do
        nextPage()
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

#main
{
    try Env.createWindow(&g_Window, {className: "PIXEL4_CLASS_NAME", title: "Pixel path and brush drawing showcase", width: W, height: H, style: FixedWindowStyle})
    try g_Window.setClientSize(W, H)
    g_RC = try g_Renderer.native.createContext(&g_Window, W, H)
    g_Renderer.setCurrentContext(g_RC)
    g_Renderer.init()

    try loadFonts()
    loadBrushTextures()
    loadTextShowcase()

    g_Window.callbacks.onResize = &onResize
    try g_Window.show()

    var loop: Env.WindowLoop
    if Env.hasArg("swag.test") do
        loop.maxTestFrames = cast(u32) MaxPages * cast(u32) TestFramesPerPage
    while loop.next()
    {
        updateShortcuts()
        display()
        updateTestMode()
    }

    g_Renderer.native.dropContext(g_RC)
}
