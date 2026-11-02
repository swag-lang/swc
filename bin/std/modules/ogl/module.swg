/*
Ogl exposes the canonical OpenGL binding surface used by Swag's Pixel
renderer and by applications that issue OpenGL commands directly.

Call [[Ogl.glInitExtensions]] only after making a rendering context current.
OpenGL 1.1 entry points come from the platform library; later core and extension
entry points are resolved from that current context. Raw `gl*` names, `GL_*`
constants, scalar widths, and pointer shapes follow the pinned Khronos registry.

On Windows, `Ogl.Platform.Win32.createContext` provides an owned WGL context.
On Linux, `Ogl.Platform.Xcb.createContext` provides an owned EGL OpenGL 3.3
compatibility context for an X11 window. Both initially own a rendering surface that borrows
a [[Core.Env.Window]]; destroy that surface before its window. The Linux adapter needs
libGL.so.1, libEGL.so.1 and EGL_EXT_platform_xcb. Linux renderers can use `Context.takeSurface` and
`Context.createSurface` to own several window surfaces independently while sharing one context.
Each surface must be destroyed before its window and before the context. A drawable borrowed
on the UI thread can be passed to `createContextForDrawable` on the rendering thread.
For offscreen GPU rendering, `Ogl.Platform.Egl.createOffscreenContext` creates an EGL pbuffer
without an X11 connection. It requires EGL_MESA_platform_surfaceless. `Platform.Egl.Context`
and `Surface` alias the existing EGL owners in `Platform.Xcb`; `Context.createPbufferSurface`
creates another pbuffer on the same display, including a compatible window context's display.
No CPU fallback is selected. Native Wayland contexts are not provided.
*/

#import("core")
#static if #os == Swag.TargetOs.Windows
{
    #import("win32")
    #import("gdi32")
}

#static if #os == Swag.TargetOs.Linux
{
    #import("linux")
}

#run
{
    let itf = Swag.compiler()
    let cfg = unwrap itf.getBuildCfg()
    cfg.moduleVersion   = #swcversion
    cfg.moduleRevision  = #swcrevision
    cfg.moduleBuildNum  = #swcbuildnum
    cfg.moduleNamespace = "Ogl"
    cfg.backendKind     = .SharedLibrary
    cfg.repoPath        = "https://github.com/swag-lang/swc/blob/master/bin/std/modules/ogl"

    cfg.genDoc.kind       = .Api
    cfg.genDoc.outputName = "std.ogl"
    cfg.genDoc.icon       = "favicon.svg"
    cfg.genDoc.css        = "css/style.css"
}
