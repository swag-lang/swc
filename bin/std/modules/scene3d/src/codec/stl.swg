#global public

using Core, Core.Errors

private func readU32(bytes: const [..] u8, at: u64)->u32
{
    return cast(u32, bytes[at]) |
           (cast(u32, bytes[at + 1]) << 8) |
           (cast(u32, bytes[at + 2]) << 16) |
           (cast(u32, bytes[at + 3]) << 24)
}

private func readF32(bytes: const [..] u8, at: u64)->f32 => cast #bit (f32, readU32(bytes, at))

private func splitStlWords(line: string)->Array'(string)
{
    var result: #returntype
    var start = 0'u64
    while start < line.count
    {
        while start < line.count and (line[start] == ' 'u8 or line[start] == '\t'u8) do
            start += 1
        if start == line.count do
            break
        var end = start
        while end < line.count and line[end] != ' 'u8 and line[end] != '\t'u8 do
            end += 1
        result.add(line[start until end])
        start = end
    }
    return result
}

private func stlVertex(bytes: const [..] u8, at: u64)->Math.Vector3 fail
{
    let x = readF32(bytes, at)
    let y = readF32(bytes, at + 4)
    let z = readF32(bytes, at + 8)
    if not Math.isFinite(x) or not Math.isFinite(y) or not Math.isFinite(z) do
        fail InvalidFormatError{"STL vertex has a non-finite coordinate"}
    return Math.Vector3{x, y, z}
}

// Decodes a binary STL buffer with its fixed 80-byte header and 50-byte facet records.
//
// The header and attribute words are ignored; facet normals are decoded and copied to their three
// vertices. The returned scene owns its geometry.
internal func decodeBinaryStl(bytes: const [..] u8, limits: Limits = {})->Scene fail
{
    if not limits.isValid() do
        fail InvalidFormatError{"scene limits must all be positive"}
    if bytes.count < 84 do
        fail InvalidFormatError{"binary STL is shorter than its header"}

    let count = cast(u64, readU32(bytes, 80))
    if count > limits.maxTriangles do
        fail UnsupportedFormatError{"binary STL exceeds the triangle limit"}
    if count > (bytes.count - 84) / 50 or 84 + count * 50 != bytes.count do
        fail InvalidFormatError{"binary STL facet data does not match its declared count"}
    if count * 3 > limits.maxVertices do
        fail UnsupportedFormatError{"binary STL exceeds the vertex limit"}

    var result = Scene.create()
    result.meshes.add(Mesh{"Mesh"})
    var root = Node.create()
    root.meshIndex = 0
    result.nodes.add(#move root)
    result.materials.add(Material{"Default"})
    let mesh = &result.meshes[0]
    var at = 84'u64
    for count
    {
        let normal = try stlVertex(bytes, at)
        at += 12
        let a = try stlVertex(bytes, at)
        at += 12
        let b = try stlVertex(bytes, at)
        at += 12
        let c = try stlVertex(bytes, at)
        at += 14    // The final two bytes are the facet attribute word.

        let first = cast(u32, mesh.vertices.count)
        var va: Vertex
        va.position = a
        va.normal = normal
        va.hasNormal = true
        var vb: Vertex
        vb.position = b
        vb.normal = normal
        vb.hasNormal = true
        var vc: Vertex
        vc.position = c
        vc.normal = normal
        vc.hasNormal = true
        mesh.vertices.add(#move va)
        mesh.vertices.add(#move vb)
        mesh.vertices.add(#move vc)
        mesh.triangles.add(Triangle{first, first + 1, first + 2, -1})
        try mesh.bounds.include(a)
        try mesh.bounds.include(b)
        try mesh.bounds.include(c)
        try result.bounds.include(a)
        try result.bounds.include(b)
        try result.bounds.include(c)
    }
    return result
}

// Decodes ASCII STL facets and their three vertex records.
internal func decodeAsciiStl(source: string, limits: Limits = {})->Scene fail
{
    if not limits.isValid() do
        fail InvalidFormatError{"scene limits must all be positive"}

    var result = Scene.create()
    result.meshes.add(Mesh{"Mesh"})
    var root = Node.create()
    root.meshIndex = 0
    result.nodes.add(#move root)
    result.materials.add(Material{"Default"})
    var inFacet = false
    var inLoop = false
    var vertices: [3] Math.Vector3
    var normal: Math.Vector3
    var vertexCount = 0'u32
    for line in Tokenize.splitLines(source)
    {
        let words = splitStlWords(line)
        if words.isEmpty() do
            continue
        if words[0] == "facet"
        {
            if inFacet or words.count < 5 or words[1] != "normal" do
                fail InvalidFormatError{"ASCII STL facet declaration is malformed"}
            let x = try StrConv.parseF32Invariant(words[2])
            let y = try StrConv.parseF32Invariant(words[3])
            let z = try StrConv.parseF32Invariant(words[4])
            if x.eat != words[2].count or x.ovf or y.eat != words[3].count or y.ovf or z.eat != words[4].count or z.ovf do
                fail InvalidFormatError{"ASCII STL facet normal is malformed"}
            normal = Math.Vector3{x.value, y.value, z.value}
            if not Math.isFinite(normal.x) or not Math.isFinite(normal.y) or not Math.isFinite(normal.z) do
                fail InvalidFormatError{"ASCII STL facet normal is not finite"}
            inFacet = true
            inLoop = false
            vertexCount = 0
            continue
        }
        if words[0] == "outer"
        {
            if not inFacet or inLoop or words.count < 2 or words[1] != "loop" do
                fail InvalidFormatError{"ASCII STL outer loop is malformed"}
            inLoop = true
            continue
        }
        if words[0] == "vertex"
        {
            if not inFacet or not inLoop or words.count < 4 or vertexCount >= 3 do
                fail InvalidFormatError{"ASCII STL vertex is outside a facet"}
            let x = try StrConv.parseF32Invariant(words[1])
            let y = try StrConv.parseF32Invariant(words[2])
            let z = try StrConv.parseF32Invariant(words[3])
            if x.eat != words[1].count or x.ovf or y.eat != words[2].count or y.ovf or z.eat != words[3].count or z.ovf do
                fail InvalidFormatError{"ASCII STL vertex coordinate is malformed"}
            vertices[vertexCount] = Math.Vector3{x.value, y.value, z.value}
            if not Math.isFinite(vertices[vertexCount].x) or not Math.isFinite(vertices[vertexCount].y) or not Math.isFinite(vertices[vertexCount].z) do
                fail InvalidFormatError{"ASCII STL vertex has a non-finite coordinate"}
            vertexCount += 1
            continue
        }
        if words[0] == "endloop"
        {
            if not inLoop or vertexCount != 3 do
                fail InvalidFormatError{"ASCII STL loop needs three vertices"}
            inLoop = false
            continue
        }
        if words[0] == "endfacet"
        {
            if not inFacet or inLoop or vertexCount != 3 do
                fail InvalidFormatError{"ASCII STL facet needs three vertices"}
            if result.meshes[0].triangles.count >= limits.maxTriangles or result.meshes[0].vertices.count + 3 > limits.maxVertices do
                fail UnsupportedFormatError{"ASCII STL exceeds geometry limits"}
            let mesh = &result.meshes[0]
            let first = cast(u32, mesh.vertices.count)
            for vertex in vertices
            {
                var decoded: Vertex
                decoded.position = vertex
                decoded.normal = normal
                decoded.hasNormal = true
                mesh.vertices.add(#move decoded)
            }
            mesh.triangles.add(Triangle{first, first + 1, first + 2, -1})
            for vertex in vertices
            {
                try mesh.bounds.include(vertex)
                try result.bounds.include(vertex)
            }
            inFacet = false
            continue
        }
    }
    if inFacet or inLoop or result.meshes[0].triangles.isEmpty() do
        fail InvalidFormatError{"ASCII STL ends inside a facet or has no facets"}
    return result
}
