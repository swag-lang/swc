#global if #os == Swag.TargetOs.Windows

using Swag, Core, Win32, Ogl, Gdi32

internal impl NativeRenderOgl
{
    // Creates a rendering context for a window handle.
    //
    // When `mainRC` is provided, it is borrowed instead of creating a new context.
    mtd createWindowContext(hWnd: #null const *void, width, height: s32, mainRC: #null const *void = null)->OglContext fail
    {
        let nativeWindow = cast(HWND) hWnd
        var result       = try .createContextForDeviceContext(cast(#null const *void) GetDC(nativeWindow), width, height, mainRC)
        result.hWnd   = hWnd
        result.ownsDC = true
        return result
    }

    // Creates a rendering context for an environment window.
    mtd createContext(window: &Env.Window, width, height: s32, mainRC: HGLRC = null)->OglContext fail
    {
        return try .createWindowContext(window.nativeRenderHandle(), width, height, cast(#null const *void) mainRC)
    }

    // Creates a rendering context for an existing device context.
    //
    // The device context remains caller-owned. A supplied `mainRC` is borrowed.
    mtd createDeviceContext(hdc: HDC, width, height: s32, mainRC: HGLRC = null)->OglContext fail
    {
        return try .createContextForDeviceContext(cast(#null const *void) hdc, width, height, cast(#null const *void) mainRC)
    }

    // Establishes the pixel format and the rendering context of a device context.
    //
    // 'HWND' and 'HDC' are the same handle type, so the two public overloads above cannot be
    // told apart at a call site. Everything that needs this work calls it here by its own name
    // instead of picking between them.
    private mtd createContextForDeviceContext(hdc: #null const *void, width, height: s32, mainRC: #null const *void)->OglContext fail
    {
        var result: retval
        result.hDC    = hdc
        result.width  = width
        result.height = height

        // Double buffering is not an option here: without it rendering lands straight in the
        // compositor's redirection surface, which can be sampled mid-frame — and with paint-on-
        // dirty a torn frame stays on screen until the next invalidation, so the same window
        // came up clean or half-drawn depending on the launch. Composition support keeps the
        // swap DWM-friendly on every driver.
        var pfd: PIXELFORMATDESCRIPTOR
        pfd.nSize        = #sizeof(pfd)
        pfd.nVersion     = 1
        pfd.dwFlags      = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER | PFD_SUPPORT_COMPOSITION
        pfd.iPixelType   = PFD_TYPE_RGBA
        pfd.cStencilBits = 8
        pfd.cColorBits   = 24
        pfd.cAlphaBits   = 8
        let nativeDC = cast(HDC) hdc
        let pf       = try ChoosePixelFormat(nativeDC, &pfd)
        try SetPixelFormat(nativeDC, pf, &pfd)

        result.hRC    = mainRC orelse cast(#null const *void) try Ogl.wglCreateContext(nativeDC)
        result.ownsRC = mainRC == null

        return result
    }

    // Releases native resources owned by `rc`.
    mtd dropContext(rc: OglContext)
    {
        catch wglMakeCurrent(null, null)
        if rc.ownsRC do
            catch wglDeleteContext(cast(HGLRC) rc.hRC)
        if rc.ownsDC do
            ReleaseDC(cast(HWND) rc.hWnd, cast(HDC) rc.hDC)
    }

    // Deletes a renderer-owned shared OpenGL context after its last drawable is gone.
    mtd deleteContextHandle(hRC: #null const *void)
    {
        catch wglDeleteContext(cast(HGLRC) hRC)
    }

    // Makes `rc` current on the calling thread.
    mtd setCurrentContext(rc: OglContext)
    {
        catch wglMakeCurrent(cast(HDC) rc.hDC, cast(HGLRC) rc.hRC)
    }

    // Presents the current back buffer for `rc`.
    mtd swapBuffers(rc: OglContext)
    {
        expect SwapBuffers(cast(HDC) rc.hDC)
    }
}
