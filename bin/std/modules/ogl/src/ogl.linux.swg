#global if #os == Swag.TargetOs.Linux

#foreignlib("libEGL.so.1")
#foreignlib("libGL.so.1")

using Core

// Resolves an OpenGL entry point through the EGL client API dispatcher.
internal func getExtensionAddress(name: const [*]u8)->const *void? => Linux.eglGetProcAddress(name)

namespace Platform.Xcb
{
    private var g_Display:     Linux.EGLDisplay
    private var g_Connection:  *void?
    private var g_Screen:      s32
    private var g_DisplayLock: Swag.Mutex

    private func check(result: Linux.EGLBoolean, operation: string) fail
    {
        if result == 0 do
            fail Swag.SystemError{operation, errorID: Linux.eglGetError()}
    }

    private func hasExtension(display: Linux.EGLDisplay, name: string)->bool
    {
        let text = Linux.eglQueryString(display, Linux.EGL_EXTENSIONS)
        if not text do
            return false
        for item in Tokenize.split(cast(string, cast(const cstring, text)), " ") where item == name do
            return true
        return false
    }

    private func displayFor(drawable: Env.XcbDrawable)->Linux.EGLDisplay fail
    {
        g_DisplayLock.lock()
        defer g_DisplayLock.unlock()
        if g_Display
        {
            if g_Connection != drawable.connection or g_Screen != drawable.screen do
                fail Errors.BadParameterError{"EGL display belongs to another XCB connection or screen"}
            return g_Display
        }

        if not hasExtension(null, "EGL_EXT_platform_base") or not hasExtension(null, "EGL_EXT_platform_xcb") do
            fail Swag.SystemError{"EGL needs EXT_platform_base and EXT_platform_xcb"}
        let getDisplay = cast(Linux.eglGetPlatformDisplayEXT_fn?, Linux.eglGetProcAddress("eglGetPlatformDisplayEXT".buffer))
        if not getDisplay do
            fail Swag.SystemError{"EGL has no eglGetPlatformDisplayEXT entry point"}
        let attributes: [3]s32 = [Linux.EGL_PLATFORM_XCB_SCREEN_EXT, drawable.screen, Linux.EGL_NONE]
        let display = getDisplay(Linux.EGL_PLATFORM_XCB_EXT, drawable.connection, &attributes[0])
        if not display do
            fail Swag.SystemError{"cannot obtain an EGL display for the XCB connection"}
        var major, minor: s32
        try check(Linux.eglInitialize(display, &major, &minor), "eglInitialize")
        defer #fail discard Linux.eglTerminate(display)
        if major < 1 or (major == 1 and minor < 4) do
            fail Swag.SystemError{"OpenGL contexts need EGL 1.4 or later"}
        if not hasExtension(display, "EGL_KHR_create_context") and major == 1 and minor < 5 do
            fail Swag.SystemError{"OpenGL 3.3 contexts need EGL_KHR_create_context or EGL 1.5"}
        g_Connection = drawable.connection
        g_Screen     = drawable.screen
        g_Display    = display
        return display
    }

    // Owns an EGL OpenGL 3.3 compatibility context and an XCB window surface.
    //
    // The environment window is borrowed and must outlive this owner. Create, use and destroy
    // the context on the window thread. Multiple owners have independent OpenGL objects.
    // Destroy every owner before unloading Ogl; the shared EGL display is retained until then.
    #[Swag.NoCopy, Swag.Opaque]
    public struct Context
    {
        display: Linux.EGLDisplay
        surface: Linux.EGLSurface
        context: Linux.EGLContext
        thread:  s32
    }

    // Creates a context for an open XCB window and makes it current on its owning thread.
    //
    // Requires EGL 1.4 with EXT_platform_xcb and OpenGL 3.3 compatibility support. The selected
    // configuration matches the window visual and provides RGB8, alpha8 and stencil8 or better.
    // Failure releases partial context/surface ownership and preserves the previously current
    // context. Success selects the OpenGL client API; call [[Ogl.glInitExtensions]] before using
    // post-1.1 entry points. Destroy this context before closing its window.
    public func createContext(window: *Env.Window)->Context fail
    {
        let drawable = try window.xcbDrawable()
        var result: #returntype
        result.display = try displayFor(drawable)
        result.thread  = Linux.gettid()
        defer #fail result.destroy()
        let attributes: [15]s32 = [Linux.EGL_SURFACE_TYPE, Linux.EGL_WINDOW_BIT,
                                   Linux.EGL_RENDERABLE_TYPE, Linux.EGL_OPENGL_BIT,
                                   Linux.EGL_RED_SIZE, 8, Linux.EGL_GREEN_SIZE, 8,
                                   Linux.EGL_BLUE_SIZE, 8, Linux.EGL_ALPHA_SIZE, 8,
                                   Linux.EGL_STENCIL_SIZE, 8, Linux.EGL_NONE]
        var count: s32
        try check(Linux.eglChooseConfig(result.display, &attributes[0], null, 0, &count), "eglChooseConfig")
        if count <= 0 do
            fail Swag.SystemError{"EGL has no OpenGL window configuration with RGB8, alpha8 and stencil8"}
        var configs: Array'Linux.EGLConfig
        configs.resize(cast(u64, count))
        try check(Linux.eglChooseConfig(result.display, &attributes[0], configs.buffer, count, &count), "eglChooseConfig")
        var config: Linux.EGLConfig
        for candidate in configs.toSlice()[0 until cast(u64, count)]
        {
            var visual: s32
            try check(Linux.eglGetConfigAttrib(result.display, candidate, Linux.EGL_NATIVE_VISUAL_ID, &visual), "eglGetConfigAttrib")
            if cast(u32, visual) == drawable.visual
            {
                config = candidate
                break
            }
        }

        if not config do
            fail Swag.SystemError{"EGL has no configuration matching the XCB window visual"}
        let createSurface = cast(Linux.eglCreatePlatformWindowSurfaceEXT_fn?, Linux.eglGetProcAddress("eglCreatePlatformWindowSurfaceEXT".buffer))
        if not createSurface do
            fail Swag.SystemError{"EGL has no eglCreatePlatformWindowSurfaceEXT entry point"}
        var windowId = drawable.window
        result.surface = createSurface(result.display, config, &windowId, null)
        try check(result.surface != null ? 1 : 0, "eglCreatePlatformWindowSurfaceEXT")
        let previousApi = Linux.eglQueryAPI()
        try check(Linux.eglBindAPI(Linux.EGL_OPENGL_API), "eglBindAPI")
        defer #fail discard Linux.eglBindAPI(previousApi)
        let contextAttributes: [7]s32 = [Linux.EGL_CONTEXT_MAJOR_VERSION_KHR, 3,
                                         Linux.EGL_CONTEXT_MINOR_VERSION_KHR, 3,
                                         Linux.EGL_CONTEXT_OPENGL_PROFILE_MASK_KHR,
                                         Linux.EGL_CONTEXT_OPENGL_COMPATIBILITY_PROFILE_BIT_KHR,
                                         Linux.EGL_NONE]
        result.context = Linux.eglCreateContext(result.display, config, null, &contextAttributes[0])
        try check(result.context != null ? 1 : 0, "eglCreateContext")
        try result.makeCurrent()
        return result
    }

    public impl Context
    {
        // Releases any context and surface still owned by this value.
        mtd opDrop() { .destroy() }

        // Reports whether this owner contains a rendering context.
        mtd const isValid()->bool => .context != null

        // Makes this context current on its creating thread, or fails if it is closed.
        mtd makeCurrent() fail
        {
            if not .isValid() do
                fail Errors.BadParameterError{"cannot make a closed EGL context current"}
            Swag.assert(.thread == Linux.gettid(), "EGL contexts stay on their creating thread")
            try check(Linux.eglBindAPI(Linux.EGL_OPENGL_API), "eglBindAPI")
            try check(Linux.eglMakeCurrent(.display, .surface, .surface, .context), "eglMakeCurrent")
        }

        // Unbinds this context if it is current; leaves another current context unchanged.
        mtd clearCurrent() fail
        {
            if not .isValid() do
                return
            Swag.assert(.thread == Linux.gettid(), "EGL contexts stay on their creating thread")
            if Linux.eglGetCurrentContext() == .context do
                try check(Linux.eglMakeCurrent(.display, null, null, null), "eglMakeCurrent")
        }

        // Presents this context's window back buffer; the context must be current.
        mtd swapBuffers() fail
        {
            if not .isValid() do
                fail Errors.BadParameterError{"cannot present a closed EGL context"}
            Swag.assert(.thread == Linux.gettid() and Linux.eglGetCurrentContext() == .context,
                        "presenting needs this EGL context current on its creating thread")
            try check(Linux.eglSwapBuffers(.display, .surface), "eglSwapBuffers")
        }

        // Releases owned resources without unbinding another current context; repeated calls are harmless.
        mtd destroy()
        {
            if not .display do
                return
            Swag.assert(.thread == Linux.gettid(), "EGL contexts stay on their creating thread")
            catch .clearCurrent()
            if .context do
                discard Linux.eglDestroyContext(.display, .context)
            if .surface do
                discard Linux.eglDestroySurface(.display, .surface)
            Swag.init(me, 1)
        }
    }

    #drop
    {
        if g_Display do
            discard Linux.eglTerminate(g_Display)
        g_Display    = null
        g_Connection = null
    }
}
