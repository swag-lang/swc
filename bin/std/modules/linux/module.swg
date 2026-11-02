/*
Raw GNU/Linux x86-64 bindings for standard-library host backends.

Names, return values and errno follow the native interfaces documented by the
[Linux man-pages project](https://www.kernel.org/doc/man-pages/). Calls do not
translate errors or take ownership on behalf of their caller. Core supplies the
portable resource owners and error contracts. EGL declarations follow the
[Khronos EGL registry](https://registry.khronos.org/EGL/); Ogl owns its rendering contexts.
*/
#run
{
    let itf = Swag.compiler()
    let cfg = unwrap itf.getBuildCfg()
    cfg.moduleVersion   = #swcversion
    cfg.moduleRevision  = #swcrevision
    cfg.moduleBuildNum  = #swcbuildnum
    cfg.moduleNamespace = "Linux"
    cfg.backendKind     = .Export
    cfg.repoPath        = "https://github.com/swag-lang/swc/blob/master/bin/std/modules/linux"

    cfg.genDoc.kind       = .Api
    cfg.genDoc.outputName = "std.linux"
    cfg.genDoc.icon       = "favicon.svg"
    cfg.genDoc.css        = "css/style.css"
}
