using Core, Ogl

var g_Window:    Env.Window
var g_Context:   Ogl.Platform.Win32.Context
var g_Frame:     Time.FrameTiming

func display()
{
    const SPEED = 100
    glClearColor(0, 0, 0, 0)
    glRotatef(SPEED * g_Frame.dt, 0.0, 0.0, 1)
    glClear(GL_COLOR_BUFFER_BIT)
    glBegin(GL_TRIANGLES)
    glColor3f(1.0, 0.0, 0.0)
    glVertex2i(0, 1)
    glColor3f(0.0, 1.0, 0.0)
    glVertex2i(-1, -1)
    glColor3f(0.0, 0.0, 1.0)
    glVertex2i(1, -1)
    glEnd()
    glFlush()
    g_Context.swapBuffers()
}

func onPaint(_window: *Env.Window)
{
    display()
}

func onResize(window: *Env.Window, width, height: s32)
{
    glViewport(0, 0, width, height)
    window.requestPaint()
}

#main
{
    try Env.createWindow(&g_Window, {className: "OPENGL1_CLASS_NAME", title: "OpenGL example", width: 512, height: 512})
    g_Context = try Ogl.Platform.Win32.createContext(&g_Window)

    g_Window.callbacks.onPaint  = &onPaint
    g_Window.callbacks.onResize = &onResize

    display()
    try g_Window.show()

    var loop: Env.WindowLoop
    while true
    {
        g_Frame.update()

        g_Frame.pause()
        if !loop.next()
        {
            g_Frame.unpause()
            break
        }
        g_Frame.unpause()

        display()
    }

    g_Context.destroy()
}
