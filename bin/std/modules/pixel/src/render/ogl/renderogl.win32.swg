#global if #os == Swag.TargetOs.Windows

using Swag, Core, Win32, Ogl, Gdi32

internal impl NativeRenderOgl
{
    // Creates a rendering context for a window handle.
    //
    // When `mainRC` is provided, it is borrowed instead of creating a new context.
    mtd createWindowContext(hWnd: const *void?, width, height: s32, mainRC: const *void? = null)->OglContext fail
    {
        var nativeWindow = cast(HWND, hWnd)
        let ownsWindow   = not nativeWindow or (GetWindowLongPtrW(nativeWindow, GWL_EXSTYLE) & WS_EX_LAYERED) != 0
        if ownsWindow
        {
            // Layered presentation and offscreen rendering use a private invisible drawable.
            // Its fixed size keeps capture dimensions independent of desktop geometry.
            let className = Utf16.toZeroTerminated("STATIC")
            let hostName  = Utf16.toZeroTerminated("Swag OpenGL context")
            nativeWindow = CreateWindowExW(0, className.buffer, hostName.buffer, WS_POPUP, 0, 0, 1, 1, null, null, GetModuleHandleW(null), null)
            if not nativeWindow do
                try failWinError(GetLastError())
        }

        defer #fail if ownsWindow do
            catch DestroyWindow(nativeWindow)
        let dc = GetDC(nativeWindow)
        defer #fail ReleaseDC(nativeWindow, dc)
        var result = try .createContextForDeviceContext(cast(const *void?, dc), width, height, mainRC)
        result.hWnd       = cast(const *void?, nativeWindow)
        result.ownsDC     = true
        result.ownsWindow = ownsWindow
        return result
    }

    // Creates a rendering context for an environment window.
    mtd createContext(window: *Env.Window, width, height: s32, mainRC: HGLRC = null)->OglContext fail => try .createWindowContext(window.nativeRenderHandle(), width, height, cast(const *void?, mainRC))

    // Creates a rendering context for an existing device context.
    //
    // The device context remains caller-owned. A supplied `mainRC` is borrowed.
    mtd createDeviceContext(hdc: HDC, width, height: s32, mainRC: HGLRC = null)->OglContext fail => try .createContextForDeviceContext(cast(const *void?, hdc), width, height, cast(const *void?, mainRC))

    // Establishes the pixel format and the rendering context of a device context.
    //
    // 'HWND' and 'HDC' are the same handle type, so the two public overloads above cannot be
    // told apart at a call site. Everything that needs this work calls it here by its own name
    // instead of picking between them.
    private mtd createContextForDeviceContext(hdc: const *void?, width, height: s32, mainRC: const *void?)->OglContext fail
    {
        var result: #returntype
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
        let nativeDC = cast(HDC, hdc)
        let pf       = try ChoosePixelFormat(nativeDC, &pfd)
        try SetPixelFormat(nativeDC, pf, &pfd)

        result.hRC    = mainRC orelse cast(const *void?, try .createSharedContext(nativeDC))
        result.ownsRC = mainRC == null

        return result
    }

    // Creates the context every drawable of the renderer shares, reporting device resets when the
    // driver can.
    //
    // A context made by `wglCreateContext` goes on answering after the driver reset the device:
    // it has lost every resource and draws nothing, without one call failing, so the windows it
    // presents show stale pixels for good. A robust context that is lost on reset says so
    // instead, which is what lets the renderer rebuild. The entry point that creates one is only
    // reachable through a current context, and that legacy context stays the fallback.
    private mtd createSharedContext(hdc: HDC)->HGLRC fail
    {
        let legacy = try Ogl.wglCreateContext(hdc)
        defer #fail catch Ogl.wglDeleteContext(legacy)
        try Ogl.wglMakeCurrent(hdc, legacy)
        defer catch Ogl.wglMakeCurrent(null, null)

        .notifiesReset = false
        let names = Ogl.wglGetExtensionsStringARB(hdc)
        if not names do
            return legacy
        for name in Tokenize.split(names, ' 'u8) where name == "WGL_ARB_create_context_robustness"
        {
            const Attributes: [5] s32 = [WGL_CONTEXT_FLAGS_ARB, WGL_CONTEXT_ROBUST_ACCESS_BIT_ARB,
                                         WGL_CONTEXT_RESET_NOTIFICATION_STRATEGY_ARB, WGL_LOSE_CONTEXT_ON_RESET_ARB, 0]
            let robust = Ogl.wglCreateContextAttribsARB(hdc, null, Attributes)
            if not robust do
                break
            catch Ogl.wglMakeCurrent(null, null)
            catch Ogl.wglDeleteContext(legacy)
            .notifiesReset = true
            return robust
        }

        return legacy
    }

    // Replaces the lost shared context of `contexts` and returns the new one.
    //
    // The replacement is created before the lost context is deleted, so a failure leaves every
    // drawable on a context that still answers calls, even though it draws nothing.
    mtd replaceLostContext(contexts: const [..] *OglContext, lost: const *void?)->const *void? fail
    {
        let replacement = try .createSharedContext(cast(HDC, contexts[0].hDC))
        catch Ogl.wglMakeCurrent(null, null)
        catch Ogl.wglDeleteContext(cast(HGLRC, lost))
        for index in contexts.count do
            contexts[index].hRC = cast(const *void?, replacement)
        return cast(const *void?, replacement)
    }

    // Releases native resources owned by `rc`.
    mtd dropContext(rc: OglContext)
    {
        catch wglMakeCurrent(null, null)
        if rc.ownsRC do
            catch wglDeleteContext(cast(HGLRC, rc.hRC))
        if rc.ownsDC do
            ReleaseDC(cast(HWND, rc.hWnd), cast(HDC, rc.hDC))
        if rc.ownsWindow do
            catch DestroyWindow(cast(HWND, rc.hWnd))
    }

    // Deletes a renderer-owned shared OpenGL context after its last drawable is gone.
    mtd deleteContextHandle(hRC: const *void?)
    {
        catch wglDeleteContext(cast(HGLRC, hRC))
    }

    // Makes `rc` current on the calling thread.
    mtd setCurrentContext(rc: OglContext)
    {
        let dc      = cast(HDC, rc.hDC)
        let context = cast(HGLRC, rc.hRC)
        if wglGetCurrentContext() == context and wglGetCurrentDC() == dc do
            return
        expect wglMakeCurrent(dc, context)
    }

    // Presents the current back buffer for `rc`.
    mtd swapBuffers(rc: OglContext)
    {
        if rc.ownsWindow do
            return
        expect SwapBuffers(cast(HDC, rc.hDC))
    }

    // States the presentation cadence of the context that has just become current.
    //
    // One refresh per present is what the surface layer relies on to pace a border drag: it
    // presents from inside the size transaction and lets the display, rather than a timer, decide
    // how often that happens. Leaving the interval unstated inherits a driver or control-panel
    // default that can be zero, which turns that pacing into a busy loop.
    mtd applyPresentPolicy()
    {
        discard Ogl.wglSwapIntervalEXT(1)
    }
}
