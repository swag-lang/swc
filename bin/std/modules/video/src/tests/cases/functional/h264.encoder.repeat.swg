#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Core.Errors, Pixel

// Repeated slots preserve the decoded picture across P slices and periodic IDR pictures.
#test
{
    let image = Image.create(50, 34, .BGRA8)
    for index in image.pixels.count do
        image.pixels[index] = cast(u8, (index * 37 + index / 13) & 255)
    var frame: Nv12Frame
    expect frame.convertFrom(&image)

    for qp in [0'u32, 28]
    {
        for sliceCount in [1'u32, 3]
        {
            let path = videoTempPath("h264-repeat", "mp4")
            defer discard catch File.delete(path)
            var encoder = expect H264.Encoder.create(50, 34, keyInterval: 3,
                                                      quantizationQp: qp,
                                                      sliceCount: sliceCount)
            var writer = expect Mp4.FragmentedWriter.create(path, 50, 34, 90_000,
                                                             encoder.decoderConfig())
            var rejected: Swag.Error
            discard catch encoder.repeatPrevious(0, 3_000) as rejected
            Swag.require(rejected.value() is BadParameterError)

            expect writer.addPacket(expect encoder.encode(&frame, 0, 3_000))
            for index in 1'u64 until 5
            {
                let packet = expect encoder.repeatPrevious(index * 3_000, 3_000)
                Swag.require(packet.isKeyFrame == (index == 3))
                expect writer.addPacket(packet)
            }
            expect writer.end()

            var reader = expect Reader.open(path)
            Swag.require(reader.frameCount() == 5)
            var first: PlanarFrame
            var decoded: PlanarFrame
            expect reader.decodeFramePlanesInto(&first, 0)
            for index in 1'u64 until 5
            {
                expect reader.decodeFramePlanesInto(&decoded, index)
                Swag.require(Slice.equals(first.luma.toSlice(), decoded.luma.toSlice()))
                Swag.require(Slice.equals(first.chromaB.toSlice(), decoded.chromaB.toSlice()))
                Swag.require(Slice.equals(first.chromaR.toSlice(), decoded.chromaR.toSlice()))
            }
            expect reader.decodeFramePlanesInto(&decoded, 4)
            Swag.require(Slice.equals(first.luma.toSlice(), decoded.luma.toSlice()))
        }
    }
}
