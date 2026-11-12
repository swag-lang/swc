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
        watch.restart()
        let staticPicture = expect encoder.encode(&changed, 6_000, 3_000)
        watch.stop()
        let staticMicros = watch.elapsedMicroseconds()
        let staticBytes = staticPicture.bytes.count
        expect writer.addPacket(staticPicture)
        watch.restart()
        let held = expect encoder.repeatPrevious(9_000, 3_000)
        watch.stop()
        let heldMicros = watch.elapsedMicroseconds()
        let heldBytes = held.bytes.count
        expect writer.addPacket(held)
        expect writer.end()

        var reader = expect Reader.open(path)
        Swag.require(reader.frameCount() == 4)
        var decoded: PlanarFrame
        watch.restart()
        expect reader.decodeFramePlanesInto(&decoded, 0)
        watch.stop()
        let decodeIdrMicros = watch.elapsedMicroseconds()
        watch.restart()
        expect reader.decodeFramePlanesInto(&decoded, 1)
        watch.stop()
        let decodePMicros = watch.elapsedMicroseconds()
        var staticDecoded: PlanarFrame
        expect reader.decodeFramePlanesInto(&staticDecoded, 2)
        var heldPicture: PlanarFrame
        watch.restart()
        expect reader.decodeFramePlanesInto(&heldPicture, 3)
        watch.stop()
        let decodeHeldMicros = watch.elapsedMicroseconds()
        Swag.require(decoded.width == 3840 and decoded.height == 2160)
        Swag.require(Slice.equals(decoded.luma.toSlice(), staticDecoded.luma.toSlice()))
        Swag.require(Slice.equals(decoded.chromaB.toSlice(), staticDecoded.chromaB.toSlice()))
        Swag.require(Slice.equals(decoded.chromaR.toSlice(), staticDecoded.chromaR.toSlice()))
        Swag.require(Slice.equals(decoded.luma.toSlice(), heldPicture.luma.toSlice()))
        Swag.require(Slice.equals(decoded.chromaB.toSlice(), heldPicture.chromaB.toSlice()))
        Swag.require(Slice.equals(decoded.chromaR.toSlice(), heldPicture.chromaR.toSlice()))
        Console.printf("H264 4K % slices: IDR % us/% bytes, P % us/% bytes, static % us/% bytes, held % us/% bytes, Reader IDR % us/P % us/held % us\n",
                       count, idrMicros, idrBytes, pMicros, pBytes,
                       staticMicros, staticBytes, heldMicros, heldBytes,
                       decodeIdrMicros, decodePMicros, decodeHeldMicros)
    }
}

// Repeated changing pictures expose per-frame allocation and scratch-reset costs.
#[Swag.TestTag("stress")]
#test
{
    let first = expect sliceStressFrame(0)
    let changed = expect sliceStressFrame(1)
    var encoder = expect H264.Encoder.create(3840, 2160, quantizationQp: 28,
                                              sliceCount: 4)
    discard expect encoder.encode(&first, 0, 3_000)
    discard expect encoder.encode(&changed, 3_000, 3_000)
    var watch: Time.Stopwatch
    watch.start()
    var totalBytes: u64
    for index in 100'u64
    {
        let picture = index % 2 ? &changed : &first
        let packet = expect encoder.encode(picture, (index + 2) * 3_000, 3_000)
        totalBytes += packet.bytes.count
    }
    watch.stop()
    Console.printf("H264 4K QP28 four slices: 100 changing P pictures % us/% bytes\n",
                   watch.elapsedMicroseconds(), totalBytes)
    Swag.require(totalBytes > 0)
}
