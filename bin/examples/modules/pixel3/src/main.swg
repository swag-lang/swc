using Core, Pixel, TrueType

const W = 920
const H = 520

var g_Window:   Env.Window
var g_Renderer: Pixel.RenderOgl
var g_Painter:  Pixel.Painter
var g_RC:       Pixel.RenderingContext

var g_FontBytes:   Array'u8
var g_TrueType:    Library
var g_Face:        *Face
var g_TypeFace:    *Pixel.TypeFace
var g_TitleFont:   *Pixel.Font
var g_BigSdfFont:  *Pixel.Font
var g_BodySdfFont: *Pixel.Font
var g_BitmapFont:  *Pixel.Font
var g_InfoFont:    *Pixel.Font
var g_FontInfo:    String

func fontPath(fileName: string, loc = #callerlocation)->String
{
    let srcPath = Path.getDirectoryName(loc.fileName)
    return Path.combine(Path.combine(srcPath, "data"), fileName)
}

func loadFonts() throw
{
    let path = fontPath("segoeui.ttf")

    g_FontBytes = File.readAllBytes(path)
    g_TrueType.init()
    g_Face = try g_TrueType.loadFace(g_FontBytes.toSlice())

    g_FontInfo = Format.toString("% % | % glyphs | SDF atlas spread 10", g_Face.familyName, g_Face.styleName, g_Face.glyphCount)

    g_TypeFace    = TypeFace.create(path, g_FontBytes.toSlice())
    g_TitleFont   = Font.createSdf(g_TypeFace, 42, 10)
    g_BigSdfFont  = Font.createSdf(g_TypeFace, 38, 10)
    g_BodySdfFont = Font.createSdf(g_TypeFace, 26, 8)
    g_BitmapFont  = Font.create(g_TypeFace, 38)
    g_InfoFont    = Font.create(g_TypeFace, 18)
}

func dropFonts()
{
    if g_Face
    {
        g_Face.destroy()
        g_Face = null
    }
}

func drawTextSample(painter: *Pixel.Painter)
{
    painter.drawString(74, 76, "Signed distance field text", g_TitleFont, Argb.White)
    painter.drawString(78, 148, "Smooth at 2.4x", g_BigSdfFont, Argb.MintCream, .None, 2.4)
    painter.drawString(78, 300, "The glyph atlas stores distances, then the shader reconstructs the edge.", g_BodySdfFont, Argb.LightCyan)
    painter.drawString(78, 338, g_FontInfo, g_InfoFont, Argb.PaleGoldenrod)
}

func drawBitmapComparison(painter: *Pixel.Painter)
{
    var labelColor: Color = Argb.LightSteelBlue
    labelColor.a = 210

    painter.drawString(586, 120, "Bitmap atlas", g_InfoFont, labelColor)
    painter.drawString(586, 154, "Smooth", g_BitmapFont, Argb.White, .None, 2.4)
}

func drawScene(painter: *Pixel.Painter)
{
    painter.clear(Argb.WhiteSmoke)
    painter.setParams(.Antialiased)

    var panelColor: Color = Argb.MidnightBlue
    var accentColor: Color = Argb.DeepSkyBlue
    var shadowColor: Color = Argb.Black
    accentColor.a = 72
    shadowColor.a = 28

    painter.fillRoundRect(46, 48, 828, 384, 20, 20, shadowColor)
    painter.fillRoundRect(58, 38, 804, 386, 20, 20, panelColor)
    painter.fillCircle(728, 106, 92, accentColor)
    painter.drawRoundRect(58, 38, 804, 386, 20, 20, Argb.DarkSlateBlue, 3)

    drawTextSample(painter)
    drawBitmapComparison(painter)

    var baseline = Pen.createSolid(Argb.CadetBlue, 2)
    baseline.begCapStyle = .Round
    baseline.endCapStyle = .Round
    painter.drawLine(74, 390, 820, 390, baseline)

    painter.drawStringCenter(W * 0.5, 468, "Pixel text shader", g_BodySdfFont, Argb.DarkSlateGray)
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

#main
{
    try Env.createWindow(&g_Window, {className: "PIXEL3_CLASS_NAME", title: "Pixel signed distance field text", width: W, height: H})
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
