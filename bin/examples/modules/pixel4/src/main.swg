using Core, Pixel, Win32

const W = 980
const H = 720
const MaxPages = 3

const FixedWindowStyle = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_CLIPSIBLINGS | WS_CLIPCHILDREN

struct CapRow
{
    label:        string
    begCap:       LineCapStyle
    endCap:       LineCapStyle
    color:        Color
}

const CapRows = [
    CapRow{"None / None", .None, .None, Argb.SlateGray},
    CapRow{"Round / Round", .Round, .Round, Argb.Tomato},
    CapRow{"Square / Square", .Square, .Square, Argb.SteelBlue},
    CapRow{"Triangle / Triangle", .Triangle, .Triangle, Argb.MediumSeaGreen},
    CapRow{"Arrow / None", .ArrowAnchor, .None, Argb.DarkOrange},
    CapRow{"None / Arrow 2", .None, .ArrowAnchor2, Argb.MediumPurple},
    CapRow{"Round anchor / Square anchor", .RoundAnchor, .SquareAnchor, Argb.Goldenrod},
]

struct JoinCard
{
    label:        string
    joinStyle:    JoinStyle
    color:        Color
}

const JoinCards = [
    JoinCard{"None", .None, Argb.Gray},
    JoinCard{"Bevel", .Bevel, Argb.CadetBlue},
    JoinCard{"Round", .Round, Argb.SeaGreen},
    JoinCard{"Miter", .Miter, Argb.Crimson},
    JoinCard{"Miter bevel", .MiterBevel, Argb.DarkOrchid},
]

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
    let pageText = Format.toString("F1 : next page (%/%). Pages : caps, joins, transparence.", g_Page + 1, MaxPages)
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

func makeCapPath(left, right, y: f32)->LinePath
{
    var path: retval
    path.start(left, y)
    path.lineTo(right, y)
    return path
}

func drawCapRow(painter: *Pixel.Painter, rect: Math.Rectangle, row: CapRow)
{
    let baselineY = Math.round(rect.vertCenter())
    let startX    = rect.x + 250
    let endX      = rect.right() - 32

    painter.fillRect(rect.x, rect.y + rect.height - 1, rect.width, 1, Color.fromArgb(30, Argb.SlateGray))
    painter.drawString(rect.x + 8, rect.y + 18, row.label, g_LabelFont, Argb.DarkSlateGray)
    painter.drawString(startX - 44, rect.y + 18, "start", g_HelpFont, Argb.LightSlateGray)
    painter.drawString(endX - 16, rect.y + 18, "end", g_HelpFont, Argb.LightSlateGray)

    painter.drawLine(startX, baselineY, endX, baselineY, Color.fromArgb(44, Argb.Black), 2)
    painter.fillCircle(startX, baselineY, 3, Argb.DarkSlateGray)
    painter.fillCircle(endX, baselineY, 3, Argb.DarkSlateGray)

    var path = makeCapPath(startX, endX, baselineY)
    var pen  = Pen.createSolid(row.color, 18)
    pen.begCapStyle = row.begCap
    pen.endCapStyle = row.endCap
    pen.joinStyle   = .Round

    if isAnchorCap(row.begCap)
    {
        pen.capBegScaleX = 2.4
        pen.capBegScaleY = 2.3
    }

    if isAnchorCap(row.endCap)
    {
        pen.capEndScaleX = 2.4
        pen.capEndScaleY = 2.3
    }

    painter.drawPath(&path, pen)
}

func drawCapsPage(painter: *Pixel.Painter)
{
    drawPageHeader(painter, "Pixel path drawing", "Page 1 : starts, endings and cap styles on the same straight segment.")

    let body = drawPanel(painter, {28, 98, 924, 586}, "Caps and endings", "The path starts on the left, ends on the right. Only the pen changes from row to row.")
    let rowHeight = body.height / cast(f32) @countof(CapRows)

    painter.pushClippingSurfaceRect(body)
    for i in @countof(CapRows)
    {
        let rowRect = Math.Rectangle{body.x, body.y + i * rowHeight, body.width, rowHeight}
        drawCapRow(painter, rowRect, CapRows[i])
    }
    painter.popClippingRect()
}

func makeJoinPath(rect: Math.Rectangle)->LinePath
{
    var path: retval
    let left = rect.x + 20
    let top  = rect.y + rect.height * 0.75
    path.start(left, top)
    path.lineTo(left + rect.width * 0.18, rect.y + rect.height * 0.18)
    path.lineTo(left + rect.width * 0.36, rect.y + rect.height * 0.74)
    path.lineTo(left + rect.width * 0.58, rect.y + rect.height * 0.28)
    path.lineTo(left + rect.width * 0.78, rect.y + rect.height * 0.78)
    path.lineTo(left + rect.width * 0.92, rect.y + rect.height * 0.24)
    return path
}

func getJoinCardRect(index: s32)->Math.Rectangle
{
    if index < 3 do
        return {28 + index * 308, 118, 288, 224}

    return {182 + (index - 3) * 308, 372, 288, 224}
}

func drawJoinCard(painter: *Pixel.Painter, rect: Math.Rectangle, card: JoinCard)
{
    let body = drawPanel(painter, rect, card.label, "")
    var path = makeJoinPath(body)

    var guide = Pen.createSolid(Color.fromArgb(60, Argb.Black), 3)
    guide.begCapStyle = .None
    guide.endCapStyle = .None
    guide.joinStyle   = .Round
    painter.drawPath(&path, guide)

    var pen = Pen.createSolid(card.color, 24)
    pen.begCapStyle     = .None
    pen.endCapStyle     = .None
    pen.joinStyle       = card.joinStyle
    pen.joinMiterLimit  = 1.7
    painter.drawPath(&path, pen)
}

func drawJoinsPage(painter: *Pixel.Painter)
{
    drawPageHeader(painter, "Pixel path drawing", "Page 2 : join handling on sharp bends and reflex angles.")

    for i in @countof(JoinCards)
    {
        drawJoinCard(painter, getJoinCardRect(i), JoinCards[i])
    }
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

func drawBlobSurface(painter: *Pixel.Painter, rect: Math.Rectangle)
{
    var blob = makeBlobPath(rect)
    painter.fillPath(&blob, Color.fromArgb(42, Argb.MediumPurple))

    var pen = Pen.createSolid(Color.fromArgb(136, Argb.MediumPurple), 6)
    pen.begCapStyle = .None
    pen.endCapStyle = .None
    pen.joinStyle   = .Round
    painter.drawPath(&blob, pen)
}

func drawAlphaRow(painter: *Pixel.Painter, rect: Math.Rectangle, alpha: u8, label: string)
{
    painter.drawString(rect.x, rect.y + 10, label, g_LabelFont, Argb.DarkSlateGray)

    let pathRect = insetRect(rect, 150, 6, 16, 8)
    painter.drawLine(pathRect.x, pathRect.vertCenter(), pathRect.right(), pathRect.vertCenter(), Color.fromArgb(24, Argb.Black), 1)

    var path = makeTransparencyPath(pathRect, 0)
    var pen  = Pen.createSolid(Color.fromArgb(alpha, Argb.DeepSkyBlue), 20)
    pen.begCapStyle = .RoundAnchor
    pen.endCapStyle = .ArrowAnchor
    pen.joinStyle   = .Round
    painter.drawPath(&path, pen)
}

func drawTransparencyPage(painter: *Pixel.Painter)
{
    drawPageHeader(painter, "Pixel path drawing", "Page 3 : color stacking and alpha blending on a filled surface plus overlapping strokes.")

    let sceneBody = drawPanel(painter, {28, 102, 924, 404}, "Transparency and layering", "A translucent surface sits behind overlapping paths, with a border that stays outside the fill.")
    painter.fillRoundRect(sceneBody.x, sceneBody.y, sceneBody.width, sceneBody.height, 14, 14, Color.fromArgb(255, 248, 250, 252))
    painter.pushClippingSurfaceRect(sceneBody)

    drawBlobSurface(painter, sceneBody)

    {
        var path = makeTransparencyPath(sceneBody, 0)
        var pen  = Pen.createSolid(Color.fromArgb(122, Argb.Tomato), 34)
        pen.begCapStyle = .Round
        pen.endCapStyle = .Round
        pen.joinStyle   = .Round
        painter.drawPath(&path, pen)
    }

    {
        var path = makeTransparencyPath(sceneBody, 1)
        var pen  = Pen.createSolid(Color.fromArgb(126, Argb.SeaGreen), 28)
        pen.begCapStyle = .Square
        pen.endCapStyle = .SquareAnchor
        pen.joinStyle   = .Bevel
        pen.capEndScaleX = 2.5
        pen.capEndScaleY = 2.4
        painter.drawPath(&path, pen)
    }

    {
        var path = makeTransparencyPath(sceneBody, 2)
        var pen  = Pen.createSolid(Color.fromArgb(120, Argb.DeepSkyBlue), 24)
        pen.begCapStyle = .ArrowAnchor2
        pen.endCapStyle = .RoundAnchor
        pen.joinStyle   = .MiterBevel
        pen.capBegScaleX = 2.6
        pen.capBegScaleY = 2.3
        pen.capEndScaleX = 2.4
        pen.capEndScaleY = 2.2
        painter.drawPath(&path, pen)
    }

    painter.popClippingRect()

    let alphaBody = drawPanel(painter, {28, 530, 924, 154}, "Opacity samples", "Same path, same geometry, different alpha values.")
    let alphaRowHeight = alphaBody.height / 3.0
    drawAlphaRow(painter, {alphaBody.x, alphaBody.y + 0 * alphaRowHeight, alphaBody.width, alphaRowHeight}, 64, "25% alpha")
    drawAlphaRow(painter, {alphaBody.x, alphaBody.y + 1 * alphaRowHeight, alphaBody.width, alphaRowHeight}, 128, "50% alpha")
    drawAlphaRow(painter, {alphaBody.x, alphaBody.y + 2 * alphaRowHeight, alphaBody.width, alphaRowHeight}, 216, "85% alpha")
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
    try Env.createWindow(&g_Window, {className: "PIXEL4_CLASS_NAME", title: "Pixel path drawing showcase", width: W, height: H, style: FixedWindowStyle})
    try g_Window.setClientSize(W, H)
    g_RC = try g_Renderer.native.createContext(&g_Window, W, H)
    g_Renderer.setCurrentContext(g_RC)
    g_Renderer.init()

    try loadFonts()

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
