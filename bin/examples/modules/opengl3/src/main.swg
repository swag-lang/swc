// A spinning, directionally-lit 3D cube rendered with modern OpenGL.
//
// Highlights compared to the opengl2 triangle:
//   - Interleaved vertex buffer (position + normal + color) and an index buffer.
//   - A perspective projection and a model/view transform built on the CPU and
//     uploaded as mat4 uniforms.
//   - Per-pixel diffuse lighting from a fixed light direction in the shader.
//   - Back-face culling, which renders a convex solid correctly without needing
//     a depth buffer (the legacy context does not request one).

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

var g_LocMVP:      GLint
var g_LocModel:    GLint
var g_LocLightDir: GLint

var g_Width:  s32 = 640
var g_Height: s32 = 640
var g_Angle:  f32

// 24 vertices (4 per face) so each face carries its own flat normal and color.
// Layout per vertex: position.xyz, normal.xyz, color.rgb.
const Vertices: [?] GLfloat = [
    // Front face (+Z) - red
    -1, -1, 1, 0, 0, 1, 0.95, 0.30, 0.30,
     1, -1, 1, 0, 0, 1, 0.95, 0.30, 0.30,
     1, 1, 1, 0, 0, 1, 0.95, 0.30, 0.30,
    -1, 1, 1, 0, 0, 1, 0.95, 0.30, 0.30,
     // Back face (-Z) - green
     1, -1, -1, 0, 0, -1, 0.30, 0.80, 0.40,
    -1, -1, -1, 0, 0, -1, 0.30, 0.80, 0.40,
    -1, 1, -1, 0, 0, -1, 0.30, 0.80, 0.40,
     1, 1, -1, 0, 0, -1, 0.30, 0.80, 0.40,
    // Left face (-X) - blue
    -1, -1, -1, -1, 0, 0, 0.30, 0.55, 0.95,
    -1, -1, 1, -1, 0, 0, 0.30, 0.55, 0.95,
    -1, 1, 1, -1, 0, 0, 0.30, 0.55, 0.95,
    -1, 1, -1, -1, 0, 0, 0.30, 0.55, 0.95,
     // Right face (+X) - yellow
     1, -1, 1, 1, 0, 0, 0.95, 0.80, 0.30,
     1, -1, -1, 1, 0, 0, 0.95, 0.80, 0.30,
     1, 1, -1, 1, 0, 0, 0.95, 0.80, 0.30,
     1, 1, 1, 1, 0, 0, 0.95, 0.80, 0.30,
    // Top face (+Y) - magenta
    -1, 1, 1, 0, 1, 0, 0.85, 0.45, 0.90,
     1, 1, 1, 0, 1, 0, 0.85, 0.45, 0.90,
     1, 1, -1, 0, 1, 0, 0.85, 0.45, 0.90,
    -1, 1, -1, 0, 1, 0, 0.85, 0.45, 0.90,
    // Bottom face (-Y) - cyan
    -1, -1, -1, 0, -1, 0, 0.40, 0.85, 0.90,
     1, -1, -1, 0, -1, 0, 0.40, 0.85, 0.90,
     1, -1, 1, 0, -1, 0, 0.40, 0.85, 0.90,
    -1, -1, 1, 0, -1, 0, 0.40, 0.85, 0.90]

// Two triangles per face, wound counter-clockwise when seen from outside.
const Indices: [?] GLuint = [
    0, 1, 2, 0, 2, 3,
    4, 5, 6, 4, 6, 7,
    8, 9, 10, 8, 10, 11,
    12, 13, 14, 12, 14, 15,
    16, 17, 18, 16, 18, 19,
    20, 21, 22, 20, 22, 23]

const VertexShader = """
    #version 330 core
    layout(location = 0) in vec3 aPos;
    layout(location = 1) in vec3 aNormal;
    layout(location = 2) in vec3 aColor;
    uniform mat4 uMVP;
    uniform mat4 uModel;
    out vec3 vNormal;
    out vec3 vColor;
    void main()
    {
        gl_Position = uMVP * vec4(aPos, 1.0);
        vNormal     = mat3(uModel) * aNormal;
        vColor      = aColor;
    }
"""

const FragmentShader = """
    #version 330 core
    in vec3 vNormal;
    in vec3 vColor;
    uniform vec3 uLightDir;
    out vec4 fragColor;
    void main()
    {
        vec3  n       = normalize(vNormal);
        float diffuse = max(dot(n, normalize(uLightDir)), 0.0);
        float ambient = 0.25;
        vec3  shaded  = vColor * (ambient + diffuse * 0.85);
        fragColor     = vec4(shaded, 1.0);
    }
"""

// Column-major 4x4 matrix, ready to upload to OpenGL with transpose = GL_FALSE.
struct Mat4
{
    m: [16] f32
}

impl Mat4
{
    func identity()->Mat4
    {
        var r: Mat4
        r.m[0]  = 1
        r.m[5]  = 1
        r.m[10] = 1
        r.m[15] = 1
        return r
    }

    // C = A * B (both column-major).
    func mul(a, b: Mat4)->Mat4
    {
        var r: Mat4
        for col in 4
        {
            for row in 4
            {
                var sum = 0'f32
                for k in 4 do
                    sum += a.m[k * 4 + row] * b.m[col * 4 + k]
                r.m[col * 4 + row] = sum
            }
        }

        return r
    }

    func perspective(fovY, aspect, near, far: f32)->Mat4
    {
        let f = 1 / Math.tan(fovY * 0.5)
        var r: Mat4
        r.m[0]  = f / aspect
        r.m[5]  = f
        r.m[10] = (far + near) / (near - far)
        r.m[11] = -1
        r.m[14] = (2 * far * near) / (near - far)
        return r
    }

    func translation(x, y, z: f32)->Mat4
    {
        var r = Mat4.identity()
        r.m[12] = x
        r.m[13] = y
        r.m[14] = z
        return r
    }

    func rotationX(a: f32)->Mat4
    {
        let c = Math.cos(a)
        let s = Math.sin(a)
        var r = Mat4.identity()
        r.m[5]  = c
        r.m[6]  = s
        r.m[9]  = -s
        r.m[10] = c
        return r
    }

    func rotationY(a: f32)->Mat4
    {
        let c = Math.cos(a)
        let s = Math.sin(a)
        var r = Mat4.identity()
        r.m[0]  = c
        r.m[2]  = -s
        r.m[8]  = s
        r.m[10] = c
        return r
    }
}

func display() fail
{
    g_Angle += g_Frame.deltaSeconds

    if g_Width <= 0 or g_Height <= 0 do
        return

    glClearColor(0.06, 0.07, 0.10, 1)
    glClear(GL_COLOR_BUFFER_BIT)

    // Build model -> view -> projection. The model spins on two axes, the view
    // pushes the cube away from the camera, and the projection adds perspective.
    let aspect     = cast(f32, g_Width) / cast(f32, g_Height)
    let model      = Mat4.mul(Mat4.rotationY(g_Angle * 0.9), Mat4.rotationX(g_Angle * 0.6))
    let view       = Mat4.translation(0, 0, -6)
    let projection = Mat4.perspective(Math.toRadians(45'f32), aspect, 0.1, 100)
    var mvp        = Mat4.mul(projection, Mat4.mul(view, model))
    var modelCopy  = model

    glUniformMatrix4fv(g_LocMVP, 1, GL_FALSE, &mvp.m[0])
    glUniformMatrix4fv(g_LocModel, 1, GL_FALSE, &modelCopy.m[0])

    glDrawElements(GL_TRIANGLES, Indices.count, GL_UNSIGNED_INT, null)

    glFlush()
    #static if #os == Swag.TargetOs.Linux do
        try g_Context.swapBuffers()
    else do
        g_Context.swapBuffers()
}

func onResize(_: *Env.Window, width, height: s32)
{
    g_Width  = width
    g_Height = height
    glViewport(0, 0, width, height)
}

#main
{
    g_Window = try Env.createWindow({
        identifier: "opengl3",
        title: "OpenGL example - lit spinning cube",
        width: g_Width,
        height: g_Height})
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
    glBufferData(GL_ARRAY_BUFFER, #sizeof(Vertices), Vertices.buffer, GL_STATIC_DRAW)

    var indexBuffer: GLuint
    glGenBuffers(1, &indexBuffer)
    defer glDeleteBuffers(1, &indexBuffer)
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, indexBuffer)
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, #sizeof(Indices), Indices.buffer, GL_STATIC_DRAW)

    const Stride = 9 * #sizeof(GLfloat)
    for attribute in 3
    {
        let index  = cast(GLuint, attribute)
        let offset = cast(const [*] u8?, attribute * 3 * #sizeof(GLfloat))
        glEnableVertexAttribArray(index)
        glVertexAttribPointer(index, 3, GL_FLOAT, GL_FALSE, Stride, offset)
    }

    let program = try createProgram(VertexShader, FragmentShader)
    defer glDeleteProgram(program)
    glUseProgram(program)
    g_LocMVP      = glGetUniformLocation(program, "uMVP".buffer)
    g_LocModel    = glGetUniformLocation(program, "uModel".buffer)
    g_LocLightDir = glGetUniformLocation(program, "uLightDir".buffer)
    glUniform3f(g_LocLightDir, 0.4, 0.7, 1.0)

    glEnable(GL_CULL_FACE)
    glCullFace(GL_BACK)
    glFrontFace(GL_CCW)

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
