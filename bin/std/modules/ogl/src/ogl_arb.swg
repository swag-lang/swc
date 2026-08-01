#global public

using Swag

/* ----------------------------- GL_ARB_shadow ----------------------------- */

const GL_TEXTURE_COMPARE_MODE_ARB = 0x884C
const GL_TEXTURE_COMPARE_FUNC_ARB = 0x884D
const GL_COMPARE_R_TO_TEXTURE_ARB = 0x884E

/* ---------------------------- GL_ARB_imaging ----------------------------- */

const GL_CONSTANT_COLOR                      = 0x8001
const GL_ONE_MINUS_CONSTANT_COLOR            = 0x8002
const GL_CONSTANT_ALPHA                      = 0x8003
const GL_ONE_MINUS_CONSTANT_ALPHA            = 0x8004
const GL_BLEND_COLOR                         = 0x8005
const GL_FUNC_ADD                            = 0x8006
const GL_MIN                                 = 0x8007
const GL_MAX                                 = 0x8008
const GL_BLEND_EQUATION                      = 0x8009
const GL_FUNC_SUBTRACT                       = 0x800A
const GL_FUNC_REVERSE_SUBTRACT               = 0x800B
const GL_CONVOLUTION_1D                      = 0x8010
const GL_CONVOLUTION_2D                      = 0x8011
const GL_SEPARABLE_2D                        = 0x8012
const GL_CONVOLUTION_BORDER_MODE             = 0x8013
const GL_CONVOLUTION_FILTER_SCALE            = 0x8014
const GL_CONVOLUTION_FILTER_BIAS             = 0x8015
const GL_REDUCE                              = 0x8016
const GL_CONVOLUTION_FORMAT                  = 0x8017
const GL_CONVOLUTION_WIDTH                   = 0x8018
const GL_CONVOLUTION_HEIGHT                  = 0x8019
const GL_MAX_CONVOLUTION_WIDTH               = 0x801A
const GL_MAX_CONVOLUTION_HEIGHT              = 0x801B
const GL_POST_CONVOLUTION_RED_SCALE          = 0x801C
const GL_POST_CONVOLUTION_GREEN_SCALE        = 0x801D
const GL_POST_CONVOLUTION_BLUE_SCALE         = 0x801E
const GL_POST_CONVOLUTION_ALPHA_SCALE        = 0x801F
const GL_POST_CONVOLUTION_RED_BIAS           = 0x8020
const GL_POST_CONVOLUTION_GREEN_BIAS         = 0x8021
const GL_POST_CONVOLUTION_BLUE_BIAS          = 0x8022
const GL_POST_CONVOLUTION_ALPHA_BIAS         = 0x8023
const GL_HISTOGRAM                           = 0x8024
const GL_PROXY_HISTOGRAM                     = 0x8025
const GL_HISTOGRAM_WIDTH                     = 0x8026
const GL_HISTOGRAM_FORMAT                    = 0x8027
const GL_HISTOGRAM_RED_SIZE                  = 0x8028
const GL_HISTOGRAM_GREEN_SIZE                = 0x8029
const GL_HISTOGRAM_BLUE_SIZE                 = 0x802A
const GL_HISTOGRAM_ALPHA_SIZE                = 0x802B
const GL_HISTOGRAM_LUMINANCE_SIZE            = 0x802C
const GL_HISTOGRAM_SINK                      = 0x802D
const GL_MINMAX                              = 0x802E
const GL_MINMAX_FORMAT                       = 0x802F
const GL_MINMAX_SINK                         = 0x8030
const GL_TABLE_TOO_LARGE                     = 0x8031
const GL_COLOR_MATRIX                        = 0x80B1
const GL_COLOR_MATRIX_STACK_DEPTH            = 0x80B2
const GL_MAX_COLOR_MATRIX_STACK_DEPTH        = 0x80B3
const GL_POST_COLOR_MATRIX_RED_SCALE         = 0x80B4
const GL_POST_COLOR_MATRIX_GREEN_SCALE       = 0x80B5
const GL_POST_COLOR_MATRIX_BLUE_SCALE        = 0x80B6
const GL_POST_COLOR_MATRIX_ALPHA_SCALE       = 0x80B7
const GL_POST_COLOR_MATRIX_RED_BIAS          = 0x80B8
const GL_POST_COLOR_MATRIX_GREEN_BIAS        = 0x80B9
const GL_POST_COLOR_MATRIX_BLUE_BIAS         = 0x80BA
const GL_POST_COLOR_MATRIX_ALPHA_BIAS        = 0x80BB
const GL_COLOR_TABLE                         = 0x80D0
const GL_POST_CONVOLUTION_COLOR_TABLE        = 0x80D1
const GL_POST_COLOR_MATRIX_COLOR_TABLE       = 0x80D2
const GL_PROXY_COLOR_TABLE                   = 0x80D3
const GL_PROXY_POST_CONVOLUTION_COLOR_TABLE  = 0x80D4
const GL_PROXY_POST_COLOR_MATRIX_COLOR_TABLE = 0x80D5
const GL_COLOR_TABLE_SCALE                   = 0x80D6
const GL_COLOR_TABLE_BIAS                    = 0x80D7
const GL_COLOR_TABLE_FORMAT                  = 0x80D8
const GL_COLOR_TABLE_WIDTH                   = 0x80D9
const GL_COLOR_TABLE_RED_SIZE                = 0x80DA
const GL_COLOR_TABLE_GREEN_SIZE              = 0x80DB
const GL_COLOR_TABLE_BLUE_SIZE               = 0x80DC
const GL_COLOR_TABLE_ALPHA_SIZE              = 0x80DD
const GL_COLOR_TABLE_LUMINANCE_SIZE          = 0x80DE
const GL_COLOR_TABLE_INTENSITY_SIZE          = 0x80DF
const GL_IGNORE_BORDER                       = 0x8150
const GL_CONSTANT_BORDER                     = 0x8151
const GL_WRAP_BORDER                         = 0x8152
const GL_REPLICATE_BORDER                    = 0x8153
const GL_CONVOLUTION_BORDER_COLOR            = 0x8154
const GL_ARB_imaging                         = 1

/* ------------------- GL_ARB_framebuffer_no_attachments ------------------- */

const GL_FRAMEBUFFER_DEFAULT_WIDTH                  = 0x9310
const GL_FRAMEBUFFER_DEFAULT_HEIGHT                 = 0x9311
const GL_FRAMEBUFFER_DEFAULT_LAYERS                 = 0x9312
const GL_FRAMEBUFFER_DEFAULT_SAMPLES                = 0x9313
const GL_FRAMEBUFFER_DEFAULT_FIXED_SAMPLE_LOCATIONS = 0x9314
const GL_MAX_FRAMEBUFFER_WIDTH                      = 0x9315
const GL_MAX_FRAMEBUFFER_HEIGHT                     = 0x9316
const GL_MAX_FRAMEBUFFER_LAYERS                     = 0x9317
const GL_MAX_FRAMEBUFFER_SAMPLES                    = 0x9318
const GL_ARB_framebuffer_no_attachments             = 1

#[Extension, Swag.PlaceHolder]
{
    func glFramebufferParameteri(target: GLenum, pname: GLenum, param: GLint)
    func glGetFramebufferParameteriv(target: GLenum, pname: GLenum, params: #null *GLint)
    func glGetNamedFramebufferParameterivEXT(framebuffer: GLuint, pname: GLenum, params: #null *GLint)
    func glNamedFramebufferParameteriEXT(framebuffer: GLuint, pname: GLenum, param: GLint)
}

/* ----------------------- GL_ARB_framebuffer_object ----------------------- */

const GL_INVALID_FRAMEBUFFER_OPERATION                = 0x0506
const GL_FRAMEBUFFER_ATTACHMENT_COLOR_ENCODING        = 0x8210
const GL_FRAMEBUFFER_ATTACHMENT_COMPONENT_TYPE        = 0x8211
const GL_FRAMEBUFFER_ATTACHMENT_RED_SIZE              = 0x8212
const GL_FRAMEBUFFER_ATTACHMENT_GREEN_SIZE            = 0x8213
const GL_FRAMEBUFFER_ATTACHMENT_BLUE_SIZE             = 0x8214
const GL_FRAMEBUFFER_ATTACHMENT_ALPHA_SIZE            = 0x8215
const GL_FRAMEBUFFER_ATTACHMENT_DEPTH_SIZE            = 0x8216
const GL_FRAMEBUFFER_ATTACHMENT_STENCIL_SIZE          = 0x8217
const GL_FRAMEBUFFER_DEFAULT                          = 0x8218
const GL_FRAMEBUFFER_UNDEFINED                        = 0x8219
const GL_DEPTH_STENCIL_ATTACHMENT                     = 0x821A
const GL_INDEX                                        = 0x8222
const GL_MAX_RENDERBUFFER_SIZE                        = 0x84E8
const GL_DEPTH_STENCIL                                = 0x84F9
const GL_UNSIGNED_INT_24_8                            = 0x84FA
const GL_DEPTH24_STENCIL8                             = 0x88F0
const GL_TEXTURE_STENCIL_SIZE                         = 0x88F1
const GL_UNSIGNED_NORMALIZED                          = 0x8C17
const GL_DRAW_FRAMEBUFFER_BINDING                     = 0x8CA6
const GL_FRAMEBUFFER_BINDING                          = 0x8CA6
const GL_RENDERBUFFER_BINDING                         = 0x8CA7
const GL_READ_FRAMEBUFFER                             = 0x8CA8
const GL_DRAW_FRAMEBUFFER                             = 0x8CA9
const GL_READ_FRAMEBUFFER_BINDING                     = 0x8CAA
const GL_RENDERBUFFER_SAMPLES                         = 0x8CAB
const GL_FRAMEBUFFER_ATTACHMENT_OBJECT_TYPE           = 0x8CD0
const GL_FRAMEBUFFER_ATTACHMENT_OBJECT_NAME           = 0x8CD1
const GL_FRAMEBUFFER_ATTACHMENT_TEXTURE_LEVEL         = 0x8CD2
const GL_FRAMEBUFFER_ATTACHMENT_TEXTURE_CUBE_MAP_FACE = 0x8CD3
const GL_FRAMEBUFFER_ATTACHMENT_TEXTURE_LAYER         = 0x8CD4
const GL_FRAMEBUFFER_COMPLETE                         = 0x8CD5
const GL_FRAMEBUFFER_INCOMPLETE_ATTACHMENT            = 0x8CD6
const GL_FRAMEBUFFER_INCOMPLETE_MISSING_ATTACHMENT    = 0x8CD7
const GL_FRAMEBUFFER_INCOMPLETE_DRAW_BUFFER           = 0x8CDB
const GL_FRAMEBUFFER_INCOMPLETE_READ_BUFFER           = 0x8CDC
const GL_FRAMEBUFFER_UNSUPPORTED                      = 0x8CDD
const GL_MAX_COLOR_ATTACHMENTS                        = 0x8CDF
const GL_COLOR_ATTACHMENT0                            = 0x8CE0
const GL_COLOR_ATTACHMENT1                            = 0x8CE1
const GL_COLOR_ATTACHMENT2                            = 0x8CE2
const GL_COLOR_ATTACHMENT3                            = 0x8CE3
const GL_COLOR_ATTACHMENT4                            = 0x8CE4
const GL_COLOR_ATTACHMENT5                            = 0x8CE5
const GL_COLOR_ATTACHMENT6                            = 0x8CE6
const GL_COLOR_ATTACHMENT7                            = 0x8CE7
const GL_COLOR_ATTACHMENT8                            = 0x8CE8
const GL_COLOR_ATTACHMENT9                            = 0x8CE9
const GL_COLOR_ATTACHMENT10                           = 0x8CEA
const GL_COLOR_ATTACHMENT11                           = 0x8CEB
const GL_COLOR_ATTACHMENT12                           = 0x8CEC
const GL_COLOR_ATTACHMENT13                           = 0x8CED
const GL_COLOR_ATTACHMENT14                           = 0x8CEE
const GL_COLOR_ATTACHMENT15                           = 0x8CEF
const GL_DEPTH_ATTACHMENT                             = 0x8D00
const GL_STENCIL_ATTACHMENT                           = 0x8D20
const GL_FRAMEBUFFER                                  = 0x8D40
const GL_RENDERBUFFER                                 = 0x8D41
const GL_RENDERBUFFER_WIDTH                           = 0x8D42
const GL_RENDERBUFFER_HEIGHT                          = 0x8D43
const GL_RENDERBUFFER_INTERNAL_FORMAT                 = 0x8D44
const GL_STENCIL_INDEX1                               = 0x8D46
const GL_STENCIL_INDEX4                               = 0x8D47
const GL_STENCIL_INDEX8                               = 0x8D48
const GL_STENCIL_INDEX16                              = 0x8D49
const GL_RENDERBUFFER_RED_SIZE                        = 0x8D50
const GL_RENDERBUFFER_GREEN_SIZE                      = 0x8D51
const GL_RENDERBUFFER_BLUE_SIZE                       = 0x8D52
const GL_RENDERBUFFER_ALPHA_SIZE                      = 0x8D53
const GL_RENDERBUFFER_DEPTH_SIZE                      = 0x8D54
const GL_RENDERBUFFER_STENCIL_SIZE                    = 0x8D55
const GL_FRAMEBUFFER_INCOMPLETE_MULTISAMPLE           = 0x8D56
const GL_MAX_SAMPLES                                  = 0x8D57
const GL_ARB_framebuffer_object                       = 1

#[Extension, Swag.PlaceHolder]
{
    func glBindFramebuffer(target: GLenum, framebuffer: GLuint)
    func glBindRenderbuffer(target: GLenum, renderbuffer: GLuint)
    func glBlitFramebuffer(srcX0: GLint, srcY0: GLint, srcX1: GLint, srcY1: GLint, dstX0: GLint, dstY0: GLint, dstX1: GLint, dstY1: GLint, mask: GLbitfield, filter: GLenum)
    func glCheckFramebufferStatus(target: GLenum)->GLenum
    func glDeleteFramebuffers(n: GLsizei, framebuffers: #null const *GLuint)
    func glDeleteRenderbuffers(n: GLsizei, renderbuffers: #null const *GLuint)
    func glFramebufferRenderbuffer(target: GLenum, attachment: GLenum, renderbuffertarget: GLenum, renderbuffer: GLuint)
    func glFramebufferTexture1D(target: GLenum, attachment: GLenum, textarget: GLenum, texture: GLuint, level: GLint)
    func glFramebufferTexture2D(target: GLenum, attachment: GLenum, textarget: GLenum, texture: GLuint, level: GLint)
    func glFramebufferTexture3D(target: GLenum, attachment: GLenum, textarget: GLenum, texture: GLuint, level: GLint, layer: GLint)
    func glFramebufferTextureLayer(target: GLenum, attachment: GLenum, texture: GLuint, level: GLint, layer: GLint)
    func glGenFramebuffers(n: GLsizei, framebuffers: #null *GLuint)
    func glGenRenderbuffers(n: GLsizei, renderbuffers: #null *GLuint)
    func glGenerateMipmap(target: GLenum)
    func glGetFramebufferAttachmentParameteriv(target: GLenum, attachment: GLenum, pname: GLenum, params: #null *GLint)
    func glGetRenderbufferParameteriv(target: GLenum, pname: GLenum, params: #null *GLint)
    func glIsFramebuffer(framebuffer: GLuint)->GLboolean
    func glIsRenderbuffer(renderbuffer: GLuint)->GLboolean
    func glRenderbufferStorage(target: GLenum, internalformat: GLenum, width: GLsizei, height: GLsizei)
    func glRenderbufferStorageMultisample(target: GLenum, samples: GLsizei, internalformat: GLenum, width: GLsizei, height: GLsizei)
}

/* ------------------------ GL_ARB_framebuffer_sRGB ------------------------ */

const GL_ARB_framebuffer_sRGB = 1

/* -------------------- GL_ARB_shading_language_include -------------------- */

const GL_SHADER_INCLUDE_ARB           = 0x8DAE
const GL_NAMED_STRING_LENGTH_ARB      = 0x8DE9
const GL_NAMED_STRING_TYPE_ARB        = 0x8DEA
const GL_FRAMEBUFFER_SRGB             = 0x8DB9
const GL_ARB_shading_language_include = 1

#[Extension, Swag.PlaceHolder]
{
    func glCompileShaderIncludeARB(shader: GLuint, count: GLsizei, path: #null const *#null *GLchar, length: #null const *GLint)
    func glDeleteNamedStringARB(namelen: GLint, name: #null const *GLchar)
    func glGetNamedStringARB(namelen: GLint, name: #null const *GLchar, bufSize: GLsizei, stringlen: #null *GLint, str: #null *GLchar)
    func glGetNamedStringivARB(namelen: GLint, name: #null const *GLchar, pname: GLenum, params: #null *GLint)
    func glIsNamedStringARB(namelen: GLint, name: #null const *GLchar)->GLboolean
    func glNamedStringARB(type: GLenum, namelen: GLint, name: #null const *GLchar, stringlen: GLint, str: #null const *GLchar)
}

/* ----------------------- GL_ARB_ES2_compatibility ------------------------ */

const GL_ARB_ES2_compatibility = 1

/* ---------------------- GL_ARB_ES3_1_compatibility ----------------------- */

const GL_ARB_ES3_1_compatibility = 1

/* ---------------------- GL_ARB_ES3_2_compatibility ----------------------- */

const GL_ARB_ES3_2_compatibility                = 1
const GL_PRIMITIVE_BOUNDING_BOX_ARB             = 0x92BE
const GL_MULTISAMPLE_LINE_WIDTH_RANGE_ARB       = 0x9381
const GL_MULTISAMPLE_LINE_WIDTH_GRANULARITY_ARB = 0x9382

#[Extension, Swag.PlaceHolder]
{
    func glPrimitiveBoundingBoxARB(minX: GLfloat, minY: GLfloat, minZ: GLfloat, minW: GLfloat, maxX: GLfloat, maxY: GLfloat, maxZ: GLfloat, maxW: GLfloat)
}

/* ----------------------- GL_ARB_ES3_compatibility ------------------------ */

const GL_ARB_ES3_compatibility = 1

/* ------------------------ GL_ARB_arrays_of_arrays ------------------------ */

const GL_ARB_arrays_of_arrays = 1

/* ------------------------- GL_ARB_base_instance -------------------------- */

const GL_ARB_base_instance = 1

/* ------------------------ GL_ARB_bindless_texture ------------------------ */

alias GLuint64EXT = u64

const GL_ARB_bindless_texture = 1
const GL_UNSIGNED_INT64_ARB   = 0x140F

#[Extension, Swag.PlaceHolder]
{
    func glGetImageHandleARB(texture: GLuint, level: GLint, layered: GLboolean, layer: GLint, format: GLenum)->GLuint64
    func glGetTextureHandleARB(texture: GLuint)->GLuint64
    func glGetTextureSamplerHandleARB(texture: GLuint, sampler: GLuint)->GLuint64
    func glGetVertexAttribLui64vARB(index: GLuint, pname: GLenum, params: #null *GLuint64EXT)
    func glIsImageHandleResidentARB(handle: GLuint64)->GLboolean
    func glIsTextureHandleResidentARB(handle: GLuint64)->GLboolean
    func glMakeImageHandleNonResidentARB(handle: GLuint64)
    func glMakeImageHandleResidentARB(handle: GLuint64, access: GLenum)
    func glMakeTextureHandleNonResidentARB(handle: GLuint64)
    func glMakeTextureHandleResidentARB(handle: GLuint64)
    func glProgramUniformHandleui64ARB(program: GLuint, location: GLint, value: GLuint64)
    func glProgramUniformHandleui64vARB(program: GLuint, location: GLint, count: GLsizei, values: #null const *GLuint64)
    func glUniformHandleui64ARB(location: GLint, value: GLuint64)
    func glUniformHandleui64vARB(location: GLint, count: GLsizei, value: #null const *GLuint64)
    func glVertexAttribL1ui64ARB(index: GLuint, x: GLuint64EXT)
    func glVertexAttribL1ui64vARB(index: GLuint, v: #null const *GLuint64EXT)
}

/* ---------------------- GL_ARB_blend_func_extended ----------------------- */

const GL_ARB_blend_func_extended = 1

/* ------------------------- GL_ARB_buffer_storage ------------------------- */

const GL_ARB_buffer_storage = 1

/* ---------------------------- GL_ARB_cl_event ---------------------------- */

alias GLclContext = #null *void
alias GLclEvent   = #null *void

const GL_ARB_cl_event               = 1
const GL_SYNC_CL_EVENT_ARB          = 0x8240
const GL_SYNC_CL_EVENT_COMPLETE_ARB = 0x8241

#[Extension, Swag.PlaceHolder]
{
    func glCreateSyncFromCLeventARB(context: #null *GLclContext, event: #null *GLclEvent, flags: GLbitfield)->GLsync
}

/* ---------------------- GL_ARB_clear_buffer_object ----------------------- */

const GL_ARB_clear_buffer_object = 1

/* ------------------------- GL_ARB_clear_texture -------------------------- */

const GL_ARB_clear_texture = 1

/* -------------------------- GL_ARB_clip_control -------------------------- */

const GL_ARB_clip_control = 1

/* ---------------- GL_ARB_compressed_texture_pixel_storage ---------------- */

const GL_ARB_compressed_texture_pixel_storage = 1

/* ------------------------- GL_ARB_compute_shader ------------------------- */

const GL_ARB_compute_shader = 1

/* ------------------ GL_ARB_compute_variable_group_size ------------------- */

const GL_ARB_compute_variable_group_size            = 1
const GL_MAX_COMPUTE_VARIABLE_GROUP_INVOCATIONS_ARB = 0x9344
const GL_MAX_COMPUTE_FIXED_GROUP_INVOCATIONS_ARB    = 0x90EB
const GL_MAX_COMPUTE_VARIABLE_GROUP_SIZE_ARB        = 0x9345
const GL_MAX_COMPUTE_FIXED_GROUP_SIZE_ARB           = 0x91BF

#[Extension, Swag.PlaceHolder]
{
    func glDispatchComputeGroupSizeARB(num_groups_x: GLuint, num_groups_y: GLuint, num_groups_z: GLuint, group_size_x: GLuint, group_size_y: GLuint, group_size_z: GLuint)
}

/* ------------------ GL_ARB_conditional_render_inverted ------------------- */

const GL_ARB_conditional_render_inverted = 1

/* ----------------------- GL_ARB_conservative_depth ----------------------- */

const GL_ARB_conservative_depth = 1

/* -------------------------- GL_ARB_copy_buffer --------------------------- */

const GL_ARB_copy_buffer = 1

/* --------------------------- GL_ARB_copy_image --------------------------- */

const GL_ARB_copy_image = 1

/* ------------------------- GL_ARB_cull_distance -------------------------- */

const GL_ARB_cull_distance = 1

/* -------------------------- GL_ARB_debug_output -------------------------- */

alias GLDEBUGPROCARB = func(GLenum, GLenum, GLuint, GLenum, GLsizei, #null const *GLchar, #null const *void)

const GL_ARB_debug_output                     = 1
const GL_DEBUG_OUTPUT_SYNCHRONOUS_ARB         = 0x8242
const GL_DEBUG_NEXT_LOGGED_MESSAGE_LENGTH_ARB = 0x8243
const GL_DEBUG_CALLBACK_FUNCTION_ARB          = 0x8244
const GL_DEBUG_CALLBACK_USER_PARAM_ARB        = 0x8245
const GL_DEBUG_SOURCE_API_ARB                 = 0x8246
const GL_DEBUG_SOURCE_WINDOW_SYSTEM_ARB       = 0x8247
const GL_DEBUG_SOURCE_SHADER_COMPILER_ARB     = 0x8248
const GL_DEBUG_SOURCE_THIRD_PARTY_ARB         = 0x8249
const GL_DEBUG_SOURCE_APPLICATION_ARB         = 0x824A
const GL_DEBUG_SOURCE_OTHER_ARB               = 0x824B
const GL_DEBUG_TYPE_ERROR_ARB                 = 0x824C
const GL_DEBUG_TYPE_DEPRECATED_BEHAVIOR_ARB   = 0x824D
const GL_DEBUG_TYPE_UNDEFINED_BEHAVIOR_ARB    = 0x824E
const GL_DEBUG_TYPE_PORTABILITY_ARB           = 0x824F
const GL_DEBUG_TYPE_PERFORMANCE_ARB           = 0x8250
const GL_DEBUG_TYPE_OTHER_ARB                 = 0x8251
const GL_MAX_DEBUG_MESSAGE_LENGTH_ARB         = 0x9143
const GL_MAX_DEBUG_LOGGED_MESSAGES_ARB        = 0x9144
const GL_DEBUG_LOGGED_MESSAGES_ARB            = 0x9145
const GL_DEBUG_SEVERITY_HIGH_ARB              = 0x9146
const GL_DEBUG_SEVERITY_MEDIUM_ARB            = 0x9147
const GL_DEBUG_SEVERITY_LOW_ARB               = 0x9148

#[Extension, Swag.PlaceHolder]
{
    func glDebugMessageCallbackARB(callback: GLDEBUGPROCARB, userParam: #null const *void)
    func glDebugMessageControlARB(source: GLenum, type: GLenum, severity: GLenum, count: GLsizei, ids: #null const *GLuint, enabled: GLboolean)
    func glDebugMessageInsertARB(source: GLenum, type: GLenum, id: GLuint, severity: GLenum, length: GLsizei, buf: #null const *GLchar)
    func glGetDebugMessageLogARB(count: GLuint, bufSize: GLsizei, sources: #null *GLenum, types: #null *GLenum, ids: #null *GLuint, severities: #null *GLenum, lengths: #null *GLsizei, messageLog: #null *GLchar)->GLuint
}

/* ----------------------- GL_ARB_depth_buffer_float ----------------------- */

const GL_ARB_depth_buffer_float = 1

/* -------------------------- GL_ARB_depth_clamp --------------------------- */

const GL_ARB_depth_clamp = 1

/* ----------------------- GL_ARB_derivative_control ----------------------- */

const GL_ARB_derivative_control = 1

/* ---------------------- GL_ARB_direct_state_access ----------------------- */

const GL_ARB_direct_state_access = 1

/* ----------------------- GL_ARB_draw_buffers_blend ----------------------- */

const GL_ARB_draw_buffers_blend = 1

#[Extension, Swag.PlaceHolder]
{
    func glBlendEquationSeparateiARB(buf: GLuint, modeRGB: GLenum, modeAlpha: GLenum)
    func glBlendEquationiARB(buf: GLuint, mode: GLenum)
    func glBlendFuncSeparateiARB(buf: GLuint, srcRGB: GLenum, dstRGB: GLenum, srcAlpha: GLenum, dstAlpha: GLenum)
    func glBlendFunciARB(buf: GLuint, src: GLenum, dst: GLenum)
}

/* ------------------- GL_ARB_draw_elements_base_vertex -------------------- */

const GL_ARB_draw_elements_base_vertex = 1

/* ------------------------- GL_ARB_draw_indirect -------------------------- */

const GL_ARB_draw_indirect = 1

/* ------------------------- GL_ARB_draw_instanced ------------------------- */

const GL_ARB_draw_instanced = 1

#[Extension, Swag.PlaceHolder]
{
    func glDrawArraysInstancedARB(mode: GLenum, first: GLint, count: GLsizei, primcount: GLsizei)
    func glDrawElementsInstancedARB(mode: GLenum, count: GLsizei, type: GLenum, indices: #null const *void, primcount: GLsizei)
}

/* ------------------------ GL_ARB_enhanced_layouts ------------------------ */

const GL_ARB_enhanced_layouts = 1

/* -------------------- GL_ARB_explicit_attrib_location -------------------- */

const GL_ARB_explicit_attrib_location = 1

/* ------------------- GL_ARB_explicit_uniform_location -------------------- */

const GL_ARB_explicit_uniform_location = 1

/* ------------------- GL_ARB_fragment_coord_conventions ------------------- */

const GL_ARB_fragment_coord_conventions = 1

/* -------------------- GL_ARB_fragment_layer_viewport --------------------- */

const GL_ARB_fragment_layer_viewport = 1

/* ------------------- GL_ARB_fragment_shader_interlock -------------------- */

const GL_ARB_fragment_shader_interlock = 1

/* ------------------------ GL_ARB_geometry_shader4 ------------------------ */

const GL_ARB_geometry_shader4                     = 1
const GL_LINES_ADJACENCY_ARB                      = 0x000A
const GL_LINE_STRIP_ADJACENCY_ARB                 = 0x000B
const GL_TRIANGLES_ADJACENCY_ARB                  = 0x000C
const GL_TRIANGLE_STRIP_ADJACENCY_ARB             = 0x000D
const GL_PROGRAM_POINT_SIZE_ARB                   = 0x8642
const GL_MAX_GEOMETRY_TEXTURE_IMAGE_UNITS_ARB     = 0x8C29
const GL_FRAMEBUFFER_ATTACHMENT_LAYERED_ARB       = 0x8DA7
const GL_FRAMEBUFFER_INCOMPLETE_LAYER_TARGETS_ARB = 0x8DA8
const GL_FRAMEBUFFER_INCOMPLETE_LAYER_COUNT_ARB   = 0x8DA9
const GL_GEOMETRY_SHADER_ARB                      = 0x8DD9
const GL_GEOMETRY_VERTICES_OUT_ARB                = 0x8DDA
const GL_GEOMETRY_INPUT_TYPE_ARB                  = 0x8DDB
const GL_GEOMETRY_OUTPUT_TYPE_ARB                 = 0x8DDC
const GL_MAX_GEOMETRY_VARYING_COMPONENTS_ARB      = 0x8DDD
const GL_MAX_VERTEX_VARYING_COMPONENTS_ARB        = 0x8DDE
const GL_MAX_GEOMETRY_UNIFORM_COMPONENTS_ARB      = 0x8DDF
const GL_MAX_GEOMETRY_OUTPUT_VERTICES_ARB         = 0x8DE0
const GL_MAX_GEOMETRY_TOTAL_OUTPUT_COMPONENTS_ARB = 0x8DE1

#[Extension, Swag.PlaceHolder]
{
    func glFramebufferTextureARB(target: GLenum, attachment: GLenum, texture: GLuint, level: GLint)
    func glFramebufferTextureFaceARB(target: GLenum, attachment: GLenum, texture: GLuint, level: GLint, face: GLenum)
    func glFramebufferTextureLayerARB(target: GLenum, attachment: GLenum, texture: GLuint, level: GLint, layer: GLint)
    func glProgramParameteriARB(program: GLuint, pname: GLenum, value: GLint)
}

/* ----------------------- GL_ARB_get_program_binary ----------------------- */

const GL_ARB_get_program_binary = 1

/* --------------------- GL_ARB_get_texture_sub_image ---------------------- */

const GL_ARB_get_texture_sub_image = 1

/* ---------------------------- GL_ARB_gl_spirv ---------------------------- */

const GL_ARB_gl_spirv                    = 1
const GL_SHADER_BINARY_FORMAT_SPIR_V_ARB = 0x9551
const GL_SPIR_V_BINARY_ARB               = 0x9552

#[Extension, Swag.PlaceHolder]
{
    func glSpecializeShaderARB(shader: GLuint, pEntryPoint: #null const *GLchar, numSpecializationConstants: GLuint, pConstantIndex: #null const *GLuint, pConstantValue: #null const *GLuint)
}

/* -------------------------- GL_ARB_gpu_shader5 --------------------------- */

const GL_ARB_gpu_shader5 = 1

/* ------------------------ GL_ARB_gpu_shader_fp64 ------------------------- */

const GL_ARB_gpu_shader_fp64 = 1

/* ------------------------ GL_ARB_gpu_shader_int64 ------------------------ */

const GL_ARB_gpu_shader_int64    = 1
const GL_INT64_ARB               = 0x140E
const GL_INT64_VEC2_ARB          = 0x8FE9
const GL_INT64_VEC3_ARB          = 0x8FEA
const GL_INT64_VEC4_ARB          = 0x8FEB
const GL_UNSIGNED_INT64_VEC2_ARB = 0x8FF5
const GL_UNSIGNED_INT64_VEC3_ARB = 0x8FF6
const GL_UNSIGNED_INT64_VEC4_ARB = 0x8FF7

#[Extension, Swag.PlaceHolder]
{
    func glGetUniformi64vARB(program: GLuint, location: GLint, params: #null *GLint64)
    func glGetUniformui64vARB(program: GLuint, location: GLint, params: #null *GLuint64)
    func glGetnUniformi64vARB(program: GLuint, location: GLint, bufSize: GLsizei, params: #null *GLint64)
    func glGetnUniformui64vARB(program: GLuint, location: GLint, bufSize: GLsizei, params: #null *GLuint64)
    func glProgramUniform1i64ARB(program: GLuint, location: GLint, x: GLint64)
    func glProgramUniform1i64vARB(program: GLuint, location: GLint, count: GLsizei, value: #null const *GLint64)
    func glProgramUniform1ui64ARB(program: GLuint, location: GLint, x: GLuint64)
    func glProgramUniform1ui64vARB(program: GLuint, location: GLint, count: GLsizei, value: #null const *GLuint64)
    func glProgramUniform2i64ARB(program: GLuint, location: GLint, x: GLint64, y: GLint64)
    func glProgramUniform2i64vARB(program: GLuint, location: GLint, count: GLsizei, value: #null const *GLint64)
    func glProgramUniform2ui64ARB(program: GLuint, location: GLint, x: GLuint64, y: GLuint64)
    func glProgramUniform2ui64vARB(program: GLuint, location: GLint, count: GLsizei, value: #null const *GLuint64)
    func glProgramUniform3i64ARB(program: GLuint, location: GLint, x: GLint64, y: GLint64, z: GLint64)
    func glProgramUniform3i64vARB(program: GLuint, location: GLint, count: GLsizei, value: #null const *GLint64)
    func glProgramUniform3ui64ARB(program: GLuint, location: GLint, x: GLuint64, y: GLuint64, z: GLuint64)
    func glProgramUniform3ui64vARB(program: GLuint, location: GLint, count: GLsizei, value: #null const *GLuint64)
    func glProgramUniform4i64ARB(program: GLuint, location: GLint, x: GLint64, y: GLint64, z: GLint64, w: GLint64)
    func glProgramUniform4i64vARB(program: GLuint, location: GLint, count: GLsizei, value: #null const *GLint64)
    func glProgramUniform4ui64ARB(program: GLuint, location: GLint, x: GLuint64, y: GLuint64, z: GLuint64, w: GLuint64)
    func glProgramUniform4ui64vARB(program: GLuint, location: GLint, count: GLsizei, value: #null const *GLuint64)
    func glUniform1i64ARB(location: GLint, x: GLint64)
    func glUniform1i64vARB(location: GLint, count: GLsizei, value: #null const *GLint64)
    func glUniform1ui64ARB(location: GLint, x: GLuint64)
    func glUniform1ui64vARB(location: GLint, count: GLsizei, value: #null const *GLuint64)
    func glUniform2i64ARB(location: GLint, x: GLint64, y: GLint64)
    func glUniform2i64vARB(location: GLint, count: GLsizei, value: #null const *GLint64)
    func glUniform2ui64ARB(location: GLint, x: GLuint64, y: GLuint64)
    func glUniform2ui64vARB(location: GLint, count: GLsizei, value: #null const *GLuint64)
    func glUniform3i64ARB(location: GLint, x: GLint64, y: GLint64, z: GLint64)
    func glUniform3i64vARB(location: GLint, count: GLsizei, value: #null const *GLint64)
    func glUniform3ui64ARB(location: GLint, x: GLuint64, y: GLuint64, z: GLuint64)
    func glUniform3ui64vARB(location: GLint, count: GLsizei, value: #null const *GLuint64)
    func glUniform4i64ARB(location: GLint, x: GLint64, y: GLint64, z: GLint64, w: GLint64)
    func glUniform4i64vARB(location: GLint, count: GLsizei, value: #null const *GLint64)
    func glUniform4ui64ARB(location: GLint, x: GLuint64, y: GLuint64, z: GLuint64, w: GLuint64)
    func glUniform4ui64vARB(location: GLint, count: GLsizei, value: #null const *GLuint64)
}

/* ----------------------- GL_ARB_half_float_vertex ------------------------ */

const GL_ARB_half_float_vertex = 1

/* ---------------------- GL_ARB_indirect_parameters ----------------------- */

const GL_ARB_indirect_parameters      = 1
const GL_PARAMETER_BUFFER_ARB         = 0x80EE
const GL_PARAMETER_BUFFER_BINDING_ARB = 0x80EF

#[Extension, Swag.PlaceHolder]
{
    func glMultiDrawArraysIndirectCountARB(mode: GLenum, indirect: #null const *void, drawcount: GLintptr, maxdrawcount: GLsizei, stride: GLsizei)
    func glMultiDrawElementsIndirectCountARB(mode: GLenum, type: GLenum, indirect: #null const *void, drawcount: GLintptr, maxdrawcount: GLsizei, stride: GLsizei)
}

/* ------------------------ GL_ARB_instanced_arrays ------------------------ */

const GL_ARB_instanced_arrays            = 1
const GL_VERTEX_ATTRIB_ARRAY_DIVISOR_ARB = 0x88FE

#[Extension, Swag.PlaceHolder]
{
    func glVertexAttribDivisorARB(index: GLuint, divisor: GLuint)
}

/* ---------------------- GL_ARB_internalformat_query ---------------------- */

const GL_ARB_internalformat_query = 1

/* --------------------- GL_ARB_internalformat_query2 ---------------------- */

const GL_ARB_internalformat_query2  = 1
const GL_SRGB_DECODE_ARB            = 0x8299
const GL_VIEW_CLASS_EAC_R11         = 0x9383
const GL_VIEW_CLASS_EAC_RG11        = 0x9384
const GL_VIEW_CLASS_ETC2_RGB        = 0x9385
const GL_VIEW_CLASS_ETC2_RGBA       = 0x9386
const GL_VIEW_CLASS_ETC2_EAC_RGBA   = 0x9387
const GL_VIEW_CLASS_ASTC_4x4_RGBA   = 0x9388
const GL_VIEW_CLASS_ASTC_5x4_RGBA   = 0x9389
const GL_VIEW_CLASS_ASTC_5x5_RGBA   = 0x938A
const GL_VIEW_CLASS_ASTC_6x5_RGBA   = 0x938B
const GL_VIEW_CLASS_ASTC_6x6_RGBA   = 0x938C
const GL_VIEW_CLASS_ASTC_8x5_RGBA   = 0x938D
const GL_VIEW_CLASS_ASTC_8x6_RGBA   = 0x938E
const GL_VIEW_CLASS_ASTC_8x8_RGBA   = 0x938F
const GL_VIEW_CLASS_ASTC_10x5_RGBA  = 0x9390
const GL_VIEW_CLASS_ASTC_10x6_RGBA  = 0x9391
const GL_VIEW_CLASS_ASTC_10x8_RGBA  = 0x9392
const GL_VIEW_CLASS_ASTC_10x10_RGBA = 0x9393
const GL_VIEW_CLASS_ASTC_12x10_RGBA = 0x9394
const GL_VIEW_CLASS_ASTC_12x12_RGBA = 0x9395

/* ----------------------- GL_ARB_invalidate_subdata ----------------------- */

const GL_ARB_invalidate_subdata = 1

/* ---------------------- GL_ARB_map_buffer_alignment ---------------------- */

const GL_ARB_map_buffer_alignment = 1

/* ------------------------ GL_ARB_map_buffer_range ------------------------ */

const GL_ARB_map_buffer_range = 1

/* --------------------------- GL_ARB_multi_bind --------------------------- */

const GL_ARB_multi_bind = 1

/* ---------------------- GL_ARB_multi_draw_indirect ----------------------- */

const GL_ARB_multi_draw_indirect = 1

/* ------------------------ GL_ARB_occlusion_query2 ------------------------ */

const GL_ARB_occlusion_query2 = 1

/* -------------------- GL_ARB_parallel_shader_compile --------------------- */

const GL_ARB_parallel_shader_compile     = 1
const GL_MAX_SHADER_COMPILER_THREADS_ARB = 0x91B0
const GL_COMPLETION_STATUS_ARB           = 0x91B1

#[Extension, Swag.PlaceHolder]
{
    func glMaxShaderCompilerThreadsARB(count: GLuint)
}

/* ------------------- GL_ARB_pipeline_statistics_query -------------------- */

const GL_ARB_pipeline_statistics_query          = 1
const GL_VERTICES_SUBMITTED_ARB                 = 0x82EE
const GL_PRIMITIVES_SUBMITTED_ARB               = 0x82EF
const GL_VERTEX_SHADER_INVOCATIONS_ARB          = 0x82F0
const GL_TESS_CONTROL_SHADER_PATCHES_ARB        = 0x82F1
const GL_TESS_EVALUATION_SHADER_INVOCATIONS_ARB = 0x82F2
const GL_GEOMETRY_SHADER_PRIMITIVES_EMITTED_ARB = 0x82F3
const GL_FRAGMENT_SHADER_INVOCATIONS_ARB        = 0x82F4
const GL_COMPUTE_SHADER_INVOCATIONS_ARB         = 0x82F5
const GL_CLIPPING_INPUT_PRIMITIVES_ARB          = 0x82F6
const GL_CLIPPING_OUTPUT_PRIMITIVES_ARB         = 0x82F7

/* ---------------------- GL_ARB_pixel_buffer_object ----------------------- */

const GL_ARB_pixel_buffer_object         = 1
const GL_PIXEL_PACK_BUFFER_ARB           = 0x88EB
const GL_PIXEL_UNPACK_BUFFER_ARB         = 0x88EC
const GL_PIXEL_PACK_BUFFER_BINDING_ARB   = 0x88ED
const GL_PIXEL_UNPACK_BUFFER_BINDING_ARB = 0x88EF

/* ---------------------- GL_ARB_polygon_offset_clamp ---------------------- */

const GL_ARB_polygon_offset_clamp = 1

/* ---------------------- GL_ARB_post_depth_coverage ----------------------- */

const GL_ARB_post_depth_coverage = 1

/* -------------------- GL_ARB_program_interface_query --------------------- */

const GL_ARB_program_interface_query = 1

/* ------------------------ GL_ARB_provoking_vertex ------------------------ */

const GL_ARB_provoking_vertex = 1

/* ---------------------- GL_ARB_query_buffer_object ----------------------- */

const GL_ARB_query_buffer_object = 1

/* ----------------- GL_ARB_robust_buffer_access_behavior ------------------ */

const GL_ARB_robust_buffer_access_behavior = 1

/* --------------------------- GL_ARB_robustness --------------------------- */

const GL_ARB_robustness                     = 1
const GL_CONTEXT_FLAG_ROBUST_ACCESS_BIT_ARB = 0x00000004
const GL_LOSE_CONTEXT_ON_RESET_ARB          = 0x8252
const GL_GUILTY_CONTEXT_RESET_ARB           = 0x8253
const GL_INNOCENT_CONTEXT_RESET_ARB         = 0x8254
const GL_UNKNOWN_CONTEXT_RESET_ARB          = 0x8255
const GL_RESET_NOTIFICATION_STRATEGY_ARB    = 0x8256
const GL_NO_RESET_NOTIFICATION_ARB          = 0x8261

#[Extension, Swag.PlaceHolder]
{
    func glGetGraphicsResetStatusARB()->GLenum
    func glGetnCompressedTexImageARB(target: GLenum, lod: GLint, bufSize: GLsizei, img: #null *void)
    func glGetnTexImageARB(target: GLenum, level: GLint, format: GLenum, type: GLenum, bufSize: GLsizei, img: #null *void)
    func glGetnUniformdvARB(program: GLuint, location: GLint, bufSize: GLsizei, params: #null *GLdouble)
    func glGetnUniformfvARB(program: GLuint, location: GLint, bufSize: GLsizei, params: #null *GLfloat)
    func glGetnUniformivARB(program: GLuint, location: GLint, bufSize: GLsizei, params: #null *GLint)
    func glGetnUniformuivARB(program: GLuint, location: GLint, bufSize: GLsizei, params: #null *GLuint)
    func glReadnPixelsARB(x: GLint, y: GLint, width: GLsizei, height: GLsizei, format: GLenum, type: GLenum, bufSize: GLsizei, data: #null *void)
}

/* ---------------------- GL_ARB_robustness_isolation ---------------------- */

const GL_ARB_robustness_isolation = 1

/* ------------------------ GL_ARB_sample_locations ------------------------ */

const GL_ARB_sample_locations                          = 1
const GL_SAMPLE_LOCATION_SUBPIXEL_BITS_ARB             = 0x933D
const GL_SAMPLE_LOCATION_PIXEL_GRID_WIDTH_ARB          = 0x933E
const GL_SAMPLE_LOCATION_PIXEL_GRID_HEIGHT_ARB         = 0x933F
const GL_PROGRAMMABLE_SAMPLE_LOCATION_TABLE_SIZE_ARB   = 0x9340
const GL_SAMPLE_LOCATION_ARB                           = 0x8E50
const GL_PROGRAMMABLE_SAMPLE_LOCATION_ARB              = 0x9341
const GL_FRAMEBUFFER_PROGRAMMABLE_SAMPLE_LOCATIONS_ARB = 0x9342
const GL_FRAMEBUFFER_SAMPLE_LOCATION_PIXEL_GRID_ARB    = 0x9343

#[Extension, Swag.PlaceHolder]
{
    func glEvaluateDepthValuesARB()
    func glFramebufferSampleLocationsfvARB(target: GLenum, start: GLuint, count: GLsizei, v: #null const *GLfloat)
    func glNamedFramebufferSampleLocationsfvARB(framebuffer: GLuint, start: GLuint, count: GLsizei, v: #null const *GLfloat)
}

/* ------------------------- GL_ARB_sample_shading ------------------------- */

const GL_ARB_sample_shading           = 1
const GL_SAMPLE_SHADING_ARB           = 0x8C36
const GL_MIN_SAMPLE_SHADING_VALUE_ARB = 0x8C37

#[Extension, Swag.PlaceHolder]
{
    func glMinSampleShadingARB(value: GLfloat)
}

/* ------------------------ GL_ARB_sampler_objects ------------------------- */

const GL_ARB_sampler_objects = 1

/* ----------------------- GL_ARB_seamless_cube_map ------------------------ */

const GL_ARB_seamless_cube_map = 1

/* ------------------ GL_ARB_seamless_cubemap_per_texture ------------------ */

const GL_ARB_seamless_cubemap_per_texture = 1

/* -------------------- GL_ARB_separate_shader_objects --------------------- */

const GL_ARB_separate_shader_objects = 1

/* ------------------- GL_ARB_shader_atomic_counter_ops -------------------- */

const GL_ARB_shader_atomic_counter_ops = 1

/* --------------------- GL_ARB_shader_atomic_counters --------------------- */

const GL_ARB_shader_atomic_counters = 1

/* ------------------------- GL_ARB_shader_ballot -------------------------- */

const GL_ARB_shader_ballot = 1

/* ---------------------- GL_ARB_shader_bit_encoding ----------------------- */

const GL_ARB_shader_bit_encoding = 1

/* -------------------------- GL_ARB_shader_clock -------------------------- */

const GL_ARB_shader_clock = 1

/* --------------------- GL_ARB_shader_draw_parameters --------------------- */

const GL_ARB_shader_draw_parameters = 1

/* ----------------------- GL_ARB_shader_group_vote ------------------------ */

const GL_ARB_shader_group_vote = 1

/* -------------------- GL_ARB_shader_image_load_store --------------------- */

const GL_ARB_shader_image_load_store = 1

/* ----------------------- GL_ARB_shader_image_size ------------------------ */

const GL_ARB_shader_image_size = 1

/* ------------------------ GL_ARB_shader_precision ------------------------ */

const GL_ARB_shader_precision = 1

/* --------------------- GL_ARB_shader_stencil_export ---------------------- */

const GL_ARB_shader_stencil_export = 1

/* ------------------ GL_ARB_shader_storage_buffer_object ------------------ */

const GL_ARB_shader_storage_buffer_object = 1

/* ----------------------- GL_ARB_shader_subroutine ------------------------ */

const GL_ARB_shader_subroutine = 1

/* ------------------ GL_ARB_shader_texture_image_samples ------------------ */

const GL_ARB_shader_texture_image_samples = 1

/* ------------------ GL_ARB_shader_viewport_layer_array ------------------- */

const GL_ARB_shader_viewport_layer_array = 1

/* -------------------- GL_ARB_shading_language_420pack -------------------- */

const GL_ARB_shading_language_420pack = 1

/* -------------------- GL_ARB_shading_language_packing -------------------- */

const GL_ARB_shading_language_packing = 1

/* ------------------------- GL_ARB_sparse_buffer -------------------------- */

const GL_ARB_sparse_buffer           = 1
const GL_SPARSE_STORAGE_BIT_ARB      = 0x0400
const GL_SPARSE_BUFFER_PAGE_SIZE_ARB = 0x82F8

#[Extension, Swag.PlaceHolder]
{
    func glBufferPageCommitmentARB(target: GLenum, offset: GLintptr, size: GLsizeiptr, commit: GLboolean)
    func glNamedBufferPageCommitmentARB(buffer: GLuint, offset: GLintptr, size: GLsizeiptr, commit: GLboolean)
    func glNamedBufferPageCommitmentEXT(buffer: GLuint, offset: GLintptr, size: GLsizeiptr, commit: GLboolean)
}

/* ------------------------- GL_ARB_sparse_texture ------------------------- */

const GL_ARB_sparse_texture                         = 1
const GL_TEXTURE_SPARSE_ARB                         = 0x91A6
const GL_VIRTUAL_PAGE_SIZE_INDEX_ARB                = 0x91A7
const GL_NUM_SPARSE_LEVELS_ARB                      = 0x91AA
const GL_NUM_VIRTUAL_PAGE_SIZES_ARB                 = 0x91A8
const GL_VIRTUAL_PAGE_SIZE_X_ARB                    = 0x9195
const GL_VIRTUAL_PAGE_SIZE_Y_ARB                    = 0x9196
const GL_VIRTUAL_PAGE_SIZE_Z_ARB                    = 0x9197
const GL_MAX_SPARSE_TEXTURE_SIZE_ARB                = 0x9198
const GL_MAX_SPARSE_3D_TEXTURE_SIZE_ARB             = 0x9199
const GL_MAX_SPARSE_ARRAY_TEXTURE_LAYERS_ARB        = 0x919A
const GL_SPARSE_TEXTURE_FULL_ARRAY_CUBE_MIPMAPS_ARB = 0x91A9

#[Extension, Swag.PlaceHolder]
{
    func glTexPageCommitmentARB(target: GLenum, level: GLint, xoffset: GLint, yoffset: GLint, zoffset: GLint, width: GLsizei, height: GLsizei, depth: GLsizei, commit: GLboolean)
}

/* ------------------------ GL_ARB_sparse_texture2 ------------------------- */

const GL_ARB_sparse_texture2 = 1

/* ---------------------- GL_ARB_sparse_texture_clamp ---------------------- */

const GL_ARB_sparse_texture_clamp = 1

/* ------------------------ GL_ARB_spirv_extensions ------------------------ */

const GL_ARB_spirv_extensions = 1

/* ----------------------- GL_ARB_stencil_texturing ------------------------ */

const GL_ARB_stencil_texturing = 1

/* ------------------------------ GL_ARB_sync ------------------------------ */

const GL_ARB_sync = 1

/* ---------------------- GL_ARB_tessellation_shader ----------------------- */

const GL_ARB_tessellation_shader = 1

/* ------------------------ GL_ARB_texture_barrier ------------------------- */

const GL_ARB_texture_barrier = 1

/* ---------------------- GL_ARB_texture_border_clamp ---------------------- */

const GL_ARB_texture_border_clamp = 1
const GL_CLAMP_TO_BORDER_ARB      = 0x812D

/* --------------------- GL_ARB_texture_buffer_object ---------------------- */

const GL_ARB_texture_buffer_object             = 1
const GL_TEXTURE_BUFFER_ARB                    = 0x8C2A
const GL_MAX_TEXTURE_BUFFER_SIZE_ARB           = 0x8C2B
const GL_TEXTURE_BINDING_BUFFER_ARB            = 0x8C2C
const GL_TEXTURE_BUFFER_DATA_STORE_BINDING_ARB = 0x8C2D
const GL_TEXTURE_BUFFER_FORMAT_ARB             = 0x8C2E

#[Extension, Swag.PlaceHolder]
{
    func glTexBufferARB(target: GLenum, internalformat: GLenum, buffer: GLuint)
}

/* ------------------ GL_ARB_texture_buffer_object_rgb32 ------------------- */

const GL_ARB_texture_buffer_object_rgb32 = 1

/* ---------------------- GL_ARB_texture_buffer_range ---------------------- */

const GL_ARB_texture_buffer_range = 1

/* -------------------- GL_ARB_texture_compression_bptc -------------------- */

const GL_ARB_texture_compression_bptc           = 1
const GL_COMPRESSED_RGBA_BPTC_UNORM_ARB         = 0x8E8C
const GL_COMPRESSED_SRGB_ALPHA_BPTC_UNORM_ARB   = 0x8E8D
const GL_COMPRESSED_RGB_BPTC_SIGNED_FLOAT_ARB   = 0x8E8E
const GL_COMPRESSED_RGB_BPTC_UNSIGNED_FLOAT_ARB = 0x8E8F

/* -------------------- GL_ARB_texture_compression_rgtc -------------------- */

const GL_ARB_texture_compression_rgtc = 1

/* --------------------- GL_ARB_texture_cube_map_array --------------------- */

const GL_ARB_texture_cube_map_array              = 1
const GL_TEXTURE_CUBE_MAP_ARRAY_ARB              = 0x9009
const GL_TEXTURE_BINDING_CUBE_MAP_ARRAY_ARB      = 0x900A
const GL_PROXY_TEXTURE_CUBE_MAP_ARRAY_ARB        = 0x900B
const GL_SAMPLER_CUBE_MAP_ARRAY_ARB              = 0x900C
const GL_SAMPLER_CUBE_MAP_ARRAY_SHADOW_ARB       = 0x900D
const GL_INT_SAMPLER_CUBE_MAP_ARRAY_ARB          = 0x900E
const GL_UNSIGNED_INT_SAMPLER_CUBE_MAP_ARRAY_ARB = 0x900F

/* ------------------- GL_ARB_texture_filter_anisotropic ------------------- */

const GL_ARB_texture_filter_anisotropic = 1

/* --------------------- GL_ARB_texture_filter_minmax ---------------------- */

const GL_ARB_texture_filter_minmax  = 1
const GL_TEXTURE_REDUCTION_MODE_ARB = 0x9366
const GL_WEIGHTED_AVERAGE_ARB       = 0x9367

/* ------------------------- GL_ARB_texture_gather ------------------------- */

const GL_ARB_texture_gather                        = 1
const GL_MIN_PROGRAM_TEXTURE_GATHER_OFFSET_ARB     = 0x8E5E
const GL_MAX_PROGRAM_TEXTURE_GATHER_OFFSET_ARB     = 0x8E5F
const GL_MAX_PROGRAM_TEXTURE_GATHER_COMPONENTS_ARB = 0x8F9F

/* ------------------ GL_ARB_texture_mirror_clamp_to_edge ------------------ */

const GL_ARB_texture_mirror_clamp_to_edge = 1

/* -------------------- GL_ARB_texture_mirrored_repeat --------------------- */

const GL_ARB_texture_mirrored_repeat = 1
const GL_MIRRORED_REPEAT_ARB         = 0x8370

/* ---------------------- GL_ARB_texture_multisample ----------------------- */

const GL_ARB_texture_multisample = 1

/* -------------------- GL_ARB_texture_non_power_of_two -------------------- */

const GL_ARB_texture_non_power_of_two = 1

/* ---------------------- GL_ARB_texture_query_levels ---------------------- */

const GL_ARB_texture_query_levels = 1

/* ----------------------- GL_ARB_texture_query_lod ------------------------ */

const GL_ARB_texture_query_lod = 1

/* --------------------------- GL_ARB_texture_rg --------------------------- */

const GL_ARB_texture_rg = 1

/* ----------------------- GL_ARB_texture_rgb10_a2ui ----------------------- */

const GL_ARB_texture_rgb10_a2ui = 1

/* ------------------------ GL_ARB_texture_stencil8 ------------------------ */

const GL_ARB_texture_stencil8 = 1

/* ------------------------ GL_ARB_texture_storage ------------------------- */

const GL_ARB_texture_storage = 1

/* ------------------ GL_ARB_texture_storage_multisample ------------------- */

const GL_ARB_texture_storage_multisample = 1

/* ------------------------ GL_ARB_texture_swizzle ------------------------- */

const GL_ARB_texture_swizzle = 1

/* -------------------------- GL_ARB_texture_view -------------------------- */

const GL_ARB_texture_view = 1

/* -------------------------- GL_ARB_timer_query --------------------------- */

const GL_ARB_timer_query = 1

/* ---------------------- GL_ARB_transform_feedback2 ----------------------- */

const GL_ARB_transform_feedback2 = 1

/* ---------------------- GL_ARB_transform_feedback3 ----------------------- */

const GL_ARB_transform_feedback3 = 1

/* ------------------ GL_ARB_transform_feedback_instanced ------------------ */

const GL_ARB_transform_feedback_instanced = 1

/* --------------- GL_ARB_transform_feedback_overflow_query ---------------- */

const GL_ARB_transform_feedback_overflow_query  = 1
const GL_TRANSFORM_FEEDBACK_OVERFLOW_ARB        = 0x82EC
const GL_TRANSFORM_FEEDBACK_STREAM_OVERFLOW_ARB = 0x82ED

/* --------------------- GL_ARB_uniform_buffer_object ---------------------- */

const GL_ARB_uniform_buffer_object = 1

/* ----------------------- GL_ARB_vertex_array_bgra ------------------------ */

const GL_ARB_vertex_array_bgra = 1

/* ---------------------- GL_ARB_vertex_array_object ----------------------- */

const GL_ARB_vertex_array_object = 1

/* ---------------------- GL_ARB_vertex_attrib_64bit ----------------------- */

const GL_ARB_vertex_attrib_64bit = 1

/* --------------------- GL_ARB_vertex_attrib_binding ---------------------- */

const GL_ARB_vertex_attrib_binding = 1

/* ------------------ GL_ARB_vertex_type_10f_11f_11f_rev ------------------- */

const GL_ARB_vertex_type_10f_11f_11f_rev = 1

/* ------------------- GL_ARB_vertex_type_2_10_10_10_rev ------------------- */

const GL_ARB_vertex_type_2_10_10_10_rev = 1

/* ------------------------- GL_ARB_viewport_array ------------------------- */

const GL_ARB_viewport_array = 1

#[Extension, Swag.PlaceHolder]
{
    func glDepthRangeArraydvNV(first: GLuint, count: GLsizei, v: #null const *GLdouble)
    func glDepthRangeIndexeddNV(index: GLuint, n: GLdouble, f: GLdouble)
}
