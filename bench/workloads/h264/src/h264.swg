using Core, Pixel, Video

// Input is a sequence of tightly packed, bottom-up RGB8 pictures. Save the actual NV12 input
// beside the MP4 so external encoders and quality metrics use precisely the same samples.
#[Swag.Safety(.Assert, true)]
#main
{
    func encodeCase(args: const [..] string)
    {
        let width  = expect StrConv.toS32(args[1])
        let height = expect StrConv.toS32(args[2])
        let count  = expect StrConv.toU32(args[3])
        let qp     = expect StrConv.toU32(args[4])
        let slices = expect StrConv.toU32(args[5])
        Swag.require(width > 0 and height > 0 and width % 2 == 0 and height % 2 == 0 and count > 0)
        let rgb   = expect File.readAllBytes(args[0])
        let bytes = cast(u64, width) * cast(u64, height) * 3
        Swag.require(rgb.count == bytes * count, "RGB input length differs from the requested picture count")

        // Conversion, allocation, file writes and decoding all stay outside the encode timer.
        var frames: Array'Nv12Frame
        var source = expect File.open(Format.toString("%.nv12", args[6]).toString(), .Create, .Write, .Read)
        for index in cast(u64, count)
        {
            let image = Image.create(width, height, .RGB8, rgb.toSlice()[index * bytes until (index + 1) * bytes])
            var frame: Nv12Frame
            expect frame.convertFrom(&image)
            expect source.writeAll(frame.bytes.toSlice())
            frames.add(#move frame)
        }

        source.close()
        var encoder     = expect Video.H264.Encoder.create(width, height, keyInterval: 120, quantizationQp: qp, sliceCount: slices)
        var writer      = expect Mp4.FragmentedWriter.create(args[6], width, height, 90_000, encoder.decoderConfig())
        var micros      = 0'u64
        var packetBytes = 0'u64
        for &frame, index in frames
        {
            var watch: Time.Stopwatch
            watch.start()
            let packet = expect encoder.encode(frame, index * 3_000, 3_000)
            watch.stop()
            micros      += watch.elapsedMicroseconds()
            packetBytes += packet.bytes.count
            expect writer.addPacket(packet)
        }

        expect writer.end()
        Console.printf("H264 frames=% qp=% slices=% us=% bytes=%\n", count, qp, slices, micros, packetBytes)

        // The independent decoder's planar output is retained for a byte comparison with FFmpeg.
        var reader = expect Reader.open(args[6])
        Swag.require(reader.frameCount() == count)
        var decoded = expect File.open(Format.toString("%.yuv", args[6]).toString(), .Create, .Write, .Read)
        var picture: PlanarFrame
        for index in cast(u64, count)
        {
            expect reader.decodeFramePlanesInto(&picture, index)
            expect decoded.writeAll(picture.luma.toSlice())
            expect decoded.writeAll(picture.chromaB.toSlice())
            expect decoded.writeAll(picture.chromaR.toSlice())
        }
    }

    let args = Env.arguments()
    Swag.require(args.count >= 8 and (args.count - 1) % 7 == 0,
                 "benchmark needs groups of RGB path, width, height, frame count, QP, slices and output MP4 path")
    Swag.setWorkerCount(3)
    Swag.startWorkers()
    for index in (args.count - 1) / 7 do
        encodeCase(args[1 + index * 7 until 1 + (index + 1) * 7])
}
