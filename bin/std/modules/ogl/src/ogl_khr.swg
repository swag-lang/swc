#global public

using Swag

/* ----------------------------- GL_KHR_debug ------------------------------ */

alias GLDEBUGPROC = func(GLenum, GLenum, GLuint, GLenum, GLsizei, #null const *GLchar, #null const *void)

const GL_CONTEXT_FLAG_DEBUG_BIT           = 0x00000002
const GL_DEBUG_OUTPUT_SYNCHRONOUS         = 0x8242
const GL_DEBUG_NEXT_LOGGED_MESSAGE_LENGTH = 0x8243
const GL_DEBUG_CALLBACK_FUNCTION          = 0x8244
const GL_DEBUG_CALLBACK_USER_PARAM        = 0x8245
const GL_DEBUG_SOURCE_API                 = 0x8246
const GL_DEBUG_SOURCE_WINDOW_SYSTEM       = 0x8247
const GL_DEBUG_SOURCE_SHADER_COMPILER     = 0x8248
const GL_DEBUG_SOURCE_THIRD_PARTY         = 0x8249
const GL_DEBUG_SOURCE_APPLICATION         = 0x824A
const GL_DEBUG_SOURCE_OTHER               = 0x824B
const GL_DEBUG_TYPE_ERROR                 = 0x824C
const GL_DEBUG_TYPE_DEPRECATED_BEHAVIOR   = 0x824D
const GL_DEBUG_TYPE_UNDEFINED_BEHAVIOR    = 0x824E
const GL_DEBUG_TYPE_PORTABILITY           = 0x824F
const GL_DEBUG_TYPE_PERFORMANCE           = 0x8250
const GL_DEBUG_TYPE_OTHER                 = 0x8251
const GL_DEBUG_TYPE_MARKER                = 0x8268
const GL_DEBUG_TYPE_PUSH_GROUP            = 0x8269
const GL_DEBUG_TYPE_POP_GROUP             = 0x826A
const GL_DEBUG_SEVERITY_NOTIFICATION      = 0x826B
const GL_MAX_DEBUG_GROUP_STACK_DEPTH      = 0x826C
const GL_DEBUG_GROUP_STACK_DEPTH          = 0x826D
const GL_BUFFER                           = 0x82E0
const GL_SHADER                           = 0x82E1
const GL_PROGRAM                          = 0x82E2
const GL_QUERY                            = 0x82E3
const GL_PROGRAM_PIPELINE                 = 0x82E4
const GL_SAMPLER                          = 0x82E6
const GL_DISPLAY_LIST                     = 0x82E7
const GL_MAX_LABEL_LENGTH                 = 0x82E8
const GL_MAX_DEBUG_MESSAGE_LENGTH         = 0x9143
const GL_MAX_DEBUG_LOGGED_MESSAGES        = 0x9144
const GL_DEBUG_LOGGED_MESSAGES            = 0x9145
const GL_DEBUG_SEVERITY_HIGH              = 0x9146
const GL_DEBUG_SEVERITY_MEDIUM            = 0x9147
const GL_DEBUG_SEVERITY_LOW               = 0x9148
const GL_DEBUG_OUTPUT                     = 0x92E0
const GL_KHR_debug                        = 1

// alias GLDEBUGPROC = func(source: GLenum, type: GLenum, id: GLuint, severity: GLenum, length: GLsizei, message: #null const *GLchar, userParam: #null const *void)

#[Extension, Swag.PlaceHolder]
{
    func glDebugMessageCallback(callback: GLDEBUGPROC, userParam: #null const *void)
    func glDebugMessageControl(source: GLenum, type: GLenum, severity: GLenum, count: GLsizei, ids: #null const *GLuint, enabled: GLboolean)
    func glDebugMessageInsert(source: GLenum, type: GLenum, id: GLuint, severity: GLenum, length: GLsizei, buf: #null const *GLchar)
    func glGetDebugMessageLog(count: GLuint, bufSize: GLsizei, sources: #null *GLenum, types: #null *GLenum, ids: #null *GLuint, severities: #null *GLenum, lengths: #null *GLsizei, messageLog: #null *GLchar)->GLuint
    func glGetObjectLabel(identifier: GLenum, name: GLuint, bufSize: GLsizei, length: #null *GLsizei, label: #null *GLchar)
    func glGetObjectPtrLabel(ptr: #null const *void, bufSize: GLsizei, length: #null *GLsizei, label: #null *GLchar)
    func glObjectLabel(identifier: GLenum, name: GLuint, length: GLsizei, label: #null const *GLchar)
    func glObjectPtrLabel(ptr: #null *void, length: GLsizei, label: #null const *GLchar)
    func glPopDebugGroup()
    func glPushDebugGroup(source: GLenum, id: GLuint, length: GLsizei, message: #null const *GLchar)
}

/* -------------------- GL_KHR_blend_equation_advanced --------------------- */

const GL_KHR_blend_equation_advanced = 1
const GL_MULTIPLY_KHR                = 0x9294
const GL_SCREEN_KHR                  = 0x9295
const GL_OVERLAY_KHR                 = 0x9296
const GL_DARKEN_KHR                  = 0x9297
const GL_LIGHTEN_KHR                 = 0x9298
const GL_COLORDODGE_KHR              = 0x9299
const GL_COLORBURN_KHR               = 0x929A
const GL_HARDLIGHT_KHR               = 0x929B
const GL_SOFTLIGHT_KHR               = 0x929C
const GL_DIFFERENCE_KHR              = 0x929E
const GL_EXCLUSION_KHR               = 0x92A0
const GL_HSL_HUE_KHR                 = 0x92AD
const GL_HSL_SATURATION_KHR          = 0x92AE
const GL_HSL_COLOR_KHR               = 0x92AF
const GL_HSL_LUMINOSITY_KHR          = 0x92B0

#[Extension, Swag.PlaceHolder]
{
    func glBlendBarrierKHR()
}

/* ---------------- GL_KHR_blend_equation_advanced_coherent ---------------- */

const GL_KHR_blend_equation_advanced_coherent = 1
const GL_BLEND_ADVANCED_COHERENT_KHR          = 0x9285

/* --------------------- GL_KHR_context_flush_control ---------------------- */

const GL_KHR_context_flush_control = 1

/* ---------------------------- GL_KHR_no_error ---------------------------- */

const GL_KHR_no_error = 1
const GL_CONTEXT_FLAG_NO_ERROR_BIT_KHR = 0x00000008

/* -------------------- GL_KHR_parallel_shader_compile --------------------- */

const GL_KHR_parallel_shader_compile     = 1
const GL_MAX_SHADER_COMPILER_THREADS_KHR = 0x91B0
const GL_COMPLETION_STATUS_KHR           = 0x91B1

#[Extension, Swag.PlaceHolder]
{
    func glMaxShaderCompilerThreadsKHR(count: GLuint)
}

/* ----------------- GL_KHR_robust_buffer_access_behavior ------------------ */

const GL_KHR_robust_buffer_access_behavior = 1

/* --------------------------- GL_KHR_robustness --------------------------- */

const GL_KHR_robustness        = 1
const GL_CONTEXT_ROBUST_ACCESS = 0x90F3

/* ------------------------ GL_KHR_shader_subgroup ------------------------- */

const GL_KHR_shader_subgroup                       = 1
const GL_SUBGROUP_SIZE_KHR                         = 0x9532
const GL_SUBGROUP_SUPPORTED_STAGES_KHR             = 0x9533
const GL_SUBGROUP_SUPPORTED_FEATURES_KHR           = 0x9534
const GL_SUBGROUP_QUAD_ALL_STAGES_KHR              = 0x9535
const GL_SUBGROUP_FEATURE_BASIC_BIT_KHR            = 0x00000001
const GL_SUBGROUP_FEATURE_VOTE_BIT_KHR             = 0x00000002
const GL_SUBGROUP_FEATURE_ARITHMETIC_BIT_KHR       = 0x00000004
const GL_SUBGROUP_FEATURE_BALLOT_BIT_KHR           = 0x00000008
const GL_SUBGROUP_FEATURE_SHUFFLE_BIT_KHR          = 0x00000010
const GL_SUBGROUP_FEATURE_SHUFFLE_RELATIVE_BIT_KHR = 0x00000020
const GL_SUBGROUP_FEATURE_CLUSTERED_BIT_KHR        = 0x00000040
const GL_SUBGROUP_FEATURE_QUAD_BIT_KHR             = 0x00000080

/* ------------------ GL_KHR_texture_compression_astc_hdr ------------------ */

const GL_KHR_texture_compression_astc_hdr       = 1
const GL_COMPRESSED_RGBA_ASTC_4x4_KHR           = 0x93B0
const GL_COMPRESSED_RGBA_ASTC_5x4_KHR           = 0x93B1
const GL_COMPRESSED_RGBA_ASTC_5x5_KHR           = 0x93B2
const GL_COMPRESSED_RGBA_ASTC_6x5_KHR           = 0x93B3
const GL_COMPRESSED_RGBA_ASTC_6x6_KHR           = 0x93B4
const GL_COMPRESSED_RGBA_ASTC_8x5_KHR           = 0x93B5
const GL_COMPRESSED_RGBA_ASTC_8x6_KHR           = 0x93B6
const GL_COMPRESSED_RGBA_ASTC_8x8_KHR           = 0x93B7
const GL_COMPRESSED_RGBA_ASTC_10x5_KHR          = 0x93B8
const GL_COMPRESSED_RGBA_ASTC_10x6_KHR          = 0x93B9
const GL_COMPRESSED_RGBA_ASTC_10x8_KHR          = 0x93BA
const GL_COMPRESSED_RGBA_ASTC_10x10_KHR         = 0x93BB
const GL_COMPRESSED_RGBA_ASTC_12x10_KHR         = 0x93BC
const GL_COMPRESSED_RGBA_ASTC_12x12_KHR         = 0x93BD
const GL_COMPRESSED_SRGB8_ALPHA8_ASTC_4x4_KHR   = 0x93D0
const GL_COMPRESSED_SRGB8_ALPHA8_ASTC_5x4_KHR   = 0x93D1
const GL_COMPRESSED_SRGB8_ALPHA8_ASTC_5x5_KHR   = 0x93D2
const GL_COMPRESSED_SRGB8_ALPHA8_ASTC_6x5_KHR   = 0x93D3
const GL_COMPRESSED_SRGB8_ALPHA8_ASTC_6x6_KHR   = 0x93D4
const GL_COMPRESSED_SRGB8_ALPHA8_ASTC_8x5_KHR   = 0x93D5
const GL_COMPRESSED_SRGB8_ALPHA8_ASTC_8x6_KHR   = 0x93D6
const GL_COMPRESSED_SRGB8_ALPHA8_ASTC_8x8_KHR   = 0x93D7
const GL_COMPRESSED_SRGB8_ALPHA8_ASTC_10x5_KHR  = 0x93D8
const GL_COMPRESSED_SRGB8_ALPHA8_ASTC_10x6_KHR  = 0x93D9
const GL_COMPRESSED_SRGB8_ALPHA8_ASTC_10x8_KHR  = 0x93DA
const GL_COMPRESSED_SRGB8_ALPHA8_ASTC_10x10_KHR = 0x93DB
const GL_COMPRESSED_SRGB8_ALPHA8_ASTC_12x10_KHR = 0x93DC
const GL_COMPRESSED_SRGB8_ALPHA8_ASTC_12x12_KHR = 0x93DD

/* ------------------ GL_KHR_texture_compression_astc_ldr ------------------ */

const GL_KHR_texture_compression_astc_ldr = 1

/* --------------- GL_KHR_texture_compression_astc_sliced_3d --------------- */

const GL_KHR_texture_compression_astc_sliced_3d = 1
