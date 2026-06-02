#global #if #command == Swag.CompilerCommand.Test
using Swag, Core

func getDrawFontPath()->String
{
    var path = Path.getDirectoryName(#curlocation.fileName) orelse ""
    for 5 do
        path = Path.getDirectoryName(path) orelse ""

    path = Path.combine(path, "examples/modules/draw/data/arial.ttf")
    @assert(File.exists(path))
    return path
}

func assertOutlineOffsetPathCount(text: string, expectedCount: u64)
{
    let face = assume Pixel.TypeFace.load(getDrawFontPath())

    var paths: Pixel.LinePathList
    assume face.getStringOutline(&paths, text, 80)
    paths.flatten(.Normal)
    paths.offset(4, Pixel.JoinStyle.Round, 0.5)
    @assert(paths.paths.count == expectedCount)

    paths.clean()
    @assert(paths.paths.count == expectedCount)
}

#test
{
    assertOutlineOffsetPathCount("A B C D", 8)
    assertOutlineOffsetPathCount("D F G H", 5)
}
