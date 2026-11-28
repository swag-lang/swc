#global if #os == Swag.TargetOs.Linux
#global public

// EGL 1.4 and EXT_platform_base/XCB entry points follow the Khronos EGL registry.
//
// Native calls retain their EGLBoolean/error-code contract; Core/Ogl own their resources.
alias EGLDisplay = *void?
alias EGLConfig  = *void?
alias EGLContext = *void?
alias EGLSurface = *void?
alias EGLBoolean = u32
alias EGLenum    = u32
alias EGLint     = s32

const EGL_DRAW = 0x3059_s32
const EGL_READ = 0x305A_s32

const EGL_NONE                            = 0x3038_s32
const EGL_EXTENSIONS                      = 0x3055_s32
const EGL_SURFACE_TYPE                    = 0x3033_s32
const EGL_PBUFFER_BIT                     = 0x0001_s32
const EGL_WIDTH                           = 0x3057_s32
const EGL_HEIGHT                          = 0x3056_s32
const EGL_PLATFORM_SURFACELESS_MESA       = 0x31DD_u32
const EGL_WINDOW_BIT                      = 0x0004_s32
const EGL_RENDERABLE_TYPE                 = 0x3040_s32
const EGL_OPENGL_BIT                      = 0x0008_s32
const EGL_OPENGL_API                      = 0x30A2_u32
const EGL_RED_SIZE                        = 0x3024_s32
const EGL_GREEN_SIZE                      = 0x3023_s32
const EGL_BLUE_SIZE                       = 0x3022_s32
const EGL_ALPHA_SIZE                      = 0x3021_s32
const EGL_STENCIL_SIZE                    = 0x3026_s32
const EGL_NATIVE_VISUAL_ID                = 0x302E_s32
const EGL_CONTEXT_MAJOR_VERSION_KHR       = 0x3098_s32
const EGL_CONTEXT_MINOR_VERSION_KHR       = 0x30FB_s32
const EGL_CONTEXT_OPENGL_PROFILE_MASK_KHR = 0x30FD_s32
const EGL_CONTEXT_OPENGL_COMPATIBILITY_PROFILE_BIT_KHR = 0x0002_s32
const EGL_PLATFORM_XCB_EXT                = 0x31DC_u32
const EGL_PLATFORM_XCB_SCREEN_EXT         = 0x31DE_s32

#[Swag.CallingConvention(.C)]
alias eglGetPlatformDisplayEXT_fn = func(EGLenum, *void?, const *EGLint?)->EGLDisplay
#[Swag.CallingConvention(.C)]
alias eglCreatePlatformWindowSurfaceEXT_fn = func(EGLDisplay, EGLConfig, *void?, const *EGLint?)->EGLSurface

#[Swag.Foreign(module: "libEGL.so.1", link: "libEGL.so.1", callconv: .C)]
{
    func eglGetError()->EGLint
    func eglQueryString(display: EGLDisplay, name: EGLint)->const [*]u8?
    func eglGetProcAddress(name: const [*]u8)->const *void?
    func eglInitialize(display: EGLDisplay, major: *EGLint?, minor: *EGLint?)->EGLBoolean
    func eglTerminate(display: EGLDisplay)->EGLBoolean
    func eglBindAPI(api: EGLenum)->EGLBoolean
    func eglQueryAPI()->EGLenum
    func eglChooseConfig(display: EGLDisplay, attributes: const *EGLint?, configs: *EGLConfig?, size: EGLint, count: *EGLint)->EGLBoolean
    func eglGetConfigAttrib(display: EGLDisplay, config: EGLConfig, attribute: EGLint, value: *EGLint)->EGLBoolean
    func eglCreatePbufferSurface(display: EGLDisplay, config: EGLConfig, attributes: const *EGLint?)->EGLSurface
    func eglCreateContext(display: EGLDisplay, config: EGLConfig, shared: EGLContext, attributes: const *EGLint?)->EGLContext
    func eglDestroyContext(display: EGLDisplay, context: EGLContext)->EGLBoolean
    func eglDestroySurface(display: EGLDisplay, surface: EGLSurface)->EGLBoolean
    func eglMakeCurrent(display: EGLDisplay, draw: EGLSurface, read: EGLSurface, context: EGLContext)->EGLBoolean
    func eglGetCurrentContext()->EGLContext
    func eglGetCurrentDisplay()->EGLDisplay
    func eglGetCurrentSurface(which: EGLint)->EGLSurface
    func eglSwapBuffers(display: EGLDisplay, surface: EGLSurface)->EGLBoolean
    func eglSwapInterval(display: EGLDisplay, interval: EGLint)->EGLBoolean
}
