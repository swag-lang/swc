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

const VertexBufferData: [?] GLfloat = [
    -0.658, -0.38,
    0.658, -0.38,
    0.0, 0.76]

const VertexShader = """
    #version 330 core
    layout(location = 0) in vec2 position;
    void main()
    {
        gl_Position = vec4(position, 0.0, 1.0);
    }
"""

const FragmentShader = """
    #version 330 core
    out vec4 color;
    void main()
    {
        color = vec4(0.22, 0.74, 0.97, 1.0);
    }
"""

func display() fail
{
    glClearColor(0.06, 0.07, 0.10, 1)
    glClear(GL_COLOR_BUFFER_BIT)

    glDrawArrays(GL_TRIANGLES, 0, 3)

    glFlush()
    #static if #os == Swag.TargetOs.Linux do
        try g_Context.swapBuffers()
    else do
        g_Context.swapBuffers()
}

func onResize(_: *Env.Window, width, height: s32)
{
    let extent = Math.min(width, height)
    glViewport((width - extent) / 2, (height - extent) / 2, extent, extent)
}

#main
{
    g_Window = try Env.createWindow({identifier: "opengl2", title: "OpenGL shader triangle", width: 512, height: 512})
    defer catch g_Window.close()
    #static if #os == Swag.TargetOs.Linux do
        g_Context = try Ogl.Platform.Xcb.createContext(&g_Window)
    else do
        g_Context = try Ogl.Platform.Win32.createContext(&g_Window)
    defer g_Context.destroy()
    glInitExtensions()

    var vertexArray: GLuint
    glGenVertexArrays(1, &vertexArray)
    defer glDeleteVertexArrays(1, &vertexArray)
    glBindVertexArray(vertexArray)

    var vertexBuffer: GLuint
    glGenBuffers(1, &vertexBuffer)
    defer glDeleteBuffers(1, &vertexBuffer)
    glBindBuffer(GL_ARRAY_BUFFER, vertexBuffer)
    glBufferData(GL_ARRAY_BUFFER, #sizeof(VertexBufferData), VertexBufferData.buffer, GL_STATIC_DRAW)
    glEnableVertexAttribArray(0)
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, null)

    let program = try createProgram(VertexShader, FragmentShader)
    defer glDeleteProgram(program)
    glUseProgram(program)

    g_Window.callbacks.onResize = &onResize

    try g_Window.show()

    var loop: Env.WindowLoop
    while loop.next()
    {
        try display()
        if Env.isSmokeRun() do
            break
    }
}
