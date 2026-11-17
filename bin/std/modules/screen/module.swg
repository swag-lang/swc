/*
Screen acquires live desktop pixels independently of GUI event handling. A [[Screen.Source]]
captures one area in physical desktop pixels and writes bottom-up BGRA8 into a reusable
[[Pixel.Image]]. The source owns its native handles; callers own the returned image.

```swag
#import("screen")
using Screen

var source = try Source.open(SourceOptions{0, 0, 1920, 1080})
var frame: Pixel.Image
discard try source.grabInto(&frame)
```

A source can report a temporary absence of a newer desktop frame. Its last frame remains
available for a constant-rate recording. Native source loss is reported through `fail` and
the caller may reopen it after a display change.
*/

#import("core")
#import("pixel")
#static if #os == Swag.TargetOs.Windows do
    #import("win32")
#static if #os == Swag.TargetOs.Linux do
    #import("linux")

#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.moduleVersion   = #swcversion
    cfg.moduleRevision  = #swcrevision
    cfg.moduleBuildNum  = #swcbuildnum
    cfg.moduleNamespace = "Screen"
    cfg.backendKind     = .SharedLibrary
    cfg.repoPath        = "https://github.com/swag-lang/swc/blob/master/bin/std/modules/screen"

    cfg.genDoc.kind         = .Api
    cfg.genDoc.outputName   = "std.screen"
    cfg.genDoc.titleContent = "Screen"
    cfg.genDoc.titleToc     = "Screen documentation"
    cfg.genDoc.icon         = "favicon.svg"
    cfg.genDoc.css          = "css/style.css"
}
