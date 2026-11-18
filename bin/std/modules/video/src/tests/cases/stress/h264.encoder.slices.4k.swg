#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

func sliceStressFrame(bright: u32)->Nv12Frame fail
{
    const Width  = 3840'u64
    const Height = 2160'u64
    var image = Image.create(cast(s32, Width), cast(s32, Height), .RGB8)
    for y in Height
    {
        for x in Width
        {
            let at    = (y * Width + x) * 3
            let value = cast(u8, 32 + (x / 4 * 17 + y / 4 * 31) % 160 + bright)
            image.pixels[at]     = value
            image.pixels[at + 1] = value
            image.pixels[at + 2] = value
        }
    }

    var result: Nv12Frame
    try result.convertFrom(&image)
    return result
}

// A 4K changing picture and its held copies decode identically across the supported slice layouts.
#[Swag.TestTag("stress")]
#test
{
    let first   = expect sliceStressFrame(0)
    let changed = expect sliceStressFrame(1)
    for qp in [18'u32, 28]
    {
        for count in [1'u32, 4, 8]
        {
            let path = videoTempPath("h264-encoder-slices-4k", "mp4")
            defer discard catch File.delete(path)
            var encoder = expect H264.Encoder.create(3840, 2160, quantizationQp: qp, sliceCount: count)
            var writer  = expect Mp4.FragmentedWriter.create(path, 3840, 2160, 90_000, encoder.decoderConfig())
            expect writer.addPacket(expect encoder.encode(&first, 0, 3_000))
            expect writer.addPacket(expect encoder.encode(&changed, 3_000, 3_000))
            expect writer.addPacket(expect encoder.encode(&first, 6_000, 3_000))
            expect writer.addPacket(expect encoder.encode(&changed, 9_000, 3_000))
            expect writer.addPacket(expect encoder.encode(&changed, 12_000, 3_000))
            expect writer.addPacket(expect encoder.repeatPrevious(15_000, 3_000))
            expect writer.end()

            var reader = expect Reader.open(path)
            Swag.require(reader.frameCount() == 6)
            var changedPicture: PlanarFrame
            expect reader.decodeFramePlanesInto(&changedPicture, 3)
            Swag.require(changedPicture.width == 3840 and changedPicture.height == 2160)
            var held: PlanarFrame
            for index in [4'u64, 5]
            {
                expect reader.decodeFramePlanesInto(&held, index)
                Swag.require(Slice.equals(changedPicture.luma.toSlice(), held.luma.toSlice()))
                Swag.require(Slice.equals(changedPicture.chromaB.toSlice(), held.chromaB.toSlice()))
                Swag.require(Slice.equals(changedPicture.chromaR.toSlice(), held.chromaR.toSlice()))
            }
        }
    }
}
