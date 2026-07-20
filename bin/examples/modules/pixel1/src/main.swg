using Core, Pixel, Win32

const W    = 820
const H    = 560
const COLW = 400      // width of one column

const FixedWindowStyle = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_CLIPSIBLINGS | WS_CLIPCHILDREN

// Draw the same set of figures inside a column starting at 'ox'.
// 'aa' toggles antialiasing so the two columns can be compared side by side.
func drawFigures(painter: #nonull *Pixel.Painter, ox: f32, aa: bool)
{
    painter.setAntialiased(aa)

    // Header cue (no text): green = antialiased, red = aliased.
    painter.fillRect(ox + 24, 20, COLW - 48, 14, aa ? Argb.MediumSeaGreen : Argb.IndianRed)

    // --- Circle: curved edges are the clearest AA showcase ---
    painter.fillCircle(ox + 96, 110, 58, Argb.Tomato)
    painter.drawCircle(ox + 96, 110, 58, Argb.Firebrick, 4)

    // --- Rotated square (diamond): diagonal straight edges ---
    let dcx   = ox + 270
    let dcy   = 110'f32
    let dhalf = 62'f32
    let diamond = [
        Math.Vector2{dcx, dcy - dhalf},
        Math.Vector2{dcx + dhalf, dcy},
        Math.Vector2{dcx, dcy + dhalf},
        Math.Vector2{dcx - dhalf, dcy},
    ]
    painter.fillPolygon(diamond[to], Brush.createSolid(Argb.SteelBlue))
    drawClosedOutline(painter, diamond[to], Pen.createSolid(Argb.MidnightBlue, 4))

    // --- Triangle: slanted edges and sharp corners ---
    let tri = [
        Math.Vector2{ox + 96, 210},
        Math.Vector2{ox + 36, 320},
        Math.Vector2{ox + 156, 320},
    ]
    painter.fillPolygon(tri[to], Brush.createSolid(Argb.MediumSeaGreen))
    drawClosedOutline(painter, tri[to], Pen.createSolid(Argb.DarkGreen, 4))

    // --- Filled 5-point star: the non-convex fill path (clean + triangulate +
    // centered fringe AA). Alternating outer/inner radii give sharp convex tips
    // and concave notches, the clearest showcase for non-convex antialiasing. ---
    var star: Array'Math.Vector2
    let scx = ox + 272
    let scy = 268'f32
    for i in 10
    {
        let sr    = ((i & 1) == 0) ? 70'f32 : 28'f32
        let angle = -Math.ConstF32.Pi * 0.5 + cast(f32) i * (Math.ConstF32.Pi * 2 / 10)
        star.add(Math.Vector2{scx + Math.cos(angle) * sr, scy + Math.sin(angle) * sr})
    }
    painter.fillPolygon(star[to], Brush.createSolid(Argb.Goldenrod))
    drawClosedOutline(painter, star[to], Pen.createSolid(Argb.SaddleBrown, 3))

    // --- Diagonal thick line with round caps ---
    var pen = Pen.createSolid(Argb.MediumPurple, 12)
    pen.begCapStyle = .Round
    pen.endCapStyle = .Round
    painter.drawLine(ox + 40, 430, ox + COLW - 40, 372, pen)

    // --- Rounded rectangle: curved corners + straight edges ---
    painter.fillRoundRect(ox + 40, 456, COLW - 80, 78, 22, 22, Argb.LightSeaGreen)
    painter.drawRoundRect(ox + 40, 456, COLW - 80, 78, 22, 22, Argb.Teal, 4)
}

// Draw a closed polygon outline from a list of points.
func drawClosedOutline(painter: #nonull *Pixel.Painter, points: #nonull [..] Math.Vector2, pen: Pen)
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

func drawScene(painter: #nonull *Pixel.Painter)
{
    painter.clear(Argb.WhiteSmoke)

    // Left column: antialiased. Right column: aliased.
    drawFigures(painter, 0, true)
    drawFigures(painter, COLW + 20, false)

    // Divider between the two columns (drawn aliased, 1px).
    painter.setAntialiased(false)
    painter.fillRect(COLW + 9, 0, 2, H, Argb.Gainsboro)
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

var g_Window:   Env.Window
var g_Renderer: Pixel.RenderOgl
var g_Painter:  Pixel.Painter
var g_RC:       Pixel.RenderingContext

#main
{
    try Env.createWindow(&g_Window, {className: "PIXEL1_CLASS_NAME", title: "Pixel example - antialiasing comparison", width: W, height: H, style: FixedWindowStyle})
    try g_Window.setClientSize(W, H)
    g_RC = try g_Renderer.native.createContext(&g_Window, W, H)
    g_Renderer.setCurrentContext(g_RC)
    g_Renderer.init()

    g_Window.callbacks.onResize = &onResize

    try g_Window.show()

    var loop: Env.WindowLoop
    while loop.next()
    {
        display()
    }

    g_Renderer.native.dropContext(g_RC)
}
