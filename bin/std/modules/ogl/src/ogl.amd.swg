#global public

using Swag

/* ---------------- GL_AMD_framebuffer_multisample_advanced ---------------- */

const GL_AMD_framebuffer_multisample_advanced      = 1
const GL_RENDERBUFFER_STORAGE_SAMPLES_AMD          = 0x91B2
const GL_MAX_COLOR_FRAMEBUFFER_SAMPLES_AMD         = 0x91B3
const GL_MAX_COLOR_FRAMEBUFFER_STORAGE_SAMPLES_AMD = 0x91B4
const GL_MAX_DEPTH_STENCIL_FRAMEBUFFER_SAMPLES_AMD = 0x91B5
const GL_NUM_SUPPORTED_MULTISAMPLE_MODES_AMD       = 0x91B6
const GL_SUPPORTED_MULTISAMPLE_MODES_AMD           = 0x91B7

#[Extension, Swag.PlaceHolder]
{
    func glNamedRenderbufferStorageMultisampleAdvancedAMD(renderbuffer: GLuint, samples: GLsizei, storageSamples: GLsizei, internalformat: GLenum, width: GLsizei, height: GLsizei)
    func glRenderbufferStorageMultisampleAdvancedAMD(target: GLenum, samples: GLsizei, storageSamples: GLsizei, internalformat: GLenum, width: GLsizei, height: GLsizei)
}

/* ---------------------- GL_AMD_performance_monitor ----------------------- */

const GL_AMD_performance_monitor      = 1
const GL_COUNTER_TYPE_AMD             = 0x8BC0
const GL_COUNTER_RANGE_AMD            = 0x8BC1
const GL_UNSIGNED_INT64_AMD           = 0x8BC2
const GL_PERCENTAGE_AMD               = 0x8BC3
const GL_PERFMON_RESULT_AVAILABLE_AMD = 0x8BC4
const GL_PERFMON_RESULT_SIZE_AMD      = 0x8BC5
const GL_PERFMON_RESULT_AMD           = 0x8BC6

#[Extension, Swag.PlaceHolder]
{
    func glBeginPerfMonitorAMD(monitor: GLuint)
    func glDeletePerfMonitorsAMD(n: GLsizei, monitors: *GLuint?)
    func glEndPerfMonitorAMD(monitor: GLuint)
    func glGenPerfMonitorsAMD(n: GLsizei, monitors: *GLuint?)
    func glGetPerfMonitorCounterDataAMD(monitor: GLuint, pname: GLenum, dataSize: GLsizei, data: *GLuint?, bytesWritten: *GLint?)
    func glGetPerfMonitorCounterInfoAMD(group: GLuint, counter: GLuint, pname: GLenum, data: *void?)
    func glGetPerfMonitorCounterStringAMD(group: GLuint, counter: GLuint, bufSize: GLsizei, length: *GLsizei?, counterString: *GLchar?)
    func glGetPerfMonitorCountersAMD(group: GLuint, numCounters: *GLint?, maxActiveCounters: *GLint?, counterSize: GLsizei, counters: *GLuint?)
    func glGetPerfMonitorGroupStringAMD(group: GLuint, bufSize: GLsizei, length: *GLsizei?, groupString: *GLchar?)
    func glGetPerfMonitorGroupsAMD(numGroups: *GLint?, groupsSize: GLsizei, groups: *GLuint?)
    func glSelectPerfMonitorCountersAMD(monitor: GLuint, enable: GLboolean, group: GLuint, numCounters: GLint, counterList: *GLuint?)
}
