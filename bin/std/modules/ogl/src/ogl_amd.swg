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
    func glDeletePerfMonitorsAMD(n: GLsizei, monitors: #null *GLuint)
    func glEndPerfMonitorAMD(monitor: GLuint)
    func glGenPerfMonitorsAMD(n: GLsizei, monitors: #null *GLuint)
    func glGetPerfMonitorCounterDataAMD(monitor: GLuint, pname: GLenum, dataSize: GLsizei, data: #null *GLuint, bytesWritten: #null *GLint)
    func glGetPerfMonitorCounterInfoAMD(group: GLuint, counter: GLuint, pname: GLenum, data: #null *void)
    func glGetPerfMonitorCounterStringAMD(group: GLuint, counter: GLuint, bufSize: GLsizei, length: #null *GLsizei, counterString: #null *GLchar)
    func glGetPerfMonitorCountersAMD(group: GLuint, numCounters: #null *GLint, maxActiveCounters: #null *GLint, counterSize: GLsizei, counters: #null *GLuint)
    func glGetPerfMonitorGroupStringAMD(group: GLuint, bufSize: GLsizei, length: #null *GLsizei, groupString: #null *GLchar)
    func glGetPerfMonitorGroupsAMD(numGroups: #null *GLint, groupsSize: GLsizei, groups: #null *GLuint)
    func glSelectPerfMonitorCountersAMD(monitor: GLuint, enable: GLboolean, group: GLuint, numCounters: GLint, counterList: #null *GLuint)
}
