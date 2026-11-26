using Core, Ogl

private func compileShader(stage: GLenum, source: string)->GLuint fail
{
    let shader = glCreateShader(stage)
    defer #fail glDeleteShader(shader)

    var pointer = source.buffer
    var length  = cast(GLint, source.count)
    glShaderSource(shader, 1, &pointer, &length)
    glCompileShader(shader)

    var status: GLint
    glGetShaderiv(shader, GL_COMPILE_STATUS, &status)
    if not status
    {
        glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &length)
        var log: String
        log.reserve(cast(u64, length) + 1)
        var written: GLsizei
        glGetShaderInfoLog(shader, length, &written, log.buffer)
        log.length = cast(u64, written)
        fail Swag.SystemError{Errors.mkString(Format.toString("Cannot compile the shader. %", log))}
    }

    return shader
}

func createProgram(vertexSource, fragmentSource: string)->GLuint fail
{
    let vertex = try compileShader(GL_VERTEX_SHADER, vertexSource)
    defer glDeleteShader(vertex)
    let fragment = try compileShader(GL_FRAGMENT_SHADER, fragmentSource)
    defer glDeleteShader(fragment)

    let program = glCreateProgram()
    defer #fail glDeleteProgram(program)
    glAttachShader(program, vertex)
    glAttachShader(program, fragment)
    glLinkProgram(program)

    var status: GLint
    glGetProgramiv(program, GL_LINK_STATUS, &status)
    if not status
    {
        var length: GLint
        glGetProgramiv(program, GL_INFO_LOG_LENGTH, &length)
        var log: String
        log.reserve(cast(u64, length) + 1)
        var written: GLsizei
        glGetProgramInfoLog(program, length, &written, log.buffer)
        log.length = cast(u64, written)
        fail Swag.SystemError{Errors.mkString(Format.toString("Cannot link the shader program. %", log))}
    }

    glDetachShader(program, vertex)
    glDetachShader(program, fragment)
    return program
}
