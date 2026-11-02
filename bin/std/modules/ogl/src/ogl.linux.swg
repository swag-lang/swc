#global if #os == Swag.TargetOs.Linux

#foreignlib("libEGL.so.1")
#foreignlib("libGL.so.1")

using Core

// Resolves an OpenGL entry point through the EGL client API dispatcher.
internal func getExtensionAddress(name: const [*]u8)->const *void? => Linux.eglGetProcAddress(name)

namespace Platform.Xcb
{
    private struct DisplayOwner
    {
        display:    Linux.EGLDisplay
        connection: *void?
        screen:     s32
        contexts:   u32
    }

    private var g_Displays:    Array'DisplayOwner
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

    private func displayFor(connection: *void?, screen: s32, offscreen: bool)->Linux.EGLDisplay fail
    {
        g_DisplayLock.lock()
        defer g_DisplayLock.unlock()
        for &owner in g_Displays where owner.connection == connection and owner.screen == screen
        {
            owner.contexts += 1
            return owner.display
        }

        if not hasExtension(null, "EGL_EXT_platform_base") do
            fail Swag.SystemError{"EGL needs EXT_platform_base"}
        let extension = offscreen ? "EGL_MESA_platform_surfaceless" : "EGL_EXT_platform_xcb"
        if not hasExtension(null, extension) do
            fail Swag.SystemError{extension}
        let getDisplay = cast(Linux.eglGetPlatformDisplayEXT_fn?, Linux.eglGetProcAddress("eglGetPlatformDisplayEXT".buffer))
        if not getDisplay do
            fail Swag.SystemError{"EGL has no eglGetPlatformDisplayEXT entry point"}
        let attributes: [3]s32 = [Linux.EGL_PLATFORM_XCB_SCREEN_EXT, screen, Linux.EGL_NONE]
        let display = getDisplay(offscreen ? Linux.EGL_PLATFORM_SURFACELESS_MESA : Linux.EGL_PLATFORM_XCB_EXT,
                                 connection,
                                 offscreen ? null : &attributes[0])
        if not display do
            fail Swag.SystemError{"cannot obtain the requested EGL display"}
        var major, minor: s32
        try check(Linux.eglInitialize(display, &major, &minor), "eglInitialize")
        defer #fail discard Linux.eglTerminate(display)
        if major < 1 or (major == 1 and minor < 4) do
            fail Swag.SystemError{"OpenGL contexts need EGL 1.4 or later"}
        if not hasExtension(display, "EGL_KHR_create_context") and major == 1 and minor < 5 do
            fail Swag.SystemError{"OpenGL 3.3 contexts need EGL_KHR_create_context or EGL 1.5"}
        g_Displays.add({display, connection, screen, 1})
        return display
    }

    private func releaseDisplay(display: Linux.EGLDisplay)
    {
        g_DisplayLock.lock()
        defer g_DisplayLock.unlock()
        for &owner, index in g_Displays where owner.display == display
        {
            Swag.assert(owner.contexts != 0)
            owner.contexts -= 1
            if owner.contexts == 0
            {
                discard Linux.eglTerminate(display)
                g_Displays.removeAt(index)
            }

            return
        }
    }

    private func createPbuffer(display: Linux.EGLDisplay, config: Linux.EGLConfig, width, height: s32)->Linux.EGLSurface fail
    {
        if width <= 0 or height <= 0 do
            fail Errors.BadParameterError{"EGL pbuffer dimensions must be positive"}
        let attributes: [5]s32 = [Linux.EGL_WIDTH, width, Linux.EGL_HEIGHT, height, Linux.EGL_NONE]
        let result = Linux.eglCreatePbufferSurface(display, config, &attributes[0])
        try check(result != null ? 1 : 0, "eglCreatePbufferSurface")
        return result
    }

    // Owns an EGL OpenGL 3.3 compatibility context and its initial window surface or pbuffer.
    //
    // The initial window is borrowed until its surface is destroyed or transferred. Create, use and destroy
    // the context on its creating thread. Multiple owners have independent OpenGL objects.
    // Extra surfaces from this context share its objects and must be destroyed before it.
    // The EGL display is retained until its final context is destroyed. Destroy all window
    // contexts before disconnecting their borrowed XCB connection.
    #[Swag.NoCopy, Swag.Opaque]
    public struct Context
    {
        display:    Linux.EGLDisplay
        surface:    Linux.EGLSurface
        context:    Linux.EGLContext
        thread:     s32
        config:     Linux.EGLConfig
        connection: *void?
        screen:     s32
    }

    // Owns one EGL window surface or pbuffer and borrows its OpenGL context.
    //
    // Destroy this surface before its window and context. Create, bind, present and destroy it
    // on the context's creating thread. Several surfaces may use the same context in turn.
    #[Swag.NoCopy, Swag.Opaque]
    public struct Surface
    {
        display: Linux.EGLDisplay
        handle:  Linux.EGLSurface
        context: Linux.EGLContext
        thread:  s32
    }

    private func createWindowSurface(display: Linux.EGLDisplay, config: Linux.EGLConfig, drawable: Env.XcbDrawable)->Linux.EGLSurface fail
    {
        var visual: s32
        try check(Linux.eglGetConfigAttrib(display, config, Linux.EGL_NATIVE_VISUAL_ID, &visual), "eglGetConfigAttrib")
        if cast(u32, visual) != drawable.visual do
            fail Errors.BadParameterError{"drawable visual does not match the EGL context"}
        let createSurface = cast(Linux.eglCreatePlatformWindowSurfaceEXT_fn?, Linux.eglGetProcAddress("eglCreatePlatformWindowSurfaceEXT".buffer))
        if not createSurface do
            fail Swag.SystemError{"EGL has no eglCreatePlatformWindowSurfaceEXT entry point"}
        var windowId = drawable.window
        let result   = createSurface(display, config, &windowId, null)
        try check(result != null ? 1 : 0, "eglCreatePlatformWindowSurfaceEXT")
        return result
    }

    // Creates a context for an open XCB window and makes it current on its owning thread.
    //
    // Requires EGL 1.4 with EXT_platform_xcb and OpenGL 3.3 compatibility support. The selected
    // configuration matches the window visual and provides RGB8, alpha8 and stencil8 or better.
    // Failure releases partial context/surface ownership and preserves the previously current
    // context. Success selects the OpenGL client API; call [[Ogl.glInitExtensions]] before using
    // post-1.1 entry points. Destroy its surface before closing the window; takeSurface can
    // transfer that surface to an independent owner while keeping this context alive.
    public func createContext(window: *Env.Window)->Context fail => try createContextForDrawable(try window.xcbDrawable())

    // Creates a context on the calling rendering thread from a borrowed XCB descriptor.
    //
    // Obtain the descriptor on the window thread first, then keep the window open until its
    // rendering surface has been destroyed. This does not consume XCB events.
    // The context is made current and otherwise follows [[Ogl.Platform.Xcb.createContext]].
    public func createContextForDrawable(drawable: Env.XcbDrawable)->Context fail
    {
        if not drawable.connection or drawable.window == 0 or drawable.visual == 0 do
            fail Errors.BadParameterError{"an EGL context needs a valid XCB drawable"}
        var result: #returntype
        result.display    = try displayFor(drawable.connection, drawable.screen, false)
        result.connection = drawable.connection
        result.screen     = drawable.screen
        result.thread     = Linux.gettid()
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
        result.config  = config
        result.surface = try createWindowSurface(result.display, config, drawable)
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

        // Transfers the initial window surface to a separate owner, preserving its current binding.
        //
        // The context remains valid. Destroy the returned surface before this context and its
        // window. After transfer, bind and present through the surface's methods; calling this
        // again fails because the context no longer owns an initial surface.
        mtd takeSurface()->Surface fail
        {
            if not .isValid() or not .surface do
                fail Errors.BadParameterError{"EGL context has no owned surface to transfer"}
            Swag.assert(.thread == Linux.gettid(), "EGL contexts stay on their creating thread")
            var result = Surface{.display, .surface, .context, .thread}
            .surface = null
            return result
        }

        // Creates another window surface using this context's display and visual configuration.
        //
        // The returned owner borrows this context and the drawable's window. It must be destroyed
        // before both. Creation leaves the current binding unchanged and fails for an incompatible
        // connection, screen or visual. Bind through [[Ogl.Platform.Xcb.Surface.makeCurrent]].
        mtd createSurface(drawable: Env.XcbDrawable)->Surface fail
        {
            if not .isValid() do
                fail Errors.BadParameterError{"cannot create a surface for a closed EGL context"}
            Swag.assert(.thread == Linux.gettid(), "EGL contexts stay on their creating thread")
            if not drawable.connection or drawable.window == 0 or drawable.visual == 0 do
                fail Errors.BadParameterError{"an EGL surface needs a valid XCB drawable"}
            if .connection != drawable.connection or .screen != drawable.screen do
                fail Errors.BadParameterError{"drawable belongs to another EGL display"}
            let surface = try createWindowSurface(.display, .config, drawable)
            return {.display, surface, .context, .thread}
        }

        // Creates an offscreen pbuffer on this context's existing EGL display and configuration.
        //
        // It shares this context's OpenGL objects, and must be destroyed before the context.
        // No native window is needed. Fails if the configuration does not support pbuffers.
        // Creation preserves the current binding; makeCurrent selects the returned surface.
        mtd createPbufferSurface(width, height: s32)->Surface fail
        {
            if not .isValid() do
                fail Errors.BadParameterError{"cannot create a pbuffer for a closed EGL context"}
            Swag.assert(.thread == Linux.gettid(), "EGL contexts stay on their creating thread")
            let surface = try createPbuffer(.display, .config, width, height)
            return {.display, surface, .context, .thread}
        }

        // Makes the owned initial surface current, or fails if the context or surface was released.
        mtd makeCurrent() fail
        {
            if not .isValid() or not .surface do
                fail Errors.BadParameterError{"EGL context has no owned surface to bind"}
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
            if not .isValid() or not .surface do
                fail Errors.BadParameterError{"EGL context has no owned surface to present"}
            Swag.assert(.thread == Linux.gettid() and
                        Linux.eglGetCurrentContext() == .context and
                        Linux.eglGetCurrentSurface(Linux.EGL_DRAW) == .surface,
                        "presenting needs this EGL surface current on its creating thread")
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
            releaseDisplay(.display)
            Swag.init(me, 1)
        }
    }

    public impl Surface
    {
        // Destroys the owned native surface when this value leaves scope.
        mtd opDrop() { .destroy() }

        // Reports whether this owner still holds a native window surface.
        mtd const isValid()->bool => .handle != null

        // Makes this surface and its borrowed context current on their creating thread.
        //
        // Fails for a destroyed surface. Its borrowed context and window must still be alive.
        mtd makeCurrent() fail
        {
            if not .isValid() do
                fail Errors.BadParameterError{"cannot bind a destroyed EGL surface"}
            Swag.assert(.thread == Linux.gettid(), "EGL surfaces stay on their creating thread")
            try check(Linux.eglBindAPI(Linux.EGL_OPENGL_API), "eglBindAPI")
            if Linux.eglGetCurrentContext() == .context and
               Linux.eglGetCurrentSurface(Linux.EGL_DRAW) == .handle and
               Linux.eglGetCurrentSurface(Linux.EGL_READ) == .handle do
                return
            try check(Linux.eglMakeCurrent(.display, .handle, .handle, .context), "eglMakeCurrent")
        }

        // Presents the window back buffer; this surface and its borrowed context must be current.
        mtd swapBuffers() fail
        {
            if not .isValid() do
                fail Errors.BadParameterError{"cannot present a destroyed EGL surface"}
            Swag.assert(.thread == Linux.gettid() and
                        Linux.eglGetCurrentContext() == .context and
                        Linux.eglGetCurrentSurface(Linux.EGL_DRAW) == .handle,
                        "presenting needs this EGL surface current on its creating thread")
            try check(Linux.eglSwapBuffers(.display, .handle), "eglSwapBuffers")
        }

        // Destroys the surface, unbinding it only if it is current; repeated calls are harmless.
        //
        // The borrowed OpenGL context remains alive and can be bound to another surface.
        mtd destroy()
        {
            if not .handle do
                return
            Swag.assert(.thread == Linux.gettid(), "EGL surfaces stay on their creating thread")
            if Linux.eglGetCurrentSurface(Linux.EGL_DRAW) == .handle or Linux.eglGetCurrentSurface(Linux.EGL_READ) == .handle do
                discard Linux.eglMakeCurrent(.display, null, null, null)
            discard Linux.eglDestroySurface(.display, .handle)
            Swag.init(me, 1)
        }
    }

    // Requests the number of display refresh intervals between swaps of the current EGL surface.
    //
    // Zero requests uncapped presentation. The driver may clamp the interval to its configuration's
    // supported range. Fails for a negative interval or when no EGL context is current.
    public func setSwapInterval(interval: s32) fail
    {
        if interval < 0 do
            fail Errors.BadParameterError{"EGL swap interval cannot be negative"}
        try check(Linux.eglSwapInterval(Linux.eglGetCurrentDisplay(), interval), "eglSwapInterval")
    }

    #drop
    {
        for owner in g_Displays do
            discard Linux.eglTerminate(owner.display)
        g_Displays.clear()
    }
}

namespace Platform.Egl
{
    // EGL context owner; the Xcb spelling remains available for existing window consumers.
    public alias Context = Ogl.Platform.Xcb.Context

    // EGL surface owner, used for a native window or an offscreen pbuffer.
    public alias Surface = Ogl.Platform.Xcb.Surface

    // Creates an OpenGL pbuffer without opening an X11 connection or a visible window.
    //
    // Requires EGL_EXT_platform_base, EGL_MESA_platform_surfaceless and OpenGL 3.3
    // compatibility support. RGB8, alpha8 and stencil8 are required. Makes the context
    // current on its creating thread; failure preserves the previous context. The display
    // remains initialized until its final context is destroyed. Call [[Ogl.glInitExtensions]]
    // before using post-1.1 entry points. There is no software-renderer substitution.
    public func createOffscreenContext(width, height: s32)->Context fail
    {
        if width <= 0 or height <= 0 do
            fail Errors.BadParameterError{"EGL pbuffer dimensions must be positive"}
        var result: #returntype
        result.display = try Ogl.Platform.Xcb.displayFor(null, -1, true)
        result.thread  = Linux.gettid()
        result.screen  = -1
        defer #fail result.destroy()
        let attributes: [15]s32 = [Linux.EGL_SURFACE_TYPE, Linux.EGL_PBUFFER_BIT,
                                   Linux.EGL_RENDERABLE_TYPE, Linux.EGL_OPENGL_BIT,
                                   Linux.EGL_RED_SIZE, 8, Linux.EGL_GREEN_SIZE, 8,
                                   Linux.EGL_BLUE_SIZE, 8, Linux.EGL_ALPHA_SIZE, 8,
                                   Linux.EGL_STENCIL_SIZE, 8, Linux.EGL_NONE]
        var count: s32
        try Ogl.Platform.Xcb.check(Linux.eglChooseConfig(result.display, &attributes[0], &result.config, 1, &count), "eglChooseConfig")
        if count == 0 do
            fail Swag.SystemError{"EGL has no offscreen OpenGL configuration with RGB8, alpha8 and stencil8"}
        result.surface = try Ogl.Platform.Xcb.createPbuffer(result.display, result.config, width, height)
        let previousApi = Linux.eglQueryAPI()
        try Ogl.Platform.Xcb.check(Linux.eglBindAPI(Linux.EGL_OPENGL_API), "eglBindAPI")
        defer #fail discard Linux.eglBindAPI(previousApi)
        let contextAttributes: [7]s32 = [Linux.EGL_CONTEXT_MAJOR_VERSION_KHR, 3,
                                         Linux.EGL_CONTEXT_MINOR_VERSION_KHR, 3, Linux.EGL_CONTEXT_OPENGL_PROFILE_MASK_KHR,
                                         Linux.EGL_CONTEXT_OPENGL_COMPATIBILITY_PROFILE_BIT_KHR, Linux.EGL_NONE]
        result.context = Linux.eglCreateContext(result.display, result.config, null, &contextAttributes[0])
        try Ogl.Platform.Xcb.check(result.context != null ? 1 : 0, "eglCreateContext")
        try result.makeCurrent()
        return result
    }
}
