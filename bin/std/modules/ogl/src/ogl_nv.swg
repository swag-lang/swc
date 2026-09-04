#global public

using Swag

/* ------------------ GL_NV_bindless_multi_draw_indirect ------------------- */

const GL_NV_bindless_multi_draw_indirect = 1

#[Extension, Swag.PlaceHolder]
{
    func glMultiDrawArraysIndirectBindlessNV(mode: GLenum, indirect: const *void?, drawCount: GLsizei, stride: GLsizei, vertexBufferCount: GLint)
    func glMultiDrawElementsIndirectBindlessNV(mode: GLenum, type: GLenum, indirect: const *void?, drawCount: GLsizei, stride: GLsizei, vertexBufferCount: GLint)
}

/* --------------- GL_NV_bindless_multi_draw_indirect_count ---------------- */

const GL_NV_bindless_multi_draw_indirect_count = 1

#[Extension, Swag.PlaceHolder]
{
    func glMultiDrawArraysIndirectBindlessCountNV(mode: GLenum, indirect: const *void?, drawCount: GLsizei, maxDrawCount: GLsizei, stride: GLsizei, vertexBufferCount: GLint)
    func glMultiDrawElementsIndirectBindlessCountNV(mode: GLenum, type: GLenum, indirect: const *void?, drawCount: GLsizei, maxDrawCount: GLsizei, stride: GLsizei, vertexBufferCount: GLint)
}

/* ------------------------ GL_NV_bindless_texture ------------------------- */

const GL_NV_bindless_texture = 1

#[Extension, Swag.PlaceHolder]
{
    func glGetImageHandleNV(texture: GLuint, level: GLint, layered: GLboolean, layer: GLint, format: GLenum)->GLuint64
    func glGetTextureHandleNV(texture: GLuint)->GLuint64
    func glGetTextureSamplerHandleNV(texture: GLuint, sampler: GLuint)->GLuint64
    func glIsImageHandleResidentNV(handle: GLuint64)->GLboolean
    func glIsTextureHandleResidentNV(handle: GLuint64)->GLboolean
    func glMakeImageHandleNonResidentNV(handle: GLuint64)
    func glMakeImageHandleResidentNV(handle: GLuint64, access: GLenum)
    func glMakeTextureHandleNonResidentNV(handle: GLuint64)
    func glMakeTextureHandleResidentNV(handle: GLuint64)
    func glProgramUniformHandleui64NV(program: GLuint, location: GLint, value: GLuint64)
    func glProgramUniformHandleui64vNV(program: GLuint, location: GLint, count: GLsizei, values: const *GLuint64?)
    func glUniformHandleui64NV(location: GLint, value: GLuint64)
    func glUniformHandleui64vNV(location: GLint, count: GLsizei, value: const *GLuint64?)
}

/* --------------------- GL_NV_blend_equation_advanced --------------------- */

const GL_NV_blend_equation_advanced = 1
const GL_BLEND_OVERLAP_NV           = 0x9281
const GL_BLEND_PREMULTIPLIED_SRC_NV = 0x9280
const GL_BLUE_NV                    = 0x1905
const GL_COLORBURN_NV               = 0x929A
const GL_COLORDODGE_NV              = 0x9299
const GL_CONJOINT_NV                = 0x9284
const GL_CONTRAST_NV                = 0x92A1
const GL_DARKEN_NV                  = 0x9297
const GL_DIFFERENCE_NV              = 0x929E
const GL_DISJOINT_NV                = 0x9283
const GL_DST_ATOP_NV                = 0x928F
const GL_DST_IN_NV                  = 0x928B
const GL_DST_NV                     = 0x9287
const GL_DST_OUT_NV                 = 0x928D
const GL_DST_OVER_NV                = 0x9289
const GL_EXCLUSION_NV               = 0x92A0
const GL_GREEN_NV                   = 0x1904
const GL_HARDLIGHT_NV               = 0x929B
const GL_HARDMIX_NV                 = 0x92A9
const GL_HSL_COLOR_NV               = 0x92AF
const GL_HSL_HUE_NV                 = 0x92AD
const GL_HSL_LUMINOSITY_NV          = 0x92B0
const GL_HSL_SATURATION_NV          = 0x92AE
const GL_INVERT_OVG_NV              = 0x92B4
const GL_INVERT_RGB_NV              = 0x92A3
const GL_LIGHTEN_NV                 = 0x9298
const GL_LINEARBURN_NV              = 0x92A5
const GL_LINEARDODGE_NV             = 0x92A4
const GL_LINEARLIGHT_NV             = 0x92A7
const GL_MINUS_CLAMPED_NV           = 0x92B3
const GL_MINUS_NV                   = 0x929F
const GL_MULTIPLY_NV                = 0x9294
const GL_OVERLAY_NV                 = 0x9296
const GL_PINLIGHT_NV                = 0x92A8
const GL_PLUS_CLAMPED_ALPHA_NV      = 0x92B2
const GL_PLUS_CLAMPED_NV            = 0x92B1
const GL_PLUS_DARKER_NV             = 0x9292
const GL_PLUS_NV                    = 0x9291
const GL_RED_NV                     = 0x1903
const GL_SCREEN_NV                  = 0x9295
const GL_SOFTLIGHT_NV               = 0x929C
const GL_SRC_ATOP_NV                = 0x928E
const GL_SRC_IN_NV                  = 0x928A
const GL_SRC_NV                     = 0x9286
const GL_SRC_OUT_NV                 = 0x928C
const GL_SRC_OVER_NV                = 0x9288
const GL_UNCORRELATED_NV            = 0x9282
const GL_VIVIDLIGHT_NV              = 0x92A6
const GL_XOR_NV                     = 0x1506

#[Extension, Swag.PlaceHolder]
{
    func glBlendBarrierNV()
    func glBlendParameteriNV(pname: GLenum, value: GLint)
}

/* ---------------- GL_NV_blend_equation_advanced_coherent ----------------- */

const GL_NV_blend_equation_advanced_coherent = 1
const GL_BLEND_ADVANCED_COHERENT_NV          = 0x9285

/* ----------------------- GL_NV_blend_minmax_factor ----------------------- */

const GL_NV_blend_minmax_factor = 1
const GL_FACTOR_MIN_AMD         = 0x901C
const GL_FACTOR_MAX_AMD         = 0x901D

/* ---------------------- GL_NV_clip_space_w_scaling ----------------------- */

const GL_NV_clip_space_w_scaling              = 1
const GL_VIEWPORT_POSITION_W_SCALE_NV         = 0x937C
const GL_VIEWPORT_POSITION_W_SCALE_X_COEFF_NV = 0x937D
const GL_VIEWPORT_POSITION_W_SCALE_Y_COEFF_NV = 0x937E

#[Extension, Swag.PlaceHolder]
{
    func glViewportPositionWScaleNV(index: GLuint, xcoeff: GLfloat, ycoeff: GLfloat)
}

/* -------------------------- GL_NV_command_list --------------------------- */

const GL_NV_command_list                    = 1
const GL_TERMINATE_SEQUENCE_COMMAND_NV      = 0x0000
const GL_NOP_COMMAND_NV                     = 0x0001
const GL_DRAW_ELEMENTS_COMMAND_NV           = 0x0002
const GL_DRAW_ARRAYS_COMMAND_NV             = 0x0003
const GL_DRAW_ELEMENTS_STRIP_COMMAND_NV     = 0x0004
const GL_DRAW_ARRAYS_STRIP_COMMAND_NV       = 0x0005
const GL_DRAW_ELEMENTS_INSTANCED_COMMAND_NV = 0x0006
const GL_DRAW_ARRAYS_INSTANCED_COMMAND_NV   = 0x0007
const GL_ELEMENT_ADDRESS_COMMAND_NV         = 0x0008
const GL_ATTRIBUTE_ADDRESS_COMMAND_NV       = 0x0009
const GL_UNIFORM_ADDRESS_COMMAND_NV         = 0x000A
const GL_BLEND_COLOR_COMMAND_NV             = 0x000B
const GL_STENCIL_REF_COMMAND_NV             = 0x000C
const GL_LINE_WIDTH_COMMAND_NV              = 0x000D
const GL_POLYGON_OFFSET_COMMAND_NV          = 0x000E
const GL_ALPHA_REF_COMMAND_NV               = 0x000F
const GL_VIEWPORT_COMMAND_NV                = 0x0010
const GL_SCISSOR_COMMAND_NV                 = 0x0011
const GL_FRONT_FACE_COMMAND_NV              = 0x0012

#[Extension, Swag.PlaceHolder]
{
    func glCallCommandListNV(list: GLuint)
    func glCommandListSegmentsNV(list: GLuint, segments: GLuint)
    func glCompileCommandListNV(list: GLuint)
    func glCreateCommandListsNV(n: GLsizei, lists: *GLuint?)
    func glCreateStatesNV(n: GLsizei, states: *GLuint?)
    func glDeleteCommandListsNV(n: GLsizei, lists: const *GLuint?)
    func glDeleteStatesNV(n: GLsizei, states: const *GLuint?)
    func glDrawCommandsAddressNV(primitiveMode: GLenum, indirects: const *GLuint64?, sizes: const *GLsizei?, count: GLuint)
    func glDrawCommandsNV(primitiveMode: GLenum, buffer: GLuint, indirects: const *GLintptr?, sizes: const *GLsizei?, count: GLuint)
    func glDrawCommandsStatesAddressNV(indirects: const *GLuint64?, sizes: const *GLsizei?, states: const *GLuint?, fbos: const *GLuint?, count: GLuint)
    func glDrawCommandsStatesNV(buffer: GLuint, indirects: const *GLintptr?, sizes: const *GLsizei?, states: const *GLuint?, fbos: const *GLuint?, count: GLuint)
    func glGetCommandHeaderNV(tokenID: GLenum, size: GLuint)->GLuint
    func glGetStageIndexNV(shadertype: GLenum)->GLushort
    func glIsCommandListNV(list: GLuint)->GLboolean
    func glIsStateNV(state: GLuint)->GLboolean
    func glListDrawCommandsStatesClientNV(list: GLuint, segment: GLuint, indirects: *(const *void?)?, sizes: const *GLsizei?, states: const *GLuint?, fbos: const *GLuint?, count: GLuint)
    func glStateCaptureNV(state: GLuint, mode: GLenum)
}

/* ------------------- GL_NV_compute_shader_derivatives -------------------- */

const GL_NV_compute_shader_derivatives = 1

/* ----------------------- GL_NV_conditional_render ------------------------ */

const GL_NV_conditional_render      = 1
const GL_QUERY_WAIT_NV              = 0x8E13
const GL_QUERY_NO_WAIT_NV           = 0x8E14
const GL_QUERY_BY_REGION_WAIT_NV    = 0x8E15
const GL_QUERY_BY_REGION_NO_WAIT_NV = 0x8E16

#[Extension, Swag.PlaceHolder]
{
    func glBeginConditionalRenderNV(id: GLuint, mode: GLenum)
    func glEndConditionalRenderNV()
}

/* ----------------------- GL_NV_conservative_raster ----------------------- */

const GL_NV_conservative_raster              = 1
const GL_CONSERVATIVE_RASTERIZATION_NV       = 0x9346
const GL_SUBPIXEL_PRECISION_BIAS_X_BITS_NV   = 0x9347
const GL_SUBPIXEL_PRECISION_BIAS_Y_BITS_NV   = 0x9348
const GL_MAX_SUBPIXEL_PRECISION_BIAS_BITS_NV = 0x9349

#[Extension, Swag.PlaceHolder]
{
    func glSubpixelPrecisionBiasNV(xbits: GLuint, ybits: GLuint)
}

/* ------------------- GL_NV_conservative_raster_dilate -------------------- */

const GL_NV_conservative_raster_dilate             = 1
const GL_CONSERVATIVE_RASTER_DILATE_NV             = 0x9379
const GL_CONSERVATIVE_RASTER_DILATE_RANGE_NV       = 0x937A
const GL_CONSERVATIVE_RASTER_DILATE_GRANULARITY_NV = 0x937B

#[Extension, Swag.PlaceHolder]
{
    func glConservativeRasterParameterfNV(pname: GLenum, value: GLfloat)
}

/* ------------------ GL_NV_conservative_raster_pre_snap ------------------- */

const GL_NV_conservative_raster_pre_snap      = 1
const GL_CONSERVATIVE_RASTER_MODE_PRE_SNAP_NV = 0x9550

/* ------------- GL_NV_conservative_raster_pre_snap_triangles -------------- */

const GL_NV_conservative_raster_pre_snap_triangles      = 1
const GL_CONSERVATIVE_RASTER_MODE_NV                    = 0x954D
const GL_CONSERVATIVE_RASTER_MODE_POST_SNAP_NV          = 0x954E
const GL_CONSERVATIVE_RASTER_MODE_PRE_SNAP_TRIANGLES_NV = 0x954F

#[Extension, Swag.PlaceHolder]
{
    func glConservativeRasterParameteriNV(pname: GLenum, param: GLint)
}

/* --------------- GL_NV_conservative_raster_underestimation --------------- */

const GL_NV_conservative_raster_underestimation = 1

/* ----------------------- GL_NV_depth_buffer_float ------------------------ */

const GL_NV_depth_buffer_float             = 1
const GL_DEPTH_COMPONENT32F_NV             = 0x8DAB
const GL_DEPTH32F_STENCIL8_NV              = 0x8DAC
const GL_FLOAT_32_UNSIGNED_INT_24_8_REV_NV = 0x8DAD
const GL_DEPTH_BUFFER_FLOAT_MODE_NV        = 0x8DAF

#[Extension, Swag.PlaceHolder]
{
    func glClearDepthdNV(depth: GLdouble)
    func glDepthBoundsdNV(zmin: GLdouble, zmax: GLdouble)
    func glDepthRangedNV(zNear: GLdouble, zFar: GLdouble)
}

/* ------------------------ GL_NV_draw_vulkan_image ------------------------ */

alias GLVULKANPROCNV = *void?

const GL_NV_draw_vulkan_image = 1

#[Extension, Swag.PlaceHolder]
{
    func glDrawVkImageNV(vkImage: GLuint64, sampler: GLuint, x0: GLfloat, y0: GLfloat, x1: GLfloat, y1: GLfloat, z: GLfloat, s0: GLfloat, t0: GLfloat, s1: GLfloat, t1: GLfloat)
    func glGetVkProcAddrNV(name: const *GLchar?)->GLVULKANPROCNV
    func glSignalVkFenceNV(vkFence: GLuint64)
    func glSignalVkSemaphoreNV(vkSemaphore: GLuint64)
    func glWaitVkSemaphoreNV(vkSemaphore: GLuint64)
}

/* ------------------------- GL_NV_fill_rectangle -------------------------- */

const GL_NV_fill_rectangle = 1
const GL_FILL_RECTANGLE_NV = 0x933C

/* ------------------- GL_NV_fragment_coverage_to_color -------------------- */

const GL_NV_fragment_coverage_to_color = 1
const GL_FRAGMENT_COVERAGE_TO_COLOR_NV = 0x92DD
const GL_FRAGMENT_COVERAGE_COLOR_NV    = 0x92DE

#[Extension, Swag.PlaceHolder]
{
    func glFragmentCoverageColorNV(color: GLuint)
}

/* ------------------- GL_NV_fragment_shader_barycentric ------------------- */

const GL_NV_fragment_shader_barycentric = 1

/* -------------------- GL_NV_fragment_shader_interlock -------------------- */

const GL_NV_fragment_shader_interlock = 1

/* -------------------- GL_NV_framebuffer_mixed_samples -------------------- */

const GL_NV_framebuffer_mixed_samples       = 1
const GL_COVERAGE_MODULATION_TABLE_NV       = 0x9331
const GL_COLOR_SAMPLES_NV                   = 0x8E20
const GL_DEPTH_SAMPLES_NV                   = 0x932D
const GL_STENCIL_SAMPLES_NV                 = 0x932E
const GL_MIXED_DEPTH_SAMPLES_SUPPORTED_NV   = 0x932F
const GL_MIXED_STENCIL_SAMPLES_SUPPORTED_NV = 0x9330
const GL_COVERAGE_MODULATION_NV             = 0x9332
const GL_COVERAGE_MODULATION_TABLE_SIZE_NV  = 0x9333

#[Extension, Swag.PlaceHolder]
{
    func glCoverageModulationNV(components: GLenum)
    func glCoverageModulationTableNV(n: GLsizei, v: const *GLfloat?)
    func glGetCoverageModulationTableNV(bufSize: GLsizei, v: *GLfloat?)
}

/* ---------------- GL_NV_framebuffer_multisample_coverage ----------------- */

const GL_NV_framebuffer_multisample_coverage = 1
const GL_RENDERBUFFER_COVERAGE_SAMPLES_NV    = 0x8CAB
const GL_RENDERBUFFER_COLOR_SAMPLES_NV       = 0x8E10
const GL_MAX_MULTISAMPLE_COVERAGE_MODES_NV   = 0x8E11
const GL_MULTISAMPLE_COVERAGE_MODES_NV       = 0x8E12

#[Extension, Swag.PlaceHolder]
{
    func glRenderbufferStorageMultisampleCoverageNV(target: GLenum, coverageSamples: GLsizei, colorSamples: GLsizei, internalformat: GLenum, width: GLsizei, height: GLsizei)
}

/* ------------------- GL_NV_geometry_shader_passthrough ------------------- */

const GL_NV_geometry_shader_passthrough = 1

/* --------------------------- GL_NV_gpu_shader5 --------------------------- */

alias GLint64EXT = s64

const GL_NV_gpu_shader5         = 1
const GL_INT64_NV               = 0x140E
const GL_UNSIGNED_INT64_NV      = 0x140F
const GL_INT8_NV                = 0x8FE0
const GL_INT8_VEC2_NV           = 0x8FE1
const GL_INT8_VEC3_NV           = 0x8FE2
const GL_INT8_VEC4_NV           = 0x8FE3
const GL_INT16_NV               = 0x8FE4
const GL_INT16_VEC2_NV          = 0x8FE5
const GL_INT16_VEC3_NV          = 0x8FE6
const GL_INT16_VEC4_NV          = 0x8FE7
const GL_INT64_VEC2_NV          = 0x8FE9
const GL_INT64_VEC3_NV          = 0x8FEA
const GL_INT64_VEC4_NV          = 0x8FEB
const GL_UNSIGNED_INT8_NV       = 0x8FEC
const GL_UNSIGNED_INT8_VEC2_NV  = 0x8FED
const GL_UNSIGNED_INT8_VEC3_NV  = 0x8FEE
const GL_UNSIGNED_INT8_VEC4_NV  = 0x8FEF
const GL_UNSIGNED_INT16_NV      = 0x8FF0
const GL_UNSIGNED_INT16_VEC2_NV = 0x8FF1
const GL_UNSIGNED_INT16_VEC3_NV = 0x8FF2
const GL_UNSIGNED_INT16_VEC4_NV = 0x8FF3
const GL_UNSIGNED_INT64_VEC2_NV = 0x8FF5
const GL_UNSIGNED_INT64_VEC3_NV = 0x8FF6
const GL_UNSIGNED_INT64_VEC4_NV = 0x8FF7
const GL_FLOAT16_NV             = 0x8FF8
const GL_FLOAT16_VEC2_NV        = 0x8FF9
const GL_FLOAT16_VEC3_NV        = 0x8FFA
const GL_FLOAT16_VEC4_NV        = 0x8FFB

#[Extension, Swag.PlaceHolder]
{
    func glGetUniformi64vNV(program: GLuint, location: GLint, params: *GLint64EXT?)
    func glProgramUniform1i64NV(program: GLuint, location: GLint, x: GLint64EXT)
    func glProgramUniform1i64vNV(program: GLuint, location: GLint, count: GLsizei, value: const *GLint64EXT?)
    func glProgramUniform1ui64NV(program: GLuint, location: GLint, x: GLuint64EXT)
    func glProgramUniform1ui64vNV(program: GLuint, location: GLint, count: GLsizei, value: const *GLuint64EXT?)
    func glProgramUniform2i64NV(program: GLuint, location: GLint, x: GLint64EXT, y: GLint64EXT)
    func glProgramUniform2i64vNV(program: GLuint, location: GLint, count: GLsizei, value: const *GLint64EXT?)
    func glProgramUniform2ui64NV(program: GLuint, location: GLint, x: GLuint64EXT, y: GLuint64EXT)
    func glProgramUniform2ui64vNV(program: GLuint, location: GLint, count: GLsizei, value: const *GLuint64EXT?)
    func glProgramUniform3i64NV(program: GLuint, location: GLint, x: GLint64EXT, y: GLint64EXT, z: GLint64EXT)
    func glProgramUniform3i64vNV(program: GLuint, location: GLint, count: GLsizei, value: const *GLint64EXT?)
    func glProgramUniform3ui64NV(program: GLuint, location: GLint, x: GLuint64EXT, y: GLuint64EXT, z: GLuint64EXT)
    func glProgramUniform3ui64vNV(program: GLuint, location: GLint, count: GLsizei, value: const *GLuint64EXT?)
    func glProgramUniform4i64NV(program: GLuint, location: GLint, x: GLint64EXT, y: GLint64EXT, z: GLint64EXT, w: GLint64EXT)
    func glProgramUniform4i64vNV(program: GLuint, location: GLint, count: GLsizei, value: const *GLint64EXT?)
    func glProgramUniform4ui64NV(program: GLuint, location: GLint, x: GLuint64EXT, y: GLuint64EXT, z: GLuint64EXT, w: GLuint64EXT)
    func glProgramUniform4ui64vNV(program: GLuint, location: GLint, count: GLsizei, value: const *GLuint64EXT?)
    func glUniform1i64NV(location: GLint, x: GLint64EXT)
    func glUniform1i64vNV(location: GLint, count: GLsizei, value: const *GLint64EXT?)
    func glUniform1ui64NV(location: GLint, x: GLuint64EXT)
    func glUniform1ui64vNV(location: GLint, count: GLsizei, value: const *GLuint64EXT?)
    func glUniform2i64NV(location: GLint, x: GLint64EXT, y: GLint64EXT)
    func glUniform2i64vNV(location: GLint, count: GLsizei, value: const *GLint64EXT?)
    func glUniform2ui64NV(location: GLint, x: GLuint64EXT, y: GLuint64EXT)
    func glUniform2ui64vNV(location: GLint, count: GLsizei, value: const *GLuint64EXT?)
    func glUniform3i64NV(location: GLint, x: GLint64EXT, y: GLint64EXT, z: GLint64EXT)
    func glUniform3i64vNV(location: GLint, count: GLsizei, value: const *GLint64EXT?)
    func glUniform3ui64NV(location: GLint, x: GLuint64EXT, y: GLuint64EXT, z: GLuint64EXT)
    func glUniform3ui64vNV(location: GLint, count: GLsizei, value: const *GLuint64EXT?)
    func glUniform4i64NV(location: GLint, x: GLint64EXT, y: GLint64EXT, z: GLint64EXT, w: GLint64EXT)
    func glUniform4i64vNV(location: GLint, count: GLsizei, value: const *GLint64EXT?)
    func glUniform4ui64NV(location: GLint, x: GLuint64EXT, y: GLuint64EXT, z: GLuint64EXT, w: GLuint64EXT)
    func glUniform4ui64vNV(location: GLint, count: GLsizei, value: const *GLuint64EXT?)
}

/* ------------------- GL_NV_internalformat_sample_query ------------------- */

const GL_NV_internalformat_sample_query = 1
const GL_MULTISAMPLES_NV                = 0x9371
const GL_SUPERSAMPLE_SCALE_X_NV         = 0x9372
const GL_SUPERSAMPLE_SCALE_Y_NV         = 0x9373
const GL_CONFORMANT_NV                  = 0x9374

#[Extension, Swag.PlaceHolder]
{
    func glGetInternalformatSampleivNV(target: GLenum, internalformat: GLenum, samples: GLsizei, pname: GLenum, count: GLsizei, params: *GLint?)
}

/* ------------------------ GL_NV_memory_attachment ------------------------ */

const GL_NV_memory_attachment           = 1
const GL_ATTACHED_MEMORY_OBJECT_NV      = 0x95A4
const GL_ATTACHED_MEMORY_OFFSET_NV      = 0x95A5
const GL_MEMORY_ATTACHABLE_ALIGNMENT_NV = 0x95A6
const GL_MEMORY_ATTACHABLE_SIZE_NV      = 0x95A7
const GL_MEMORY_ATTACHABLE_NV           = 0x95A8
const GL_DETACHED_MEMORY_INCARNATION_NV = 0x95A9
const GL_DETACHED_TEXTURES_NV           = 0x95AA
const GL_DETACHED_BUFFERS_NV            = 0x95AB
const GL_MAX_DETACHED_TEXTURES_NV       = 0x95AC
const GL_MAX_DETACHED_BUFFERS_NV        = 0x95AD

#[Extension, Swag.PlaceHolder]
{
    func glBufferAttachMemoryNV(target: GLenum, memory: GLuint, offset: GLuint64)
    func glGetMemoryObjectDetachedResourcesuivNV(memory: GLuint, pname: GLenum, first: GLint, count: GLsizei, params: *GLuint?)
    func glNamedBufferAttachMemoryNV(buffer: GLuint, memory: GLuint, offset: GLuint64)
    func glResetMemoryObjectParameterNV(memory: GLuint, pname: GLenum)
    func glTexAttachMemoryNV(target: GLenum, memory: GLuint, offset: GLuint64)
    func glTextureAttachMemoryNV(texture: GLuint, memory: GLuint, offset: GLuint64)
}

/* ---------------------- GL_NV_memory_object_sparse ----------------------- */

const GL_NV_memory_object_sparse = 1

#[Extension, Swag.PlaceHolder]
{
    func glBufferPageCommitmentMemNV(target: GLenum, offset: GLintptr, size: GLsizeiptr, memory: GLuint, memOffset: GLuint64, commit: GLboolean)
    func glNamedBufferPageCommitmentMemNV(buffer: GLuint, offset: GLintptr, size: GLsizeiptr, memory: GLuint, memOffset: GLuint64, commit: GLboolean)
    func glTexPageCommitmentMemNV(target: GLenum, layer: GLint, level: GLint, xoffset: GLint, yoffset: GLint, zoffset: GLint, width: GLsizei, height: GLsizei, depth: GLsizei, memory: GLuint, offset: GLuint64, commit: GLboolean)
    func glTexturePageCommitmentMemNV(texture: GLuint, layer: GLint, level: GLint, xoffset: GLint, yoffset: GLint, zoffset: GLint, width: GLsizei, height: GLsizei, depth: GLsizei, memory: GLuint, offset: GLuint64, commit: GLboolean)
}

/* --------------------------- GL_NV_mesh_shader --------------------------- */

const GL_NV_mesh_shader                                     = 1
const GL_MESH_SHADER_NV                                     = 0x9559
const GL_TASK_SHADER_NV                                     = 0x955A
const GL_MAX_MESH_UNIFORM_BLOCKS_NV                         = 0x8E60
const GL_MAX_MESH_TEXTURE_IMAGE_UNITS_NV                    = 0x8E61
const GL_MAX_MESH_IMAGE_UNIFORMS_NV                         = 0x8E62
const GL_MAX_MESH_UNIFORM_COMPONENTS_NV                     = 0x8E63
const GL_MAX_MESH_ATOMIC_COUNTER_BUFFERS_NV                 = 0x8E64
const GL_MAX_MESH_ATOMIC_COUNTERS_NV                        = 0x8E65
const GL_MAX_MESH_SHADER_STORAGE_BLOCKS_NV                  = 0x8E66
const GL_MAX_COMBINED_MESH_UNIFORM_COMPONENTS_NV            = 0x8E67
const GL_MAX_TASK_UNIFORM_BLOCKS_NV                         = 0x8E68
const GL_MAX_TASK_TEXTURE_IMAGE_UNITS_NV                    = 0x8E69
const GL_MAX_TASK_IMAGE_UNIFORMS_NV                         = 0x8E6A
const GL_MAX_TASK_UNIFORM_COMPONENTS_NV                     = 0x8E6B
const GL_MAX_TASK_ATOMIC_COUNTER_BUFFERS_NV                 = 0x8E6C
const GL_MAX_TASK_ATOMIC_COUNTERS_NV                        = 0x8E6D
const GL_MAX_TASK_SHADER_STORAGE_BLOCKS_NV                  = 0x8E6E
const GL_MAX_COMBINED_TASK_UNIFORM_COMPONENTS_NV            = 0x8E6F
const GL_MAX_MESH_WORK_GROUP_INVOCATIONS_NV                 = 0x95A2
const GL_MAX_TASK_WORK_GROUP_INVOCATIONS_NV                 = 0x95A3
const GL_MAX_MESH_TOTAL_MEMORY_SIZE_NV                      = 0x9536
const GL_MAX_TASK_TOTAL_MEMORY_SIZE_NV                      = 0x9537
const GL_MAX_MESH_OUTPUT_VERTICES_NV                        = 0x9538
const GL_MAX_MESH_OUTPUT_PRIMITIVES_NV                      = 0x9539
const GL_MAX_TASK_OUTPUT_COUNT_NV                           = 0x953A
const GL_MAX_DRAW_MESH_TASKS_COUNT_NV                       = 0x953D
const GL_MAX_MESH_VIEWS_NV                                  = 0x9557
const GL_MESH_OUTPUT_PER_VERTEX_GRANULARITY_NV              = 0x92DF
const GL_MESH_OUTPUT_PER_PRIMITIVE_GRANULARITY_NV           = 0x9543
const GL_MAX_MESH_WORK_GROUP_SIZE_NV                        = 0x953B
const GL_MAX_TASK_WORK_GROUP_SIZE_NV                        = 0x953C
const GL_MESH_WORK_GROUP_SIZE_NV                            = 0x953E
const GL_TASK_WORK_GROUP_SIZE_NV                            = 0x953F
const GL_MESH_VERTICES_OUT_NV                               = 0x9579
const GL_MESH_PRIMITIVES_OUT_NV                             = 0x957A
const GL_MESH_OUTPUT_TYPE_NV                                = 0x957B
const GL_UNIFORM_BLOCK_REFERENCED_BY_MESH_SHADER_NV         = 0x959C
const GL_UNIFORM_BLOCK_REFERENCED_BY_TASK_SHADER_NV         = 0x959D
const GL_REFERENCED_BY_MESH_SHADER_NV                       = 0x95A0
const GL_REFERENCED_BY_TASK_SHADER_NV                       = 0x95A1
const GL_MESH_SHADER_BIT_NV                                 = 0x00000040
const GL_TASK_SHADER_BIT_NV                                 = 0x00000080
const GL_MESH_SUBROUTINE_NV                                 = 0x957C
const GL_TASK_SUBROUTINE_NV                                 = 0x957D
const GL_MESH_SUBROUTINE_UNIFORM_NV                         = 0x957E
const GL_TASK_SUBROUTINE_UNIFORM_NV                         = 0x957F
const GL_ATOMIC_COUNTER_BUFFER_REFERENCED_BY_MESH_SHADER_NV = 0x959E
const GL_ATOMIC_COUNTER_BUFFER_REFERENCED_BY_TASK_SHADER_NV = 0x959F

#[Extension, Swag.PlaceHolder]
{
    func glDrawMeshTasksIndirectNV(indirect: GLintptr)
    func glDrawMeshTasksNV(first: GLuint, count: GLuint)
    func glMultiDrawMeshTasksIndirectCountNV(indirect: GLintptr, drawcount: GLintptr, maxdrawcount: GLsizei, stride: GLsizei)
    func glMultiDrawMeshTasksIndirectNV(indirect: GLintptr, drawcount: GLsizei, stride: GLsizei)
}

/* ------------------------- GL_NV_path_rendering -------------------------- */

const GL_NV_path_rendering                       = 1
const GL_PATH_FORMAT_SVG_NV                      = 0x9070
const GL_PATH_FORMAT_PS_NV                       = 0x9071
const GL_STANDARD_FONT_NAME_NV                   = 0x9072
const GL_SYSTEM_FONT_NAME_NV                     = 0x9073
const GL_FILE_NAME_NV                            = 0x9074
const GL_PATH_STROKE_WIDTH_NV                    = 0x9075
const GL_PATH_END_CAPS_NV                        = 0x9076
const GL_PATH_INITIAL_END_CAP_NV                 = 0x9077
const GL_PATH_TERMINAL_END_CAP_NV                = 0x9078
const GL_PATH_JOIN_STYLE_NV                      = 0x9079
const GL_PATH_MITER_LIMIT_NV                     = 0x907A
const GL_PATH_DASH_CAPS_NV                       = 0x907B
const GL_PATH_INITIAL_DASH_CAP_NV                = 0x907C
const GL_PATH_TERMINAL_DASH_CAP_NV               = 0x907D
const GL_PATH_DASH_OFFSET_NV                     = 0x907E
const GL_PATH_CLIENT_LENGTH_NV                   = 0x907F
const GL_PATH_FILL_MODE_NV                       = 0x9080
const GL_PATH_FILL_MASK_NV                       = 0x9081
const GL_PATH_FILL_COVER_MODE_NV                 = 0x9082
const GL_PATH_STROKE_COVER_MODE_NV               = 0x9083
const GL_PATH_STROKE_MASK_NV                     = 0x9084
const GL_COUNT_UP_NV                             = 0x9088
const GL_COUNT_DOWN_NV                           = 0x9089
const GL_PATH_OBJECT_BOUNDING_BOX_NV             = 0x908A
const GL_CONVEX_HULL_NV                          = 0x908B
const GL_BOUNDING_BOX_NV                         = 0x908D
const GL_TRANSLATE_X_NV                          = 0x908E
const GL_TRANSLATE_Y_NV                          = 0x908F
const GL_TRANSLATE_2D_NV                         = 0x9090
const GL_TRANSLATE_3D_NV                         = 0x9091
const GL_AFFINE_2D_NV                            = 0x9092
const GL_AFFINE_3D_NV                            = 0x9094
const GL_TRANSPOSE_AFFINE_2D_NV                  = 0x9096
const GL_TRANSPOSE_AFFINE_3D_NV                  = 0x9098
const GL_UTF8_NV                                 = 0x909A
const GL_UTF16_NV                                = 0x909B
const GL_BOUNDING_BOX_OF_BOUNDING_BOXES_NV       = 0x909C
const GL_PATH_COMMAND_COUNT_NV                   = 0x909D
const GL_PATH_COORD_COUNT_NV                     = 0x909E
const GL_PATH_DASH_ARRAY_COUNT_NV                = 0x909F
const GL_PATH_COMPUTED_LENGTH_NV                 = 0x90A0
const GL_PATH_FILL_BOUNDING_BOX_NV               = 0x90A1
const GL_PATH_STROKE_BOUNDING_BOX_NV             = 0x90A2
const GL_SQUARE_NV                               = 0x90A3
const GL_ROUND_NV                                = 0x90A4
const GL_TRIANGULAR_NV                           = 0x90A5
const GL_BEVEL_NV                                = 0x90A6
const GL_MITER_REVERT_NV                         = 0x90A7
const GL_MITER_TRUNCATE_NV                       = 0x90A8
const GL_SKIP_MISSING_GLYPH_NV                   = 0x90A9
const GL_USE_MISSING_GLYPH_NV                    = 0x90AA
const GL_PATH_ERROR_POSITION_NV                  = 0x90AB
const GL_ACCUM_ADJACENT_PAIRS_NV                 = 0x90AD
const GL_ADJACENT_PAIRS_NV                       = 0x90AE
const GL_FIRST_TO_REST_NV                        = 0x90AF
const GL_PATH_GEN_MODE_NV                        = 0x90B0
const GL_PATH_GEN_COEFF_NV                       = 0x90B1
const GL_PATH_GEN_COMPONENTS_NV                  = 0x90B3
const GL_PATH_STENCIL_FUNC_NV                    = 0x90B7
const GL_PATH_STENCIL_REF_NV                     = 0x90B8
const GL_PATH_STENCIL_VALUE_MASK_NV              = 0x90B9
const GL_PATH_STENCIL_DEPTH_OFFSET_FACTOR_NV     = 0x90BD
const GL_PATH_STENCIL_DEPTH_OFFSET_UNITS_NV      = 0x90BE
const GL_PATH_COVER_DEPTH_FUNC_NV                = 0x90BF
const GL_PATH_DASH_OFFSET_RESET_NV               = 0x90B4
const GL_MOVE_TO_RESETS_NV                       = 0x90B5
const GL_MOVE_TO_CONTINUES_NV                    = 0x90B6
const GL_CLOSE_PATH_NV                           = 0x00
const GL_MOVE_TO_NV                              = 0x02
const GL_RELATIVE_MOVE_TO_NV                     = 0x03
const GL_LINE_TO_NV                              = 0x04
const GL_RELATIVE_LINE_TO_NV                     = 0x05
const GL_HORIZONTAL_LINE_TO_NV                   = 0x06
const GL_RELATIVE_HORIZONTAL_LINE_TO_NV          = 0x07
const GL_VERTICAL_LINE_TO_NV                     = 0x08
const GL_RELATIVE_VERTICAL_LINE_TO_NV            = 0x09
const GL_QUADRATIC_CURVE_TO_NV                   = 0x0A
const GL_RELATIVE_QUADRATIC_CURVE_TO_NV          = 0x0B
const GL_CUBIC_CURVE_TO_NV                       = 0x0C
const GL_RELATIVE_CUBIC_CURVE_TO_NV              = 0x0D
const GL_SMOOTH_QUADRATIC_CURVE_TO_NV            = 0x0E
const GL_RELATIVE_SMOOTH_QUADRATIC_CURVE_TO_NV   = 0x0F
const GL_SMOOTH_CUBIC_CURVE_TO_NV                = 0x10
const GL_RELATIVE_SMOOTH_CUBIC_CURVE_TO_NV       = 0x11
const GL_SMALL_CCW_ARC_TO_NV                     = 0x12
const GL_RELATIVE_SMALL_CCW_ARC_TO_NV            = 0x13
const GL_SMALL_CW_ARC_TO_NV                      = 0x14
const GL_RELATIVE_SMALL_CW_ARC_TO_NV             = 0x15
const GL_LARGE_CCW_ARC_TO_NV                     = 0x16
const GL_RELATIVE_LARGE_CCW_ARC_TO_NV            = 0x17
const GL_LARGE_CW_ARC_TO_NV                      = 0x18
const GL_RELATIVE_LARGE_CW_ARC_TO_NV             = 0x19
const GL_RESTART_PATH_NV                         = 0xF0
const GL_DUP_FIRST_CUBIC_CURVE_TO_NV             = 0xF2
const GL_DUP_LAST_CUBIC_CURVE_TO_NV              = 0xF4
const GL_RECT_NV                                 = 0xF6
const GL_CIRCULAR_CCW_ARC_TO_NV                  = 0xF8
const GL_CIRCULAR_CW_ARC_TO_NV                   = 0xFA
const GL_CIRCULAR_TANGENT_ARC_TO_NV              = 0xFC
const GL_ARC_TO_NV                               = 0xFE
const GL_RELATIVE_ARC_TO_NV                      = 0xFF
const GL_BOLD_BIT_NV                             = 0x01
const GL_ITALIC_BIT_NV                           = 0x02
const GL_GLYPH_WIDTH_BIT_NV                      = 0x01
const GL_GLYPH_HEIGHT_BIT_NV                     = 0x02
const GL_GLYPH_HORIZONTAL_BEARING_X_BIT_NV       = 0x04
const GL_GLYPH_HORIZONTAL_BEARING_Y_BIT_NV       = 0x08
const GL_GLYPH_HORIZONTAL_BEARING_ADVANCE_BIT_NV = 0x10
const GL_GLYPH_VERTICAL_BEARING_X_BIT_NV         = 0x20
const GL_GLYPH_VERTICAL_BEARING_Y_BIT_NV         = 0x40
const GL_GLYPH_VERTICAL_BEARING_ADVANCE_BIT_NV   = 0x80
const GL_GLYPH_HAS_KERNING_BIT_NV                = 0x100
const GL_FONT_X_MIN_BOUNDS_BIT_NV                = 0x00010000
const GL_FONT_Y_MIN_BOUNDS_BIT_NV                = 0x00020000
const GL_FONT_X_MAX_BOUNDS_BIT_NV                = 0x00040000
const GL_FONT_Y_MAX_BOUNDS_BIT_NV                = 0x00080000
const GL_FONT_UNITS_PER_EM_BIT_NV                = 0x00100000
const GL_FONT_ASCENDER_BIT_NV                    = 0x00200000
const GL_FONT_DESCENDER_BIT_NV                   = 0x00400000
const GL_FONT_HEIGHT_BIT_NV                      = 0x00800000
const GL_FONT_MAX_ADVANCE_WIDTH_BIT_NV           = 0x01000000
const GL_FONT_MAX_ADVANCE_HEIGHT_BIT_NV          = 0x02000000
const GL_FONT_UNDERLINE_POSITION_BIT_NV          = 0x04000000
const GL_FONT_UNDERLINE_THICKNESS_BIT_NV         = 0x08000000
const GL_FONT_HAS_KERNING_BIT_NV                 = 0x10000000
const GL_ROUNDED_RECT_NV                         = 0xE8
const GL_RELATIVE_ROUNDED_RECT_NV                = 0xE9
const GL_ROUNDED_RECT2_NV                        = 0xEA
const GL_RELATIVE_ROUNDED_RECT2_NV               = 0xEB
const GL_ROUNDED_RECT4_NV                        = 0xEC
const GL_RELATIVE_ROUNDED_RECT4_NV               = 0xED
const GL_ROUNDED_RECT8_NV                        = 0xEE
const GL_RELATIVE_ROUNDED_RECT8_NV               = 0xEF
const GL_RELATIVE_RECT_NV                        = 0xF7
const GL_FONT_GLYPHS_AVAILABLE_NV                = 0x9368
const GL_FONT_TARGET_UNAVAILABLE_NV              = 0x9369
const GL_FONT_UNAVAILABLE_NV                     = 0x936A
const GL_FONT_UNINTELLIGIBLE_NV                  = 0x936B
const GL_CONIC_CURVE_TO_NV                       = 0x1A
const GL_RELATIVE_CONIC_CURVE_TO_NV              = 0x1B
const GL_FONT_NUM_GLYPH_INDICES_BIT_NV           = 0x20000000
const GL_STANDARD_FONT_FORMAT_NV                 = 0x936C
const GL_PATH_PROJECTION_NV                      = 0x1701
const GL_PATH_MODELVIEW_NV                       = 0x1700
const GL_PATH_MODELVIEW_STACK_DEPTH_NV           = 0x0BA3
const GL_PATH_MODELVIEW_MATRIX_NV                = 0x0BA6
const GL_PATH_MAX_MODELVIEW_STACK_DEPTH_NV       = 0x0D36
const GL_PATH_TRANSPOSE_MODELVIEW_MATRIX_NV      = 0x84E3
const GL_PATH_PROJECTION_STACK_DEPTH_NV          = 0x0BA4
const GL_PATH_PROJECTION_MATRIX_NV               = 0x0BA7
const GL_PATH_MAX_PROJECTION_STACK_DEPTH_NV      = 0x0D38
const GL_PATH_TRANSPOSE_PROJECTION_MATRIX_NV     = 0x84E4
const GL_FRAGMENT_INPUT_NV                       = 0x936D

#[Extension, Swag.PlaceHolder]
{
    func glCopyPathNV(resultPath: GLuint, srcPath: GLuint)
    func glCoverFillPathInstancedNV(numPaths: GLsizei, pathNameType: GLenum, paths: const *void?, pathBase: GLuint, coverMode: GLenum, transformType: GLenum, transformValues: const *GLfloat?)
    func glCoverFillPathNV(path: GLuint, coverMode: GLenum)
    func glCoverStrokePathInstancedNV(numPaths: GLsizei, pathNameType: GLenum, paths: const *void?, pathBase: GLuint, coverMode: GLenum, transformType: GLenum, transformValues: const *GLfloat?)
    func glCoverStrokePathNV(path: GLuint, coverMode: GLenum)
    func glDeletePathsNV(path: GLuint, range: GLsizei)
    func glGenPathsNV(range: GLsizei)->GLuint
    func glGetPathCommandsNV(path: GLuint, commands: *GLubyte?)
    func glGetPathCoordsNV(path: GLuint, coords: *GLfloat?)
    func glGetPathDashArrayNV(path: GLuint, dashArray: *GLfloat?)
    func glGetPathLengthNV(path: GLuint, startSegment: GLsizei, numSegments: GLsizei)->GLfloat
    func glGetPathMetricRangeNV(metricQueryMask: GLbitfield, firstPathName: GLuint, numPaths: GLsizei, stride: GLsizei, metrics: *GLfloat?)
    func glGetPathMetricsNV(metricQueryMask: GLbitfield, numPaths: GLsizei, pathNameType: GLenum, paths: const *void?, pathBase: GLuint, stride: GLsizei, metrics: *GLfloat?)
    func glGetPathParameterfvNV(path: GLuint, pname: GLenum, value: *GLfloat?)
    func glGetPathParameterivNV(path: GLuint, pname: GLenum, value: *GLint?)
    func glGetPathSpacingNV(pathListMode: GLenum, numPaths: GLsizei, pathNameType: GLenum, paths: const *void?, pathBase: GLuint, advanceScale: GLfloat, kerningScale: GLfloat, transformType: GLenum, returnedSpacing: *GLfloat?)
    func glGetProgramResourcefvNV(program: GLuint, programInterface: GLenum, index: GLuint, propCount: GLsizei, props: const *GLenum?, count: GLsizei, length: *GLsizei?, params: *GLfloat?)
    func glInterpolatePathsNV(resultPath: GLuint, pathA: GLuint, pathB: GLuint, weight: GLfloat)
    func glIsPathNV(path: GLuint)->GLboolean
    func glIsPointInFillPathNV(path: GLuint, mask: GLuint, x: GLfloat, y: GLfloat)->GLboolean
    func glIsPointInStrokePathNV(path: GLuint, x: GLfloat, y: GLfloat)->GLboolean
    func glMatrixLoad3x2fNV(matrixMode: GLenum, m: const *GLfloat?)
    func glMatrixLoad3x3fNV(matrixMode: GLenum, m: const *GLfloat?)
    func glMatrixLoadTranspose3x3fNV(matrixMode: GLenum, m: const *GLfloat?)
    func glMatrixMult3x2fNV(matrixMode: GLenum, m: const *GLfloat?)
    func glMatrixMult3x3fNV(matrixMode: GLenum, m: const *GLfloat?)
    func glMatrixMultTranspose3x3fNV(matrixMode: GLenum, m: const *GLfloat?)
    func glPathCommandsNV(path: GLuint, numCommands: GLsizei, commands: const *GLubyte?, numCoords: GLsizei, coordType: GLenum, coords: const *void?)
    func glPathCoordsNV(path: GLuint, numCoords: GLsizei, coordType: GLenum, coords: const *void?)
    func glPathCoverDepthFuncNV(funcValue: GLenum)
    func glPathDashArrayNV(path: GLuint, dashCount: GLsizei, dashArray: const *GLfloat?)
    func glPathGlyphIndexArrayNV(firstPathName: GLuint, fontTarget: GLenum, fontName: const *void?, fontStyle: GLbitfield, firstGlyphIndex: GLuint, numGlyphs: GLsizei, pathParameterTemplate: GLuint, emScale: GLfloat)->GLenum
    func glPathGlyphIndexRangeNV(fontTarget: GLenum, fontName: const *void?, fontStyle: GLbitfield, pathParameterTemplate: GLuint, emScale: GLfloat, baseAndCount: *GLuint?)->GLenum
    func glPathGlyphRangeNV(firstPathName: GLuint, fontTarget: GLenum, fontName: const *void?, fontStyle: GLbitfield, firstGlyph: GLuint, numGlyphs: GLsizei, handleMissingGlyphs: GLenum, pathParameterTemplate: GLuint, emScale: GLfloat)
    func glPathGlyphsNV(firstPathName: GLuint, fontTarget: GLenum, fontName: const *void?, fontStyle: GLbitfield, numGlyphs: GLsizei, type: GLenum, charcodes: const *void?, handleMissingGlyphs: GLenum, pathParameterTemplate: GLuint, emScale: GLfloat)
    func glPathMemoryGlyphIndexArrayNV(firstPathName: GLuint, fontTarget: GLenum, fontSize: GLsizeiptr, fontData: const *void?, faceIndex: GLsizei, firstGlyphIndex: GLuint, numGlyphs: GLsizei, pathParameterTemplate: GLuint, emScale: GLfloat)->GLenum
    func glPathParameterfNV(path: GLuint, pname: GLenum, value: GLfloat)
    func glPathParameterfvNV(path: GLuint, pname: GLenum, value: const *GLfloat?)
    func glPathParameteriNV(path: GLuint, pname: GLenum, value: GLint)
    func glPathParameterivNV(path: GLuint, pname: GLenum, value: const *GLint?)
    func glPathStencilDepthOffsetNV(factor: GLfloat, units: GLfloat)
    func glPathStencilFuncNV(funcValue: GLenum, refValue: GLint, mask: GLuint)
    func glPathStringNV(path: GLuint, format: GLenum, length: GLsizei, pathString: const *void?)
    func glPathSubCommandsNV(path: GLuint, commandStart: GLsizei, commandsToDelete: GLsizei, numCommands: GLsizei, commands: const *GLubyte?, numCoords: GLsizei, coordType: GLenum, coords: const *void?)
    func glPathSubCoordsNV(path: GLuint, coordStart: GLsizei, numCoords: GLsizei, coordType: GLenum, coords: const *void?)
    func glPointAlongPathNV(path: GLuint, startSegment: GLsizei, numSegments: GLsizei, distance: GLfloat, x: *GLfloat?, y: *GLfloat?, tangentX: *GLfloat?, tangentY: *GLfloat?)->GLboolean
    func glProgramPathFragmentInputGenNV(program: GLuint, location: GLint, genMode: GLenum, components: GLint, coeffs: const *GLfloat?)
    func glStencilFillPathInstancedNV(numPaths: GLsizei, pathNameType: GLenum, paths: const *void?, pathBase: GLuint, fillMode: GLenum, mask: GLuint, transformType: GLenum, transformValues: const *GLfloat?)
    func glStencilFillPathNV(path: GLuint, fillMode: GLenum, mask: GLuint)
    func glStencilStrokePathInstancedNV(numPaths: GLsizei, pathNameType: GLenum, paths: const *void?, pathBase: GLuint, reference: GLint, mask: GLuint, transformType: GLenum, transformValues: const *GLfloat?)
    func glStencilStrokePathNV(path: GLuint, reference: GLint, mask: GLuint)
    func glStencilThenCoverFillPathInstancedNV(numPaths: GLsizei, pathNameType: GLenum, paths: const *void?, pathBase: GLuint, fillMode: GLenum, mask: GLuint, coverMode: GLenum, transformType: GLenum, transformValues: const *GLfloat?)
    func glStencilThenCoverFillPathNV(path: GLuint, fillMode: GLenum, mask: GLuint, coverMode: GLenum)
    func glStencilThenCoverStrokePathInstancedNV(numPaths: GLsizei, pathNameType: GLenum, paths: const *void?, pathBase: GLuint, reference: GLint, mask: GLuint, coverMode: GLenum, transformType: GLenum, transformValues: const *GLfloat?)
    func glStencilThenCoverStrokePathNV(path: GLuint, reference: GLint, mask: GLuint, coverMode: GLenum)
    func glTransformPathNV(resultPath: GLuint, srcPath: GLuint, transformType: GLenum, transformValues: const *GLfloat?)
    func glWeightPathsNV(resultPath: GLuint, numPaths: GLsizei, paths: const *GLuint?, weights: const *GLfloat?)
}

/* ------------------- GL_NV_path_rendering_shared_edge -------------------- */

const GL_NV_path_rendering_shared_edge = 1
const GL_SHARED_EDGE_NV                = 0xC0

/* --------------------- GL_NV_primitive_shading_rate ---------------------- */

const GL_NV_primitive_shading_rate           = 1
const GL_SHADING_RATE_IMAGE_PER_PRIMITIVE_NV = 0x95B1
const GL_SHADING_RATE_IMAGE_PALETTE_COUNT_NV = 0x95B2

/* ------------------ GL_NV_representative_fragment_test ------------------- */

const GL_NV_representative_fragment_test = 1
const GL_REPRESENTATIVE_FRAGMENT_TEST_NV = 0x937F

/* ------------------------ GL_NV_sample_locations ------------------------- */

const GL_NV_sample_locations                          = 1
const GL_SAMPLE_LOCATION_SUBPIXEL_BITS_NV             = 0x933D
const GL_SAMPLE_LOCATION_PIXEL_GRID_WIDTH_NV          = 0x933E
const GL_SAMPLE_LOCATION_PIXEL_GRID_HEIGHT_NV         = 0x933F
const GL_PROGRAMMABLE_SAMPLE_LOCATION_TABLE_SIZE_NV   = 0x9340
const GL_SAMPLE_LOCATION_NV                           = 0x8E50
const GL_PROGRAMMABLE_SAMPLE_LOCATION_NV              = 0x9341
const GL_FRAMEBUFFER_PROGRAMMABLE_SAMPLE_LOCATIONS_NV = 0x9342
const GL_FRAMEBUFFER_SAMPLE_LOCATION_PIXEL_GRID_NV    = 0x9343

#[Extension, Swag.PlaceHolder]
{
    func glFramebufferSampleLocationsfvNV(target: GLenum, start: GLuint, count: GLsizei, v: const *GLfloat?)
    func glNamedFramebufferSampleLocationsfvNV(framebuffer: GLuint, start: GLuint, count: GLsizei, v: const *GLfloat?)
    func glResolveDepthValuesNV()
}

/* ------------------ GL_NV_sample_mask_override_coverage ------------------ */

const GL_NV_sample_mask_override_coverage = 1

/* ------------------------ GL_NV_scissor_exclusive ------------------------ */

const GL_NV_scissor_exclusive      = 1
const GL_SCISSOR_TEST_EXCLUSIVE_NV = 0x9555
const GL_SCISSOR_BOX_EXCLUSIVE_NV  = 0x9556

#[Extension, Swag.PlaceHolder]
{
    func glScissorExclusiveArrayvNV(first: GLuint, count: GLsizei, v: const *GLint?)
    func glScissorExclusiveNV(x: GLint, y: GLint, width: GLsizei, height: GLsizei)
}

/* --------------------- GL_NV_shader_atomic_counters ---------------------- */

const GL_NV_shader_atomic_counters = 1

/* ----------------------- GL_NV_shader_atomic_float ----------------------- */

const GL_NV_shader_atomic_float = 1

/* ---------------------- GL_NV_shader_atomic_float64 ---------------------- */

const GL_NV_shader_atomic_float64 = 1

/* -------------------- GL_NV_shader_atomic_fp16_vector -------------------- */

const GL_NV_shader_atomic_fp16_vector = 1

/* ----------------------- GL_NV_shader_atomic_int64 ----------------------- */

const GL_NV_shader_atomic_int64 = 1

/* ----------------------- GL_NV_shader_buffer_load ------------------------ */

const GL_NV_shader_buffer_load        = 1
const GL_BUFFER_GPU_ADDRESS_NV        = 0x8F1D
const GL_GPU_ADDRESS_NV               = 0x8F34
const GL_MAX_SHADER_BUFFER_ADDRESS_NV = 0x8F35

#[Extension, Swag.PlaceHolder]
{
    func glGetBufferParameterui64vNV(target: GLenum, pname: GLenum, params: *GLuint64EXT?)
    func glGetIntegerui64vNV(value: GLenum, result: *GLuint64EXT?)
    func glGetNamedBufferParameterui64vNV(buffer: GLuint, pname: GLenum, params: *GLuint64EXT?)
    func glGetUniformui64vNV(program: GLuint, location: GLint, params: *GLuint64EXT?)
    func glIsBufferResidentNV(target: GLenum)->GLboolean
    func glIsNamedBufferResidentNV(buffer: GLuint)->GLboolean
    func glMakeBufferNonResidentNV(target: GLenum)
    func glMakeBufferResidentNV(target: GLenum, access: GLenum)
    func glMakeNamedBufferNonResidentNV(buffer: GLuint)
    func glMakeNamedBufferResidentNV(buffer: GLuint, access: GLenum)
    func glProgramUniformui64NV(program: GLuint, location: GLint, value: GLuint64EXT)
    func glProgramUniformui64vNV(program: GLuint, location: GLint, count: GLsizei, value: const *GLuint64EXT?)
    func glUniformui64NV(location: GLint, value: GLuint64EXT)
    func glUniformui64vNV(location: GLint, count: GLsizei, value: const *GLuint64EXT?)
}

/* ----------------------- GL_NV_shader_buffer_store ----------------------- */

const GL_NV_shader_buffer_store              = 1
const GL_SHADER_GLOBAL_ACCESS_BARRIER_BIT_NV = 0x00000010

/* ------------------- GL_NV_shader_subgroup_partitioned ------------------- */

const GL_NV_shader_subgroup_partitioned      = 1
const GL_SUBGROUP_FEATURE_PARTITIONED_BIT_NV = 0x00000100

/* -------------------- GL_NV_shader_texture_footprint --------------------- */

const GL_NV_shader_texture_footprint = 1

/* ----------------------- GL_NV_shader_thread_group ----------------------- */

const GL_NV_shader_thread_group = 1
const GL_WARP_SIZE_NV           = 0x9339
const GL_WARPS_PER_SM_NV        = 0x933A
const GL_SM_COUNT_NV            = 0x933B

/* ---------------------- GL_NV_shader_thread_shuffle ---------------------- */

const GL_NV_shader_thread_shuffle = 1

/* ----------------------- GL_NV_shading_rate_image ------------------------ */

const GL_NV_shading_rate_image                       = 1
const GL_SHADING_RATE_IMAGE_NV                       = 0x9563
const GL_SHADING_RATE_NO_INVOCATIONS_NV              = 0x9564
const GL_SHADING_RATE_1_INVOCATION_PER_PIXEL_NV      = 0x9565
const GL_SHADING_RATE_1_INVOCATION_PER_1X2_PIXELS_NV = 0x9566
const GL_SHADING_RATE_1_INVOCATION_PER_2X1_PIXELS_NV = 0x9567
const GL_SHADING_RATE_1_INVOCATION_PER_2X2_PIXELS_NV = 0x9568
const GL_SHADING_RATE_1_INVOCATION_PER_2X4_PIXELS_NV = 0x9569
const GL_SHADING_RATE_1_INVOCATION_PER_4X2_PIXELS_NV = 0x956A
const GL_SHADING_RATE_1_INVOCATION_PER_4X4_PIXELS_NV = 0x956B
const GL_SHADING_RATE_2_INVOCATIONS_PER_PIXEL_NV     = 0x956C
const GL_SHADING_RATE_4_INVOCATIONS_PER_PIXEL_NV     = 0x956D
const GL_SHADING_RATE_8_INVOCATIONS_PER_PIXEL_NV     = 0x956E
const GL_SHADING_RATE_16_INVOCATIONS_PER_PIXEL_NV    = 0x956F
const GL_SHADING_RATE_IMAGE_BINDING_NV               = 0x955B
const GL_SHADING_RATE_IMAGE_TEXEL_WIDTH_NV           = 0x955C
const GL_SHADING_RATE_IMAGE_TEXEL_HEIGHT_NV          = 0x955D
const GL_SHADING_RATE_IMAGE_PALETTE_SIZE_NV          = 0x955E
const GL_MAX_COARSE_FRAGMENT_SAMPLES_NV              = 0x955F
const GL_SHADING_RATE_SAMPLE_ORDER_DEFAULT_NV        = 0x95AE
const GL_SHADING_RATE_SAMPLE_ORDER_PIXEL_MAJOR_NV    = 0x95AF
const GL_SHADING_RATE_SAMPLE_ORDER_SAMPLE_MAJOR_NV   = 0x95B0

#[Extension, Swag.PlaceHolder]
{
    func glBindShadingRateImageNV(texture: GLuint)
    func glGetShadingRateImagePaletteNV(viewport: GLuint, entry: GLuint, rate: *GLenum?)
    func glGetShadingRateSampleLocationivNV(rate: GLenum, samples: GLuint, index: GLuint, location: *GLint?)
    func glShadingRateImageBarrierNV(synchronize: GLboolean)
    func glShadingRateImagePaletteNV(viewport: GLuint, first: GLuint, count: GLsizei, rates: const *GLenum?)
    func glShadingRateSampleOrderCustomNV(rate: GLenum, samples: GLuint, locations: const *GLint?)
    func glShadingRateSampleOrderNV(order: GLenum)
}

/* ---------------------- GL_NV_stereo_view_rendering ---------------------- */

const GL_NV_stereo_view_rendering = 1

/* ------------------------- GL_NV_texture_barrier ------------------------- */

const GL_NV_texture_barrier = 1

#[Extension, Swag.PlaceHolder]
{
    func glTextureBarrierNV()
}

/* ------------------ GL_NV_texture_rectangle_compressed ------------------- */

const GL_NV_texture_rectangle_compressed = 1

/* ------------------ GL_NV_uniform_buffer_std430_layout ------------------- */

const GL_NV_uniform_buffer_std430_layout = 1

/* ------------------ GL_NV_uniform_buffer_unified_memory ------------------ */

const GL_NV_uniform_buffer_unified_memory = 1
const GL_UNIFORM_BUFFER_UNIFIED_NV        = 0x936E
const GL_UNIFORM_BUFFER_ADDRESS_NV        = 0x936F
const GL_UNIFORM_BUFFER_LENGTH_NV         = 0x9370

/* ------------------- GL_NV_vertex_attrib_integer_64bit ------------------- */

const GL_NV_vertex_attrib_integer_64bit = 1

#[Extension, Swag.PlaceHolder]
{
    func glGetVertexAttribLi64vNV(index: GLuint, pname: GLenum, params: *GLint64EXT?)
    func glGetVertexAttribLui64vNV(index: GLuint, pname: GLenum, params: *GLuint64EXT?)
    func glVertexAttribL1i64NV(index: GLuint, x: GLint64EXT)
    func glVertexAttribL1i64vNV(index: GLuint, v: const *GLint64EXT?)
    func glVertexAttribL1ui64NV(index: GLuint, x: GLuint64EXT)
    func glVertexAttribL1ui64vNV(index: GLuint, v: const *GLuint64EXT?)
    func glVertexAttribL2i64NV(index: GLuint, x: GLint64EXT, y: GLint64EXT)
    func glVertexAttribL2i64vNV(index: GLuint, v: const *GLint64EXT?)
    func glVertexAttribL2ui64NV(index: GLuint, x: GLuint64EXT, y: GLuint64EXT)
    func glVertexAttribL2ui64vNV(index: GLuint, v: const *GLuint64EXT?)
    func glVertexAttribL3i64NV(index: GLuint, x: GLint64EXT, y: GLint64EXT, z: GLint64EXT)
    func glVertexAttribL3i64vNV(index: GLuint, v: const *GLint64EXT?)
    func glVertexAttribL3ui64NV(index: GLuint, x: GLuint64EXT, y: GLuint64EXT, z: GLuint64EXT)
    func glVertexAttribL3ui64vNV(index: GLuint, v: const *GLuint64EXT?)
    func glVertexAttribL4i64NV(index: GLuint, x: GLint64EXT, y: GLint64EXT, z: GLint64EXT, w: GLint64EXT)
    func glVertexAttribL4i64vNV(index: GLuint, v: const *GLint64EXT?)
    func glVertexAttribL4ui64NV(index: GLuint, x: GLuint64EXT, y: GLuint64EXT, z: GLuint64EXT, w: GLuint64EXT)
    func glVertexAttribL4ui64vNV(index: GLuint, v: const *GLuint64EXT?)
    func glVertexAttribLFormatNV(index: GLuint, size: GLint, type: GLenum, stride: GLsizei)
}

/* ------------------ GL_NV_vertex_buffer_unified_memory ------------------- */

const GL_NV_vertex_buffer_unified_memory  = 1
const GL_VERTEX_ATTRIB_ARRAY_UNIFIED_NV   = 0x8F1E
const GL_ELEMENT_ARRAY_UNIFIED_NV         = 0x8F1F
const GL_VERTEX_ATTRIB_ARRAY_ADDRESS_NV   = 0x8F20
const GL_VERTEX_ARRAY_ADDRESS_NV          = 0x8F21
const GL_NORMAL_ARRAY_ADDRESS_NV          = 0x8F22
const GL_COLOR_ARRAY_ADDRESS_NV           = 0x8F23
const GL_INDEX_ARRAY_ADDRESS_NV           = 0x8F24
const GL_TEXTURE_COORD_ARRAY_ADDRESS_NV   = 0x8F25
const GL_EDGE_FLAG_ARRAY_ADDRESS_NV       = 0x8F26
const GL_SECONDARY_COLOR_ARRAY_ADDRESS_NV = 0x8F27
const GL_FOG_COORD_ARRAY_ADDRESS_NV       = 0x8F28
const GL_ELEMENT_ARRAY_ADDRESS_NV         = 0x8F29
const GL_VERTEX_ATTRIB_ARRAY_LENGTH_NV    = 0x8F2A
const GL_VERTEX_ARRAY_LENGTH_NV           = 0x8F2B
const GL_NORMAL_ARRAY_LENGTH_NV           = 0x8F2C
const GL_COLOR_ARRAY_LENGTH_NV            = 0x8F2D
const GL_INDEX_ARRAY_LENGTH_NV            = 0x8F2E
const GL_TEXTURE_COORD_ARRAY_LENGTH_NV    = 0x8F2F
const GL_EDGE_FLAG_ARRAY_LENGTH_NV        = 0x8F30
const GL_SECONDARY_COLOR_ARRAY_LENGTH_NV  = 0x8F31
const GL_FOG_COORD_ARRAY_LENGTH_NV        = 0x8F32
const GL_ELEMENT_ARRAY_LENGTH_NV          = 0x8F33
const GL_DRAW_INDIRECT_UNIFIED_NV         = 0x8F40
const GL_DRAW_INDIRECT_ADDRESS_NV         = 0x8F41
const GL_DRAW_INDIRECT_LENGTH_NV          = 0x8F42

#[Extension, Swag.PlaceHolder]
{
    func glBufferAddressRangeNV(pname: GLenum, index: GLuint, address: GLuint64EXT, length: GLsizeiptr)
    func glColorFormatNV(size: GLint, type: GLenum, stride: GLsizei)
    func glEdgeFlagFormatNV(stride: GLsizei)
    func glFogCoordFormatNV(type: GLenum, stride: GLsizei)
    func glGetIntegerui64i_vNV(value: GLenum, index: GLuint, result: *GLuint64EXT?)
    func glIndexFormatNV(type: GLenum, stride: GLsizei)
    func glNormalFormatNV(type: GLenum, stride: GLsizei)
    func glSecondaryColorFormatNV(size: GLint, type: GLenum, stride: GLsizei)
    func glTexCoordFormatNV(size: GLint, type: GLenum, stride: GLsizei)
    func glVertexAttribFormatNV(index: GLuint, size: GLint, type: GLenum, normalized: GLboolean, stride: GLsizei)
    func glVertexAttribIFormatNV(index: GLuint, size: GLint, type: GLenum, stride: GLsizei)
    func glVertexFormatNV(size: GLint, type: GLenum, stride: GLsizei)
}

/* ------------------------- GL_NV_viewport_array2 ------------------------- */

const GL_NV_viewport_array2 = 1

/* ------------------------ GL_NV_viewport_swizzle ------------------------- */

const GL_NV_viewport_swizzle            = 1
const GL_VIEWPORT_SWIZZLE_POSITIVE_X_NV = 0x9350
const GL_VIEWPORT_SWIZZLE_NEGATIVE_X_NV = 0x9351
const GL_VIEWPORT_SWIZZLE_POSITIVE_Y_NV = 0x9352
const GL_VIEWPORT_SWIZZLE_NEGATIVE_Y_NV = 0x9353
const GL_VIEWPORT_SWIZZLE_POSITIVE_Z_NV = 0x9354
const GL_VIEWPORT_SWIZZLE_NEGATIVE_Z_NV = 0x9355
const GL_VIEWPORT_SWIZZLE_POSITIVE_W_NV = 0x9356
const GL_VIEWPORT_SWIZZLE_NEGATIVE_W_NV = 0x9357
const GL_VIEWPORT_SWIZZLE_X_NV          = 0x9358
const GL_VIEWPORT_SWIZZLE_Y_NV          = 0x9359
const GL_VIEWPORT_SWIZZLE_Z_NV          = 0x935A
const GL_VIEWPORT_SWIZZLE_W_NV          = 0x935B

#[Extension, Swag.PlaceHolder]
{
    func glViewportSwizzleNV(index: GLuint, swizzlex: GLenum, swizzley: GLenum, swizzlez: GLenum, swizzlew: GLenum)
}
