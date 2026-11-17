#global public

using Core, Core.Errors

private func sceneName(fileName: string)->String => String.from(Path.fileName(fileName) orelse fileName)

// Loads OBJ or STL data from a file, selecting a decoder by extension and content.
//
// The opened stream is size-checked before reserving owned memory, so a path replacement between
// checking and reading cannot bypass `limits.maxInputBytes`.
// `.obj` and `.stl` extensions select their codecs; a recognized file signature also permits an
// extensionless or otherwise unrecognized name. Referenced OBJ material libraries and textures
// are not opened.
public func load(fileName: string, limits: Limits = {})->Scene fail
{
    if not limits.isValid() do
        fail InvalidFormatError{"scene limits must all be positive"}
    var stream = try File.openRead(fileName)
    let length = try stream.size()
    if length > limits.maxInputBytes do
        fail UnsupportedFormatError{"scene exceeds the encoded byte limit"}
    var bytes: Array'u8
    if length
    {
        bytes.reserve(length)
        bytes.count = try stream.read(unwrap bytes.buffer, length)
    }

    return try decode(fileName, bytes.toSlice(), limits)
}

// Decodes OBJ or STL bytes using their extension and recognizable file content.
//
// `fileName` supplies a format hint and scene name only; all returned geometry is copied into the
// result. Binary STL is identified by its declared facet count and exact record length, including
// when the 80-byte header starts with the word `solid`.
public func decode(fileName: string, bytes: const [..] u8, limits: Limits = {})->Scene fail
{
    if not limits.isValid() do
        fail InvalidFormatError{"scene limits must all be positive"}
    if bytes.count > limits.maxInputBytes do
        fail UnsupportedFormatError{"scene exceeds the encoded byte limit"}

    let codec = sceneCodec(fileName)
    if codec != .Obj and looksLikeBinaryStl(bytes)
    {
        var scene = try decodeBinaryStl(bytes, limits)
        scene.name = sceneName(fileName)
        scene.nodes[0].name = scene.name
        return scene
    }

    let source = cast(string, bytes)
    if codec == .Obj or looksLikeObj(source)
    {
        var scene = try decodeObj(source, limits)
        scene.name = sceneName(fileName)
        scene.nodes[0].name = scene.name
        return scene
    }

    if codec == .Stl or looksLikeAsciiStl(source)
    {
        var scene = try decodeAsciiStl(source, limits)
        scene.name = sceneName(fileName)
        scene.nodes[0].name = scene.name
        return scene
    }

    fail UnsupportedFormatError{"scene format is not recognized"}
}

// Reports whether a filename hint or recognizable full-buffer content can select a built-in decoder.
//
// Text probes require structural records instead of isolated words, which avoids claiming
// unrelated text files as OBJ or STL documents. A truncated file header cannot identify binary STL.
public func canDecode(fileName: string, bytes: const [..] u8)->bool
{
    if sceneCodec(fileName) != .Unknown do
        return true
    let source = cast(string, bytes)
    return looksLikeBinaryStl(bytes) or looksLikeObj(source) or looksLikeAsciiStl(source)
}

private func looksLikeBinaryStl(bytes: const [..] u8)->bool
{
    if bytes.count < 84 do
        return false
    let count = cast(u64,
                     cast(u32, bytes[80]) |
                     (cast(u32, bytes[81]) << 8) |
                     (cast(u32, bytes[82]) << 16) |
                     (cast(u32, bytes[83]) << 24))
    return count != 0 and 84 + count * 50 == bytes.count
}

private func looksLikeObj(source: string)->bool
{
    var hasPosition = false
    var hasFace     = false
    for line in Tokenize.splitLines(source)
    {
        let trimmed = Tokenize.eatSpaces(line)
        let words   = splitHeaderWords(trimmed)
        if words.count >= 4 and words[0] == "v" do
            hasPosition = true
        if words.count >= 4 and words[0] == "f" do
            hasFace = true
        if hasPosition and hasFace do
            return true
    }

    return hasPosition and hasFace
}

private func splitHeaderWords(line: string)->Array'(string)
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

private func looksLikeAsciiStl(source: string)->bool
{
    var hasSolid  = false
    var hasFacet  = false
    var hasVertex = false
    for line in Tokenize.splitLines(source)
    {
        let trimmed = Tokenize.eatSpaces(line)
        hasSolid = hasSolid or
                   trimmed == "solid" or
                   Utf8.startsWith(trimmed, "solid ") or
                   Utf8.startsWith(trimmed, "solid\t")
        hasFacet  = hasFacet or Utf8.startsWith(trimmed, "facet ") or Utf8.startsWith(trimmed, "facet\t")
        hasVertex = hasVertex or Utf8.startsWith(trimmed, "vertex ") or Utf8.startsWith(trimmed, "vertex\t")
    }

    return hasSolid and hasFacet and hasVertex
}
