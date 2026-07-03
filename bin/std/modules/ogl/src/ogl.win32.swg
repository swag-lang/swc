#global export
#global #if #os == Swag.TargetOs.Windows
#foreignlib("opengl32")
using Swag, Core, Win32, Gdi32

alias HGLRC               = const *void
alias getExtensionAddress = wglGetProcAddress

#[Foreign("opengl32")]
{
    func wglGetProcAddress(arg1: LPCSTR)->const *void;
}

internal namespace PrivOgl
{
    #[Foreign("opengl32")]
    {
        func wglCreateContext(hDc: HDC)->HGLRC;
        func wglDeleteContext(hRc: HGLRC)->BOOL;
        func wglMakeCurrent(hDc: HDC, hRc: HGLRC)->BOOL;
        func wglShareLists(hRc0, hRc1: HGLRC)->BOOL;
    }
}

#[Inline]
{
    func wglCreateContext(hDc: HDC)->HGLRC throw
    {
        let res = PrivOgl.wglCreateContext(hDc)
        if !res do
            throwWinError(GetLastError())
        return res
    }

    func wglDeleteContext(hRc: HGLRC) throw
    {
        if !PrivOgl.wglDeleteContext(hRc) do
            throwWinError(GetLastError())
    }

    func wglMakeCurrent(hDc: HDC, hRc: HGLRC) throw
    {
        if !PrivOgl.wglMakeCurrent(hDc, hRc) do
            throwWinError(GetLastError())
    }

    func wglShareLists(hRc0, hRc1: HGLRC) throw
    {
        if !PrivOgl.wglShareLists(hRc0, hRc1) do
            throwWinError(GetLastError())
    }
}

namespace Platform.Win32
{
    public struct Context
    {
        hDC:          HDC
        hRC:          HGLRC
        window:       *Env.Window
    }

    public func createContext(window: &Env.Window, colorBits: u8 = 32, makeCurrent = true)->Context throw
    {
        var result: retval
        result.window = &window
        result.hDC    = window.getDC()

        var pfd: PIXELFORMATDESCRIPTOR
        pfd.nSize      = #sizeof(pfd)
        pfd.nVersion   = 1
        pfd.dwFlags    = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL
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
        mtd makeCurrent() throw
        {
            try wglMakeCurrent(.hDC, .hRC)
        }

        mtd clearCurrent() throw
        {
            try wglMakeCurrent(null, null)
        }

        mtd swapBuffers()
        {
            assume SwapBuffers(.hDC)
        }

        mtd destroy()
        {
            catch .clearCurrent()
            catch wglDeleteContext(.hRC)

            if .window and .hDC do
                .window.releaseDC(.hDC)

            .hRC    = null
            .hDC    = null
            .window = null
        }
    }
}
