#global public

using Swag

#[Extension, Swag.PlaceHolder]
{
    func glActiveShaderProgram(pipeline: GLuint, program: GLuint)
    func glBindProgramPipeline(pipeline: GLuint)
    func glClearDepthf(d: GLfloat)
    func glCreateShaderProgramv(type: GLenum, count: GLsizei, strings: const *(const *GLchar?)?)->GLuint
    func glDeleteProgramPipelines(n: GLsizei, pipelines: const *GLuint?)
    func glDepthRangeArrayv(first: GLuint, count: GLsizei, v: const *GLdouble?)
    func glDepthRangeIndexed(index: GLuint, n: GLdouble, f: GLdouble)
    func glDepthRangef(n: GLfloat, f: GLfloat)
    func glGenProgramPipelines(n: GLsizei, pipelines: *GLuint?)
    func glGetDoublei_v(target: GLenum, index: GLuint, data: *GLdouble?)
    func glGetFloati_v(target: GLenum, index: GLuint, data: *GLfloat?)
    func glGetProgramBinary(program: GLuint, bufSize: GLsizei, length: *GLsizei?, binaryFormat: *GLenum?, binary: *void?)
    func glGetProgramPipelineInfoLog(pipeline: GLuint, bufSize: GLsizei, length: *GLsizei?, infoLog: *GLchar?)
    func glGetProgramPipelineiv(pipeline: GLuint, pname: GLenum, params: *GLint?)
    func glGetShaderPrecisionFormat(shadertype: GLenum, precisiontype: GLenum, range: *GLint?, precision: *GLint?)
    func glGetVertexAttribLdv(index: GLuint, pname: GLenum, params: *GLdouble?)
    func glIsProgramPipeline(pipeline: GLuint)->GLboolean
    func glProgramBinary(program: GLuint, binaryFormat: GLenum, binary: const *void?, length: GLsizei)
    func glProgramParameteri(program: GLuint, pname: GLenum, value: GLint)
    func glProgramUniform1d(program: GLuint, location: GLint, v0: GLdouble)
    func glProgramUniform1dv(program: GLuint, location: GLint, count: GLsizei, value: const *GLdouble?)
    func glProgramUniform1f(program: GLuint, location: GLint, v0: GLfloat)
    func glProgramUniform1fv(program: GLuint, location: GLint, count: GLsizei, value: const *GLfloat?)
    func glProgramUniform1i(program: GLuint, location: GLint, v0: GLint)
    func glProgramUniform1iv(program: GLuint, location: GLint, count: GLsizei, value: const *GLint?)
    func glProgramUniform1ui(program: GLuint, location: GLint, v0: GLuint)
    func glProgramUniform1uiv(program: GLuint, location: GLint, count: GLsizei, value: const *GLuint?)
    func glProgramUniform2d(program: GLuint, location: GLint, v0: GLdouble, v1: GLdouble)
    func glProgramUniform2dv(program: GLuint, location: GLint, count: GLsizei, value: const *GLdouble?)
    func glProgramUniform2f(program: GLuint, location: GLint, v0: GLfloat, v1: GLfloat)
    func glProgramUniform2fv(program: GLuint, location: GLint, count: GLsizei, value: const *GLfloat?)
    func glProgramUniform2i(program: GLuint, location: GLint, v0: GLint, v1: GLint)
    func glProgramUniform2iv(program: GLuint, location: GLint, count: GLsizei, value: const *GLint?)
    func glProgramUniform2ui(program: GLuint, location: GLint, v0: GLuint, v1: GLuint)
    func glProgramUniform2uiv(program: GLuint, location: GLint, count: GLsizei, value: const *GLuint?)
    func glProgramUniform3d(program: GLuint, location: GLint, v0: GLdouble, v1: GLdouble, v2: GLdouble)
    func glProgramUniform3dv(program: GLuint, location: GLint, count: GLsizei, value: const *GLdouble?)
    func glProgramUniform3f(program: GLuint, location: GLint, v0: GLfloat, v1: GLfloat, v2: GLfloat)
    func glProgramUniform3fv(program: GLuint, location: GLint, count: GLsizei, value: const *GLfloat?)
    func glProgramUniform3i(program: GLuint, location: GLint, v0: GLint, v1: GLint, v2: GLint)
    func glProgramUniform3iv(program: GLuint, location: GLint, count: GLsizei, value: const *GLint?)
    func glProgramUniform3ui(program: GLuint, location: GLint, v0: GLuint, v1: GLuint, v2: GLuint)
    func glProgramUniform3uiv(program: GLuint, location: GLint, count: GLsizei, value: const *GLuint?)
    func glProgramUniform4d(program: GLuint, location: GLint, v0: GLdouble, v1: GLdouble, v2: GLdouble, v3: GLdouble)
    func glProgramUniform4dv(program: GLuint, location: GLint, count: GLsizei, value: const *GLdouble?)
    func glProgramUniform4f(program: GLuint, location: GLint, v0: GLfloat, v1: GLfloat, v2: GLfloat, v3: GLfloat)
    func glProgramUniform4fv(program: GLuint, location: GLint, count: GLsizei, value: const *GLfloat?)
    func glProgramUniform4i(program: GLuint, location: GLint, v0: GLint, v1: GLint, v2: GLint, v3: GLint)
    func glProgramUniform4iv(program: GLuint, location: GLint, count: GLsizei, value: const *GLint?)
    func glProgramUniform4ui(program: GLuint, location: GLint, v0: GLuint, v1: GLuint, v2: GLuint, v3: GLuint)
    func glProgramUniform4uiv(program: GLuint, location: GLint, count: GLsizei, value: const *GLuint?)
    func glProgramUniformMatrix2dv(program: GLuint, location: GLint, count: GLsizei, transpose: GLboolean, value: const *GLdouble?)
    func glProgramUniformMatrix2fv(program: GLuint, location: GLint, count: GLsizei, transpose: GLboolean, value: const *GLfloat?)
    func glProgramUniformMatrix2x3dv(program: GLuint, location: GLint, count: GLsizei, transpose: GLboolean, value: const *GLdouble?)
    func glProgramUniformMatrix2x3fv(program: GLuint, location: GLint, count: GLsizei, transpose: GLboolean, value: const *GLfloat?)
    func glProgramUniformMatrix2x4dv(program: GLuint, location: GLint, count: GLsizei, transpose: GLboolean, value: const *GLdouble?)
    func glProgramUniformMatrix2x4fv(program: GLuint, location: GLint, count: GLsizei, transpose: GLboolean, value: const *GLfloat?)
    func glProgramUniformMatrix3dv(program: GLuint, location: GLint, count: GLsizei, transpose: GLboolean, value: const *GLdouble?)
    func glProgramUniformMatrix3fv(program: GLuint, location: GLint, count: GLsizei, transpose: GLboolean, value: const *GLfloat?)
    func glProgramUniformMatrix3x2dv(program: GLuint, location: GLint, count: GLsizei, transpose: GLboolean, value: const *GLdouble?)
    func glProgramUniformMatrix3x2fv(program: GLuint, location: GLint, count: GLsizei, transpose: GLboolean, value: const *GLfloat?)
    func glProgramUniformMatrix3x4dv(program: GLuint, location: GLint, count: GLsizei, transpose: GLboolean, value: const *GLdouble?)
    func glProgramUniformMatrix3x4fv(program: GLuint, location: GLint, count: GLsizei, transpose: GLboolean, value: const *GLfloat?)
    func glProgramUniformMatrix4dv(program: GLuint, location: GLint, count: GLsizei, transpose: GLboolean, value: const *GLdouble?)
    func glProgramUniformMatrix4fv(program: GLuint, location: GLint, count: GLsizei, transpose: GLboolean, value: const *GLfloat?)
    func glProgramUniformMatrix4x2dv(program: GLuint, location: GLint, count: GLsizei, transpose: GLboolean, value: const *GLdouble?)
    func glProgramUniformMatrix4x2fv(program: GLuint, location: GLint, count: GLsizei, transpose: GLboolean, value: const *GLfloat?)
    func glProgramUniformMatrix4x3dv(program: GLuint, location: GLint, count: GLsizei, transpose: GLboolean, value: const *GLdouble?)
    func glProgramUniformMatrix4x3fv(program: GLuint, location: GLint, count: GLsizei, transpose: GLboolean, value: const *GLfloat?)
    func glReleaseShaderCompiler()
    func glScissorArrayv(first: GLuint, count: GLsizei, v: const *GLint?)
    func glScissorIndexed(index: GLuint, left: GLint, bottom: GLint, width: GLsizei, height: GLsizei)
    func glScissorIndexedv(index: GLuint, v: const *GLint?)
    func glShaderBinary(count: GLsizei, shaders: const *GLuint?, binaryFormat: GLenum, binary: const *void?, length: GLsizei)
    func glUseProgramStages(pipeline: GLuint, stages: GLbitfield, program: GLuint)
    func glValidateProgramPipeline(pipeline: GLuint)
    func glVertexAttribL1d(index: GLuint, x: GLdouble)
    func glVertexAttribL1dv(index: GLuint, v: const *GLdouble?)
    func glVertexAttribL2d(index: GLuint, x: GLdouble, y: GLdouble)
    func glVertexAttribL2dv(index: GLuint, v: const *GLdouble?)
    func glVertexAttribL3d(index: GLuint, x: GLdouble, y: GLdouble, z: GLdouble)
    func glVertexAttribL3dv(index: GLuint, v: const *GLdouble?)
    func glVertexAttribL4d(index: GLuint, x: GLdouble, y: GLdouble, z: GLdouble, w: GLdouble)
    func glVertexAttribL4dv(index: GLuint, v: const *GLdouble?)
    func glVertexAttribLPointer(index: GLuint, size: GLint, type: GLenum, stride: GLsizei, pointer: const *void?)
    func glViewportArrayv(first: GLuint, count: GLsizei, v: const *GLfloat?)
    func glViewportIndexedf(index: GLuint, x: GLfloat, y: GLfloat, w: GLfloat, h: GLfloat)
    func glViewportIndexedfv(index: GLuint, v: const *GLfloat?)
}

const GL_FIXED                            = 0x140C
const GL_IMPLEMENTATION_COLOR_READ_TYPE   = 0x8B9A
const GL_IMPLEMENTATION_COLOR_READ_FORMAT = 0x8B9B
const GL_LOW_FLOAT                        = 0x8DF0
const GL_MEDIUM_FLOAT                     = 0x8DF1
const GL_HIGH_FLOAT                       = 0x8DF2
const GL_LOW_INT                          = 0x8DF3
const GL_MEDIUM_INT                       = 0x8DF4
const GL_HIGH_INT                         = 0x8DF5
const GL_SHADER_COMPILER                  = 0x8DFA
const GL_SHADER_BINARY_FORMATS            = 0x8DF8
const GL_NUM_SHADER_BINARY_FORMATS        = 0x8DF9
const GL_MAX_VERTEX_UNIFORM_VECTORS       = 0x8DFB
const GL_MAX_VARYING_VECTORS              = 0x8DFC
const GL_MAX_FRAGMENT_UNIFORM_VECTORS     = 0x8DFD
const GL_RGB565                           = 0x8D62
const GL_PROGRAM_BINARY_RETRIEVABLE_HINT  = 0x8257
const GL_PROGRAM_BINARY_LENGTH            = 0x8741
const GL_NUM_PROGRAM_BINARY_FORMATS       = 0x87FE
const GL_PROGRAM_BINARY_FORMATS           = 0x87FF
const GL_VERTEX_SHADER_BIT                = 0x00000001
const GL_FRAGMENT_SHADER_BIT              = 0x00000002
const GL_GEOMETRY_SHADER_BIT              = 0x00000004
const GL_TESS_CONTROL_SHADER_BIT          = 0x00000008
const GL_TESS_EVALUATION_SHADER_BIT       = 0x00000010
const GL_ALL_SHADER_BITS                  = 0xFFFFFFFF
const GL_PROGRAM_SEPARABLE                = 0x8258
const GL_ACTIVE_PROGRAM                   = 0x8259
const GL_PROGRAM_PIPELINE_BINDING         = 0x825A
const GL_MAX_VIEWPORTS                    = 0x825B
const GL_VIEWPORT_SUBPIXEL_BITS           = 0x825C
const GL_VIEWPORT_BOUNDS_RANGE            = 0x825D
const GL_LAYER_PROVOKING_VERTEX           = 0x825E
const GL_VIEWPORT_INDEX_PROVOKING_VERTEX  = 0x825F
const GL_UNDEFINED_VERTEX                 = 0x8260
