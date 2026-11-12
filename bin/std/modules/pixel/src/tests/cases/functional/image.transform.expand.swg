#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    const pixels = [
        10'u8, 20'u8, 30'u8, 40'u8, 50'u8, 60'u8, 70'u8, 80'u8,
        90'u8, 100'u8, 110'u8, 120'u8, 130'u8, 140'u8, 150'u8, 160'u8]

    let src     = makeImage(2, 2, .RGBA8, pixels)
    let bgColor = Color.fromArgb(255'u8, 1'u8, 2'u8, 3'u8)
    let grown   = src.expanded(1, 1, 1, 0, bgColor)
    assertImage(grown, 4, 3, .RGBA8)

    // The top margin is the first picture row; the source sits below it, right of the left margin.
    assertPixel(grown, 0, 0, bgColor)
    assertPixel(grown, 1, 0, bgColor)
    assertPixel(grown, 1, 2, Color.fromArgb(40'u8, 10'u8, 20'u8, 30'u8))
    assertPixel(grown, 2, 2, Color.fromArgb(80'u8, 50'u8, 60'u8, 70'u8))
    assertPixel(grown, 1, 1, Color.fromArgb(120'u8, 90'u8, 100'u8, 110'u8))
    assertPixel(grown, 2, 1, Color.fromArgb(160'u8, 130'u8, 140'u8, 150'u8))
    assertPixel(grown, 3, 1, bgColor)

    var trimmed = makeImage(2, 2, .RGBA8, pixels)
    trimmed.expand(-1, 0, 0, 0)
    assertImage(trimmed, 1, 2, .RGBA8)
    assertPixel(trimmed, 0, 1, Color.fromArgb(80'u8, 50'u8, 60'u8, 70'u8))
    assertPixel(trimmed, 0, 0, Color.fromArgb(160'u8, 130'u8, 140'u8, 150'u8))

    // Trimming the complete source is valid when positive padding still leaves
    // a non-empty result; the output then contains only the fill color.
    let paddedOnly = src.expanded(-3, 0, 4, 0, bgColor)
    assertImage(paddedOnly, 3, 2, .RGBA8)
    for x in paddedOnly.width
    {
        assertPixel(paddedOnly, x, 0, bgColor)
        assertPixel(paddedOnly, x, 1, bgColor)
    }
}

#test
{
    let source  = Image.create(3, 3, .RGBA8)
    let maximum = Swag.S32.Max

    let largest = source.getWH(maximum - source.width, maximum - source.height, 0, 0)
    Swag.require(largest.w == maximum and largest.h == maximum)

    let sourcePointer = &source
    let rejectedWidth = Swag.catchPanic(func|sourcePointer, maximum|()
    {
        discard sourcePointer[].getWH(maximum, 0, maximum, 0)
    })
    let rejectedHeight = Swag.catchPanic(func|sourcePointer, maximum|()
    {
        discard sourcePointer[].getWH(0, maximum, 0, maximum)
    })
    Swag.require(rejectedWidth.raised and rejectedHeight.raised)
}

#test
{
    let source     = Image.create(2, 2, .RGBA8)
    let fill       = Color.fromArgb(255'u8, 4'u8, 5'u8, 6'u8)
    let horizontal = source.expanded(Swag.S32.Min, 0, Swag.S32.Max, 0, fill)
    assertImage(horizontal, 1, 2, .RGBA8)
    assertPixel(horizontal, 0, 0, fill)
    assertPixel(horizontal, 0, 1, fill)

    let vertical = source.expanded(0, Swag.S32.Max, 0, Swag.S32.Min, fill)
    assertImage(vertical, 2, 1, .RGBA8)
    assertPixel(vertical, 0, 0, fill)
    assertPixel(vertical, 1, 0, fill)

    var inPlace = Image.create(2, 2, .RGBA8)
    inPlace.expand(Swag.S32.Min, 0, Swag.S32.Max, 0, fill)
    assertImage(inPlace, 1, 2, .RGBA8)
    assertPixel(inPlace, 0, 0, fill)
    assertPixel(inPlace, 0, 1, fill)
}
