#global public

using Core, Core.Errors

private func splitWords(line: string)->Array'(string)
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

private func coordinate(token: string)->f32 fail
{
    let parsed = try StrConv.parseF32Invariant(token)
    if parsed.eat != token.count or parsed.ovf or not Math.isFinite(parsed.value) do
        fail InvalidFormatError{"OBJ coordinate is not a finite number"}
    return parsed.value
}

private func resolveIndex(token: string, count: u64)->u32 fail
{
    let raw = try StrConv.toS32(token)
    if not raw do
        fail InvalidFormatError{"OBJ index cannot be zero"}
    let index = raw > 0 ? cast(s64, raw - 1) : cast(s64, count) + cast(s64, raw)
    if index < 0 or cast(u64, index) >= count do
        fail InvalidFormatError{"OBJ index is outside the values read so far"}
    return cast(u32, index)
}

private func faceVertex(token: string, positions: const [..] Math.Vector3, texCoords: const [..] Math.Vector2, normals: const [..] Math.Vector3)->Vertex fail
{
    let parts = Tokenize.split(token, '/'u8, maxSplit: 2, removeEmpty: false)
    if parts.isEmpty() do
        fail InvalidFormatError{"OBJ face vertex has no position index"}

    var result: #returntype
    result.position = positions[try resolveIndex(parts[0], positions.count)]
    if parts.count > 1 and parts[1].count
    {
        result.texCoord = texCoords[try resolveIndex(parts[1], texCoords.count)]
        result.hasTexCoord = true
    }
    if parts.count > 2 and parts[2].count
    {
        result.normal = normals[try resolveIndex(parts[2], normals.count)]
        result.hasNormal = true
    }
    return result
}

// Decodes OBJ positions, normals, texture coordinates, polygon faces, and material names.
//
// Positive and negative face indices and `v`, `v/vt`, `v//vn`, and `v/vt/vn` forms are accepted.
// Polygons are triangulated as a fan and vertices are expanded at attribute seams. Material
// library files are not opened; `usemtl` names are retained with default material values.
internal func decodeObj(source: string, limits: Limits = {})->Scene fail
{
    if not limits.isValid() do
        fail InvalidFormatError{"scene limits must all be positive"}

    var positions: Array'Math.Vector3
    var texCoords: Array'Math.Vector2
    var normals: Array'Math.Vector3
    var result = Scene.create()
    result.meshes.add(Mesh{"Mesh"})
    var root = Node.create()
    root.meshIndex = 0
    result.nodes.add(#move root)
    result.materials.add(Material{"Default"})
    var materialIndex = -1's32

    for line in Tokenize.splitLines(source)
    {
        let words = splitWords(line)
        if words.isEmpty() or words[0][0] == '#'u8 do
            continue

        if words[0] == "v"
        {
            if words.count < 4 do
                fail InvalidFormatError{"OBJ position needs three coordinates"}
            positions.add(Math.Vector3{try coordinate(words[1]), try coordinate(words[2]), try coordinate(words[3])})
            if positions.count > limits.maxVertices do
                fail UnsupportedFormatError{"OBJ exceeds the vertex limit"}
            continue
        }

        if words[0] == "vt"
        {
            if words.count < 3 do
                fail InvalidFormatError{"OBJ texture coordinate needs two components"}
            texCoords.add(Math.Vector2{try coordinate(words[1]), try coordinate(words[2])})
            if texCoords.count > limits.maxVertices do
                fail UnsupportedFormatError{"OBJ exceeds the texture coordinate limit"}
            continue
        }

        if words[0] == "vn"
        {
            if words.count < 4 do
                fail InvalidFormatError{"OBJ normal needs three components"}
            normals.add(Math.Vector3{try coordinate(words[1]), try coordinate(words[2]), try coordinate(words[3])})
            if normals.count > limits.maxVertices do
                fail UnsupportedFormatError{"OBJ exceeds the normal limit"}
            continue
        }

        if words[0] == "usemtl"
        {
            if words.count < 2 do
                fail InvalidFormatError{"OBJ material name is missing"}
            var found = -1's32
            for material, index in result.materials where material.name == words[1] do
                found = cast(s32, index)
            if found < 0
            {
                if result.materials.count >= limits.maxMaterials do
                    fail UnsupportedFormatError{"OBJ exceeds the material limit"}
                result.materials.add(Material{String.from(words[1])})
                found = cast(s32, result.materials.count - 1)
            }
            materialIndex = found
            continue
        }

        if words[0] != "f" do
            continue

        var face: Array'Vertex
        for word in words[1 to]
        {
            if word[0] == '#'u8 do
                break
            face.add(try faceVertex(word, positions.toSlice(), texCoords.toSlice(), normals.toSlice()))
            if face.count > limits.maxTriangles - result.meshes[0].triangles.count + 2 do
                fail UnsupportedFormatError{"OBJ exceeds the triangle limit"}
        }
        if face.count < 3 do
            fail InvalidFormatError{"OBJ face needs at least three vertices"}
        if face.count - 2 > limits.maxTriangles - result.meshes[0].triangles.count do
            fail UnsupportedFormatError{"OBJ exceeds the triangle limit"}
        if result.meshes[0].vertices.count + (face.count - 2) * 3 > limits.maxVertices do
            fail UnsupportedFormatError{"OBJ expanded vertices exceed the vertex limit"}

        let mesh = &result.meshes[0]
        for index in 1 until face.count - 1
        {
            let a = cast(u32, mesh.vertices.count)
            mesh.vertices.add(face[0])
            mesh.vertices.add(face[index])
            mesh.vertices.add(face[index + 1])
            mesh.triangles.add(Triangle{a, a + 1, a + 2, materialIndex})
            try mesh.bounds.include(face[0].position)
            try mesh.bounds.include(face[index].position)
            try mesh.bounds.include(face[index + 1].position)
            try result.bounds.include(face[0].position)
            try result.bounds.include(face[index].position)
            try result.bounds.include(face[index + 1].position)
        }
    }

    if result.meshes[0].triangles.isEmpty() do
        fail InvalidFormatError{"OBJ has no triangle faces"}
    return result
}
