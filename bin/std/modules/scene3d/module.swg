/*
Scene3d loads bounded triangle scenes from common local model formats. Use
[[Scene3d.Scene.decodableFormats]] to build a file filter and
[[Scene3d.Scene.canLoad]] to check an extension or [[Scene3d.canDecode]] to probe a complete
buffer. Binary STL has no distinct signature, so a header-only probe cannot identify it without
the `.stl` extension.

[[Scene3d.Scene]] owns its nodes, meshes, materials, vertices and triangles. The
initial codecs read OBJ geometry and ASCII or binary STL; they do not execute
scripts, follow external paths, or require a renderer. Coordinates retain the
units and handedness declared by the source file.

```swag
#import("scene3d")

using Scene3d

let scene = try load("model.obj")
let mesh  = &scene.meshes[0]
Console.print("% triangles", mesh.triangles.count)
```

File, syntax, unsupported-format, and resource-limit errors use Swag's `fail`
mechanism. Supply [[Scene3d.Limits]] when a caller needs tighter bounds.
*/

#import("core")

#run
{
    let itf = Swag.compiler()
    let cfg = unwrap itf.getBuildCfg()
    cfg.moduleVersion   = #swcversion
    cfg.moduleRevision  = #swcrevision
    cfg.moduleBuildNum  = #swcbuildnum
    cfg.moduleNamespace = "Scene3d"
    cfg.backendKind     = .SharedLibrary
    cfg.repoPath        = "https://github.com/swag-lang/swc/blob/master/bin/std/modules/scene3d"

    cfg.genDoc.kind         = .Api
    cfg.genDoc.outputName   = "std.scene3d"
    cfg.genDoc.titleContent = "Scene3d"
    cfg.genDoc.titleToc     = "Scene3d documentation"
}
