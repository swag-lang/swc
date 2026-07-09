#global #if #command == Swag.CompilerCommand.Test
using Swag, Core

func getOutlineFontPath()->String
{
    return getTestDataPath("segoeui.ttf")
}

func assertOutlineOffsetPathCount(text: string, expectedCount: u64)
{
    let face = assume Pixel.TypeFace.load(getOutlineFontPath())

    var paths: Pixel.LinePathList
    assume face.getStringOutline(&paths, text, 80)
    paths.flatten(.Normal)
    paths.offset(4, Pixel.JoinStyle.Round, 0.5)
    @assert(paths.paths.count == expectedCount)

    var expectedSerials:     Array's32
    var expectedClockwises:  Array'bool
    for p in paths.paths
    {
        expectedSerials.add(p.serial)
        expectedClockwises.add(p.polygon.isClockwise)
    }

    paths.clean()
    @assert(paths.paths.count == expectedCount)
    for i in paths.paths.count
    {
        @assert(paths.paths[i].serial == expectedSerials[i])
        @assert(paths.paths[i].polygon.isClockwise == expectedClockwises[i])
    }
}

#test
{
    assertOutlineOffsetPathCount("A B C D", 8)
    assertOutlineOffsetPathCount("D F G H", 5)
}
