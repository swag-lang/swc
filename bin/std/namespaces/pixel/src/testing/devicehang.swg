#global public
#global namespace Testing

using Core, Ogl

// Submits one OpenGL draw so long that the system resets the graphics device, and returns at once.
//
// The draw runs in the context current on the calling thread, which makes that context the one
// the driver holds responsible: it is how a test reproduces what a heavily loaded machine does to
// a renderer, and exercises [[Pixel.RenderOgl.recoverLostDevice]] on a real reset. Every fragment
// of a 1024x1024 target spins far past the two seconds Windows allows a GPU packet, on any adapter.
//
// > WARNING: This resets the device for real. Displays driven through a USB graphics adapter can
// > go dark for a few seconds while the driver recovers, and other processes drawing at that
// > moment can lose their work too. Keep it to tests that are run on their own.
func submitDeviceHang()
{
    const Vertex   = """
        #version 330 core
        void main()
        {
            vec2 corner = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
            gl_Position = vec4(corner * 2.0 - 1.0, 0.0, 1.0);
        }
        """
    const Fragment = """
        #version 330 core
        uniform int count;
        out vec4 color;
        void main()
        {
            float value = gl_FragCoord.x * 0.001 + gl_FragCoord.y * 0.002;
            for (int i = 0; i < count; i++)
                value = fract(sin(value * 1.0001 + float(i)) * 43758.5453);
            color = vec4(value, value, value, 1.0);
        }
        """

    func compile(kind: GLenum, source: string)->GLuint
    {
        let shader  = glCreateShader(kind)
        var pointer = source.buffer
        var length  = cast(GLint, source.count)
        glShaderSource(shader, 1, &pointer, &length)
        glCompileShader(shader)
        var compiled: GLint
        glGetShaderiv(shader, GL_COMPILE_STATUS, &compiled)
        Swag.assert(compiled != 0, "the device-hang shader does not compile")
        return shader
    }

    // The program and its target are never released: the reset takes them with the context.
    let program = glCreateProgram()
    glAttachShader(program, compile(GL_VERTEX_SHADER, Vertex))
    glAttachShader(program, compile(GL_FRAGMENT_SHADER, Fragment))
    glLinkProgram(program)
    glUseProgram(program)
    glUniform1i(glGetUniformLocation(program, ("count").buffer), 100_000_000)

    var texture, framebuffer: GLuint
    glGenTextures(1, &texture)
    glBindTexture(GL_TEXTURE_2D, texture)
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 1024, 1024, 0, GL_RGBA, GL_UNSIGNED_BYTE, null)
    glGenFramebuffers(1, &framebuffer)
    glBindFramebuffer(GL_FRAMEBUFFER, framebuffer)
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture, 0)
    glViewport(0, 0, 1024, 1024)

    // The triangle comes from the vertex index, so no vertex array is involved.
    glDrawArrays(GL_TRIANGLES, 0, 3)
    glFlush()
}
