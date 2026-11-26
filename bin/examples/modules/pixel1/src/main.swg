using Core, Pixel

const W = 840
const H = 624
const ColumnWidth = 400

late var g_TitleFont: *Font
late var g_LabelFont: *Font

// Draw the same set of figures inside a column starting at 'ox'.
// 'aa' toggles antialiasing so the two columns can be compared side by side.
func drawFigures(painter: *Pixel.Painter, ox: f32, aa: bool)
{
    painter.setAntialiased(aa)

    // Curves and diagonal edges expose differences in coverage.
    painter.fillCircle(ox + 96, 110, 58, Argb.Tomato)
    painter.drawCircle(ox + 96, 110, 58, Argb.Firebrick, 4)

    let dcx     = ox + 270
    let dcy     = 110'f32
    let dhalf   = 62'f32
    let diamond = [
        Math.Vector2{dcx, dcy - dhalf},
        Math.Vector2{dcx + dhalf, dcy},
        Math.Vector2{dcx, dcy + dhalf},
        Math.Vector2{dcx - dhalf, dcy}]
    painter.fillPolygon(diamond[to], Brush.createSolid(Argb.SteelBlue))
    drawClosedOutline(painter, diamond[to], Pen.createSolid(Argb.MidnightBlue, 4))

    let tri = [
        Math.Vector2{ox + 96, 210},
        Math.Vector2{ox + 36, 320},
        Math.Vector2{ox + 156, 320}]
    painter.fillPolygon(tri[to], Brush.createSolid(Argb.MediumSeaGreen))
    drawClosedOutline(painter, tri[to], Pen.createSolid(Argb.DarkGreen, 4))

    // Alternating radii put sharp tips and concave notches in the same polygon.
    var star: Array'Math.Vector2
    let scx = ox + 272
    let scy = 268'f32
    for i in 10
    {
        let sr    = ((i & 1) == 0) ? 70'f32 : 28'f32
        let angle = -Math.ConstF32.Pi * 0.5 + cast(f32, i) * (Math.ConstF32.Pi * 2 / 10)
        star.add(Math.Vector2{scx + Math.cos(angle) * sr, scy + Math.sin(angle) * sr})
    }

    painter.fillPolygon(star[to], Brush.createSolid(Argb.Goldenrod))
    drawClosedOutline(painter, star[to], Pen.createSolid(Argb.SaddleBrown, 3))

    // Compare stroke caps and rounded corners below the fills.
    var pen = Pen.createSolid(Argb.MediumPurple, 12)
    pen.begCapStyle = .Round
    pen.endCapStyle = .Round
    painter.drawLine(ox + 40, 430, ox + ColumnWidth - 40, 372, pen)

    painter.fillRoundRect(ox + 40, 456, ColumnWidth - 80, 78, 22, 22, Argb.LightSeaGreen)
    painter.drawRoundRect(ox + 40, 456, ColumnWidth - 80, 78, 22, 22, Argb.Teal, 4)
}

// Draw a closed polygon outline from a list of points.
func drawClosedOutline(painter: *Pixel.Painter, points: [..] Math.Vector2, pen: Pen)
{
    if points.count < 2 do
        return

    var path: LinePath
    path.start(points[0].x, points[0].y)
    for pt, index in points where index do
        path.lineTo(pt.x, pt.y)
    path.close()
    painter.drawPath(&path, pen)
}

func drawScene(painter: *Pixel.Painter)
{
    painter.setColorMaskFull()
    painter.clear(Argb.WhiteSmoke)
    painter.setColorMaskColor()

    painter.drawString(28, 20, "Antialiasing", g_TitleFont, Argb.DarkSlateGray)
    painter.drawString(28, 59, "Compare the same filled and stroked shapes.", g_LabelFont, Argb.DimGray)
    painter.drawStringCenter(W * 0.25, 100, "Antialiasing on", g_LabelFont, Argb.DarkSlateGray)
    painter.drawStringCenter(W * 0.75, 100, "Antialiasing off", g_LabelFont, Argb.DarkSlateGray)
    painter.fillRect(W * 0.5, 88, 1, H - 112, Argb.Gainsboro)

    painter.pushTransform()
    painter.translateTransform(0, 70)
    drawFigures(painter, 10, true)
    drawFigures(painter, 430, false)
    painter.popTransform()
}

func display() fail
{
    g_Render.begin(g_RC)
    g_Painter.begin()
    drawScene(&g_Painter)
    g_Painter.end()
    try g_Painter.render()
    g_Render.end()
}

func onResize(window: *Env.Window, width, height: s32)
{
    // The client size is physical device pixels; the scene keeps drawing in logical
    // W x H units, so the painter maps them to device pixels on scaled displays.
    g_RC.width  = width
    g_RC.height = height
    g_Painter.setContentScale(window.dpiScale())
}

var g_Window:      Env.Window
var g_Renderer:    Pixel.RenderOgl
late var g_Render: Pixel.IRenderer
var g_Painter:     Pixel.Painter
var g_RC:          Pixel.RenderContext

#main
{
    g_Window = try Env.createWindow({
        identifier: "pixel1",
        title: "Pixel example - antialiasing comparison",
        width: W,
        height: H,
        flags: .Minimizable})
    defer catch g_Window.close()
    try g_Window.setClientSize(W, H)
    g_Render  = &g_Renderer
    g_Painter = Pixel.Painter.create(g_Render)
    g_RC      = try g_Render.createContext(g_Window.nativeRenderHandle(), W, H)
    defer g_Render.deleteContext(&g_RC)
    g_Render.setCurrentContext(g_RC)
    g_Render.init()

    let typeface = try TypeFace.create("Inter Regular", #include("../../../assets/inter-regular.ttf"))
    g_TitleFont = g_Renderer.fonts.createFont(typeface, 30)
    g_LabelFont = g_Renderer.fonts.createFont(typeface, 15)

    g_Window.callbacks.onResize = &onResize

    try g_Window.show()

    var loop: Env.WindowLoop
    while loop.next()
    {
        try display()
    }
}
