#global #if #os == Swag.TargetOs.Windows
using Core, Win32, Pixel, Core.Math

const W = 640
const H = 480

var g_Renderer: Pixel.RenderOgl
var g_Painter:  Pixel.Painter
var g_RC:       Pixel.RenderingContext
var g_IsReady   = false

func drawScene(painter: *Pixel.Painter)
{
    painter.clear(Argb.WhiteSmoke)
    painter.setParams(.Antialiased)

    painter.fillRoundRect(48, 48, 240, 160, 18, 18, Argb.SteelBlue)
    painter.drawRoundRect(48, 48, 240, 160, 18, 18, Argb.MidnightBlue, 4)

    painter.fillCircle(414, 132, 72, Argb.Tomato)
    painter.drawCircle(414, 132, 72, Argb.Firebrick, 5)

    painter.fillRect(96, 310, 448, 72, Argb.MediumSeaGreen)
    painter.drawRect(96, 310, 448, 72, Argb.DarkGreen, 4)

    var pen = Pen.createSolid(Argb.Goldenrod, 10)
    pen.begCapStyle = .Round
    pen.endCapStyle = .Round
    painter.drawLine(80, 240, 560, 240, pen)
}

func display()
{
    if !g_IsReady do
        return

    g_Renderer.begin(g_RC)
    g_Painter.begin()
    drawScene(&g_Painter)
    g_Painter.end()
    g_Renderer.draw(&g_Painter)
    g_Renderer.end()
}

func winProc(hWnd: HWND, msg: UINT, wParam: WPARAM, lParam: LPARAM)->LRESULT
{
    switch msg
    {
    case WM_PAINT:
        var ps: PAINTSTRUCT
        BeginPaint(hWnd, &ps)
        display()
        EndPaint(hWnd, &ps)
        return 0

    case WM_SIZE:
        if g_IsReady
        {
            g_RC.width  = LOWORD(lParam)
            g_RC.height = HIWORD(lParam)
            assume PostMessageA(hWnd, WM_PAINT, 0, 0)
        }
        return 0

    case WM_DESTROY:
        PostQuitMessage(0)
    }

    return DefWindowProcA(hWnd, msg, wParam, lParam)
}

func createWindow()->HWND
{
    var wc: WNDCLASSA
    wc.style         = CS_OWNDC
    wc.lpfnWndProc   = cast() &winProc
    wc.hInstance     = GetModuleHandleA(null)
    wc.lpszClassName = @dataof("PIXEL1_CLASS_NAME")
    assume RegisterClassA(wc)

    return CreateWindowExA(0, @dataof("PIXEL1_CLASS_NAME"), @dataof("Pixel example"), WS_OVERLAPPEDWINDOW | WS_CLIPSIBLINGS | WS_CLIPCHILDREN, CW_USEDEFAULT, CW_USEDEFAULT, W, H, null, null, wc.hInstance, null)
}

func messageLoop()
{
    var msg: MSG
    var cpt  = 0
    while cpt < 100
    {
        while PeekMessageA(&msg, null, 0, 0, PM_REMOVE) != 0
        {
            if msg.message == WM_QUIT do
                return
            TranslateMessage(&msg)
            DispatchMessageA(&msg)
        }

        display()

        if Env.hasArg("swag.test") do
            cpt += 1
    }
}

#main
{
    let hWnd = createWindow()

    g_RC = try g_Renderer.native.createContext(hWnd, W, H)
    g_Renderer.setCurrentContext(g_RC)
    g_Renderer.init()
    g_IsReady = true

    display()
    ShowWindow(hWnd, SW_SHOW)
    try UpdateWindow(hWnd)

    messageLoop()

    g_IsReady = false
    g_Renderer.native.dropContext(g_RC)
    ReleaseDC(hWnd, g_RC.hDC)
}
