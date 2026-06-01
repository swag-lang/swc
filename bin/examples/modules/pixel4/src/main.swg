using Core, Pixel, Win32

const W = 980
const H = 720
const MaxPages = 5

const FixedWindowStyle = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_CLIPSIBLINGS | WS_CLIPCHILDREN

var g_Window:        Env.Window
var g_Renderer:      Pixel.RenderOgl
var g_Painter:       Pixel.Painter
var g_RC:            Pixel.RenderingContext
var g_Keyboard:      Input.Keyboard

var g_FontBytes:     Array'u8
var g_TypeFace:      *Pixel.TypeFace
var g_TitleFont:     *Pixel.Font
var g_SubTitleFont:  *Pixel.Font
var g_LabelFont:     *Pixel.Font
var g_HelpFont:      *Pixel.Font
var g_FillTexture:   Texture
var g_TileTexture:   Texture

var g_Page:          s32
var g_TestFrame:     s32

func fontPath(fileName: string, loc = #callerlocation)->String
{
    let srcPath = Path.getDirectoryName(loc.fileName)
    return Path.combine(Path.combine(srcPath, "data"), fileName)
}

func loadFonts() throw
{
    let path = fontPath("segoeui.ttf")
    g_FontBytes    = File.readAllBytes(path)
    g_TypeFace     = TypeFace.create(path, g_FontBytes.toSlice())
    g_TitleFont    = Font.create(g_TypeFace, 34)
    g_SubTitleFont = Font.create(g_TypeFace, 18)
    g_LabelFont    = Font.create(g_TypeFace, 16)
    g_HelpFont     = Font.create(g_TypeFace, 14)
}

func buildFillBrushImage()->Image
{
    var img = Image.create(96, 96, .RGBA8)
    img.fillGradient4(
        Color.fromArgb(255, 251, 208, 150),
        Color.fromArgb(255, 238, 144, 96),
        Color.fromArgb(255, 84, 182, 214),
        Color.fromArgb(255, 38, 89, 160))
    img.visitPixels()
    {
        let diag0 = (x + y) % 18
        let diag1 = (x - y + image.width * 2) % 24
        if diag0 < 3 or diag1 < 3
        {
            pix[0] = cast(u8) Math.min(cast(s32) pix[0] + 22, 255)
            pix[1] = cast(u8) Math.min(cast(s32) pix[1] + 18, 255)
            pix[2] = cast(u8) Math.min(cast(s32) pix[2] + 28, 255)
        }
    }

    return img
}

func buildTileBrushImage()->Image
{
    var img = Image.create(48, 48, .RGBA8)
    img.fillGradient4(
        Color.fromArgb(255, 250, 244, 214),
        Color.fromArgb(255, 248, 215, 122),
        Color.fromArgb(255, 242, 190, 74),
        Color.fromArgb(255, 219, 128, 54))
    img.visitPixels()
    {
        if ((x / 12 + y / 12) & 1) == 0
        {
            pix[0] = 255
            pix[1] = 241
            pix[2] = 198
        }

        if x % 12 == 0 or y % 12 == 0
        {
            pix[0] = 112
            pix[1] = 66
            pix[2] = 34
        }

        if (x + y) % 12 == 0
        {
            pix[0] = 182
            pix[1] = 95
            pix[2] = 46
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

func insetRect(rect: Math.Rectangle, left, top, right, bottom: f32)->Math.Rectangle
{
    var result = rect
    result.x += left
    result.y += top
    result.width -= left + right
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
    painter.drawString(28, 22, title, g_TitleFont, Argb.MidnightBlue)
    painter.drawString(30, 64, subtitle, g_SubTitleFont, Argb.DimGray)
}

func drawFooter(painter: *Pixel.Painter)
{
    let pageText = Format.toString("F1 : next page (%/%). Pages : caps, joins, transparency, polygons, brushes.", g_Page + 1, MaxPages)
    painter.drawString(28, H - 26, pageText, g_HelpFont, Argb.DimGray)
}

func drawPanel(painter: *Pixel.Painter, rect: Math.Rectangle, title, subtitle: string)->Math.Rectangle
{
    painter.fillRoundRect(rect.x, rect.y, rect.width, rect.height, 18, 18, Argb.White)
    painter.drawRoundRect(rect.x, rect.y, rect.width, rect.height, 18, 18, Color.fromArgb(96, Argb.SlateGray), 2)
    painter.drawString(rect.x + 18, rect.y + 12, title, g_SubTitleFont, Argb.DarkSlateBlue)
    painter.drawString(rect.x + 18, rect.y + 36, subtitle, g_HelpFont, Argb.Gray)
    return insetRect(rect, 18, 62, 18, 18)
}

func drawClosedOutline(painter: *Pixel.Painter, points: [..] Math.Vector2, pen: Pen)
{
    if @countof(points) < 2 do
        return

    var path: LinePath
    path.start(points[0].x, points[0].y)
    foreach pt in points where @index do
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
    let cx = rect.x + rect.width * 0.50
    let cy = rect.y + rect.height * 0.52

    path.start(cx - 168, cy - 18)
    path.bezierTo(cx - 44, cy - 136, cx - 160, cy - 110, cx - 102, cy - 150)
    path.bezierTo(cx + 156, cy - 24, cx + 30, cy - 116, cx + 152, cy - 98)
    path.bezierTo(cx + 40, cy + 134, cx + 168, cy + 52, cx + 110, cy + 154)
    path.bezierTo(cx - 168, cy - 18, cx - 28, cy + 146, cx - 160, cy + 94)
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

    // Exercise every page in automated example tests without user input.
    if Env.hasArg("swag.test")
    {
        g_TestFrame += 1
        if g_TestFrame % 30 == 0 do
            nextPage()
    }
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

    g_Window.callbacks.onResize = &onResize
    try g_Window.show()

    var loop: Env.WindowLoop
    while loop.next()
    {
        updateShortcuts()
        display()
    }

    g_Renderer.native.dropContext(g_RC)
}
