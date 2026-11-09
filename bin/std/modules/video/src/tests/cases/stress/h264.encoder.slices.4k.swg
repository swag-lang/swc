#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

func sliceStressFrame(bright: u32)->Nv12Frame fail
{
    const Width = 3840'u64
    const Height = 2160'u64
    var image = Image.create(cast(s32, Width), cast(s32, Height), .RGB8)
    for y in Height
    {
        for x in Width
        {
            let at = (y * Width + x) * 3
            let value = cast(u8, 32 + (x / 4 * 17 + y / 4 * 31) % 160 + bright)
            image.pixels[at] = value
            image.pixels[at + 1] = value
            image.pixels[at + 2] = value
        }
    }
    var result: Nv12Frame
    try result.convertFrom(&image)
    return result
}

// Reports 4K IDR/P encode and Reader decode costs with one or four row-band slices.
#[Swag.TestTag("stress")]
#test
{
    let first = expect sliceStressFrame(0)
    let changed = expect sliceStressFrame(1)
    for count in [1'u32, 4]
    {
        let path = videoTempPath("h264-encoder-slices-4k", "mp4")
        defer discard catch File.delete(path)
        var encoder = expect H264.Encoder.create(3840, 2160, quantizationQp: 28,
                                                  sliceCount: count)
        var writer = expect Mp4.FragmentedWriter.create(path, 3840, 2160, 90_000,
                                                        encoder.decoderConfig())
        var watch: Time.Stopwatch
        watch.start()
        let idr = expect encoder.encode(&first, 0, 3_000)
        watch.stop()
        let idrMicros = watch.elapsedMicroseconds()
        let idrBytes = idr.bytes.count
        expect writer.addPacket(idr)
        watch.restart()
        let p = expect encoder.encode(&changed, 3_000, 3_000)
        watch.stop()
        let pMicros = watch.elapsedMicroseconds()
        let pBytes = p.bytes.count
        expect writer.addPacket(p)
        expect writer.end()

        var reader = expect Reader.open(path)
        Swag.require(reader.frameCount() == 2)
        var decoded: PlanarFrame
        watch.restart()
        expect reader.decodeFramePlanesInto(&decoded, 0)
        watch.stop()
        let decodeIdrMicros = watch.elapsedMicroseconds()
        watch.restart()
        expect reader.decodeFramePlanesInto(&decoded, 1)
        watch.stop()
        let decodePMicros = watch.elapsedMicroseconds()
        Swag.require(decoded.width == 3840 and decoded.height == 2160)
        Console.printf("H264 4K % slices: IDR % us/% bytes, P % us/% bytes, Reader IDR % us/P % us\n",
                       count, idrMicros, idrBytes, pMicros, pBytes,
                       decodeIdrMicros, decodePMicros)
    }
}
