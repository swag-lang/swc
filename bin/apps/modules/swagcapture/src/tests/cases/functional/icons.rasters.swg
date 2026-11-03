#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel

func checkCaptureRaster(cell: s32, bytes: const [..] u8)
{
    let drawing  = expect Svg.Drawing.parse(cast(string, IconsSvg))
    let cols     = cast(s32, Math.round(drawing.width / 24))
    let rows     = cast(s32, Math.round(drawing.height / 24))
    let expected = drawing.rasterize(cols * cell, rows * cell, 4)
    var actual   = expect Image.decode(".png", bytes)
    actual.convertTo(.BGRA8)
    Swag.assert(actual.width == expected.width and actual.height == expected.height)
    Swag.assert(actual.byteCount == expected.byteCount)
    #static if #cfg != "release" do
        Swag.assert(Memory.compare(actual.pixels.storage(), expected.pixels.storage(), actual.byteCount) == 0)
    else
    {
        for i in actual.byteCount
        {
            let tolerance = i % 4 == 3 ? 1 : 0
            Swag.assert(Math.abs(cast(s32, actual.pixels[i]) - cast(s32, expected.pixels[i])) <= tolerance)
        }
    }
}

#test
{
    checkCaptureRaster(32, #include("../../datas/icons.32px.png"))
    checkCaptureRaster(40, #include("../../datas/icons.40px.png"))
}
