#global public

using Swag

/* ----------------------- GL_INTEL_blackhole_render ----------------------- */

const GL_INTEL_blackhole_render = 1
const GL_BLACKHOLE_RENDER_INTEL = 0x83FC

/* ------------------ GL_INTEL_conservative_rasterization ------------------ */

const GL_INTEL_conservative_rasterization = 1
const GL_CONSERVATIVE_RASTERIZATION_INTEL = 0x83FE

/* ----------------------- GL_INTEL_framebuffer_CMAA ----------------------- */

const GL_INTEL_framebuffer_CMAA = 1

#[Extension, Swag.PlaceHolder]
{
    func glApplyFramebufferAttachmentCMAAINTEL()
}

/* ---------------------- GL_INTEL_performance_query ----------------------- */

const GL_INTEL_performance_query                 = 1
const GL_PERFQUERY_SINGLE_CONTEXT_INTEL          = 0x00000000
const GL_PERFQUERY_GLOBAL_CONTEXT_INTEL          = 0x00000001
const GL_PERFQUERY_WAIT_INTEL                    = 0x83FB
const GL_PERFQUERY_FLUSH_INTEL                   = 0x83FA
const GL_PERFQUERY_DONOT_FLUSH_INTEL             = 0x83F9
const GL_PERFQUERY_COUNTER_EVENT_INTEL           = 0x94F0
const GL_PERFQUERY_COUNTER_DURATION_NORM_INTEL   = 0x94F1
const GL_PERFQUERY_COUNTER_DURATION_RAW_INTEL    = 0x94F2
const GL_PERFQUERY_COUNTER_THROUGHPUT_INTEL      = 0x94F3
const GL_PERFQUERY_COUNTER_RAW_INTEL             = 0x94F4
const GL_PERFQUERY_COUNTER_TIMESTAMP_INTEL       = 0x94F5
const GL_PERFQUERY_COUNTER_DATA_UINT32_INTEL     = 0x94F8
const GL_PERFQUERY_COUNTER_DATA_UINT64_INTEL     = 0x94F9
const GL_PERFQUERY_COUNTER_DATA_FLOAT_INTEL      = 0x94FA
const GL_PERFQUERY_COUNTER_DATA_DOUBLE_INTEL     = 0x94FB
const GL_PERFQUERY_COUNTER_DATA_BOOL32_INTEL     = 0x94FC
const GL_PERFQUERY_QUERY_NAME_LENGTH_MAX_INTEL   = 0x94FD
const GL_PERFQUERY_COUNTER_NAME_LENGTH_MAX_INTEL = 0x94FE
const GL_PERFQUERY_COUNTER_DESC_LENGTH_MAX_INTEL = 0x94FF
const GL_PERFQUERY_GPA_EXTENDED_COUNTERS_INTEL   = 0x9500

#[Extension, Swag.PlaceHolder]
{
    func glBeginPerfQueryINTEL(queryHandle: GLuint)
    func glCreatePerfQueryINTEL(queryId: GLuint, queryHandle: #null *GLuint)
    func glDeletePerfQueryINTEL(queryHandle: GLuint)
    func glEndPerfQueryINTEL(queryHandle: GLuint)
    func glGetFirstPerfQueryIdINTEL(queryId: #null *GLuint)
    func glGetNextPerfQueryIdINTEL(queryId: GLuint, nextQueryId: #null *GLuint)
    func glGetPerfCounterInfoINTEL(queryId: GLuint, counterId: GLuint, counterNameLength: GLuint, counterName: #null *GLchar, counterDescLength: GLuint, counterDesc: #null *GLchar, counterOffset: #null *GLuint, counterDataSize: #null *GLuint, counterTypeEnum: #null *GLuint, counterDataTypeEnum: #null *GLuint, rawCounterMaxValue: #null *GLuint64)
    func glGetPerfQueryDataINTEL(queryHandle: GLuint, flags: GLuint, dataSize: GLsizei, data: #null *void, bytesWritten: #null *GLuint)
    func glGetPerfQueryIdByNameINTEL(queryName: #null *GLchar, queryId: #null *GLuint)
    func glGetPerfQueryInfoINTEL(queryId: GLuint, queryNameLength: GLuint, queryName: #null *GLchar, dataSize: #null *GLuint, noCounters: #null *GLuint, noInstances: #null *GLuint, capsMask: #null *GLuint)
}
