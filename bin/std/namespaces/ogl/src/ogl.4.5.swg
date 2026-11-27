#global public

using Swag

#[Extension, Swag.PlaceHolder]
{
    func glBindTextureUnit(unit: GLuint, texture: GLuint)
    func glBlitNamedFramebuffer(readFramebuffer: GLuint, drawFramebuffer: GLuint, srcX0: GLint, srcY0: GLint, srcX1: GLint, srcY1: GLint, dstX0: GLint, dstY0: GLint, dstX1: GLint, dstY1: GLint, mask: GLbitfield, filter: GLenum)
    func glCheckNamedFramebufferStatus(framebuffer: GLuint, target: GLenum)->GLenum
    func glClearNamedBufferData(buffer: GLuint, internalformat: GLenum, format: GLenum, type: GLenum, data: const *void?)
    func glClearNamedBufferSubData(buffer: GLuint, internalformat: GLenum, offset: GLintptr, size: GLsizeiptr, format: GLenum, type: GLenum, data: const *void?)
    func glClearNamedFramebufferfi(framebuffer: GLuint, buffer: GLenum, drawbuffer: GLint, depth: GLfloat, stencil: GLint)
    func glClearNamedFramebufferfv(framebuffer: GLuint, buffer: GLenum, drawbuffer: GLint, value: const *GLfloat?)
    func glClearNamedFramebufferiv(framebuffer: GLuint, buffer: GLenum, drawbuffer: GLint, value: const *GLint?)
    func glClearNamedFramebufferuiv(framebuffer: GLuint, buffer: GLenum, drawbuffer: GLint, value: const *GLuint?)
    func glClipControl(origin: GLenum, depth: GLenum)
    func glCompressedTextureSubImage1D(texture: GLuint, level: GLint, xoffset: GLint, width: GLsizei, format: GLenum, imageSize: GLsizei, data: const *void?)
    func glCompressedTextureSubImage2D(texture: GLuint, level: GLint, xoffset: GLint, yoffset: GLint, width: GLsizei, height: GLsizei, format: GLenum, imageSize: GLsizei, data: const *void?)
    func glCompressedTextureSubImage3D(texture: GLuint, level: GLint, xoffset: GLint, yoffset: GLint, zoffset: GLint, width: GLsizei, height: GLsizei, depth: GLsizei, format: GLenum, imageSize: GLsizei, data: const *void?)
    func glCopyNamedBufferSubData(readBuffer: GLuint, writeBuffer: GLuint, readOffset: GLintptr, writeOffset: GLintptr, size: GLsizeiptr)
    func glCopyTextureSubImage1D(texture: GLuint, level: GLint, xoffset: GLint, x: GLint, y: GLint, width: GLsizei)
    func glCopyTextureSubImage2D(texture: GLuint, level: GLint, xoffset: GLint, yoffset: GLint, x: GLint, y: GLint, width: GLsizei, height: GLsizei)
    func glCopyTextureSubImage3D(texture: GLuint, level: GLint, xoffset: GLint, yoffset: GLint, zoffset: GLint, x: GLint, y: GLint, width: GLsizei, height: GLsizei)
    func glCreateBuffers(n: GLsizei, buffers: *GLuint?)
    func glCreateFramebuffers(n: GLsizei, framebuffers: *GLuint?)
    func glCreateProgramPipelines(n: GLsizei, pipelines: *GLuint?)
    func glCreateQueries(target: GLenum, n: GLsizei, ids: *GLuint?)
    func glCreateRenderbuffers(n: GLsizei, renderbuffers: *GLuint?)
    func glCreateSamplers(n: GLsizei, samplers: *GLuint?)
    func glCreateTextures(target: GLenum, n: GLsizei, textures: *GLuint?)
    func glCreateTransformFeedbacks(n: GLsizei, ids: *GLuint?)
    func glCreateVertexArrays(n: GLsizei, arrays: *GLuint?)
    func glDisableVertexArrayAttrib(vaobj: GLuint, index: GLuint)
    func glEnableVertexArrayAttrib(vaobj: GLuint, index: GLuint)
    func glFlushMappedNamedBufferRange(buffer: GLuint, offset: GLintptr, length: GLsizeiptr)
    func glGenerateTextureMipmap(texture: GLuint)
    func glGetCompressedTextureImage(texture: GLuint, level: GLint, bufSize: GLsizei, pixels: *void?)
    func glGetCompressedTextureSubImage(texture: GLuint, level: GLint, xoffset: GLint, yoffset: GLint, zoffset: GLint, width: GLsizei, height: GLsizei, depth: GLsizei, bufSize: GLsizei, pixels: *void?)
    func glGetGraphicsResetStatus()->GLenum
    func glGetNamedBufferParameteri64v(buffer: GLuint, pname: GLenum, params: *GLint64?)
    func glGetNamedBufferParameteriv(buffer: GLuint, pname: GLenum, params: *GLint?)
    func glGetNamedBufferPointerv(buffer: GLuint, pname: GLenum, params: *(*void?)?)
    func glGetNamedBufferSubData(buffer: GLuint, offset: GLintptr, size: GLsizeiptr, data: *void?)
    func glGetNamedFramebufferAttachmentParameteriv(framebuffer: GLuint, attachment: GLenum, pname: GLenum, params: *GLint?)
    func glGetNamedFramebufferParameteriv(framebuffer: GLuint, pname: GLenum, param: *GLint?)
    func glGetNamedRenderbufferParameteriv(renderbuffer: GLuint, pname: GLenum, params: *GLint?)
    func glGetQueryBufferObjecti64v(id: GLuint, buffer: GLuint, pname: GLenum, offset: GLintptr)
    func glGetQueryBufferObjectiv(id: GLuint, buffer: GLuint, pname: GLenum, offset: GLintptr)
    func glGetQueryBufferObjectui64v(id: GLuint, buffer: GLuint, pname: GLenum, offset: GLintptr)
    func glGetQueryBufferObjectuiv(id: GLuint, buffer: GLuint, pname: GLenum, offset: GLintptr)
    func glGetTextureImage(texture: GLuint, level: GLint, format: GLenum, type: GLenum, bufSize: GLsizei, pixels: *void?)
    func glGetTextureLevelParameterfv(texture: GLuint, level: GLint, pname: GLenum, params: *GLfloat?)
    func glGetTextureLevelParameteriv(texture: GLuint, level: GLint, pname: GLenum, params: *GLint?)
    func glGetTextureParameterIiv(texture: GLuint, pname: GLenum, params: *GLint?)
    func glGetTextureParameterIuiv(texture: GLuint, pname: GLenum, params: *GLuint?)
    func glGetTextureParameterfv(texture: GLuint, pname: GLenum, params: *GLfloat?)
    func glGetTextureParameteriv(texture: GLuint, pname: GLenum, params: *GLint?)
    func glGetTextureSubImage(texture: GLuint, level: GLint, xoffset: GLint, yoffset: GLint, zoffset: GLint, width: GLsizei, height: GLsizei, depth: GLsizei, format: GLenum, type: GLenum, bufSize: GLsizei, pixels: *void?)
    func glGetTransformFeedbacki64_v(xfb: GLuint, pname: GLenum, index: GLuint, param: *GLint64?)
    func glGetTransformFeedbacki_v(xfb: GLuint, pname: GLenum, index: GLuint, param: *GLint?)
    func glGetTransformFeedbackiv(xfb: GLuint, pname: GLenum, param: *GLint?)
    func glGetVertexArrayIndexed64iv(vaobj: GLuint, index: GLuint, pname: GLenum, param: *GLint64?)
    func glGetVertexArrayIndexediv(vaobj: GLuint, index: GLuint, pname: GLenum, param: *GLint?)
    func glGetVertexArrayiv(vaobj: GLuint, pname: GLenum, param: *GLint?)
    func glGetnCompressedTexImage(target: GLenum, lod: GLint, bufSize: GLsizei, pixels: *GLvoid?)
    func glGetnTexImage(tex: GLenum, level: GLint, format: GLenum, type: GLenum, bufSize: GLsizei, pixels: *GLvoid?)
    func glGetnUniformdv(program: GLuint, location: GLint, bufSize: GLsizei, params: *GLdouble?)
    func glGetnUniformfv(program: GLuint, location: GLint, bufSize: GLsizei, params: *GLfloat?)
    func glGetnUniformiv(program: GLuint, location: GLint, bufSize: GLsizei, params: *GLint?)
    func glGetnUniformuiv(program: GLuint, location: GLint, bufSize: GLsizei, params: *GLuint?)
    func glInvalidateNamedFramebufferData(framebuffer: GLuint, numAttachments: GLsizei, attachments: const *GLenum?)
    func glInvalidateNamedFramebufferSubData(framebuffer: GLuint, numAttachments: GLsizei, attachments: const *GLenum?, x: GLint, y: GLint, width: GLsizei, height: GLsizei)
    func glMemoryBarrierByRegion(barriers: GLbitfield)
    func glNamedBufferData(buffer: GLuint, size: GLsizeiptr, data: const *void?, usage: GLenum)
    func glNamedBufferStorage(buffer: GLuint, size: GLsizeiptr, data: const *void?, flags: GLbitfield)
    func glNamedBufferSubData(buffer: GLuint, offset: GLintptr, size: GLsizeiptr, data: const *void?)
    func glNamedFramebufferDrawBuffer(framebuffer: GLuint, buf: GLenum)
    func glNamedFramebufferDrawBuffers(framebuffer: GLuint, n: GLsizei, bufs: const *GLenum?)
    func glNamedFramebufferParameteri(framebuffer: GLuint, pname: GLenum, param: GLint)
    func glNamedFramebufferReadBuffer(framebuffer: GLuint, src: GLenum)
    func glNamedFramebufferRenderbuffer(framebuffer: GLuint, attachment: GLenum, renderbuffertarget: GLenum, renderbuffer: GLuint)
    func glNamedFramebufferTexture(framebuffer: GLuint, attachment: GLenum, texture: GLuint, level: GLint)
    func glNamedFramebufferTextureLayer(framebuffer: GLuint, attachment: GLenum, texture: GLuint, level: GLint, layer: GLint)
    func glNamedRenderbufferStorage(renderbuffer: GLuint, internalformat: GLenum, width: GLsizei, height: GLsizei)
    func glNamedRenderbufferStorageMultisample(renderbuffer: GLuint, samples: GLsizei, internalformat: GLenum, width: GLsizei, height: GLsizei)
    func glReadnPixels(x: GLint, y: GLint, width: GLsizei, height: GLsizei, format: GLenum, type: GLenum, bufSize: GLsizei, data: *void?)
    func glTextureBarrier()
    func glTextureBuffer(texture: GLuint, internalformat: GLenum, buffer: GLuint)
    func glTextureBufferRange(texture: GLuint, internalformat: GLenum, buffer: GLuint, offset: GLintptr, size: GLsizeiptr)
    func glTextureParameterIiv(texture: GLuint, pname: GLenum, params: const *GLint?)
    func glTextureParameterIuiv(texture: GLuint, pname: GLenum, params: const *GLuint?)
    func glTextureParameterf(texture: GLuint, pname: GLenum, param: GLfloat)
    func glTextureParameterfv(texture: GLuint, pname: GLenum, param: const *GLfloat?)
    func glTextureParameteri(texture: GLuint, pname: GLenum, param: GLint)
    func glTextureParameteriv(texture: GLuint, pname: GLenum, param: const *GLint?)
    func glTextureStorage1D(texture: GLuint, levels: GLsizei, internalformat: GLenum, width: GLsizei)
    func glTextureStorage2D(texture: GLuint, levels: GLsizei, internalformat: GLenum, width: GLsizei, height: GLsizei)
    func glTextureStorage2DMultisample(texture: GLuint, samples: GLsizei, internalformat: GLenum, width: GLsizei, height: GLsizei, fixedsamplelocations: GLboolean)
    func glTextureStorage3D(texture: GLuint, levels: GLsizei, internalformat: GLenum, width: GLsizei, height: GLsizei, depth: GLsizei)
    func glTextureStorage3DMultisample(texture: GLuint, samples: GLsizei, internalformat: GLenum, width: GLsizei, height: GLsizei, depth: GLsizei, fixedsamplelocations: GLboolean)
    func glTextureSubImage1D(texture: GLuint, level: GLint, xoffset: GLint, width: GLsizei, format: GLenum, type: GLenum, pixels: const *void?)
    func glTextureSubImage2D(texture: GLuint, level: GLint, xoffset: GLint, yoffset: GLint, width: GLsizei, height: GLsizei, format: GLenum, type: GLenum, pixels: const *void?)
    func glTextureSubImage3D(texture: GLuint, level: GLint, xoffset: GLint, yoffset: GLint, zoffset: GLint, width: GLsizei, height: GLsizei, depth: GLsizei, format: GLenum, type: GLenum, pixels: const *void?)
    func glTransformFeedbackBufferBase(xfb: GLuint, index: GLuint, buffer: GLuint)
    func glTransformFeedbackBufferRange(xfb: GLuint, index: GLuint, buffer: GLuint, offset: GLintptr, size: GLsizeiptr)
    func glUnmapNamedBuffer(buffer: GLuint)->*(*void?)?
    func glVertexArrayAttribBinding(vaobj: GLuint, attribindex: GLuint, bindingindex: GLuint)
    func glVertexArrayAttribFormat(vaobj: GLuint, attribindex: GLuint, size: GLint, type: GLenum, normalized: GLboolean, relativeoffset: GLuint)
    func glVertexArrayAttribIFormat(vaobj: GLuint, attribindex: GLuint, size: GLint, type: GLenum, relativeoffset: GLuint)
    func glVertexArrayAttribLFormat(vaobj: GLuint, attribindex: GLuint, size: GLint, type: GLenum, relativeoffset: GLuint)
    func glVertexArrayBindingDivisor(vaobj: GLuint, bindingindex: GLuint, divisor: GLuint)
    func glVertexArrayElementBuffer(vaobj: GLuint, buffer: GLuint)
    func glVertexArrayVertexBuffer(vaobj: GLuint, bindingindex: GLuint, buffer: GLuint, offset: GLintptr, stride: GLsizei)
    func glVertexArrayVertexBuffers(vaobj: GLuint, first: GLuint, count: GLsizei, buffers: const *GLuint?, offsets: const *GLintptr?, strides: const *GLsizei?)
}

const GL_CONTEXT_FLAG_ROBUST_ACCESS_BIT       = 0x00000004
const GL_CONTEXT_LOST                         = 0x0507
const GL_NEGATIVE_ONE_TO_ONE                  = 0x935E
const GL_ZERO_TO_ONE                          = 0x935F
const GL_CLIP_ORIGIN                          = 0x935C
const GL_CLIP_DEPTH_MODE                      = 0x935D
const GL_QUERY_WAIT_INVERTED                  = 0x8E17
const GL_QUERY_NO_WAIT_INVERTED               = 0x8E18
const GL_QUERY_BY_REGION_WAIT_INVERTED        = 0x8E19
const GL_QUERY_BY_REGION_NO_WAIT_INVERTED     = 0x8E1A
const GL_MAX_CULL_DISTANCES                   = 0x82F9
const GL_MAX_COMBINED_CLIP_AND_CULL_DISTANCES = 0x82FA
const GL_TEXTURE_TARGET                       = 0x1006
const GL_QUERY_TARGET                         = 0x82EA
const GL_GUILTY_CONTEXT_RESET                 = 0x8253
const GL_INNOCENT_CONTEXT_RESET               = 0x8254
const GL_UNKNOWN_CONTEXT_RESET                = 0x8255
const GL_RESET_NOTIFICATION_STRATEGY          = 0x8256
const GL_LOSE_CONTEXT_ON_RESET                = 0x8252
const GL_NO_RESET_NOTIFICATION                = 0x8261
const GL_CONTEXT_RELEASE_BEHAVIOR             = 0x82FB
const GL_CONTEXT_RELEASE_BEHAVIOR_FLUSH       = 0x82FC
