#global #if #os == Swag.TargetOs.Windows

using Swag, Core, Win32, Ogl, Gdi32

public struct NativeRenderOgl {}

public struct RenderingContext
{
    hDC:    HDC
    hRC:    HGLRC
    hWnd:   HWND
    width:  s32
    height: s32
    ownsDC: bool
    ownsRC: bool
}

public impl NativeRenderOgl
{
    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd createContext(hWnd: HWND, width, height: s32, mainRC: HGLRC = null)->RenderingContext throw
    {
        var result = try .createContext(GetDC(hWnd), width, height, mainRC)
        result.hWnd   = hWnd
        result.ownsDC = true
        return result
    }

    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd createContext(window: &Env.Window, width, height: s32, mainRC: HGLRC = null)->RenderingContext throw
    {
        return try .createContext(cast(HWND) window.nativeHandle, width, height, mainRC)
    }

    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd createContext(hdc: HDC, width, height: s32, mainRC: HGLRC = null)->RenderingContext throw
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

    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd dropContext(rc: RenderingContext)
    {
        catch wglMakeCurrent(null, null)
        if rc.ownsRC do
            catch wglDeleteContext(rc.hRC)
        if rc.ownsDC do
            ReleaseDC(rc.hWnd, rc.hDC)
    }

    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd setCurrentContext(rc: RenderingContext)
    {
        catch wglMakeCurrent(rc.hDC, rc.hRC)
    }

    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd swapBuffers(rc: RenderingContext)
    {
        assume SwapBuffers(rc.hDC)
    }
}
