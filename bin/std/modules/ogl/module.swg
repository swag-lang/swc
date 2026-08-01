/*
Ogl exposes the canonical OpenGL and WGL binding surface used by Swag's Pixel
renderer and by applications that issue OpenGL commands directly.

Call [[Ogl.glInitExtensions]] only after making a rendering context current.
OpenGL 1.1 entry points come from the platform library; later core and extension
entry points are resolved from that current context. Raw `gl*` names, `GL_*`
constants, scalar widths, and pointer shapes follow the pinned Khronos registry.

On Windows, [[Ogl.Platform.Win32.createContext]] provides an owned context for
an [[Core.Env.Window]]. Destroy it before destroying its window.
*/

#import("core")
#static if #os == Swag.TargetOs.Windows
{
    #import("win32")
    #import("gdi32")
}

#run
{
    let itf = @compiler
    let cfg = notnull itf.getBuildCfg()
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
