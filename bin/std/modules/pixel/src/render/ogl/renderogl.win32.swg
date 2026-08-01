#global if #os == Swag.TargetOs.Windows

using Swag, Core, Win32, Ogl, Gdi32

// Provides the Windows-specific OpenGL context operations used by [[Pixel.RenderOgl]].
#[Swag.Opaque, Swag.NoDoc]
public struct NativeRenderOgl {}

// Describes a Windows device context, OpenGL context, drawable, and viewport.
#[Swag.Opaque, Swag.NoDoc]
public struct OglContext
{
    hDC:        HDC       // Windows device context.
    hRC:        HGLRC     // OpenGL rendering context.
    hWnd:       HWND      // Associated window, or `null` for an externally supplied device context.
    width:      s32       // Drawable width, in pixels.
    height:     s32       // Drawable height, in pixels.
    ownsDC:     bool      // Whether dropping the context must release `hDC`.
    ownsRC:     bool      // Whether dropping the context must delete `hRC`.
}

internal impl NativeRenderOgl
{
    // Creates a rendering context for a window handle.
    //
    // When `mainRC` is provided, it is borrowed instead of creating a new context.
    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd createWindowContext(hWnd: HWND, width, height: s32, mainRC: HGLRC = null)->OglContext fail
    {
        var result = try .createContextForDeviceContext(GetDC(hWnd), width, height, mainRC)
        result.hWnd   = hWnd
        result.ownsDC = true
        return result
    }

    // Creates a rendering context for an environment window.
    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd createContext(window: &Env.Window, width, height: s32, mainRC: HGLRC = null)->OglContext fail
    {
        return try .createWindowContext(cast(HWND) window.nativeHandle, width, height, mainRC)
    }

    // Creates a rendering context for an existing device context.
    //
    // The device context remains caller-owned. A supplied `mainRC` is borrowed.
    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd createDeviceContext(hdc: HDC, width, height: s32, mainRC: HGLRC = null)->OglContext fail
    {
        return try .createContextForDeviceContext(hdc, width, height, mainRC)
    }

    // Establishes the pixel format and the rendering context of a device context.
    //
    // 'HWND' and 'HDC' are the same handle type, so the two public overloads above cannot be
    // told apart at a call site. Everything that needs this work calls it here by its own name
    // instead of picking between them.
    #[Warning("Wrn0006", WarningLevel.Disable)]
    private mtd createContextForDeviceContext(hdc: HDC, width, height: s32, mainRC: HGLRC)->OglContext fail
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

    // Releases native resources owned by `rc`.
    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd dropContext(rc: OglContext)
    {
        catch wglMakeCurrent(null, null)
        if rc.ownsRC do
            catch wglDeleteContext(rc.hRC)
        if rc.ownsDC do
            ReleaseDC(rc.hWnd, rc.hDC)
    }

    // Deletes a renderer-owned shared OpenGL context after its last drawable is gone.
    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd deleteContextHandle(hRC: HGLRC)
    {
        catch wglDeleteContext(hRC)
    }

    // Makes `rc` current on the calling thread.
    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd setCurrentContext(rc: OglContext)
    {
        catch wglMakeCurrent(rc.hDC, rc.hRC)
    }

    // Presents the current back buffer for `rc`.
    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd swapBuffers(rc: OglContext)
    {
        expect SwapBuffers(rc.hDC)
    }
}
