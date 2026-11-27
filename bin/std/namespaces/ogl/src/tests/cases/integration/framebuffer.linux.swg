#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

using Core

// A framebuffer transfer exercises an extension call with ten native C ABI arguments.
#[Swag.TestTag("integration.renderer.opengl")]
#test
{
    var window  = expect Env.createWindow({identifier: "ogl-framebuffer-test", title: "OpenGL framebuffer test", width: 32, height: 32})
    var context = expect Platform.Xcb.createContext(&window)
    glInitExtensions()
    var textures: [2] GLuint
    var buffers:  [2] GLuint
    glGenTextures(2, &textures[0])
    glGenFramebuffers(2, &buffers[0])
    defer glDeleteTextures(2, &textures[0])
    defer glDeleteFramebuffers(2, &buffers[0])
    for index in 2
    {
        glBindTexture(GL_TEXTURE_2D, textures[index])
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 32, 32, 0, GL_RGBA, GL_UNSIGNED_BYTE, null)
        glBindFramebuffer(GL_FRAMEBUFFER, buffers[index])
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, textures[index], 0)
        Swag.require(glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE)
        glClearColor(index == 0 ? 1.0 : 0.0, 0, 0, 1)
        glClear(GL_COLOR_BUFFER_BIT)
    }

    Swag.require(glGetError() == GL_NO_ERROR)
    glBindFramebuffer(GL_READ_FRAMEBUFFER, buffers[0])
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, buffers[1])
    glBlitFramebuffer(0, 32, 32, 0, 0, 0, 32, 32, GL_COLOR_BUFFER_BIT, GL_NEAREST)
    Swag.require(glGetError() == GL_NO_ERROR)
    glBindFramebuffer(GL_READ_FRAMEBUFFER, buffers[1])
    var pixel: u32
    glReadPixels(16, 16, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, cast([*] u8, &pixel))
    Swag.require(pixel == 0xFF0000FF)
}

// Context destruction must not unbind another owner on the same EGL display.
#[Swag.TestTag("integration.renderer.opengl")]
#test
{
    var firstWindow = expect Env.createWindow({identifier: "egl-first", title: "EGL first", width: 32, height: 32})
    var first       = expect Platform.Xcb.createContext(&firstWindow)
    Swag.require(first.isValid())
    let drawable = expect firstWindow.xcbDrawable()
    Swag.require(drawable.connection != null and drawable.window != 0 and drawable.visual != 0)
    var secondWindow = expect Env.createWindow({identifier: "egl-second", title: "EGL second", width: 32, height: 32})
    var second       = expect Platform.Xcb.createContext(&secondWindow)
    first.destroy()
    first.destroy()
    Swag.require(not first.isValid() and second.isValid())
    glClearColor(0, 1, 0, 1)
    glClear(GL_COLOR_BUFFER_BIT)
    var pixel: u32
    glReadPixels(16, 16, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, &pixel)
    Swag.require(pixel == 0xFF00FF00 and glGetError() == GL_NO_ERROR)
    expect secondWindow.showOffScreen()
    expect second.swapBuffers()
    expect second.clearCurrent()
    expect second.makeCurrent()
    glClearColor(0, 0, 1, 1)
    glClear(GL_COLOR_BUFFER_BIT)
    glReadPixels(16, 16, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, &pixel)
    Swag.require(pixel == 0xFFFF0000 and glGetError() == GL_NO_ERROR)
}

#[Swag.TestTag("integration.renderer.opengl")]
#test
{
    var closedWindow: Env.Window
    for 3
    {
        var outcome: Swag.Error
        discard catch Platform.Xcb.createContext(&closedWindow) as outcome
        Swag.require(outcome.value() is Errors.BadParameterError)
    }

    var closed: Platform.Xcb.Context
    closed.destroy()
    var outcome: Swag.Error
    catch closed.makeCurrent() as outcome
    Swag.require(outcome.value() is Errors.BadParameterError)
}

// Surfaces share one context's objects; releasing its first window keeps the second drawable alive.
#[Swag.TestTag("integration.renderer.opengl")]
#test
{
    var firstWindow  = expect Env.createWindow({identifier: "egl-shared-first", title: "First shared drawable", width: 32, height: 32})
    var secondWindow = expect Env.createWindow({identifier: "egl-shared-second", title: "Second shared drawable", width: 32, height: 32})
    var context      = expect Platform.Xcb.createContext(&firstWindow)
    var first        = expect context.takeSurface()
    let drawable     = cast(const *Env.XcbDrawable, unwrap secondWindow.nativeRenderHandle())[]
    var second       = expect context.createSurface(drawable)
    glInitExtensions()
    var texture: GLuint
    glGenTextures(1, &texture)
    glBindTexture(GL_TEXTURE_2D, texture)
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 1, 1, 0, GL_RGBA, GL_UNSIGNED_BYTE, null)
    defer glDeleteTextures(1, &texture)
    expect second.makeCurrent()
    Swag.require(glIsTexture(texture) != 0)
    first.destroy()
    expect firstWindow.close()
    glClearColor(0, 1, 0, 1)
    glClear(GL_COLOR_BUFFER_BIT)
    var pixel: u32
    glReadPixels(16, 16, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, &pixel)
    Swag.require(pixel == 0xFF00FF00 and glGetError() == GL_NO_ERROR)
    expect Platform.Xcb.setSwapInterval(1)
    expect second.swapBuffers()
    expect context.clearCurrent()
    expect second.makeCurrent()
    Swag.require(glIsTexture(texture) != 0)

    var invalid = drawable
    invalid.visual = 0
    var outcome: Swag.Error
    discard catch context.createSurface(invalid) as outcome
    Swag.require(outcome.value() is Errors.BadParameterError)
    outcome = {}
    discard catch context.takeSurface() as outcome
    Swag.require(outcome.value() is Errors.BadParameterError)
}

struct WorkerContextProbe
{
    drawable:  Env.XcbDrawable
    pixel:     u32
    succeeded: bool
}

func renderOnWorker(thread: const *Threading.Thread)
{
    let probe = cast(*WorkerContextProbe, unwrap thread.userParam)
    catch
    {
        var context = try Platform.Xcb.createContextForDrawable(probe.drawable)
        glClearColor(1, 0, 1, 1)
        glClear(GL_COLOR_BUFFER_BIT)
        glReadPixels(8, 8, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, &probe.pixel)
        probe.succeeded = glGetError() == GL_NO_ERROR
    }
}

// A drawable obtained by the UI thread can be borrowed by a separate rendering thread.
#[Swag.TestTag("integration.renderer.opengl")]
#test
{
    var window = expect Env.createWindow({identifier: "egl-worker", title: "Worker context", width: 16, height: 16})
    var probe  = WorkerContextProbe{drawable: cast(const *Env.XcbDrawable, unwrap window.nativeRenderHandle())[]}
    var thread: Threading.Thread
    expect thread.init(&renderOnWorker, &probe)
    expect thread.start()
    thread.wait()
    Swag.require(probe.succeeded and probe.pixel == 0xFFFF00FF)
}
