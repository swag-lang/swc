using Core, Pixel, TrueType, Win32

const W = 800
const H = 480

const FixedWindowStyle = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_CLIPSIBLINGS | WS_CLIPCHILDREN

var g_Window:   Env.Window
var g_Renderer: Pixel.RenderOgl
var g_Painter:  Pixel.Painter
var g_RC:       Pixel.RenderingContext

var g_FontBytes:  Array'u8
var g_Face:       *Face
var g_TypeFace:   *Pixel.TypeFace
var g_TitleFont:  *Pixel.Font
var g_BodyFont:   *Pixel.Font
var g_InfoFont:   *Pixel.Font
var g_FontInfo:   String

func fontPath(fileName: string, loc = #callerlocation)->String
{
    let srcPath = Path.getDirectoryName(loc.fileName)
    return Path.combine(Path.combine(srcPath, "data"), fileName)
}

func loadFonts() throw
{
    let path = fontPath("segoeui.ttf")

    g_FontBytes = File.readAllBytes(path)
    g_Face = try Face.load(g_FontBytes.toSlice())

    g_FontInfo = Format.toString("% % | % glyphs | % bytes", g_Face.familyName, g_Face.styleName, g_Face.glyphCount, g_FontBytes.count)

    g_TypeFace  = TypeFace.create(path, g_FontBytes.toSlice())
    g_TitleFont = Font.create(g_TypeFace, 54)
    g_BodyFont  = Font.create(g_TypeFace, 34)
    g_InfoFont  = Font.create(g_TypeFace, 18)
}

func dropFonts()
{
    if g_Face
    {
        g_Face.destroy()
        g_Face = null
    }
}

func drawScene(painter: *Pixel.Painter)
{
    painter.clear(Argb.WhiteSmoke)
    painter.setParams(.Antialiased)

    var panelColor: Color = Argb.MidnightBlue
    var glowColor: Color = Argb.DeepSkyBlue
    glowColor.a = 70

    painter.fillRoundRect(56, 58, 688, 320, 24, 24, panelColor)
    painter.fillCircle(650, 128, 98, glowColor)
    painter.drawRoundRect(56, 58, 688, 320, 24, 24, Argb.DarkSlateBlue, 3)

    painter.drawString(88, 92, "TrueType text", g_TitleFont, Argb.White)
    painter.drawString(92, 176, "Sphinx of black quartz, judge my vow.", g_BodyFont, Argb.LightCyan)
    painter.drawString(92, 240, "Loaded from src/data/segoeui.ttf", g_InfoFont, Argb.LightSteelBlue)
    painter.drawString(92, 270, g_FontInfo, g_InfoFont, Argb.PaleGoldenrod)

    var baseline = Pen.createSolid(Argb.CadetBlue, 2)
    baseline.begCapStyle = .Round
    baseline.endCapStyle = .Round
    painter.drawLine(88, 324, 708, 324, baseline)

    painter.drawStringCenter(W * 0.5, 414, "Pixel + TrueType", g_BodyFont, Argb.DarkSlateGray)
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

func onResize(_window: #nonull *Env.Window, width, height: s32)
{
    g_RC.width  = width
    g_RC.height = height
}

#main
{
    try Env.createWindow(&g_Window, {className: "PIXEL2_CLASS_NAME", title: "Pixel TrueType example", width: W, height: H, style: FixedWindowStyle})
    try g_Window.setClientSize(W, H)
    g_RC = try g_Renderer.native.createContext(&g_Window, W, H)
    g_Renderer.setCurrentContext(g_RC)
    g_Renderer.init()

    // RenderOgl.init clears font caches, so create Pixel fonts after it.
    try loadFonts()

    g_Window.callbacks.onResize = &onResize

    try g_Window.show()

    var loop: Env.WindowLoop
    while loop.next()
    {
        display()
    }

    g_Renderer.native.dropContext(g_RC)
    dropFonts()
}
