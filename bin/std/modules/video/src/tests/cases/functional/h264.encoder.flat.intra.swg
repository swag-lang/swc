#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

private impl H264.Encoder
{
    internal mtd const testFlatIntra(frame: const *Nv12Frame,
                                    mbX, mbY, sliceStartY: u32)->bool
    {
        return .flatIntra(frame, mbX, mbY, sliceStartY)
    }
}

private impl Nv12Frame
{
    mtd fillFlatFixture(width, height: s32, textured: bool)
    {
        .width = width
        .height = height
        let lumaCount = cast(u64, .width) * cast(u64, .height)
        .bytes.resize(lumaCount + lumaCount / 2)
        for y in cast(u64, .height)
        {
            for x in cast(u64, .width) do
                .bytes[y * cast(u64, .width) + x] =
                    textured and x % 2 == 1 ? 96'u8 : 80'u8
        }
        for pixel in lumaCount / 4
        {
            .bytes[lumaCount + pixel * 2] = 117
            .bytes[lumaCount + pixel * 2 + 1] = 141
        }
    }
}

// Complete flat macroblocks take the row comparison path. A textured sample
// fails regardless of its position, while cropped edges keep padded sampling.
#test
{
    var flat, textured: Nv12Frame
    flat.fillFlatFixture(3840, 2160, false)
    textured.fillFlatFixture(3840, 2160, true)
    var encoder = expect H264.Encoder.create(3840, 2160, 60, 28, 4)
    for mode in 2'u64
    {
        let frame = mode == 0 ? &flat : &textured
        var matches = 0'u64
        for mbY in 135'u32
        {
            for mbX in 240'u32
            {
                if encoder.testFlatIntra(frame, mbX, mbY, 0) do
                    matches += 1
            }
        }
        Swag.require(mode == 0 ? matches == 240 * 135 - 1 : matches == 0)
    }
    var cropped: Nv12Frame
    cropped.fillFlatFixture(34, 18, false)
    var edge = expect H264.Encoder.create(34, 18, 60, 28)
    Swag.require(not edge.testFlatIntra(&cropped, 0, 0, 0))
    Swag.require(edge.testFlatIntra(&cropped, 2, 0, 0))
    Swag.require(edge.testFlatIntra(&cropped, 0, 1, 0))
    Swag.require(edge.testFlatIntra(&cropped, 2, 1, 0))
}
