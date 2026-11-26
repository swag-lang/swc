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
var g_Angle: f32

func display() fail
{
    g_Angle += 75 * g_Frame.deltaSeconds
    if g_Angle >= 360 do
        g_Angle -= 360

    glClearColor(0.06, 0.07, 0.10, 1)
    glClear(GL_COLOR_BUFFER_BIT)
    glMatrixMode(GL_MODELVIEW)
    glLoadIdentity()
    glRotatef(g_Angle, 0, 0, 1)
    glBegin(GL_TRIANGLES)
    glColor3f(1.0, 0.0, 0.0)
    glVertex2f(0, 0.76)
    glColor3f(0.0, 1.0, 0.0)
    glVertex2f(-0.658, -0.38)
    glColor3f(0.0, 0.0, 1.0)
    glVertex2f(0.658, -0.38)
    glEnd()
    glFlush()
    #static if #os == Swag.TargetOs.Linux do
        try g_Context.swapBuffers()
    else do
        g_Context.swapBuffers()
}

func onResize(_: *Env.Window, width, height: s32)
{
    // A centered square viewport preserves the triangle’s proportions on resize.
    let extent = Math.min(width, height)
    glViewport((width - extent) / 2, (height - extent) / 2, extent, extent)
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
