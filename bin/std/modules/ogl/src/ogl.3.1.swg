#global public

using Swag

#[Extension, Swag.PlaceHolder]
{
    func glCopyBufferSubData(readTarget: GLenum, writeTarget: GLenum, readOffset: GLintptr, writeOffset: GLintptr, size: GLsizeiptr)
    func glDrawArraysInstanced(mode: GLenum, first: GLint, count: GLsizei, primcount: GLsizei)
    func glDrawElementsInstanced(mode: GLenum, count: GLsizei, type: GLenum, indices: const *void?, primcount: GLsizei)
    func glGetActiveUniformBlockName(program: GLuint, uniformBlockIndex: GLuint, bufSize: GLsizei, length: *GLsizei?, uniformBlockName: *GLchar?)
    func glGetActiveUniformBlockiv(program: GLuint, uniformBlockIndex: GLuint, pname: GLenum, params: *GLint?)
    func glGetActiveUniformName(program: GLuint, uniformIndex: GLuint, bufSize: GLsizei, length: *GLsizei?, uniformName: *GLchar?)
    func glGetActiveUniformsiv(program: GLuint, uniformCount: GLsizei, uniformIndices: const *GLuint?, pname: GLenum, params: *GLint?)
    func glGetUniformBlockIndex(program: GLuint, uniformBlockName: const *GLchar?)->GLuint
    func glGetUniformIndices(program: GLuint, uniformCount: GLsizei, uniformNames: const *(const *GLchar?)?, uniformIndices: *GLuint?)
    func glPrimitiveRestartIndex(buffer: GLuint)
    func glTexBuffer(target: GLenum, internalFormat: GLenum, buffer: GLuint)
    func glUniformBlockBinding(program: GLuint, uniformBlockIndex: GLuint, uniformBlockBinding: GLuint)
}

const GL_TEXTURE_RECTANGLE                           = 0x84F5
const GL_TEXTURE_BINDING_RECTANGLE                   = 0x84F6
const GL_PROXY_TEXTURE_RECTANGLE                     = 0x84F7
const GL_MAX_RECTANGLE_TEXTURE_SIZE                  = 0x84F8
const GL_SAMPLER_2D_RECT                             = 0x8B63
const GL_SAMPLER_2D_RECT_SHADOW                      = 0x8B64
const GL_TEXTURE_BUFFER                              = 0x8C2A
const GL_MAX_TEXTURE_BUFFER_SIZE                     = 0x8C2B
const GL_TEXTURE_BINDING_BUFFER                      = 0x8C2C
const GL_TEXTURE_BUFFER_DATA_STORE_BINDING           = 0x8C2D
const GL_TEXTURE_BUFFER_FORMAT                       = 0x8C2E
const GL_SAMPLER_BUFFER                              = 0x8DC2
const GL_INT_SAMPLER_2D_RECT                         = 0x8DCD
const GL_INT_SAMPLER_BUFFER                          = 0x8DD0
const GL_UNSIGNED_INT_SAMPLER_2D_RECT                = 0x8DD5
const GL_UNSIGNED_INT_SAMPLER_BUFFER                 = 0x8DD8
const GL_RED_SNORM                                   = 0x8F90
const GL_RG_SNORM                                    = 0x8F91
const GL_RGB_SNORM                                   = 0x8F92
const GL_RGBA_SNORM                                  = 0x8F93
const GL_R8_SNORM                                    = 0x8F94
const GL_RG8_SNORM                                   = 0x8F95
const GL_RGB8_SNORM                                  = 0x8F96
const GL_RGBA8_SNORM                                 = 0x8F97
const GL_R16_SNORM                                   = 0x8F98
const GL_RG16_SNORM                                  = 0x8F99
const GL_RGB16_SNORM                                 = 0x8F9A
const GL_RGBA16_SNORM                                = 0x8F9B
const GL_SIGNED_NORMALIZED                           = 0x8F9C
const GL_PRIMITIVE_RESTART                           = 0x8F9D
const GL_PRIMITIVE_RESTART_INDEX                     = 0x8F9E
const GL_BUFFER_ACCESS_FLAGS                         = 0x911F
const GL_BUFFER_MAP_LENGTH                           = 0x9120
const GL_BUFFER_MAP_OFFSET                           = 0x9121
const GL_COPY_READ_BUFFER                            = 0x8F36
const GL_COPY_WRITE_BUFFER                           = 0x8F37
const GL_UNIFORM_BUFFER                              = 0x8A11
const GL_UNIFORM_BUFFER_BINDING                      = 0x8A28
const GL_UNIFORM_BUFFER_START                        = 0x8A29
const GL_UNIFORM_BUFFER_SIZE                         = 0x8A2A
const GL_MAX_VERTEX_UNIFORM_BLOCKS                   = 0x8A2B
const GL_MAX_GEOMETRY_UNIFORM_BLOCKS                 = 0x8A2C
const GL_MAX_FRAGMENT_UNIFORM_BLOCKS                 = 0x8A2D
const GL_MAX_COMBINED_UNIFORM_BLOCKS                 = 0x8A2E
const GL_MAX_UNIFORM_BUFFER_BINDINGS                 = 0x8A2F
const GL_MAX_UNIFORM_BLOCK_SIZE                      = 0x8A30
const GL_MAX_COMBINED_VERTEX_UNIFORM_COMPONENTS      = 0x8A31
const GL_MAX_COMBINED_GEOMETRY_UNIFORM_COMPONENTS    = 0x8A32
const GL_MAX_COMBINED_FRAGMENT_UNIFORM_COMPONENTS    = 0x8A33
const GL_UNIFORM_BUFFER_OFFSET_ALIGNMENT             = 0x8A34
const GL_ACTIVE_UNIFORM_BLOCK_MAX_NAME_LENGTH        = 0x8A35
const GL_ACTIVE_UNIFORM_BLOCKS                       = 0x8A36
const GL_UNIFORM_TYPE                                = 0x8A37
const GL_UNIFORM_SIZE                                = 0x8A38
const GL_UNIFORM_NAME_LENGTH                         = 0x8A39
const GL_UNIFORM_BLOCK_INDEX                         = 0x8A3A
const GL_UNIFORM_OFFSET                              = 0x8A3B
const GL_UNIFORM_ARRAY_STRIDE                        = 0x8A3C
const GL_UNIFORM_MATRIX_STRIDE                       = 0x8A3D
const GL_UNIFORM_IS_ROW_MAJOR                        = 0x8A3E
const GL_UNIFORM_BLOCK_BINDING                       = 0x8A3F
const GL_UNIFORM_BLOCK_DATA_SIZE                     = 0x8A40
const GL_UNIFORM_BLOCK_NAME_LENGTH                   = 0x8A41
const GL_UNIFORM_BLOCK_ACTIVE_UNIFORMS               = 0x8A42
const GL_UNIFORM_BLOCK_ACTIVE_UNIFORM_INDICES        = 0x8A43
const GL_UNIFORM_BLOCK_REFERENCED_BY_VERTEX_SHADER   = 0x8A44
const GL_UNIFORM_BLOCK_REFERENCED_BY_GEOMETRY_SHADER = 0x8A45
const GL_UNIFORM_BLOCK_REFERENCED_BY_FRAGMENT_SHADER = 0x8A46
const GL_INVALID_INDEX                               = 0xFFFFFFFF
