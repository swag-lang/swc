#global export
#global if #os == Swag.TargetOs.Windows

#foreignlib("opengl32")
using Swag, Core, Win32, Gdi32

alias HGLRC = const *void?
alias getExtensionAddress = wglGetProcAddress
#[Swag.CallingConvention(.C)]
alias WglSwapIntervalProc = func(s32)->BOOL

// Sets how many display refreshes a `SwapBuffers` waits for, and reports whether it was accepted.
//
// `WGL_EXT_swap_control` is resolved against the context current on the calling thread, so this
// answers `false` before there is one and on a driver that does not publish the extension. One
// paces every present on the display, zero paces none of them. An application that never states
// an interval inherits whatever the driver and its control panel decided, which is why the two
// machines showing the same program never presented at the same cadence.
public func wglSwapIntervalEXT(interval: s32)->bool
{
    let entry = cast(WglSwapIntervalProc?, getExtensionAddress(("wglSwapIntervalEXT").buffer))
    if not entry do
        return false
    return entry(interval) != 0
}

#[Swag.CallingConvention(.C)]
alias WglGetExtensionsStringProc  = func(HDC)->const *u8?
#[Swag.CallingConvention(.C)]
alias WglCreateContextAttribsProc = func(HDC, HGLRC, const *s32)->HGLRC

// `WGL_ARB_create_context` and `WGL_ARB_create_context_robustness` attribute names and values.
const WGL_CONTEXT_FLAGS_ARB             = 0x2094
const WGL_CONTEXT_ROBUST_ACCESS_BIT_ARB = 0x00000004
const WGL_CONTEXT_RESET_NOTIFICATION_STRATEGY_ARB = 0x8256
const WGL_LOSE_CONTEXT_ON_RESET_ARB     = 0x8252

// Returns the WGL extension names published for `hDc`, separated by spaces.
//
// `WGL_ARB_extensions_string` is resolved against the context current on the calling thread, so
// this answers `null` before there is one and on a driver that does not publish the extension.
public func wglGetExtensionsStringARB(hDc: HDC)->string?
{
    let entry = cast(WglGetExtensionsStringProc?, getExtensionAddress(("wglGetExtensionsStringARB").buffer))
    if not entry do
        return null
    let names = entry(hDc)
    if not names do
        return null
    return cast(string, cast(const cstring, names))
}

// Creates a context for `hDc` described by the zero-terminated attribute list `attribs`.
//
// `WGL_ARB_create_context` is resolved against the context current on the calling thread, so a
// context must be current first. Returns `null` when the driver does not publish the extension
// or refuses the attributes; `GetLastError` then tells why. `shareContext` may be `null`.
public func wglCreateContextAttribsARB(hDc: HDC, shareContext: HGLRC, attribs: const [..] s32)->HGLRC
{
    Swag.assert(attribs.count != 0 and attribs[attribs.count - 1] == 0, "the attribute list must end with zero")
    let entry = cast(WglCreateContextAttribsProc?, getExtensionAddress(("wglCreateContextAttribsARB").buffer))
    if not entry do
        return null
    return entry(hDc, shareContext, &attribs[0])
}

#[Foreign("opengl32", callconv: Swag.CallConv.C)]
{
    func wglGetProcAddress(arg1: LPCSTR)->const *void?
}

internal namespace PrivOgl
{
    #[Foreign("opengl32", callconv: Swag.CallConv.C)]
    {
        func wglCreateContext(hDc: HDC)->HGLRC
        func wglDeleteContext(hRc: HGLRC)->BOOL
        func wglGetCurrentContext()->HGLRC
        func wglGetCurrentDC()->HDC
        func wglMakeCurrent(hDc: HDC, hRc: HGLRC)->BOOL
        func wglShareLists(hRc0, hRc1: HGLRC)->BOOL
    }
}

#[Inline]
{
    func wglCreateContext(hDc: HDC)->HGLRC fail
    {
        let res = PrivOgl.wglCreateContext(hDc)
        if not res do
            try failWinError(GetLastError())
        return res
    }

    func wglDeleteContext(hRc: HGLRC) fail
    {
        if not PrivOgl.wglDeleteContext(hRc) do
            try failWinError(GetLastError())
    }

    func wglGetCurrentContext()->HGLRC => PrivOgl.wglGetCurrentContext()
    func wglGetCurrentDC()->HDC        => PrivOgl.wglGetCurrentDC()

    func wglMakeCurrent(hDc: HDC, hRc: HGLRC) fail
    {
        if not PrivOgl.wglMakeCurrent(hDc, hRc) do
            try failWinError(GetLastError())
    }

    func wglShareLists(hRc0, hRc1: HGLRC) fail
    {
        if not PrivOgl.wglShareLists(hRc0, hRc1) do
            try failWinError(GetLastError())
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
        public
        {
            hDC:    HDC
            hRC:    HGLRC
            window: *Env.Window?
        }
    }

    // Creates an OpenGL context for `window`.
    //
    // `colorBits` selects the requested color-buffer depth. When `makeCurrent`
    // is true, the new context becomes current on the calling thread before the
    // function returns. Failure releases every partially acquired native handle.
    public func createContext(window: *Env.Window, colorBits: u8 = 32, makeCurrent = true)->Context fail
    {
        var result: #returntype
        result.window = window
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
        try DescribePixelFormat(result.hDC, pf, cast(u32, #sizeof(PIXELFORMATDESCRIPTOR)), &pfd)

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

            Swag.init(me, 1)
        }
    }
}
