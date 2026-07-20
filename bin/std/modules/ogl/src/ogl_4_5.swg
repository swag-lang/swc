#global public

#[Extension, Swag.PlaceHolder]
{
    func glGetGraphicsResetStatus()->GLenum;
    func glGetnCompressedTexImage(target: GLenum, lod: GLint, bufSize: GLsizei, pixels: #null *GLvoid);
    func glGetnTexImage(tex: GLenum, level: GLint, format: GLenum, type: GLenum, bufSize: GLsizei, pixels: #null *GLvoid);
    func glGetnUniformdv(program: GLuint, location: GLint, bufSize: GLsizei, params: #null *GLdouble);
}

const GL_CONTEXT_FLAG_ROBUST_ACCESS_BIT = 0x00000004
