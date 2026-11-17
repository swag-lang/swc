#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Core.Errors

#test
{
    let formats = Scene.decodableFormats()
    Swag.require(formats.count == 2)
    Swag.require(formats[0].extensions == ".obj" and formats[1].extensions == ".stl")
    Swag.require(Scene.canLoad("mesh.OBJ") and Scene.canLoad("mesh.stl"))
    Swag.require(not Scene.canLoad("mesh.glb"))
    Swag.require(canDecode("mesh.data", cast(const [..] u8, "v 0 0 0\nf 1 2 3\n")))
    Swag.require(canDecode("solid.data", cast(const [..] u8, "solid part\nfacet normal 0 0 1\nvertex 0 0 0\n")))
    Swag.require(not canDecode("notes.txt", cast(const [..] u8, "v is a letter\nsolid is a word\n")))
}

#test
{
    let source = "v 1000 1000 1000\nv -1 -1 -1\nv 1 -1 -1\nv 0 1 -1\nv 0 0 1\nvt 0 0\nvt 1 0\nvn 0 0 1\nusemtl ceramic\nf -4/1 -2//1 -3/2/1 -1 # tetra side\n"
    let scene = expect decode("tetra.obj", cast(const [..] u8, source))
    Swag.require(scene.meshes.count == 1 and scene.nodes.count == 1)
    Swag.require(scene.meshes[0].triangles.count == 2 and scene.meshes[0].vertices.count == 6)
    Swag.require(scene.materials.count == 2 and scene.materials[1].name == "ceramic")
    Swag.require(scene.bounds.min.x == -1 and scene.bounds.max.y == 1 and scene.bounds.max.z == 1)
    Swag.require(scene.meshes[0].triangles[0].materialIndex == 1)
}

#test
{
    var bounds: Bounds
    expect bounds.include(Math.Vector3{-2, 3, 4})
    expect bounds.include(Math.Vector3{5, -1, 2})
    Swag.require(not bounds.isEmpty)
    Swag.require(bounds.min.x == -2 and bounds.min.y == -1 and bounds.max.x == 5 and bounds.max.z == 4)
}

#test
{
    let source = "solid sample\n facet normal 0 0 1\n  outer loop\n   vertex 0 0 0\n   vertex 1 0 0\n   vertex 0 1 0\n  endloop\n endfacet\nendsolid sample\n"
    let scene = expect decode("triangle.stl", cast(const [..] u8, source))
    Swag.require(scene.meshes[0].triangles.count == 1 and scene.meshes[0].vertices.count == 3)
    Swag.require(scene.meshes[0].vertices[0].hasNormal)
    Swag.require(scene.meshes[0].bounds.max.x == 1 and scene.meshes[0].bounds.max.y == 1)
}

private func scene3dPutU32(bytes: *Array'u8, at: u64, value: u32)
{
    bytes[at]     = cast(u8, value & 0xFF)
    bytes[at + 1] = cast(u8, (value >> 8) & 0xFF)
    bytes[at + 2] = cast(u8, (value >> 16) & 0xFF)
    bytes[at + 3] = cast(u8, value >> 24)
}

private func scene3dPutF32(bytes: *Array'u8, at: u64, value: f32) => scene3dPutU32(bytes, at, cast #bit (u32, value))

#test
{
    var bytes: Array'u8
    bytes.resize(134)
    scene3dPutU32(&bytes, 80, 1)
    scene3dPutF32(&bytes, 84, 0)
    scene3dPutF32(&bytes, 88, 0)
    scene3dPutF32(&bytes, 92, 1)
    scene3dPutF32(&bytes, 96, 0)
    scene3dPutF32(&bytes, 100, 0)
    scene3dPutF32(&bytes, 104, 0)
    scene3dPutF32(&bytes, 108, 1)
    scene3dPutF32(&bytes, 112, 0)
    scene3dPutF32(&bytes, 116, 0)
    scene3dPutF32(&bytes, 120, 1)
    scene3dPutF32(&bytes, 124, 0)

    Swag.require(canDecode("solid-header.mesh", bytes.toSlice()))
    let scene = expect decode("solid-header.stl", bytes.toSlice())
    Swag.require(scene.meshes[0].triangles.count == 1 and scene.meshes[0].vertices.count == 3)
    Swag.require(scene.meshes[0].vertices[0].normal.z == 1)
}

#test
{
    let bytes: [24] u8 = [
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    var limits: Limits
    limits.maxInputBytes = 8
    var sizeError: Swag.Error
    discard catch decode("unknown.mesh", cast(const [..] u8, bytes), limits) as sizeError
    Swag.require(sizeError.value() is Errors.UnsupportedFormatError)

    let damaged = "solid bad\n facet normal 0 0 1\n  outer loop\n   vertex 0 0 0\n  endloop\n endfacet\nendsolid bad\n"
    var syntaxError: Swag.Error
    discard catch decode("damaged.stl", cast(const [..] u8, damaged)) as syntaxError
    Swag.require(syntaxError.value() is Errors.InvalidFormatError)

    let invalidIndex = "v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 4\n"
    var indexError: Swag.Error
    discard catch decode("bad-index.obj", cast(const [..] u8, invalidIndex)) as indexError
    Swag.require(indexError.value() is Errors.InvalidFormatError)

    var triangleLimits: Limits
    triangleLimits.maxTriangles = 1
    let quad = "v 0 0 0\nv 1 0 0\nv 1 1 0\nv 0 1 0\nf 1 2 3 4\n"
    var triangleError: Swag.Error
    discard catch decode("large-face.obj", cast(const [..] u8, quad), triangleLimits) as triangleError
    Swag.require(triangleError.value() is Errors.UnsupportedFormatError)

    var vertexLimits: Limits
    vertexLimits.maxVertices = 2
    let tooManyVertices = "v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n"
    var vertexError: Swag.Error
    discard catch decode("many-vertices.obj", cast(const [..] u8, tooManyVertices), vertexLimits) as vertexError
    Swag.require(vertexError.value() is Errors.UnsupportedFormatError)
}
