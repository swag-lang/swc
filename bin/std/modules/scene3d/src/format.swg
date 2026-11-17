#global public

using Core

internal enum SceneCodec
{
    Obj
    Stl
    Unknown
}

// Names one scene format and the filename extensions that select its decoder.
public struct SceneFormat
{
    public
    {
        // Stable format label suitable for a file-dialog filter.
        name: string

        // Accepted lowercase, dot-prefixed extensions separated by semicolons.
        extensions: string
    }

    codec: SceneCodec
}

public impl SceneFormat
{
    // Reports whether this format claims `fileName` by extension alone.
    mtd const matches(fileName: string)->bool
    {
        let extension = Path.lowercaseExtension(fileName)
        if extension.isEmpty() do
            return false
        for candidate in Tokenize.split(.extensions, ';'u8) where extension == candidate do
            return true
        return false
    }
}

private const SceneFormats: [2] SceneFormat = [
    SceneFormat{"Wavefront OBJ", ".obj", .Obj},
    SceneFormat{"STL", ".stl", .Stl}]

internal func sceneFormats()->Array'SceneFormat
{
    var result: #returntype
    for format in SceneFormats do
        result.add(format)
    return result
}

internal func sceneCodec(fileName: string)->SceneCodec
{
    for format in SceneFormats where format.matches(fileName) do
        return format.codec
    return .Unknown
}
