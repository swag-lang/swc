#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

private impl Nv12Frame
{
    mtd fillFlatContext(changed: bool, amplitude: u8)
    {
        .width = 64
        .height = 32
        .bytes.resize(64 * 32 * 3 / 2)
        for index in .bytes.count do
            .bytes[index] = not changed and index < 64 * 32 ? 80 : 128
        if changed
        {
            for y in 32'u64
            {
                for x in 12'u64 until 15 do
                    .bytes[y * 64 + x] = 128 + amplitude
            }
        }
    }
}

// Flat intra blocks in P pictures inherit CAVLC contexts from adjacent inter residuals.
#test
{
    for amplitude in [8'u8, 16'u8, 32'u8]
    {
        let path = videoTempPath("h264-flat-inter-context", "mp4")
        defer discard catch File.delete(path)
        var first, changed: Nv12Frame
        first.fillFlatContext(false, amplitude)
        changed.fillFlatContext(true, amplitude)
        var encoder = expect H264.Encoder.create(64, 32)
        var writer = expect Mp4.FragmentedWriter.create(path, 64, 32, 90_000, encoder.decoderConfig())
        expect writer.addPacket(expect encoder.encode(&first, 0, 3_000))
        expect writer.addPacket(expect encoder.encode(&changed, 3_000, 3_000))
        expect writer.end()
        var reader = expect Reader.open(path)
        var picture: PlanarFrame
        expect reader.decodeFramePlanesInto(&picture, 1)
        Swag.require(Memory.compare(changed.luma().buffer, picture.luma.storage(), picture.luma.count) == 0)
    }
}
