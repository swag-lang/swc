#global public

using Swag

#[Extension, Swag.PlaceHolder]
{
    func glBeginQueryIndexed(target: GLenum, index: GLuint, id: GLuint)
    func glBindTransformFeedback(target: GLenum, id: GLuint)
    func glBlendEquationSeparatei(buf: GLuint, modeRGB: GLenum, modeAlpha: GLenum)
    func glBlendEquationi(buf: GLuint, mode: GLenum)
    func glBlendFuncSeparatei(buf: GLuint, srcRGB: GLenum, dstRGB: GLenum, srcAlpha: GLenum, dstAlpha: GLenum)
    func glBlendFunci(buf: GLuint, src: GLenum, dst: GLenum)
    func glDeleteTransformFeedbacks(n: GLsizei, ids: const *GLuint?)
    func glDrawArraysIndirect(mode: GLenum, indirect: const *void?)
    func glDrawElementsIndirect(mode: GLenum, type: GLenum, indirect: const *void?)
    func glDrawTransformFeedback(mode: GLenum, id: GLuint)
    func glDrawTransformFeedbackStream(mode: GLenum, id: GLuint, stream: GLuint)
    func glEndQueryIndexed(target: GLenum, index: GLuint)
    func glGenTransformFeedbacks(n: GLsizei, ids: *GLuint?)
    func glGetActiveSubroutineName(program: GLuint, shadertype: GLenum, index: GLuint, bufSize: GLsizei, length: *GLsizei?, name: *GLchar?)
    func glGetActiveSubroutineUniformName(program: GLuint, shadertype: GLenum, index: GLuint, bufSize: GLsizei, length: *GLsizei?, name: *GLchar?)
    func glGetActiveSubroutineUniformiv(program: GLuint, shadertype: GLenum, index: GLuint, pname: GLenum, values: *GLint?)
    func glGetProgramStageiv(program: GLuint, shadertype: GLenum, pname: GLenum, values: *GLint?)
    func glGetQueryIndexediv(target: GLenum, index: GLuint, pname: GLenum, params: *GLint?)
    func glGetSubroutineIndex(program: GLuint, shadertype: GLenum, name: const *GLchar?)->GLuint
    func glGetSubroutineUniformLocation(program: GLuint, shadertype: GLenum, name: const *GLchar?)->GLint
    func glGetUniformSubroutineuiv(shadertype: GLenum, location: GLint, params: *GLuint?)
    func glGetUniformdv(program: GLuint, location: GLint, params: *GLdouble?)
    func glIsTransformFeedback(id: GLuint)->GLboolean
    func glMinSampleShading(value: GLclampf)
    func glPatchParameterfv(pname: GLenum, values: const *GLfloat?)
    func glPatchParameteri(pname: GLenum, value: GLint)
    func glPauseTransformFeedback()
    func glResumeTransformFeedback()
    func glUniform1d(location: GLint, x: GLdouble)
    func glUniform1dv(location: GLint, count: GLsizei, value: const *GLdouble?)
    func glUniform2d(location: GLint, x: GLdouble, y: GLdouble)
    func glUniform2dv(location: GLint, count: GLsizei, value: const *GLdouble?)
    func glUniform3d(location: GLint, x: GLdouble, y: GLdouble, z: GLdouble)
    func glUniform3dv(location: GLint, count: GLsizei, value: const *GLdouble?)
    func glUniform4d(location: GLint, x: GLdouble, y: GLdouble, z: GLdouble, w: GLdouble)
    func glUniform4dv(location: GLint, count: GLsizei, value: const *GLdouble?)
    func glUniformMatrix2dv(location: GLint, count: GLsizei, transpose: GLboolean, value: const *GLdouble?)
    func glUniformMatrix2x3dv(location: GLint, count: GLsizei, transpose: GLboolean, value: const *GLdouble?)
    func glUniformMatrix2x4dv(location: GLint, count: GLsizei, transpose: GLboolean, value: const *GLdouble?)
    func glUniformMatrix3dv(location: GLint, count: GLsizei, transpose: GLboolean, value: const *GLdouble?)
    func glUniformMatrix3x2dv(location: GLint, count: GLsizei, transpose: GLboolean, value: const *GLdouble?)
    func glUniformMatrix3x4dv(location: GLint, count: GLsizei, transpose: GLboolean, value: const *GLdouble?)
    func glUniformMatrix4dv(location: GLint, count: GLsizei, transpose: GLboolean, value: const *GLdouble?)
    func glUniformMatrix4x2dv(location: GLint, count: GLsizei, transpose: GLboolean, value: const *GLdouble?)
    func glUniformMatrix4x3dv(location: GLint, count: GLsizei, transpose: GLboolean, value: const *GLdouble?)
    func glUniformSubroutinesuiv(shadertype: GLenum, count: GLsizei, indices: const *GLuint?)
}

const GL_SAMPLE_SHADING                                     = 0x8C36
const GL_MIN_SAMPLE_SHADING_VALUE                           = 0x8C37
const GL_MIN_PROGRAM_TEXTURE_GATHER_OFFSET                  = 0x8E5E
const GL_MAX_PROGRAM_TEXTURE_GATHER_OFFSET                  = 0x8E5F
const GL_MAX_PROGRAM_TEXTURE_GATHER_COMPONENTS              = 0x8F9F
const GL_TEXTURE_CUBE_MAP_ARRAY                             = 0x9009
const GL_TEXTURE_BINDING_CUBE_MAP_ARRAY                     = 0x900A
const GL_PROXY_TEXTURE_CUBE_MAP_ARRAY                       = 0x900B
const GL_SAMPLER_CUBE_MAP_ARRAY                             = 0x900C
const GL_SAMPLER_CUBE_MAP_ARRAY_SHADOW                      = 0x900D
const GL_INT_SAMPLER_CUBE_MAP_ARRAY                         = 0x900E
const GL_UNSIGNED_INT_SAMPLER_CUBE_MAP_ARRAY                = 0x900F
const GL_DRAW_INDIRECT_BUFFER                               = 0x8F3F
const GL_DRAW_INDIRECT_BUFFER_BINDING                       = 0x8F43
const GL_GEOMETRY_SHADER_INVOCATIONS                        = 0x887F
const GL_MAX_GEOMETRY_SHADER_INVOCATIONS                    = 0x8E5A
const GL_MIN_FRAGMENT_INTERPOLATION_OFFSET                  = 0x8E5B
const GL_MAX_FRAGMENT_INTERPOLATION_OFFSET                  = 0x8E5C
const GL_FRAGMENT_INTERPOLATION_OFFSET_BITS                 = 0x8E5D
const GL_MAX_VERTEX_STREAMS                                 = 0x8E71
const GL_DOUBLE_VEC2                                        = 0x8FFC
const GL_DOUBLE_VEC3                                        = 0x8FFD
const GL_DOUBLE_VEC4                                        = 0x8FFE
const GL_DOUBLE_MAT2                                        = 0x8F46
const GL_DOUBLE_MAT3                                        = 0x8F47
const GL_DOUBLE_MAT4                                        = 0x8F48
const GL_DOUBLE_MAT2x3                                      = 0x8F49
const GL_DOUBLE_MAT2x4                                      = 0x8F4A
const GL_DOUBLE_MAT3x2                                      = 0x8F4B
const GL_DOUBLE_MAT3x4                                      = 0x8F4C
const GL_DOUBLE_MAT4x2                                      = 0x8F4D
const GL_DOUBLE_MAT4x3                                      = 0x8F4E
const GL_ACTIVE_SUBROUTINES                                 = 0x8DE5
const GL_ACTIVE_SUBROUTINE_UNIFORMS                         = 0x8DE6
const GL_ACTIVE_SUBROUTINE_UNIFORM_LOCATIONS                = 0x8E47
const GL_ACTIVE_SUBROUTINE_MAX_LENGTH                       = 0x8E48
const GL_ACTIVE_SUBROUTINE_UNIFORM_MAX_LENGTH               = 0x8E49
const GL_MAX_SUBROUTINES                                    = 0x8DE7
const GL_MAX_SUBROUTINE_UNIFORM_LOCATIONS                   = 0x8DE8
const GL_NUM_COMPATIBLE_SUBROUTINES                         = 0x8E4A
const GL_COMPATIBLE_SUBROUTINES                             = 0x8E4B
const GL_PATCHES                                            = 0x000E
const GL_PATCH_VERTICES                                     = 0x8E72
const GL_PATCH_DEFAULT_INNER_LEVEL                          = 0x8E73
const GL_PATCH_DEFAULT_OUTER_LEVEL                          = 0x8E74
const GL_TESS_CONTROL_OUTPUT_VERTICES                       = 0x8E75
const GL_TESS_GEN_MODE                                      = 0x8E76
const GL_TESS_GEN_SPACING                                   = 0x8E77
const GL_TESS_GEN_VERTEX_ORDER                              = 0x8E78
const GL_TESS_GEN_POINT_MODE                                = 0x8E79
const GL_ISOLINES                                           = 0x8E7A
const GL_FRACTIONAL_ODD                                     = 0x8E7B
const GL_FRACTIONAL_EVEN                                    = 0x8E7C
const GL_MAX_PATCH_VERTICES                                 = 0x8E7D
const GL_MAX_TESS_GEN_LEVEL                                 = 0x8E7E
const GL_MAX_TESS_CONTROL_UNIFORM_COMPONENTS                = 0x8E7F
const GL_MAX_TESS_EVALUATION_UNIFORM_COMPONENTS             = 0x8E80
const GL_MAX_TESS_CONTROL_TEXTURE_IMAGE_UNITS               = 0x8E81
const GL_MAX_TESS_EVALUATION_TEXTURE_IMAGE_UNITS            = 0x8E82
const GL_MAX_TESS_CONTROL_OUTPUT_COMPONENTS                 = 0x8E83
const GL_MAX_TESS_PATCH_COMPONENTS                          = 0x8E84
const GL_MAX_TESS_CONTROL_TOTAL_OUTPUT_COMPONENTS           = 0x8E85
const GL_MAX_TESS_EVALUATION_OUTPUT_COMPONENTS              = 0x8E86
const GL_MAX_TESS_CONTROL_UNIFORM_BLOCKS                    = 0x8E89
const GL_MAX_TESS_EVALUATION_UNIFORM_BLOCKS                 = 0x8E8A
const GL_MAX_TESS_CONTROL_INPUT_COMPONENTS                  = 0x886C
const GL_MAX_TESS_EVALUATION_INPUT_COMPONENTS               = 0x886D
const GL_MAX_COMBINED_TESS_CONTROL_UNIFORM_COMPONENTS       = 0x8E1E
const GL_MAX_COMBINED_TESS_EVALUATION_UNIFORM_COMPONENTS    = 0x8E1F
const GL_UNIFORM_BLOCK_REFERENCED_BY_TESS_CONTROL_SHADER    = 0x84F0
const GL_UNIFORM_BLOCK_REFERENCED_BY_TESS_EVALUATION_SHADER = 0x84F1
const GL_TESS_EVALUATION_SHADER                             = 0x8E87
const GL_TESS_CONTROL_SHADER                                = 0x8E88
const GL_TRANSFORM_FEEDBACK                                 = 0x8E22
const GL_TRANSFORM_FEEDBACK_BUFFER_PAUSED                   = 0x8E23
const GL_TRANSFORM_FEEDBACK_BUFFER_ACTIVE                   = 0x8E24
const GL_TRANSFORM_FEEDBACK_BINDING                         = 0x8E25
const GL_MAX_TRANSFORM_FEEDBACK_BUFFERS                     = 0x8E70
