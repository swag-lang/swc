#global public

using Swag

#[Extension, Swag.PlaceHolder]

{
    func glBindFragDataLocationIndexed(program: GLuint, colorNumber: GLuint, index: GLuint, name: #null const *GLchar)

    func glBindSampler(unit: GLuint, sampler: GLuint)

    func glDeleteSamplers(count: GLsizei, samplers: #null const *GLuint)

    func glGenSamplers(count: GLsizei, samplers: #null *GLuint)

    func glGetFragDataIndex(program: GLuint, name: #null const *GLchar)->GLint

    func glGetQueryObjecti64v(id: GLuint, pname: GLenum, params: #null *GLint64)

    func glGetQueryObjectui64v(id: GLuint, pname: GLenum, params: #null *GLuint64)

    func glGetSamplerParameterIiv(sampler: GLuint, pname: GLenum, params: #null *GLint)

    func glGetSamplerParameterIuiv(sampler: GLuint, pname: GLenum, params: #null *GLuint)

    func glGetSamplerParameterfv(sampler: GLuint, pname: GLenum, params: #null *GLfloat)

    func glGetSamplerParameteriv(sampler: GLuint, pname: GLenum, params: #null *GLint)

    func glIsSampler(sampler: GLuint)->GLboolean

    func glQueryCounter(id: GLuint, target: GLenum)

    func glSamplerParameterIiv(sampler: GLuint, pname: GLenum, param: #null const *GLint)

    func glSamplerParameterIuiv(sampler: GLuint, pname: GLenum, param: #null const *GLuint)

    func glSamplerParameterf(sampler: GLuint, pname: GLenum, param: GLfloat)

    func glSamplerParameterfv(sampler: GLuint, pname: GLenum, param: #null const *GLfloat)

    func glSamplerParameteri(sampler: GLuint, pname: GLenum, param: GLint)

    func glSamplerParameteriv(sampler: GLuint, pname: GLenum, param: #null const *GLint)

    func glVertexAttribDivisor(index: GLuint, divisor: GLuint)

    func glVertexAttribP1ui(index: GLuint, type: GLenum, normalized: GLboolean, value: GLuint)

    func glVertexAttribP1uiv(index: GLuint, type: GLenum, normalized: GLboolean, value: #null const *GLuint)

    func glVertexAttribP2ui(index: GLuint, type: GLenum, normalized: GLboolean, value: GLuint)

    func glVertexAttribP2uiv(index: GLuint, type: GLenum, normalized: GLboolean, value: #null const *GLuint)

    func glVertexAttribP3ui(index: GLuint, type: GLenum, normalized: GLboolean, value: GLuint)

    func glVertexAttribP3uiv(index: GLuint, type: GLenum, normalized: GLboolean, value: #null const *GLuint)

    func glVertexAttribP4ui(index: GLuint, type: GLenum, normalized: GLboolean, value: GLuint)

    func glVertexAttribP4uiv(index: GLuint, type: GLenum, normalized: GLboolean, value: #null const *GLuint)
}

const GL_VERTEX_ATTRIB_ARRAY_DIVISOR = 0x88FE

const GL_RGB10_A2UI = 0x906F

const GL_SRC1_COLOR = 0x88F9

const GL_ONE_MINUS_SRC1_COLOR = 0x88FA

const GL_ONE_MINUS_SRC1_ALPHA = 0x88FB

const GL_MAX_DUAL_SOURCE_DRAW_BUFFERS = 0x88FC

const GL_ANY_SAMPLES_PASSED = 0x8C2F

const GL_SAMPLER_BINDING = 0x8919

const GL_TEXTURE_SWIZZLE_R = 0x8E42

const GL_TEXTURE_SWIZZLE_G = 0x8E43

const GL_TEXTURE_SWIZZLE_B = 0x8E44

const GL_TEXTURE_SWIZZLE_A = 0x8E45

const GL_TEXTURE_SWIZZLE_RGBA = 0x8E46

const GL_TIME_ELAPSED = 0x88BF

const GL_TIMESTAMP = 0x8E28

const GL_INT_2_10_10_10_REV = 0x8D9F
