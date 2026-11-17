using Core, Ogl

var g_Window: Env.Window
#static if #os == Swag.TargetOs.Linux
{
    var g_Context: Ogl.Platform.Xcb.Context
}
else
{
    var g_Context: Ogl.Platform.Win32.Context
}

var g_Frame: Time.FrameTiming

func display() fail
{
    const SPEED = 100
    glClearColor(0, 0, 0, 0)
    glRotatef(SPEED * g_Frame.deltaSeconds, 0.0, 0.0, 1)
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
    #static if #os == Swag.TargetOs.Linux do
        try g_Context.swapBuffers()
    else do
        g_Context.swapBuffers()
}

func onResize(_: *Env.Window, width, height: s32)
{
    glViewport(0, 0, width, height)
}

#main
{
    g_Window = try Env.createWindow({identifier: "opengl1", title: "OpenGL legacy triangle", width: 512, height: 512})
    defer catch g_Window.close()
    #static if #os == Swag.TargetOs.Linux do
        g_Context = try Ogl.Platform.Xcb.createContext(&g_Window)
    else do
        g_Context = try Ogl.Platform.Win32.createContext(&g_Window)
    defer g_Context.destroy()

    g_Window.callbacks.onResize = &onResize

    try g_Window.show()

    var loop: Env.WindowLoop
    while loop.next()
    {
        g_Frame.update()
        try display()
        if Env.isSmokeRun() do
            break
    }
}
