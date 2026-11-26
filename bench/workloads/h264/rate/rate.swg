using Core, Pixel, Video

#main
{
    let args = Env.arguments()
    Swag.require(args.count == 5 or args.count == 6)
    let target     = expect StrConv.toU64(args[1])
    let slices     = expect StrConv.toU32(args[2])
    let input      = args[3]
    let output     = args[4]
    let sourcePath = args.count == 6 ? args[5] : ""
    const Width      = 640
    const Height     = 360
    const FrameBytes = Width * Height * 3'u64
    const Duration   = 3_000'u32
    Swag.startWorkers()

    let rgb = expect File.readAllBytes(input)
    Swag.require(rgb.count % FrameBytes == 0)
    let options   = Mp4.SoftwareVideoRateControl{targetBitsPerSecond: target, reservoirBits: target / 2, minQp: 1, maxQp: 51}
    var recording = expect Mp4.SoftwareRecording.createVideoOnly(output, Width, Height, 90_000, keyInterval: 120, sliceCount: slices, rateControl: &options)
    var source: File.FileStream
    if sourcePath.count do
        source = expect File.open(sourcePath, .Create, .Write, .Read)
    var nv12: Nv12Frame
    for idx in rgb.count / FrameBytes
    {
        let frame = Image.create(Width, Height, .RGB8, rgb.toSlice()[idx * FrameBytes until (idx + 1) * FrameBytes])
        let slot  = FrameSlot{index: idx, decodeTime: idx * Duration, duration: Duration}
        let start = recording.videoPacketByteCount()
        expect recording.addFrame(&frame, slot)
        Console.printf("rate frame=% qp=% packet_bytes=%\n", idx, recording.videoQuantizationQp(), recording.videoPacketByteCount() - start)
        if sourcePath.count
        {
            expect nv12.convertFrom(&frame)
            expect source.writeAll(nv12.bytes.toSlice())
        }
    }

    expect recording.end()
}
