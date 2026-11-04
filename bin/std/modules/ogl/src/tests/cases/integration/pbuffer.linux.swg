#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Linux
#global private

using Core

// Two pbuffers share GL objects while owning independent storage; display ownership is counted.
#[Swag.TestTag("integration.renderer.offscreen")]
#test
{
    var context = expect Platform.Egl.createOffscreenContext(16, 16)
    glInitExtensions()
    var first  = expect context.takeSurface()
    var second = expect context.createPbufferSurface(24, 24)
    var texture: GLuint
    glGenTextures(1, &texture)
    glBindTexture(GL_TEXTURE_2D, texture)
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 1, 1, 0, GL_RGBA, GL_UNSIGNED_BYTE, null)
    defer glDeleteTextures(1, &texture)
    expect second.makeCurrent()
    Swag.require(glIsTexture(texture) != 0)
    first.destroy()
    glClearColor(0, 1, 0, 1)
    glClear(GL_COLOR_BUFFER_BIT)
    var pixel: u32
    glReadPixels(8, 8, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, &pixel)
    Swag.require(pixel == 0xFF00FF00 and glGetError() == GL_NO_ERROR)
    var independent = expect Platform.Egl.createOffscreenContext(8, 8)
    independent.destroy()
    expect second.makeCurrent()
    glReadPixels(8, 8, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, &pixel)
    Swag.require(pixel == 0xFF00FF00 and glGetError() == GL_NO_ERROR)
    var rejected: bool
    discard catch Platform.Egl.createOffscreenContext(0, 16) { rejected = true; }
    Swag.require(rejected)
    glReadPixels(8, 8, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, &pixel)
    Swag.require(pixel == 0xFF00FF00 and glGetError() == GL_NO_ERROR)
}

private var g_OffscreenPixel: u32

// A second rendering thread owns its context and may close it without unbinding this thread.
#[Swag.TestTag("integration.renderer.offscreen")]
#test
{
    var context = expect Platform.Egl.createOffscreenContext(8, 8)
    glClearColor(0, 0, 1, 1)
    glClear(GL_COLOR_BUFFER_BIT)
    var thread: Threading.Thread
    expect thread.init(func(_)
    {
        var workerContext = expect Platform.Egl.createOffscreenContext(8, 8)
        glClearColor(1, 0, 0, 1)
        glClear(GL_COLOR_BUFFER_BIT)
        glReadPixels(4, 4, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, &g_OffscreenPixel)
    })
    expect thread.start()
    thread.wait()
    Swag.require(g_OffscreenPixel == 0xFF0000FF)
    var pixel: u32
    glReadPixels(4, 4, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, &pixel)
    Swag.require(pixel == 0xFFFF0000 and glGetError() == GL_NO_ERROR)
}

// A pbuffer from a window context remains usable after that window surface and window close.
#[Swag.TestTag("integration.renderer.opengl")]
#test
{
    var window        = expect Env.createWindow({identifier: "egl-window-pbuffer", title: "EGL pbuffer", width: 16, height: 16})
    var context       = expect Platform.Xcb.createContext(&window)
    var windowSurface = expect context.takeSurface()
    var offscreen     = expect context.createPbufferSurface(16, 16)
    expect offscreen.makeCurrent()
    windowSurface.destroy()
    expect window.close()
    glClearColor(1, 0, 1, 1)
    glClear(GL_COLOR_BUFFER_BIT)
    var pixel: u32
    glReadPixels(4, 4, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, &pixel)
    Swag.require(pixel == 0xFFFF00FF and glGetError() == GL_NO_ERROR)
    var otherDisplay = expect Platform.Egl.createOffscreenContext(8, 8)
    otherDisplay.destroy()
    expect offscreen.makeCurrent()
    glReadPixels(4, 4, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, &pixel)
    Swag.require(pixel == 0xFFFF00FF and glGetError() == GL_NO_ERROR)
}

// Final-context teardown on a separate XCB connection must not disturb another current display.
#[Swag.TestTag("integration.renderer.opengl")]
#test
{
    var firstWindow = expect Env.createWindow({identifier: "egl-connections", title: "EGL connections", width: 16, height: 16})
    var first = expect Platform.Xcb.createContext(&firstWindow)
    scope
    {
        let library = Linux.dlopen("libxcb.so.1".buffer, Linux.RTLD_NOW | Linux.RTLD_LOCAL)
        Swag.require(library != null)
        defer discard Linux.dlclose(unwrap library)
        func(T) symbol(library: *void, name: string)->T
        {
            let address = Linux.dlsym(library, name.buffer)
            Swag.require(address != null)
            return cast(T, address)
        }
        let connect = symbol'Linux.xcb_connect_fn(library, "xcb_connect")
        let disconnect = symbol'Linux.xcb_disconnect_fn(library, "xcb_disconnect")
        let setup = symbol'Linux.xcb_get_setup_fn(library, "xcb_get_setup")
        let roots = symbol'Linux.xcb_setup_roots_iterator_fn(library, "xcb_setup_roots_iterator")
        let generate = symbol'Linux.xcb_generate_id_fn(library, "xcb_generate_id")
        let create = symbol'Linux.xcb_create_window_checked_fn(library, "xcb_create_window_checked")
        let check = symbol'Linux.xcb_request_check_fn(library, "xcb_request_check")
        let connection = connect(null, null)
        Swag.require(connection != null)
        defer disconnect(unwrap connection)
        let screen = roots(setup(connection)).data
        Swag.require(screen != null)
        let window = generate(connection)
        let error = check(connection, create(connection, screen.root_depth, window, screen.root,
            0, 0, 16, 16, 0, 1, screen.root_visual, 0, null))
        defer Linux.free(error)
        Swag.require(error == null)
        var second = expect Platform.Xcb.createContextForDrawable({connection, window, screen.root_visual, 0})
        expect first.makeCurrent()
        second.destroy()
    }
    // The second native connection and its EGL display have both gone away.
    glClearColor(0, 0, 1, 1)
    glClear(GL_COLOR_BUFFER_BIT)
    var pixel: u32
    glReadPixels(4, 4, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, &pixel)
    Swag.require(pixel == 0xFFFF0000 and glGetError() == GL_NO_ERROR)
}
