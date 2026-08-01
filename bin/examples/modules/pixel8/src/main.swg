using Core, Pixel, Win32

const W          = 1320
const H          = 900
const TestFrames = 4
const Margin     = 28.0

const FixedWindowStyle = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_CLIPSIBLINGS | WS_CLIPCHILDREN

const FormulaCount = 6
const Titles       = [
    "Quadratic formula",
    "Gaussian integral",
    "Finite series with limits",
    "Matrix notation",
    "Piecewise function",
    "Nested layout and accents",
    ]
const Sources = [
    #raw "x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}",
    #raw "\int_{0}^{\infty} e^{-x^2}\,dx = \frac{\sqrt{\pi}}{2}",
    #raw "\sum_{k=1}^{n} k^3 = \left(\frac{n(n+1)}{2}\right)^2",
    #raw "A = \begin{pmatrix}a&b\\c&d\end{pmatrix},\quad \det A = ad-bc",
    #raw "f(x) = \begin{cases}x^2&x\ge0\\-x&x<0\end{cases}",
    #raw "\vec{v}_{i+1} = \frac{\hat{u}+\sqrt[3]{1+\alpha_i^2}}{1+\lVert u\rVert}",
    ]
const Accents = [
    Argb.RoyalBlue,
    Argb.MediumVioletRed,
    Argb.DarkOrange,
    Argb.SeaGreen,
    Argb.SlateBlue,
    Argb.Crimson,
    ]
const Subtitle = "Reusable LaTeX parsing, TeX atom spacing, scalable scripts, fractions, radicals, " ++
                 "limits, delimiters and matrices."

struct SceneLayout
{
    scale: f32
    rect:  Math.Rectangle
}

var g_Window:   Env.Window
var g_Renderer: Pixel.RenderOgl
var g_Render:   Pixel.IRenderer = undefined
var g_Painter:  Pixel.Painter
var g_RC:       Pixel.RenderContext

var g_TypeFace:     #null *Pixel.TypeFace
var g_BoldTypeFace: #null *Pixel.TypeFace
var g_TitleFont:    #null *Pixel.Font
var g_SubtitleFont: #null *Pixel.Font
var g_LabelFont:    #null *Pixel.Font
var g_SourceFont:   #null *Pixel.Font
var g_MathFont:     #null *Pixel.Font
var g_Formulas:     [FormulaCount] MathExpression

func initContent() fail
{
    g_TypeFace     = TypeFace.load("segoeui.ttf")
    g_BoldTypeFace = TypeFace.load("segoeuib.ttf")
    g_TitleFont    = g_Renderer.fonts.createFont(notnull g_BoldTypeFace, 32, .Auto)
    g_SubtitleFont = g_Renderer.fonts.createFont(notnull g_TypeFace, 15, .Auto)
    g_LabelFont    = g_Renderer.fonts.createFont(notnull g_BoldTypeFace, 15, .Auto)
    g_SourceFont   = g_Renderer.fonts.createFont(notnull g_TypeFace, 12, .Auto)
    g_MathFont     = g_Renderer.fonts.createFont(notnull g_TypeFace, 34, .Auto)

    for source, [idx] in Sources do
        g_Formulas[idx] = try MathExpression.parse(source)
}

func computeSceneLayout(width, height: s32)->SceneLayout
{
    let surfaceWidth  = Math.max(width, 1)
    let surfaceHeight = Math.max(height, 1)
    let scaleX        = cast(f32) surfaceWidth / cast(f32) W
    let scaleY        = cast(f32) surfaceHeight / cast(f32) H

    with var result: retval = undefined
    {
        .scale  = Math.min(scaleX, scaleY)
        .rect   = {0, 0, cast(f32) W * .scale, cast(f32) H * .scale}
        .rect.x = Math.round((cast(f32) surfaceWidth - .rect.width) * 0.5)
        .rect.y = Math.round((cast(f32) surfaceHeight - .rect.height) * 0.5)
    }

    return result
}

func drawCard(painter: *Pixel.Painter, rect: Math.Rectangle, index: u64)
{
    let accent = Color.fromArgb(Accents[index])
    painter.fillRoundRect(rect, 12, 12, Argb.White)
    painter.drawRoundRect(rect, 12, 12, Color.fromArgb(38, Argb.SlateGray), 1)
    painter.fillRoundRect({rect.x, rect.y, 6, rect.height}, 3, 3, accent)

    painter.drawString(rect.x + 22, rect.y + 16, Titles[index], notnull g_LabelFont, accent)
    painter.drawString(rect.x + 22, rect.bottom() - 31, Sources[index], notnull g_SourceFont, Argb.DimGray)

    let formulaArea = Math.Rectangle{rect.x + 22, rect.y + 48, rect.width - 44, rect.height - 91}
    let metrics     = g_Formulas[index].measure(notnull g_MathFont)
    var zoom        = 1.0'f32
    if metrics.width > formulaArea.width do
        zoom = formulaArea.width / metrics.width

    painter.pushTransform()
    painter.translateTransform(formulaArea.horzCenter(), formulaArea.vertCenter())
    painter.scaleTransform(zoom)
    painter.drawMathCenter(0, 0, &g_Formulas[index], notnull g_MathFont, Argb.MidnightBlue)
    painter.popTransform()
}

func drawScene(painter: *Pixel.Painter)
{
    painter.clear(Color.fromArgb(255, 241, 244, 249))
    painter.setParams(.Antialiased)

    painter.drawString(Margin, 24, "Pixel mathematical typesetting", notnull g_TitleFont, Argb.MidnightBlue)
    painter.drawString(Margin + 2, 67, Subtitle, notnull g_SubtitleFont, Argb.DimGray)

    let top   = 104.0
    let gap   = 18.0
    let cardW = (cast(f32) W - Margin * 2 - gap) * 0.5
    let cardH = (cast(f32) H - top - Margin - gap * 2) / 3
    for [idx] in FormulaCount
    {
        let column = cast(f32) (idx % 2)
        let row    = cast(f32) (idx / 2)
        let rect   = Math.Rectangle{Margin + column * (cardW + gap), top + row * (cardH + gap), cardW, cardH}
        drawCard(painter, rect, idx)
    }
}

func display()
{
    let layout = computeSceneLayout(g_RC.width, g_RC.height)
    g_Render.begin(g_RC)
    g_Painter.begin()

    g_Painter.pushClippingSurfaceRect(layout.rect)
    g_Painter.pushTransform()
    g_Painter.scaleTransform(layout.scale)
    g_Painter.translateTransform(layout.rect.x, layout.rect.y)
    drawScene(&g_Painter)
    g_Painter.popTransform()
    g_Painter.popClippingRect()

    g_Painter.end()
    g_Painter.render()
    g_Render.end()
}

func onResize(_window: *Env.Window, width, height: s32)
{
    g_RC.width  = width
    g_RC.height = height
}

#main
{
    try Env.createWindow(&g_Window, {className: "PIXEL8_CLASS_NAME", title: "Pixel mathematical typesetting", width: W, height: H, style: FixedWindowStyle})
    try g_Window.setClientSize(W, H)
    g_Render  = &g_Renderer
    g_Painter = Pixel.Painter.create(g_Render)
    g_RC      = try g_Render.createContext(cast(#null const *void) g_Window.nativeHandle, W, H)
    g_Render.setCurrentContext(g_RC)
    g_Render.init()

    // RenderOgl.init clears the shared font caches, so fonts and formula layout are
    // initialized only after the renderer.
    try initContent()
    g_Window.callbacks.onResize = &onResize
    try g_Window.show()

    var loop: Env.WindowLoop
    if Env.hasArgument("swag.test") do
        loop.maxTestFrames = TestFrames
    while loop.next() do
        display()

    g_Render.deleteContext(&g_RC)
}
