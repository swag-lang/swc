#global public

using Swag

/* ----------------------- GL_EXT_EGL_image_storage ------------------------ */

alias GLeglImageOES = *void?

const GL_EXT_EGL_image_storage = 1

#[Extension, Swag.PlaceHolder]
{
    func glEGLImageTargetTexStorageEXT(target: GLenum, image: GLeglImageOES, attrib_list: const *GLint?)
    func glEGLImageTargetTextureStorageEXT(texture: GLuint, image: GLeglImageOES, attrib_list: const *GLint?)
}

/* ---------------------------- GL_EXT_EGL_sync ---------------------------- */

const GL_EXT_EGL_sync = 1

/* -------------------------- GL_EXT_debug_label --------------------------- */

const GL_EXT_debug_label             = 1
const GL_PROGRAM_PIPELINE_OBJECT_EXT = 0x8A4F
const GL_PROGRAM_OBJECT_EXT          = 0x8B40
const GL_SHADER_OBJECT_EXT           = 0x8B48
const GL_BUFFER_OBJECT_EXT           = 0x9151
const GL_QUERY_OBJECT_EXT            = 0x9153
const GL_VERTEX_ARRAY_OBJECT_EXT     = 0x9154

#[Extension, Swag.PlaceHolder]
{
    func glGetObjectLabelEXT(type: GLenum, object: GLuint, bufSize: GLsizei, length: *GLsizei?, label: *GLchar?)
    func glLabelObjectEXT(type: GLenum, object: GLuint, length: GLsizei, label: const *GLchar?)
}

/* -------------------------- GL_EXT_debug_marker -------------------------- */

const GL_EXT_debug_marker = 1

#[Extension, Swag.PlaceHolder]
{
    func glInsertEventMarkerEXT(length: GLsizei, marker: const *GLchar?)
    func glPopGroupMarkerEXT()
    func glPushGroupMarkerEXT(length: GLsizei, marker: const *GLchar?)
}

/* ---------------------- GL_EXT_direct_state_access ----------------------- */

const GL_EXT_direct_state_access        = 1
const GL_PROGRAM_MATRIX_EXT             = 0x8E2D
const GL_TRANSPOSE_PROGRAM_MATRIX_EXT   = 0x8E2E
const GL_PROGRAM_MATRIX_STACK_DEPTH_EXT = 0x8E2F

#[Extension, Swag.PlaceHolder]
{
    func glBindMultiTextureEXT(texunit: GLenum, target: GLenum, texture: GLuint)
    func glCheckNamedFramebufferStatusEXT(framebuffer: GLuint, target: GLenum)->GLenum
    func glClearNamedBufferDataEXT(buffer: GLuint, internalformat: GLenum, format: GLenum, type: GLenum, data: const *void?)
    func glClearNamedBufferSubDataEXT(buffer: GLuint, internalformat: GLenum, offset: GLsizeiptr, size: GLsizeiptr, format: GLenum, type: GLenum, data: const *void?)
    func glClientAttribDefaultEXT(mask: GLbitfield)
    func glCompressedMultiTexImage1DEXT(texunit: GLenum, target: GLenum, level: GLint, internalformat: GLenum, width: GLsizei, border: GLint, imageSize: GLsizei, bits: const *void?)
    func glCompressedMultiTexImage2DEXT(texunit: GLenum, target: GLenum, level: GLint, internalformat: GLenum, width: GLsizei, height: GLsizei, border: GLint, imageSize: GLsizei, bits: const *void?)
    func glCompressedMultiTexImage3DEXT(texunit: GLenum, target: GLenum, level: GLint, internalformat: GLenum, width: GLsizei, height: GLsizei, depth: GLsizei, border: GLint, imageSize: GLsizei, bits: const *void?)
    func glCompressedMultiTexSubImage1DEXT(texunit: GLenum, target: GLenum, level: GLint, xoffset: GLint, width: GLsizei, format: GLenum, imageSize: GLsizei, bits: const *void?)
    func glCompressedMultiTexSubImage2DEXT(texunit: GLenum, target: GLenum, level: GLint, xoffset: GLint, yoffset: GLint, width: GLsizei, height: GLsizei, format: GLenum, imageSize: GLsizei, bits: const *void?)
    func glCompressedMultiTexSubImage3DEXT(texunit: GLenum, target: GLenum, level: GLint, xoffset: GLint, yoffset: GLint, zoffset: GLint, width: GLsizei, height: GLsizei, depth: GLsizei, format: GLenum, imageSize: GLsizei, bits: const *void?)
    func glCompressedTextureImage1DEXT(texture: GLuint, target: GLenum, level: GLint, internalformat: GLenum, width: GLsizei, border: GLint, imageSize: GLsizei, bits: const *void?)
    func glCompressedTextureImage2DEXT(texture: GLuint, target: GLenum, level: GLint, internalformat: GLenum, width: GLsizei, height: GLsizei, border: GLint, imageSize: GLsizei, bits: const *void?)
    func glCompressedTextureImage3DEXT(texture: GLuint, target: GLenum, level: GLint, internalformat: GLenum, width: GLsizei, height: GLsizei, depth: GLsizei, border: GLint, imageSize: GLsizei, bits: const *void?)
    func glCompressedTextureSubImage1DEXT(texture: GLuint, target: GLenum, level: GLint, xoffset: GLint, width: GLsizei, format: GLenum, imageSize: GLsizei, bits: const *void?)
    func glCompressedTextureSubImage2DEXT(texture: GLuint, target: GLenum, level: GLint, xoffset: GLint, yoffset: GLint, width: GLsizei, height: GLsizei, format: GLenum, imageSize: GLsizei, bits: const *void?)
    func glCompressedTextureSubImage3DEXT(texture: GLuint, target: GLenum, level: GLint, xoffset: GLint, yoffset: GLint, zoffset: GLint, width: GLsizei, height: GLsizei, depth: GLsizei, format: GLenum, imageSize: GLsizei, bits: const *void?)
    func glCopyMultiTexImage1DEXT(texunit: GLenum, target: GLenum, level: GLint, internalformat: GLenum, x: GLint, y: GLint, width: GLsizei, border: GLint)
    func glCopyMultiTexImage2DEXT(texunit: GLenum, target: GLenum, level: GLint, internalformat: GLenum, x: GLint, y: GLint, width: GLsizei, height: GLsizei, border: GLint)
    func glCopyMultiTexSubImage1DEXT(texunit: GLenum, target: GLenum, level: GLint, xoffset: GLint, x: GLint, y: GLint, width: GLsizei)
    func glCopyMultiTexSubImage2DEXT(texunit: GLenum, target: GLenum, level: GLint, xoffset: GLint, yoffset: GLint, x: GLint, y: GLint, width: GLsizei, height: GLsizei)
    func glCopyMultiTexSubImage3DEXT(texunit: GLenum, target: GLenum, level: GLint, xoffset: GLint, yoffset: GLint, zoffset: GLint, x: GLint, y: GLint, width: GLsizei, height: GLsizei)
    func glCopyTextureImage1DEXT(texture: GLuint, target: GLenum, level: GLint, internalformat: GLenum, x: GLint, y: GLint, width: GLsizei, border: GLint)
    func glCopyTextureImage2DEXT(texture: GLuint, target: GLenum, level: GLint, internalformat: GLenum, x: GLint, y: GLint, width: GLsizei, height: GLsizei, border: GLint)
    func glCopyTextureSubImage1DEXT(texture: GLuint, target: GLenum, level: GLint, xoffset: GLint, x: GLint, y: GLint, width: GLsizei)
    func glCopyTextureSubImage2DEXT(texture: GLuint, target: GLenum, level: GLint, xoffset: GLint, yoffset: GLint, x: GLint, y: GLint, width: GLsizei, height: GLsizei)
    func glCopyTextureSubImage3DEXT(texture: GLuint, target: GLenum, level: GLint, xoffset: GLint, yoffset: GLint, zoffset: GLint, x: GLint, y: GLint, width: GLsizei, height: GLsizei)
    func glDisableClientStateIndexedEXT(array: GLenum, index: GLuint)
    func glDisableClientStateiEXT(array: GLenum, index: GLuint)
    func glDisableIndexedEXT(target: GLenum, index: GLuint)
    func glDisableVertexArrayAttribEXT(vaobj: GLuint, index: GLuint)
    func glDisableVertexArrayEXT(vaobj: GLuint, array: GLenum)
    func glEnableClientStateIndexedEXT(array: GLenum, index: GLuint)
    func glEnableClientStateiEXT(array: GLenum, index: GLuint)
    func glEnableIndexedEXT(target: GLenum, index: GLuint)
    func glEnableVertexArrayAttribEXT(vaobj: GLuint, index: GLuint)
    func glEnableVertexArrayEXT(vaobj: GLuint, array: GLenum)
    func glFlushMappedNamedBufferRangeEXT(buffer: GLuint, offset: GLintptr, length: GLsizeiptr)->*void?
    func glFramebufferDrawBufferEXT(framebuffer: GLuint, mode: GLenum)
    func glFramebufferDrawBuffersEXT(framebuffer: GLuint, n: GLsizei, bufs: const *GLenum?)
    func glFramebufferReadBufferEXT(framebuffer: GLuint, mode: GLenum)
    func glGenerateMultiTexMipmapEXT(texunit: GLenum, target: GLenum)
    func glGenerateTextureMipmapEXT(texture: GLuint, target: GLenum)
    func glGetBooleanIndexedvEXT(target: GLenum, index: GLuint, data: *GLboolean?)
    func glGetCompressedMultiTexImageEXT(texunit: GLenum, target: GLenum, lod: GLint, img: *void?)
    func glGetCompressedTextureImageEXT(texture: GLuint, target: GLenum, lod: GLint, img: *void?)
    func glGetDoubleIndexedvEXT(target: GLenum, index: GLuint, data: *GLdouble?)
    func glGetDoublei_vEXT(pname: GLenum, index: GLuint, params: *GLdouble?)
    func glGetFloatIndexedvEXT(target: GLenum, index: GLuint, data: *GLfloat?)
    func glGetFloati_vEXT(pname: GLenum, index: GLuint, params: *GLfloat?)
    func glGetFramebufferParameterivEXT(framebuffer: GLuint, pname: GLenum, params: *GLint?)
    func glGetIntegerIndexedvEXT(target: GLenum, index: GLuint, data: *GLint?)
    func glGetMultiTexEnvfvEXT(texunit: GLenum, target: GLenum, pname: GLenum, params: *GLfloat?)
    func glGetMultiTexEnvivEXT(texunit: GLenum, target: GLenum, pname: GLenum, params: *GLint?)
    func glGetMultiTexGendvEXT(texunit: GLenum, coord: GLenum, pname: GLenum, params: *GLdouble?)
    func glGetMultiTexGenfvEXT(texunit: GLenum, coord: GLenum, pname: GLenum, params: *GLfloat?)
    func glGetMultiTexGenivEXT(texunit: GLenum, coord: GLenum, pname: GLenum, params: *GLint?)
    func glGetMultiTexImageEXT(texunit: GLenum, target: GLenum, level: GLint, format: GLenum, type: GLenum, pixels: *void?)
    func glGetMultiTexLevelParameterfvEXT(texunit: GLenum, target: GLenum, level: GLint, pname: GLenum, params: *GLfloat?)
    func glGetMultiTexLevelParameterivEXT(texunit: GLenum, target: GLenum, level: GLint, pname: GLenum, params: *GLint?)
    func glGetMultiTexParameterIivEXT(texunit: GLenum, target: GLenum, pname: GLenum, params: *GLint?)
    func glGetMultiTexParameterIuivEXT(texunit: GLenum, target: GLenum, pname: GLenum, params: *GLuint?)
    func glGetMultiTexParameterfvEXT(texunit: GLenum, target: GLenum, pname: GLenum, params: *GLfloat?)
    func glGetMultiTexParameterivEXT(texunit: GLenum, target: GLenum, pname: GLenum, params: *GLint?)
    func glGetNamedBufferParameterivEXT(buffer: GLuint, pname: GLenum, params: *GLint?)
    func glGetNamedBufferPointervEXT(buffer: GLuint, pname: GLenum, params: *(*void?)?)
    func glGetNamedBufferSubDataEXT(buffer: GLuint, offset: GLintptr, size: GLsizeiptr, data: *void?)
    func glGetNamedFramebufferAttachmentParameterivEXT(framebuffer: GLuint, attachment: GLenum, pname: GLenum, params: *GLint?)
    func glGetNamedProgramLocalParameterIivEXT(program: GLuint, target: GLenum, index: GLuint, params: *GLint?)
    func glGetNamedProgramLocalParameterIuivEXT(program: GLuint, target: GLenum, index: GLuint, params: *GLuint?)
    func glGetNamedProgramLocalParameterdvEXT(program: GLuint, target: GLenum, index: GLuint, params: *GLdouble?)
    func glGetNamedProgramLocalParameterfvEXT(program: GLuint, target: GLenum, index: GLuint, params: *GLfloat?)
    func glGetNamedProgramStringEXT(program: GLuint, target: GLenum, pname: GLenum, stringValue: *void?)
    func glGetNamedProgramivEXT(program: GLuint, target: GLenum, pname: GLenum, params: *GLint?)
    func glGetNamedRenderbufferParameterivEXT(renderbuffer: GLuint, pname: GLenum, params: *GLint?)
    func glGetPointerIndexedvEXT(target: GLenum, index: GLuint, data: *(*void?)?)
    func glGetPointeri_vEXT(pname: GLenum, index: GLuint, params: *(*void?)?)
    func glGetTextureImageEXT(texture: GLuint, target: GLenum, level: GLint, format: GLenum, type: GLenum, pixels: *void?)
    func glGetTextureLevelParameterfvEXT(texture: GLuint, target: GLenum, level: GLint, pname: GLenum, params: *GLfloat?)
    func glGetTextureLevelParameterivEXT(texture: GLuint, target: GLenum, level: GLint, pname: GLenum, params: *GLint?)
    func glGetTextureParameterIivEXT(texture: GLuint, target: GLenum, pname: GLenum, params: *GLint?)
    func glGetTextureParameterIuivEXT(texture: GLuint, target: GLenum, pname: GLenum, params: *GLuint?)
    func glGetTextureParameterfvEXT(texture: GLuint, target: GLenum, pname: GLenum, params: *GLfloat?)
    func glGetTextureParameterivEXT(texture: GLuint, target: GLenum, pname: GLenum, params: *GLint?)
    func glGetVertexArrayIntegeri_vEXT(vaobj: GLuint, index: GLuint, pname: GLenum, param: *GLint?)
    func glGetVertexArrayIntegervEXT(vaobj: GLuint, pname: GLenum, param: *GLint?)
    func glGetVertexArrayPointeri_vEXT(vaobj: GLuint, index: GLuint, pname: GLenum, param: *(*void?)?)
    func glGetVertexArrayPointervEXT(vaobj: GLuint, pname: GLenum, param: *(*void?)?)
    func glIsEnabledIndexedEXT(target: GLenum, index: GLuint)->GLboolean
    func glMatrixFrustumEXT(mode: GLenum, left: GLdouble, right: GLdouble, bottom: GLdouble, top: GLdouble, zNear: GLdouble, zFar: GLdouble)
    func glMatrixLoadIdentityEXT(mode: GLenum)
    func glMatrixLoadTransposedEXT(mode: GLenum, m: const *GLdouble?)
    func glMatrixLoadTransposefEXT(mode: GLenum, m: const *GLfloat?)
    func glMatrixLoaddEXT(mode: GLenum, m: const *GLdouble?)
    func glMatrixLoadfEXT(mode: GLenum, m: const *GLfloat?)
    func glMatrixMultTransposedEXT(mode: GLenum, m: const *GLdouble?)
    func glMatrixMultTransposefEXT(mode: GLenum, m: const *GLfloat?)
    func glMatrixMultdEXT(mode: GLenum, m: const *GLdouble?)
    func glMatrixMultfEXT(mode: GLenum, m: const *GLfloat?)
    func glMatrixOrthoEXT(mode: GLenum, left: GLdouble, right: GLdouble, bottom: GLdouble, top: GLdouble, zNear: GLdouble, zFar: GLdouble)
    func glMatrixPopEXT(mode: GLenum)
    func glMatrixPushEXT(mode: GLenum)
    func glMatrixRotatedEXT(mode: GLenum, angle: GLdouble, x: GLdouble, y: GLdouble, z: GLdouble)
    func glMatrixRotatefEXT(mode: GLenum, angle: GLfloat, x: GLfloat, y: GLfloat, z: GLfloat)
    func glMatrixScaledEXT(mode: GLenum, x: GLdouble, y: GLdouble, z: GLdouble)
    func glMatrixScalefEXT(mode: GLenum, x: GLfloat, y: GLfloat, z: GLfloat)
    func glMatrixTranslatedEXT(mode: GLenum, x: GLdouble, y: GLdouble, z: GLdouble)
    func glMatrixTranslatefEXT(mode: GLenum, x: GLfloat, y: GLfloat, z: GLfloat)
    func glMultiTexBufferEXT(texunit: GLenum, target: GLenum, internalformat: GLenum, buffer: GLuint)
    func glMultiTexCoordPointerEXT(texunit: GLenum, size: GLint, type: GLenum, stride: GLsizei, pointer: const *void?)
    func glMultiTexEnvfEXT(texunit: GLenum, target: GLenum, pname: GLenum, param: GLfloat)
    func glMultiTexEnvfvEXT(texunit: GLenum, target: GLenum, pname: GLenum, params: const *GLfloat?)
    func glMultiTexEnviEXT(texunit: GLenum, target: GLenum, pname: GLenum, param: GLint)
    func glMultiTexEnvivEXT(texunit: GLenum, target: GLenum, pname: GLenum, params: const *GLint?)
    func glMultiTexGendEXT(texunit: GLenum, coord: GLenum, pname: GLenum, param: GLdouble)
    func glMultiTexGendvEXT(texunit: GLenum, coord: GLenum, pname: GLenum, params: const *GLdouble?)
    func glMultiTexGenfEXT(texunit: GLenum, coord: GLenum, pname: GLenum, param: GLfloat)
    func glMultiTexGenfvEXT(texunit: GLenum, coord: GLenum, pname: GLenum, params: const *GLfloat?)
    func glMultiTexGeniEXT(texunit: GLenum, coord: GLenum, pname: GLenum, param: GLint)
    func glMultiTexGenivEXT(texunit: GLenum, coord: GLenum, pname: GLenum, params: const *GLint?)
    func glMultiTexImage1DEXT(texunit: GLenum, target: GLenum, level: GLint, internalformat: GLint, width: GLsizei, border: GLint, format: GLenum, type: GLenum, pixels: const *void?)
    func glMultiTexImage2DEXT(texunit: GLenum, target: GLenum, level: GLint, internalformat: GLint, width: GLsizei, height: GLsizei, border: GLint, format: GLenum, type: GLenum, pixels: const *void?)
    func glMultiTexImage3DEXT(texunit: GLenum, target: GLenum, level: GLint, internalformat: GLint, width: GLsizei, height: GLsizei, depth: GLsizei, border: GLint, format: GLenum, type: GLenum, pixels: const *void?)
    func glMultiTexParameterIivEXT(texunit: GLenum, target: GLenum, pname: GLenum, params: const *GLint?)
    func glMultiTexParameterIuivEXT(texunit: GLenum, target: GLenum, pname: GLenum, params: const *GLuint?)
    func glMultiTexParameterfEXT(texunit: GLenum, target: GLenum, pname: GLenum, param: GLfloat)
    func glMultiTexParameterfvEXT(texunit: GLenum, target: GLenum, pname: GLenum, params: const *GLfloat?)
    func glMultiTexParameteriEXT(texunit: GLenum, target: GLenum, pname: GLenum, param: GLint)
    func glMultiTexParameterivEXT(texunit: GLenum, target: GLenum, pname: GLenum, params: const *GLint?)
    func glMultiTexRenderbufferEXT(texunit: GLenum, target: GLenum, renderbuffer: GLuint)
    func glMultiTexSubImage1DEXT(texunit: GLenum, target: GLenum, level: GLint, xoffset: GLint, width: GLsizei, format: GLenum, type: GLenum, pixels: const *void?)
    func glMultiTexSubImage2DEXT(texunit: GLenum, target: GLenum, level: GLint, xoffset: GLint, yoffset: GLint, width: GLsizei, height: GLsizei, format: GLenum, type: GLenum, pixels: const *void?)
    func glMultiTexSubImage3DEXT(texunit: GLenum, target: GLenum, level: GLint, xoffset: GLint, yoffset: GLint, zoffset: GLint, width: GLsizei, height: GLsizei, depth: GLsizei, format: GLenum, type: GLenum, pixels: const *void?)
    func glNamedBufferDataEXT(buffer: GLuint, size: GLsizeiptr, data: const *void?, usage: GLenum)
    func glNamedBufferStorageEXT(buffer: GLuint, size: GLsizeiptr, data: const *void?, flags: GLbitfield)
    func glNamedBufferSubDataEXT(buffer: GLuint, offset: GLintptr, size: GLsizeiptr, data: const *void?)
    func glNamedCopyBufferSubDataEXT(readBuffer: GLuint, writeBuffer: GLuint, readOffset: GLintptr, writeOffset: GLintptr, size: GLsizeiptr)
    func glNamedFramebufferRenderbufferEXT(framebuffer: GLuint, attachment: GLenum, renderbuffertarget: GLenum, renderbuffer: GLuint)
    func glNamedFramebufferTexture1DEXT(framebuffer: GLuint, attachment: GLenum, textarget: GLenum, texture: GLuint, level: GLint)
    func glNamedFramebufferTexture2DEXT(framebuffer: GLuint, attachment: GLenum, textarget: GLenum, texture: GLuint, level: GLint)
    func glNamedFramebufferTexture3DEXT(framebuffer: GLuint, attachment: GLenum, textarget: GLenum, texture: GLuint, level: GLint, zoffset: GLint)
    func glNamedFramebufferTextureEXT(framebuffer: GLuint, attachment: GLenum, texture: GLuint, level: GLint)
    func glNamedFramebufferTextureFaceEXT(framebuffer: GLuint, attachment: GLenum, texture: GLuint, level: GLint, face: GLenum)
    func glNamedFramebufferTextureLayerEXT(framebuffer: GLuint, attachment: GLenum, texture: GLuint, level: GLint, layer: GLint)
    func glNamedProgramLocalParameter4dEXT(program: GLuint, target: GLenum, index: GLuint, x: GLdouble, y: GLdouble, z: GLdouble, w: GLdouble)
    func glNamedProgramLocalParameter4dvEXT(program: GLuint, target: GLenum, index: GLuint, params: const *GLdouble?)
    func glNamedProgramLocalParameter4fEXT(program: GLuint, target: GLenum, index: GLuint, x: GLfloat, y: GLfloat, z: GLfloat, w: GLfloat)
    func glNamedProgramLocalParameter4fvEXT(program: GLuint, target: GLenum, index: GLuint, params: const *GLfloat?)
    func glNamedProgramLocalParameterI4iEXT(program: GLuint, target: GLenum, index: GLuint, x: GLint, y: GLint, z: GLint, w: GLint)
    func glNamedProgramLocalParameterI4ivEXT(program: GLuint, target: GLenum, index: GLuint, params: const *GLint?)
    func glNamedProgramLocalParameterI4uiEXT(program: GLuint, target: GLenum, index: GLuint, x: GLuint, y: GLuint, z: GLuint, w: GLuint)
    func glNamedProgramLocalParameterI4uivEXT(program: GLuint, target: GLenum, index: GLuint, params: const *GLuint?)
    func glNamedProgramLocalParameters4fvEXT(program: GLuint, target: GLenum, index: GLuint, count: GLsizei, params: const *GLfloat?)
    func glNamedProgramLocalParametersI4ivEXT(program: GLuint, target: GLenum, index: GLuint, count: GLsizei, params: const *GLint?)
    func glNamedProgramLocalParametersI4uivEXT(program: GLuint, target: GLenum, index: GLuint, count: GLsizei, params: const *GLuint?)
    func glNamedProgramStringEXT(program: GLuint, target: GLenum, format: GLenum, len: GLsizei, stringValue: const *void?)
    func glNamedRenderbufferStorageEXT(renderbuffer: GLuint, internalformat: GLenum, width: GLsizei, height: GLsizei)
    func glNamedRenderbufferStorageMultisampleCoverageEXT(renderbuffer: GLuint, coverageSamples: GLsizei, colorSamples: GLsizei, internalformat: GLenum, width: GLsizei, height: GLsizei)
    func glNamedRenderbufferStorageMultisampleEXT(renderbuffer: GLuint, samples: GLsizei, internalformat: GLenum, width: GLsizei, height: GLsizei)
    func glProgramUniform1dEXT(program: GLuint, location: GLint, x: GLdouble)
    func glProgramUniform1dvEXT(program: GLuint, location: GLint, count: GLsizei, value: const *GLdouble?)
    func glProgramUniform1fEXT(program: GLuint, location: GLint, v0: GLfloat)
    func glProgramUniform1fvEXT(program: GLuint, location: GLint, count: GLsizei, value: const *GLfloat?)
    func glProgramUniform1iEXT(program: GLuint, location: GLint, v0: GLint)
    func glProgramUniform1ivEXT(program: GLuint, location: GLint, count: GLsizei, value: const *GLint?)
    func glProgramUniform1uiEXT(program: GLuint, location: GLint, v0: GLuint)
    func glProgramUniform1uivEXT(program: GLuint, location: GLint, count: GLsizei, value: const *GLuint?)
    func glProgramUniform2dEXT(program: GLuint, location: GLint, x: GLdouble, y: GLdouble)
    func glProgramUniform2dvEXT(program: GLuint, location: GLint, count: GLsizei, value: const *GLdouble?)
    func glProgramUniform2fEXT(program: GLuint, location: GLint, v0: GLfloat, v1: GLfloat)
    func glProgramUniform2fvEXT(program: GLuint, location: GLint, count: GLsizei, value: const *GLfloat?)
    func glProgramUniform2iEXT(program: GLuint, location: GLint, v0: GLint, v1: GLint)
    func glProgramUniform2ivEXT(program: GLuint, location: GLint, count: GLsizei, value: const *GLint?)
    func glProgramUniform2uiEXT(program: GLuint, location: GLint, v0: GLuint, v1: GLuint)
    func glProgramUniform2uivEXT(program: GLuint, location: GLint, count: GLsizei, value: const *GLuint?)
    func glProgramUniform3dEXT(program: GLuint, location: GLint, x: GLdouble, y: GLdouble, z: GLdouble)
    func glProgramUniform3dvEXT(program: GLuint, location: GLint, count: GLsizei, value: const *GLdouble?)
    func glProgramUniform3fEXT(program: GLuint, location: GLint, v0: GLfloat, v1: GLfloat, v2: GLfloat)
    func glProgramUniform3fvEXT(program: GLuint, location: GLint, count: GLsizei, value: const *GLfloat?)
    func glProgramUniform3iEXT(program: GLuint, location: GLint, v0: GLint, v1: GLint, v2: GLint)
    func glProgramUniform3ivEXT(program: GLuint, location: GLint, count: GLsizei, value: const *GLint?)
    func glProgramUniform3uiEXT(program: GLuint, location: GLint, v0: GLuint, v1: GLuint, v2: GLuint)
    func glProgramUniform3uivEXT(program: GLuint, location: GLint, count: GLsizei, value: const *GLuint?)
    func glProgramUniform4dEXT(program: GLuint, location: GLint, x: GLdouble, y: GLdouble, z: GLdouble, w: GLdouble)
    func glProgramUniform4dvEXT(program: GLuint, location: GLint, count: GLsizei, value: const *GLdouble?)
    func glProgramUniform4fEXT(program: GLuint, location: GLint, v0: GLfloat, v1: GLfloat, v2: GLfloat, v3: GLfloat)
    func glProgramUniform4fvEXT(program: GLuint, location: GLint, count: GLsizei, value: const *GLfloat?)
    func glProgramUniform4iEXT(program: GLuint, location: GLint, v0: GLint, v1: GLint, v2: GLint, v3: GLint)
    func glProgramUniform4ivEXT(program: GLuint, location: GLint, count: GLsizei, value: const *GLint?)
    func glProgramUniform4uiEXT(program: GLuint, location: GLint, v0: GLuint, v1: GLuint, v2: GLuint, v3: GLuint)
    func glProgramUniform4uivEXT(program: GLuint, location: GLint, count: GLsizei, value: const *GLuint?)
    func glProgramUniformMatrix2dvEXT(program: GLuint, location: GLint, count: GLsizei, transpose: GLboolean, value: const *GLdouble?)
    func glProgramUniformMatrix2fvEXT(program: GLuint, location: GLint, count: GLsizei, transpose: GLboolean, value: const *GLfloat?)
    func glProgramUniformMatrix2x3dvEXT(program: GLuint, location: GLint, count: GLsizei, transpose: GLboolean, value: const *GLdouble?)
    func glProgramUniformMatrix2x3fvEXT(program: GLuint, location: GLint, count: GLsizei, transpose: GLboolean, value: const *GLfloat?)
    func glProgramUniformMatrix2x4dvEXT(program: GLuint, location: GLint, count: GLsizei, transpose: GLboolean, value: const *GLdouble?)
    func glProgramUniformMatrix2x4fvEXT(program: GLuint, location: GLint, count: GLsizei, transpose: GLboolean, value: const *GLfloat?)
    func glProgramUniformMatrix3dvEXT(program: GLuint, location: GLint, count: GLsizei, transpose: GLboolean, value: const *GLdouble?)
    func glProgramUniformMatrix3fvEXT(program: GLuint, location: GLint, count: GLsizei, transpose: GLboolean, value: const *GLfloat?)
    func glProgramUniformMatrix3x2dvEXT(program: GLuint, location: GLint, count: GLsizei, transpose: GLboolean, value: const *GLdouble?)
    func glProgramUniformMatrix3x2fvEXT(program: GLuint, location: GLint, count: GLsizei, transpose: GLboolean, value: const *GLfloat?)
    func glProgramUniformMatrix3x4dvEXT(program: GLuint, location: GLint, count: GLsizei, transpose: GLboolean, value: const *GLdouble?)
    func glProgramUniformMatrix3x4fvEXT(program: GLuint, location: GLint, count: GLsizei, transpose: GLboolean, value: const *GLfloat?)
    func glProgramUniformMatrix4dvEXT(program: GLuint, location: GLint, count: GLsizei, transpose: GLboolean, value: const *GLdouble?)
    func glProgramUniformMatrix4fvEXT(program: GLuint, location: GLint, count: GLsizei, transpose: GLboolean, value: const *GLfloat?)
    func glProgramUniformMatrix4x2dvEXT(program: GLuint, location: GLint, count: GLsizei, transpose: GLboolean, value: const *GLdouble?)
    func glProgramUniformMatrix4x2fvEXT(program: GLuint, location: GLint, count: GLsizei, transpose: GLboolean, value: const *GLfloat?)
    func glProgramUniformMatrix4x3dvEXT(program: GLuint, location: GLint, count: GLsizei, transpose: GLboolean, value: const *GLdouble?)
    func glProgramUniformMatrix4x3fvEXT(program: GLuint, location: GLint, count: GLsizei, transpose: GLboolean, value: const *GLfloat?)
    func glPushClientAttribDefaultEXT(mask: GLbitfield)
    func glTextureBufferEXT(texture: GLuint, target: GLenum, internalformat: GLenum, buffer: GLuint)
    func glTextureBufferRangeEXT(texture: GLuint, target: GLenum, internalformat: GLenum, buffer: GLuint, offset: GLintptr, size: GLsizeiptr)
    func glTextureImage1DEXT(texture: GLuint, target: GLenum, level: GLint, internalformat: GLint, width: GLsizei, border: GLint, format: GLenum, type: GLenum, pixels: const *void?)
    func glTextureImage2DEXT(texture: GLuint, target: GLenum, level: GLint, internalformat: GLint, width: GLsizei, height: GLsizei, border: GLint, format: GLenum, type: GLenum, pixels: const *void?)
    func glTextureImage3DEXT(texture: GLuint, target: GLenum, level: GLint, internalformat: GLint, width: GLsizei, height: GLsizei, depth: GLsizei, border: GLint, format: GLenum, type: GLenum, pixels: const *void?)
    func glTexturePageCommitmentEXT(texture: GLuint, level: GLint, xoffset: GLint, yoffset: GLint, zoffset: GLint, width: GLsizei, height: GLsizei, depth: GLsizei, commit: GLboolean)
    func glTextureParameterIivEXT(texture: GLuint, target: GLenum, pname: GLenum, params: const *GLint?)
    func glTextureParameterIuivEXT(texture: GLuint, target: GLenum, pname: GLenum, params: const *GLuint?)
    func glTextureParameterfEXT(texture: GLuint, target: GLenum, pname: GLenum, param: GLfloat)
    func glTextureParameterfvEXT(texture: GLuint, target: GLenum, pname: GLenum, params: const *GLfloat?)
    func glTextureParameteriEXT(texture: GLuint, target: GLenum, pname: GLenum, param: GLint)
    func glTextureParameterivEXT(texture: GLuint, target: GLenum, pname: GLenum, params: const *GLint?)
    func glTextureRenderbufferEXT(texture: GLuint, target: GLenum, renderbuffer: GLuint)
    func glTextureStorage1DEXT(texture: GLuint, target: GLenum, levels: GLsizei, internalformat: GLenum, width: GLsizei)
    func glTextureStorage2DEXT(texture: GLuint, target: GLenum, levels: GLsizei, internalformat: GLenum, width: GLsizei, height: GLsizei)
    func glTextureStorage2DMultisampleEXT(texture: GLuint, target: GLenum, samples: GLsizei, internalformat: GLenum, width: GLsizei, height: GLsizei, fixedsamplelocations: GLboolean)
    func glTextureStorage3DEXT(texture: GLuint, target: GLenum, levels: GLsizei, internalformat: GLenum, width: GLsizei, height: GLsizei, depth: GLsizei)
    func glTextureStorage3DMultisampleEXT(texture: GLuint, target: GLenum, samples: GLsizei, internalformat: GLenum, width: GLsizei, height: GLsizei, depth: GLsizei, fixedsamplelocations: GLboolean)
    func glTextureSubImage1DEXT(texture: GLuint, target: GLenum, level: GLint, xoffset: GLint, width: GLsizei, format: GLenum, type: GLenum, pixels: const *void?)
    func glTextureSubImage2DEXT(texture: GLuint, target: GLenum, level: GLint, xoffset: GLint, yoffset: GLint, width: GLsizei, height: GLsizei, format: GLenum, type: GLenum, pixels: const *void?)
    func glTextureSubImage3DEXT(texture: GLuint, target: GLenum, level: GLint, xoffset: GLint, yoffset: GLint, zoffset: GLint, width: GLsizei, height: GLsizei, depth: GLsizei, format: GLenum, type: GLenum, pixels: const *void?)
    func glUnmapNamedBufferEXT(buffer: GLuint)->*void?
    func glVertexArrayBindVertexBufferEXT(vaobj: GLuint, bindingindex: GLuint, buffer: GLuint, offset: GLintptr, stride: GLsizei)
    func glVertexArrayColorOffsetEXT(vaobj: GLuint, buffer: GLuint, size: GLint, type: GLenum, stride: GLsizei, offset: GLintptr)
    func glVertexArrayEdgeFlagOffsetEXT(vaobj: GLuint, buffer: GLuint, stride: GLsizei, offset: GLintptr)
    func glVertexArrayFogCoordOffsetEXT(vaobj: GLuint, buffer: GLuint, type: GLenum, stride: GLsizei, offset: GLintptr)
    func glVertexArrayIndexOffsetEXT(vaobj: GLuint, buffer: GLuint, type: GLenum, stride: GLsizei, offset: GLintptr)
    func glVertexArrayMultiTexCoordOffsetEXT(vaobj: GLuint, buffer: GLuint, texunit: GLenum, size: GLint, type: GLenum, stride: GLsizei, offset: GLintptr)
    func glVertexArrayNormalOffsetEXT(vaobj: GLuint, buffer: GLuint, type: GLenum, stride: GLsizei, offset: GLintptr)
    func glVertexArraySecondaryColorOffsetEXT(vaobj: GLuint, buffer: GLuint, size: GLint, type: GLenum, stride: GLsizei, offset: GLintptr)
    func glVertexArrayTexCoordOffsetEXT(vaobj: GLuint, buffer: GLuint, size: GLint, type: GLenum, stride: GLsizei, offset: GLintptr)
    func glVertexArrayVertexAttribBindingEXT(vaobj: GLuint, attribindex: GLuint, bindingindex: GLuint)
    func glVertexArrayVertexAttribDivisorEXT(vaobj: GLuint, index: GLuint, divisor: GLuint)
    func glVertexArrayVertexAttribFormatEXT(vaobj: GLuint, attribindex: GLuint, size: GLint, type: GLenum, normalized: GLboolean, relativeoffset: GLuint)
    func glVertexArrayVertexAttribIFormatEXT(vaobj: GLuint, attribindex: GLuint, size: GLint, type: GLenum, relativeoffset: GLuint)
    func glVertexArrayVertexAttribIOffsetEXT(vaobj: GLuint, buffer: GLuint, index: GLuint, size: GLint, type: GLenum, stride: GLsizei, offset: GLintptr)
    func glVertexArrayVertexAttribLFormatEXT(vaobj: GLuint, attribindex: GLuint, size: GLint, type: GLenum, relativeoffset: GLuint)
    func glVertexArrayVertexAttribLOffsetEXT(vaobj: GLuint, buffer: GLuint, index: GLuint, size: GLint, type: GLenum, stride: GLsizei, offset: GLintptr)
    func glVertexArrayVertexAttribOffsetEXT(vaobj: GLuint, buffer: GLuint, index: GLuint, size: GLint, type: GLenum, normalized: GLboolean, stride: GLsizei, offset: GLintptr)
    func glVertexArrayVertexBindingDivisorEXT(vaobj: GLuint, bindingindex: GLuint, divisor: GLuint)
    func glVertexArrayVertexOffsetEXT(vaobj: GLuint, buffer: GLuint, size: GLint, type: GLenum, stride: GLsizei, offset: GLintptr)
}

/* ------------------------- GL_EXT_draw_instanced ------------------------- */

const GL_EXT_draw_instanced = 1

#[Extension, Swag.PlaceHolder]
{
    func glDrawArraysInstancedEXT(mode: GLenum, start: GLint, count: GLsizei, primcount: GLsizei)
    func glDrawElementsInstancedEXT(mode: GLenum, count: GLsizei, type: GLenum, indices: const *void?, primcount: GLsizei)
}

/* --------------------- GL_EXT_fragment_shading_rate ---------------------- */

const GL_EXT_fragment_shading_rate                                               = 1
const GL_SHADING_RATE_1X1_PIXELS_EXT                                             = 0x96A6
const GL_SHADING_RATE_1X2_PIXELS_EXT                                             = 0x96A7
const GL_SHADING_RATE_2X1_PIXELS_EXT                                             = 0x96A8
const GL_SHADING_RATE_2X2_PIXELS_EXT                                             = 0x96A9
const GL_SHADING_RATE_1X4_PIXELS_EXT                                             = 0x96AA
const GL_SHADING_RATE_4X1_PIXELS_EXT                                             = 0x96AB
const GL_SHADING_RATE_4X2_PIXELS_EXT                                             = 0x96AC
const GL_SHADING_RATE_2X4_PIXELS_EXT                                             = 0x96AD
const GL_SHADING_RATE_4X4_PIXELS_EXT                                             = 0x96AE
const GL_SHADING_RATE_EXT                                                        = 0x96D0
const GL_SHADING_RATE_ATTACHMENT_EXT                                             = 0x96D1
const GL_FRAGMENT_SHADING_RATE_COMBINER_OP_KEEP_EXT                              = 0x96D2
const GL_FRAGMENT_SHADING_RATE_COMBINER_OP_REPLACE_EXT                           = 0x96D3
const GL_FRAGMENT_SHADING_RATE_COMBINER_OP_MIN_EXT                               = 0x96D4
const GL_FRAGMENT_SHADING_RATE_COMBINER_OP_MAX_EXT                               = 0x96D5
const GL_FRAGMENT_SHADING_RATE_COMBINER_OP_MUL_EXT                               = 0x96D6
const GL_MIN_FRAGMENT_SHADING_RATE_ATTACHMENT_TEXEL_WIDTH_EXT                    = 0x96D7
const GL_MAX_FRAGMENT_SHADING_RATE_ATTACHMENT_TEXEL_WIDTH_EXT                    = 0x96D8
const GL_MIN_FRAGMENT_SHADING_RATE_ATTACHMENT_TEXEL_HEIGHT_EXT                   = 0x96D9
const GL_MAX_FRAGMENT_SHADING_RATE_ATTACHMENT_TEXEL_HEIGHT_EXT                   = 0x96DA
const GL_MAX_FRAGMENT_SHADING_RATE_ATTACHMENT_TEXEL_ASPECT_RATIO_EXT             = 0x96DB
const GL_MAX_FRAGMENT_SHADING_RATE_ATTACHMENT_LAYERS_EXT                         = 0x96DC
const GL_FRAGMENT_SHADING_RATE_WITH_SHADER_DEPTH_STENCIL_WRITES_SUPPORTED_EXT    = 0x96DD
const GL_FRAGMENT_SHADING_RATE_WITH_SAMPLE_MASK_SUPPORTED_EXT                    = 0x96DE
const GL_FRAGMENT_SHADING_RATE_ATTACHMENT_WITH_DEFAULT_FRAMEBUFFER_SUPPORTED_EXT = 0x96DF
const GL_FRAGMENT_SHADING_RATE_NON_TRIVIAL_COMBINERS_SUPPORTED_EXT               = 0x8F6F
const GL_FRAGMENT_SHADING_RATE_PRIMITIVE_RATE_WITH_MULTI_VIEWPORT_SUPPORTED_EXT  = 0x9780

#[Extension, Swag.PlaceHolder]
{
    func glFramebufferShadingRateEXT(target: GLenum, attachment: GLenum, texture: GLuint, baseLayer: GLint, numLayers: GLsizei, texelWidth: GLsizei, texelHeight: GLsizei)
    func glGetFragmentShadingRatesEXT(samples: GLsizei, maxCount: GLsizei, count: *GLsizei?, shadingRates: *GLenum?)
    func glShadingRateCombinerOpsEXT(combinerOp0: GLenum, combinerOp1: GLenum)
    func glShadingRateEXT(rate: GLenum)
}

/* -------------------------- GL_EXT_mesh_shader --------------------------- */

const GL_EXT_mesh_shader                                     = 1
const GL_MESH_SHADER_EXT                                     = 0x9559
const GL_TASK_SHADER_EXT                                     = 0x955A
const GL_MAX_MESH_UNIFORM_BLOCKS_EXT                         = 0x8E60
const GL_MAX_MESH_TEXTURE_IMAGE_UNITS_EXT                    = 0x8E61
const GL_MAX_MESH_IMAGE_UNIFORMS_EXT                         = 0x8E62
const GL_MAX_MESH_UNIFORM_COMPONENTS_EXT                     = 0x8E63
const GL_MAX_MESH_ATOMIC_COUNTER_BUFFERS_EXT                 = 0x8E64
const GL_MAX_MESH_ATOMIC_COUNTERS_EXT                        = 0x8E65
const GL_MAX_MESH_SHADER_STORAGE_BLOCKS_EXT                  = 0x8E66
const GL_MAX_COMBINED_MESH_UNIFORM_COMPONENTS_EXT            = 0x8E67
const GL_MAX_TASK_UNIFORM_BLOCKS_EXT                         = 0x8E68
const GL_MAX_TASK_TEXTURE_IMAGE_UNITS_EXT                    = 0x8E69
const GL_MAX_TASK_IMAGE_UNIFORMS_EXT                         = 0x8E6A
const GL_MAX_TASK_UNIFORM_COMPONENTS_EXT                     = 0x8E6B
const GL_MAX_TASK_ATOMIC_COUNTER_BUFFERS_EXT                 = 0x8E6C
const GL_MAX_TASK_ATOMIC_COUNTERS_EXT                        = 0x8E6D
const GL_MAX_TASK_SHADER_STORAGE_BLOCKS_EXT                  = 0x8E6E
const GL_MAX_COMBINED_TASK_UNIFORM_COMPONENTS_EXT            = 0x8E6F
const GL_MAX_TASK_WORK_GROUP_TOTAL_COUNT_EXT                 = 0x9740
const GL_MAX_MESH_WORK_GROUP_TOTAL_COUNT_EXT                 = 0x9741
const GL_MAX_MESH_WORK_GROUP_INVOCATIONS_EXT                 = 0x9757
const GL_MAX_TASK_WORK_GROUP_INVOCATIONS_EXT                 = 0x9759
const GL_MAX_TASK_PAYLOAD_SIZE_EXT                           = 0x9742
const GL_MAX_TASK_SHARED_MEMORY_SIZE_EXT                     = 0x9743
const GL_MAX_MESH_SHARED_MEMORY_SIZE_EXT                     = 0x9744
const GL_MAX_TASK_PAYLOAD_AND_SHARED_MEMORY_SIZE_EXT         = 0x9745
const GL_MAX_MESH_PAYLOAD_AND_SHARED_MEMORY_SIZE_EXT         = 0x9746
const GL_MAX_MESH_OUTPUT_MEMORY_SIZE_EXT                     = 0x9747
const GL_MAX_MESH_PAYLOAD_AND_OUTPUT_MEMORY_SIZE_EXT         = 0x9748
const GL_MAX_MESH_OUTPUT_VERTICES_EXT                        = 0x9538
const GL_MAX_MESH_OUTPUT_PRIMITIVES_EXT                      = 0x9756
const GL_MAX_MESH_OUTPUT_COMPONENTS_EXT                      = 0x9749
const GL_MAX_MESH_OUTPUT_LAYERS_EXT                          = 0x974A
const GL_MAX_MESH_MULTIVIEW_VIEW_COUNT_EXT                   = 0x9557
const GL_MESH_OUTPUT_PER_VERTEX_GRANULARITY_EXT              = 0x92DF
const GL_MESH_OUTPUT_PER_PRIMITIVE_GRANULARITY_EXT           = 0x9543
const GL_MAX_PREFERRED_TASK_WORK_GROUP_INVOCATIONS_EXT       = 0x974B
const GL_MAX_PREFERRED_MESH_WORK_GROUP_INVOCATIONS_EXT       = 0x974C
const GL_MESH_PREFERS_LOCAL_INVOCATION_VERTEX_OUTPUT_EXT     = 0x974D
const GL_MESH_PREFERS_LOCAL_INVOCATION_PRIMITIVE_OUTPUT_EXT  = 0x974E
const GL_MESH_PREFERS_COMPACT_VERTEX_OUTPUT_EXT              = 0x974F
const GL_MESH_PREFERS_COMPACT_PRIMITIVE_OUTPUT_EXT           = 0x9750
const GL_MAX_TASK_WORK_GROUP_COUNT_EXT                       = 0x9751
const GL_MAX_MESH_WORK_GROUP_COUNT_EXT                       = 0x9752
const GL_MAX_MESH_WORK_GROUP_SIZE_EXT                        = 0x9758
const GL_MAX_TASK_WORK_GROUP_SIZE_EXT                        = 0x975A
const GL_MESH_WORK_GROUP_SIZE_EXT                            = 0x953E
const GL_TASK_WORK_GROUP_SIZE_EXT                            = 0x953F
const GL_MESH_VERTICES_OUT_EXT                               = 0x9579
const GL_MESH_PRIMITIVES_OUT_EXT                             = 0x957A
const GL_MESH_OUTPUT_TYPE_EXT                                = 0x957B
const GL_UNIFORM_BLOCK_REFERENCED_BY_MESH_SHADER_EXT         = 0x959C
const GL_UNIFORM_BLOCK_REFERENCED_BY_TASK_SHADER_EXT         = 0x959D
const GL_REFERENCED_BY_MESH_SHADER_EXT                       = 0x95A0
const GL_REFERENCED_BY_TASK_SHADER_EXT                       = 0x95A1
const GL_TASK_SHADER_INVOCATIONS_EXT                         = 0x9753
const GL_MESH_SHADER_INVOCATIONS_EXT                         = 0x9754
const GL_MESH_PRIMITIVES_GENERATED_EXT                       = 0x9755
const GL_MESH_SHADER_BIT_EXT                                 = 0x00000040
const GL_TASK_SHADER_BIT_EXT                                 = 0x00000080
const GL_MESH_SUBROUTINE_EXT                                 = 0x957C
const GL_TASK_SUBROUTINE_EXT                                 = 0x957D
const GL_MESH_SUBROUTINE_UNIFORM_EXT                         = 0x957E
const GL_TASK_SUBROUTINE_UNIFORM_EXT                         = 0x957F
const GL_ATOMIC_COUNTER_BUFFER_REFERENCED_BY_MESH_SHADER_EXT = 0x959E
const GL_ATOMIC_COUNTER_BUFFER_REFERENCED_BY_TASK_SHADER_EXT = 0x959F

#[Extension, Swag.PlaceHolder]
{
    func glDrawMeshTasksEXT(num_groups_x: GLuint, num_groups_y: GLuint, num_groups_z: GLuint)
    func glDrawMeshTasksIndirectEXT(indirect: GLintptr)
    func glMultiDrawMeshTasksIndirectCountEXT(indirect: GLintptr, drawcount: GLintptr, maxdrawcount: GLsizei, stride: GLsizei)
    func glMultiDrawMeshTasksIndirectEXT(indirect: GLintptr, drawcount: GLsizei, stride: GLsizei)
}

/* ------------- GL_EXT_multiview_tessellation_geometry_shader ------------- */

const GL_EXT_multiview_tessellation_geometry_shader = 1

/* ----------------- GL_EXT_multiview_texture_multisample ------------------ */

const GL_EXT_multiview_texture_multisample = 1

/* --------------------- GL_EXT_multiview_timer_query ---------------------- */

const GL_EXT_multiview_timer_query = 1

/* ---------------------- GL_EXT_polygon_offset_clamp ---------------------- */

const GL_EXT_polygon_offset_clamp = 1
const GL_POLYGON_OFFSET_CLAMP_EXT = 0x8E1B

#[Extension, Swag.PlaceHolder]
{
    func glPolygonOffsetClampEXT(factor: GLfloat, units: GLfloat, clamp: GLfloat)
}

/* ---------------------- GL_EXT_post_depth_coverage ----------------------- */

const GL_EXT_post_depth_coverage = 1

/* ----------------------- GL_EXT_raster_multisample ----------------------- */

const GL_EXT_raster_multisample                = 1
const GL_RASTER_MULTISAMPLE_EXT                = 0x9327
const GL_RASTER_SAMPLES_EXT                    = 0x9328
const GL_MAX_RASTER_SAMPLES_EXT                = 0x9329
const GL_RASTER_FIXED_SAMPLE_LOCATIONS_EXT     = 0x932A
const GL_MULTISAMPLE_RASTERIZATION_ALLOWED_EXT = 0x932B
const GL_EFFECTIVE_RASTER_SAMPLES_EXT          = 0x932C

#[Extension, Swag.PlaceHolder]
{
    func glRasterSamplesEXT(samples: GLuint, fixedsamplelocations: GLboolean)
}

/* -------------------- GL_EXT_separate_shader_objects --------------------- */

const GL_EXT_separate_shader_objects = 1
const GL_ACTIVE_PROGRAM_EXT          = 0x8B8D

#[Extension, Swag.PlaceHolder]
{
    func glActiveProgramEXT(program: GLuint)
    func glCreateShaderProgramEXT(type: GLenum, stringValue: const *GLchar?)->GLuint
    func glUseShaderProgramEXT(type: GLenum, program: GLuint)
}

/* -------------------- GL_EXT_shader_framebuffer_fetch -------------------- */

const GL_EXT_shader_framebuffer_fetch         = 1
const GL_FRAGMENT_SHADER_DISCARDS_SAMPLES_EXT = 0x8A52

/* ------------- GL_EXT_shader_framebuffer_fetch_non_coherent -------------- */

const GL_EXT_shader_framebuffer_fetch_non_coherent = 1

#[Extension, Swag.PlaceHolder]
{
    func glFramebufferFetchBarrierEXT()
}

/* ----------------------- GL_EXT_shader_integer_mix ----------------------- */

const GL_EXT_shader_integer_mix = 1

/* -------------------- GL_EXT_texture_compression_s3tc -------------------- */

const GL_EXT_texture_compression_s3tc  = 1
const GL_COMPRESSED_RGB_S3TC_DXT1_EXT  = 0x83F0
const GL_COMPRESSED_RGBA_S3TC_DXT1_EXT = 0x83F1
const GL_COMPRESSED_RGBA_S3TC_DXT3_EXT = 0x83F2
const GL_COMPRESSED_RGBA_S3TC_DXT5_EXT = 0x83F3

/* --------------------- GL_EXT_texture_filter_minmax ---------------------- */

const GL_EXT_texture_filter_minmax  = 1
const GL_TEXTURE_REDUCTION_MODE_EXT = 0x9366
const GL_WEIGHTED_AVERAGE_EXT       = 0x9367

/* -------------------------- GL_EXT_texture_sRGB -------------------------- */

const GL_EXT_texture_sRGB                    = 1
const GL_SRGB_EXT                            = 0x8C40
const GL_SRGB8_EXT                           = 0x8C41
const GL_SRGB_ALPHA_EXT                      = 0x8C42
const GL_SRGB8_ALPHA8_EXT                    = 0x8C43
const GL_COMPRESSED_SRGB_EXT                 = 0x8C48
const GL_COMPRESSED_SRGB_ALPHA_EXT           = 0x8C49
const GL_COMPRESSED_SRGB_S3TC_DXT1_EXT       = 0x8C4C
const GL_COMPRESSED_SRGB_ALPHA_S3TC_DXT1_EXT = 0x8C4D
const GL_COMPRESSED_SRGB_ALPHA_S3TC_DXT3_EXT = 0x8C4E
const GL_COMPRESSED_SRGB_ALPHA_S3TC_DXT5_EXT = 0x8C4F

/* ------------------------ GL_EXT_texture_sRGB_R8 ------------------------- */

const GL_EXT_texture_sRGB_R8 = 1
const GL_SR8_EXT             = 0x8FBD

/* ------------------------ GL_EXT_texture_sRGB_RG8 ------------------------ */

const GL_EXT_texture_sRGB_RG8 = 1
const GL_SRG8_EXT             = 0x8FBE

/* ---------------------- GL_EXT_texture_sRGB_decode ----------------------- */

const GL_EXT_texture_sRGB_decode = 1
const GL_TEXTURE_SRGB_DECODE_EXT = 0x8A48
const GL_DECODE_EXT              = 0x8A49
const GL_SKIP_DECODE_EXT         = 0x8A4A

/* ----------------------- GL_EXT_texture_shadow_lod ----------------------- */

const GL_EXT_texture_shadow_lod = 1

/* ------------------------ GL_EXT_texture_storage ------------------------- */

const GL_EXT_texture_storage          = 1
const GL_TEXTURE_IMMUTABLE_FORMAT_EXT = 0x912F
const GL_ALPHA8_EXT                   = 0x803C
const GL_LUMINANCE8_EXT               = 0x8040
const GL_LUMINANCE8_ALPHA8_EXT        = 0x8045
const GL_RGBA32F_EXT                  = 0x8814
const GL_RGB32F_EXT                   = 0x8815
const GL_ALPHA32F_EXT                 = 0x8816
const GL_LUMINANCE32F_EXT             = 0x8818
const GL_LUMINANCE_ALPHA32F_EXT       = 0x8819
const GL_RGBA16F_EXT                  = 0x881A
const GL_RGB16F_EXT                   = 0x881B
const GL_ALPHA16F_EXT                 = 0x881C
const GL_LUMINANCE16F_EXT             = 0x881E
const GL_LUMINANCE_ALPHA16F_EXT       = 0x881F
const GL_RGB10_A2_EXT                 = 0x8059
const GL_RGB10_EXT                    = 0x8052
const GL_BGRA8_EXT                    = 0x93A1
const GL_R8_EXT                       = 0x8229
const GL_RG8_EXT                      = 0x822B
const GL_R32F_EXT                     = 0x822E
const GL_RG32F_EXT                    = 0x8230
const GL_R16F_EXT                     = 0x822D
const GL_RG16F_EXT                    = 0x822F

#[Extension, Swag.PlaceHolder]
{
    func glTexStorage1DEXT(target: GLenum, levels: GLsizei, internalformat: GLenum, width: GLsizei)
    func glTexStorage2DEXT(target: GLenum, levels: GLsizei, internalformat: GLenum, width: GLsizei, height: GLsizei)
    func glTexStorage3DEXT(target: GLenum, levels: GLsizei, internalformat: GLenum, width: GLsizei, height: GLsizei, depth: GLsizei)
}

/* ----------------------- GL_EXT_window_rectangles ------------------------ */

const GL_EXT_window_rectangles     = 1
const GL_INCLUSIVE_EXT             = 0x8F10
const GL_EXCLUSIVE_EXT             = 0x8F11
const GL_WINDOW_RECTANGLE_EXT      = 0x8F12
const GL_WINDOW_RECTANGLE_MODE_EXT = 0x8F13
const GL_MAX_WINDOW_RECTANGLES_EXT = 0x8F14
const GL_NUM_WINDOW_RECTANGLES_EXT = 0x8F15

#[Extension, Swag.PlaceHolder]
{
    func glWindowRectanglesEXT(mode: GLenum, count: GLsizei, box: const *GLint?)
}
