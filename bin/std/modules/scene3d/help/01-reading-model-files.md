# Reading model files

Use `Scene.decodableFormats` to build a file filter and `Scene.canLoad` to check whether an
extension is listed. Use `load` to open a local model or `decode` when the caller already owns its
bytes. Both select OBJ or STL from a known extension and recognizable content. Pass a `Limits` value to lower the
default byte, vertex, triangle, node, or material ceilings for untrusted files.

The first OBJ codec keeps position, normal, texture-coordinate, and `usemtl` assignments. It does
not open `mtllib` files or resolve texture paths. STL ASCII and binary facets become triangle
meshes; the binary codec requires the declared facet records to fill the file exactly. Both
formats produce an identity root node and opaque-white material records where the file does not
provide material appearance.

```swag
#import("scene3d")

using Scene3d

var limits: Limits
limits.maxInputBytes = 8 * 1024 * 1024
let scene = try load("model.stl", limits)
for mesh in scene.meshes do
    Console.print("% triangles", mesh.triangles.count)
```

The returned scene owns its arrays. The decoder does not retain the input byte slice.
