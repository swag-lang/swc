#global if #os == Swag.TargetOs.Windows

using Swag, Core, Win32, Ogl, Gdi32

// Provides the Windows-specific OpenGL context operations used by [[Pixel.RenderOgl]].
public struct NativeRenderOgl {}

// Describes a Windows device context, OpenGL context, drawable, and viewport.
public struct RenderingContext
{
    hDC:        HDC       // Windows device context.
    hRC:        HGLRC     // OpenGL rendering context.
    hWnd:       HWND      // Associated window, or `null` for an externally supplied device context.
    width:      s32       // Drawable width, in pixels.
    height:     s32       // Drawable height, in pixels.
    ownsDC:     bool      // Whether dropping the context must release `hDC`.
    ownsRC:     bool      // Whether dropping the context must delete `hRC`.
    ownsWindow: bool      // Whether dropping the context must destroy `hWnd`.
}

public impl NativeRenderOgl
{
    // Creates a rendering context for a window handle.
    //
    // When `mainRC` is provided, it is borrowed instead of creating a new context.
    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd createContext(hWnd: HWND, width, height: s32, mainRC: HGLRC = null)->RenderingContext fail
    {
        var result = try .createContextForDeviceContext(GetDC(hWnd), width, height, mainRC)
        result.hWnd   = hWnd
        result.ownsDC = true
        return result
    }

    // Creates a rendering context for an environment window.
    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd createContext(window: &Env.Window, width, height: s32, mainRC: HGLRC = null)->RenderingContext fail
    {
        return try .createContext(cast(HWND) window.nativeHandle, width, height, mainRC)
    }

    // Creates a rendering context for an existing device context.
    //
    // The device context remains caller-owned. A supplied `mainRC` is borrowed.
    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd createContext(hdc: HDC, width, height: s32, mainRC: HGLRC = null)->RenderingContext fail
    {
        return try .createContextForDeviceContext(hdc, width, height, mainRC)
    }

    // Establishes the pixel format and the rendering context of a device context.
    //
    // 'HWND' and 'HDC' are the same handle type, so the two public overloads above cannot be
    // told apart at a call site. Everything that needs this work calls it here by its own name
    // instead of picking between them.
    #[Warning("Wrn0006", WarningLevel.Disable)]
    private mtd createContextForDeviceContext(hdc: HDC, width, height: s32, mainRC: HGLRC)->RenderingContext fail
    {
        var result: retval
        result.hDC    = hdc
        result.width  = width
        result.height = height

        var pfd: PIXELFORMATDESCRIPTOR
        pfd.nSize        = #sizeof(pfd)
        pfd.nVersion     = 1
        pfd.dwFlags      = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL
        pfd.iPixelType   = PFD_TYPE_RGBA
        pfd.cStencilBits = 8
        pfd.cColorBits   = 24
        pfd.cAlphaBits   = 8
        let pf = try ChoosePixelFormat(hdc, &pfd)
        try SetPixelFormat(hdc, pf, &pfd)

        result.hRC    = mainRC orelse try Ogl.wglCreateContext(result.hDC)
        result.ownsRC = mainRC == null

        return result
    }

    // Creates a rendering context that never reaches the screen.
    //
    // The context is backed by a window that is created but never shown. The screen device
    // context would be simpler, but Windows answers it with a legacy context that has neither
    // framebuffer objects nor shaders, so nothing would render. The window costs one handle and
    // buys the same accelerated context an application gets.
    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd createOffscreenContext(width, height: s32)->RenderingContext fail
    {
        // 'STATIC' is registered by the system, so no window class has to be added for a window
        // that is only ever a handle to hang a rendering context on.
        let hWnd = CreateWindowExA(0, @dataof("STATIC"), @dataof(""), WS_POPUP, 0, 0, width, height, null, null, null, null)
        if hWnd == null do
            fail Core.Errors.UnsupportedFormatError{"an off-screen window could not be created"}

        var result = catch .createContextForDeviceContext(GetDC(hWnd), width, height, null) as err
        if err != null
        {
            catch DestroyWindow(hWnd)
            fail err
        }

        result.hWnd       = hWnd
        result.ownsDC     = true
        result.ownsWindow = true
        return result
    }

    // Releases native resources owned by `rc`.
    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd dropContext(rc: RenderingContext)
    {
        catch wglMakeCurrent(null, null)
        if rc.ownsRC do
            catch wglDeleteContext(rc.hRC)
        if rc.ownsDC do
            ReleaseDC(rc.hWnd, rc.hDC)
        if rc.ownsWindow do
            catch DestroyWindow(rc.hWnd)
    }

    // Makes `rc` current on the calling thread.
    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd setCurrentContext(rc: RenderingContext)
    {
        catch wglMakeCurrent(rc.hDC, rc.hRC)
    }

    // Presents the current back buffer for `rc`.
    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd swapBuffers(rc: RenderingContext)
    {
        expect SwapBuffers(rc.hDC)
    }
}
