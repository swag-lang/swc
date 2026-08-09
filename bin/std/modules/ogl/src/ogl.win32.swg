#global export
#global if #os == Swag.TargetOs.Windows

#foreignlib("opengl32")
using Swag, Core, Win32, Gdi32

alias HGLRC               = #null const *void
alias getExtensionAddress = wglGetProcAddress

#[Foreign("opengl32")]
{
    func wglGetProcAddress(arg1: LPCSTR)->#null const *void
}

internal namespace PrivOgl
{
    #[Foreign("opengl32")]
    {
        func wglCreateContext(hDc: HDC)->HGLRC
        func wglDeleteContext(hRc: HGLRC)->BOOL
        func wglGetCurrentContext()->HGLRC
        func wglMakeCurrent(hDc: HDC, hRc: HGLRC)->BOOL
        func wglShareLists(hRc0, hRc1: HGLRC)->BOOL
    }
}

#[Inline]
{
    func wglCreateContext(hDc: HDC)->HGLRC fail
    {
        let res = PrivOgl.wglCreateContext(hDc)
        if !res do
            failWinError(GetLastError())
        return res
    }

    func wglDeleteContext(hRc: HGLRC) fail
    {
        if !PrivOgl.wglDeleteContext(hRc) do
            failWinError(GetLastError())
    }

    func wglGetCurrentContext()->HGLRC => PrivOgl.wglGetCurrentContext()

    func wglMakeCurrent(hDc: HDC, hRc: HGLRC) fail
    {
        if !PrivOgl.wglMakeCurrent(hDc, hRc) do
            failWinError(GetLastError())
    }

    func wglShareLists(hRc0, hRc1: HGLRC) fail
    {
        if !PrivOgl.wglShareLists(hRc0, hRc1) do
            failWinError(GetLastError())
    }
}

namespace Platform.Win32
{
    // Owns a Windows OpenGL context and the window device context paired with it.
    //
    // Create this value with [[Ogl.Platform.Win32.createContext]]. It releases any remaining
    // native resources when it leaves scope; call [[Ogl.Platform.Win32.Context.destroy]] to
    // release them earlier.
    #[Swag.NoCopy]
    #[Swag.Opaque]
    public struct Context
    {
        hDC:    HDC
        hRC:    HGLRC
        window: #null *Env.Window
    }

    // Creates an OpenGL context for `window`.
    //
    // `colorBits` selects the requested color-buffer depth. When `makeCurrent`
    // is true, the new context becomes current on the calling thread before the
    // function returns. Failure releases every partially acquired native handle.
    public func createContext(window: &Env.Window, colorBits: u8 = 32, makeCurrent = true)->Context fail
    {
        var result: retval
        result.window = &window
        result.hDC    = window.acquireWin32DeviceContext()
        defer #fail result.destroy()

        var pfd: PIXELFORMATDESCRIPTOR
        pfd.nSize      = #sizeof(pfd)
        pfd.nVersion   = 1
        pfd.dwFlags    = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER
        pfd.iPixelType = PFD_TYPE_RGBA
        pfd.cColorBits = colorBits

        let pf = try ChoosePixelFormat(result.hDC, &pfd)
        try SetPixelFormat(result.hDC, pf, &pfd)
        try DescribePixelFormat(result.hDC, pf, cast(u32) #sizeof(PIXELFORMATDESCRIPTOR), &pfd)

        result.hRC = try wglCreateContext(result.hDC)
        if makeCurrent do
            try result.makeCurrent()

        return result
    }

    public impl Context
    {
        // Releases any remaining native resources when this value leaves scope.
        mtd opDrop()
        {
            .destroy()
        }

        // Returns whether this value owns a native rendering context.
        mtd const isValid()->bool => .hRC != null

        // Makes this context current on the calling thread.
        mtd makeCurrent() fail
        {
            try wglMakeCurrent(.hDC, .hRC)
        }

        // Clears the current OpenGL context from the calling thread.
        mtd clearCurrent() fail
        {
            try wglMakeCurrent(null, null)
        }

        // Presents the back buffer for this context's window.
        mtd swapBuffers()
        {
            expect SwapBuffers(.hDC)
        }

        // Releases the rendering context and its acquired device context.
        //
        // Repeated calls are harmless. Destroying a context that is not current
        // does not disturb another context currently bound to the thread.
        mtd destroy()
        {
            if .hRC
            {
                if wglGetCurrentContext() == .hRC do
                    catch .clearCurrent()
                catch wglDeleteContext(.hRC)
            }

            if .window and .hDC do
                .window.releaseWin32DeviceContext(.hDC)

            @init(me, 1)
        }
    }
}
