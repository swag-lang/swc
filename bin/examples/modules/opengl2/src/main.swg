using Core, Ogl, Core.Time

var g_Window:       Env.Window
var g_Context:      Ogl.Platform.Win32.Context
var g_VertexBuffer: GLuint
var g_ProgramID:    GLuint

const VertexBufferData: [?] GLfloat = [
    -1.0, -1.0, 0.0,
    1.0, -1.0, 0.0,
    0.0, 1.0, 0.0]

const VertexShader = """
    #version 330 core
    layout(location = 0) in vec3 vertexPosition_modelspace;
    out vec3 vcolor;
    void main()
    {
        gl_Position.xyz = vertexPosition_modelspace;
        gl_Position.w = 1.0;
        vcolor = vec3(1,0,1);
    }
"""

const PixelShader = """
    #version 330 core
    in vec3 vcolor;
    out vec3 color;
    void main()
    {
        color = vcolor;//vec3(1,0,0);
    }
"""

func display()
{
    glClearColor(0, 0, 0, 0)
    glClear(GL_COLOR_BUFFER_BIT)

    glUseProgram(g_ProgramID)
    glEnableVertexAttribArray(0)
    glBindBuffer(GL_ARRAY_BUFFER, g_VertexBuffer)
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 0, null)
    glDrawArrays(GL_TRIANGLES, 0, 3)
    glDisableVertexAttribArray(0)

    glFlush()
    g_Context.swapBuffers()
}

func onPaint(_window: *Env.Window)
{
    display()
}

func onResize(_window: *Env.Window, width, height: s32)
{
    glViewport(0, 0, width, height)
    display()
}

func createShader()
{
    var result:        GLint
    var infoLogLength: s32
    var infoLog:       String

    let vertexShaderID      = glCreateShader(GL_VERTEX_SHADER)
    var vertexSourcePointer = @dataof(VertexShader)
    glShaderSource(vertexShaderID, 1, &vertexSourcePointer, null)
    glCompileShader(vertexShaderID)
    glGetShaderiv(vertexShaderID, GL_COMPILE_STATUS, &result)
    glGetShaderiv(vertexShaderID, GL_INFO_LOG_LENGTH, &infoLogLength)
    infoLog.reserve(cast(u64) infoLogLength + 1)
    glGetShaderInfoLog(vertexShaderID, infoLogLength, null, infoLog.buffer)

    let fragmentShaderID   = glCreateShader(GL_FRAGMENT_SHADER)
    var pixelSourcePointer = @dataof(PixelShader)
    glShaderSource(fragmentShaderID, 1, &pixelSourcePointer, null)
    glCompileShader(fragmentShaderID)
    glGetShaderiv(fragmentShaderID, GL_COMPILE_STATUS, &result)
    glGetShaderiv(fragmentShaderID, GL_INFO_LOG_LENGTH, &infoLogLength)
    infoLog.reserve(cast(u64) infoLogLength + 1)
    glGetShaderInfoLog(fragmentShaderID, infoLogLength, null, infoLog.buffer)

    g_ProgramID = glCreateProgram()
    glAttachShader(g_ProgramID, vertexShaderID)
    glAttachShader(g_ProgramID, fragmentShaderID)
    glLinkProgram(g_ProgramID)
    glGetProgramiv(g_ProgramID, GL_LINK_STATUS, &result)
    glGetProgramiv(g_ProgramID, GL_INFO_LOG_LENGTH, &infoLogLength)
    glGetProgramInfoLog(g_ProgramID, infoLogLength, null, infoLog.buffer)

    glDetachShader(g_ProgramID, vertexShaderID)
    glDetachShader(g_ProgramID, fragmentShaderID)
    glDeleteShader(vertexShaderID)
    glDeleteShader(fragmentShaderID)
}

#main
{
    try Env.createWindow(&g_Window, {className: "OPENGL2_CLASS_NAME", title: "OpenGL example", width: 512, height: 512})
    g_Context = try Ogl.Platform.Win32.createContext(&g_Window)
    glInitExtensions()

    glGenBuffers(1, &g_VertexBuffer)
    glBindBuffer(GL_ARRAY_BUFFER, g_VertexBuffer)
    glBufferData(GL_ARRAY_BUFFER, #sizeof(VertexBufferData), @dataof(VertexBufferData), GL_STATIC_DRAW)
    createShader()

    g_Window.callbacks.onPaint  = &onPaint
    g_Window.callbacks.onResize = &onResize

    display()
    try g_Window.show()

    var loop: Env.WindowLoop
    while loop.next()
    {
        display()
    }

    g_Context.destroy()
}
