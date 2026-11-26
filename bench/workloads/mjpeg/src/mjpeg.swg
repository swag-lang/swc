using Core, Pixel

#[Swag.Safety(.Assert, true)]
#main
{
    let args = Env.arguments()
    Swag.require(args.count == 7, "benchmark needs RGB path, width, height, frame count, quality and output path")
    let width   = expect StrConv.toS32(args[2])
    let height  = expect StrConv.toS32(args[3])
    let count   = expect StrConv.toU32(args[4])
    let quality = expect StrConv.toU32(args[5])
    let rgb     = expect File.readAllBytes(args[1])
    let bytes   = cast(u64, width) * cast(u64, height) * 3
    Swag.require(width > 0 and
                 height > 0 and
                 count > 0 and
                 quality >= 1 and
                 quality <= 100 and
                 rgb.count == bytes * count)
    Swag.setWorkerCount(1)
    var frames: Array'Image
    for index in cast(u64, count) do
        frames.add(Image.create(width, height, .RGB8, rgb.toSlice()[index * bytes until (index + 1) * bytes]))

    var packets: Array'ConcatBuffer
    packets.reserve(count)
    var cpuStart, cpuStop: Linux.timespec
    Swag.require(Linux.clock_gettime(Linux.CLOCK_PROCESS_CPUTIME_ID, &cpuStart) == 0)
    var watch: Time.Stopwatch
    watch.start()
    for &image in frames
    {
        var encoded = expect image.encode("frame.jpg", Jpg.EncodeOptions{cast(u8, quality)})
        encoded.makeLinear()
        packets.add(#move encoded)
    }

    watch.stop()
    Swag.require(Linux.clock_gettime(Linux.CLOCK_PROCESS_CPUTIME_ID, &cpuStop) == 0)
    let cpu    = (cpuStop.tv_sec - cpuStart.tv_sec) * 1_000_000 + (cpuStop.tv_nsec - cpuStart.tv_nsec) / 1_000
    var output = expect File.open(args[6], .Create, .Write, .Read)
    var total  = 0'u64
    for &packet in packets
    {
        let payload = unwrap packet.toSlice()
        expect output.writeAll(payload)
        total += payload.count
    }

    Console.printf("MJPEG frames=% us=% cpu_us=% bytes=%\n", count, watch.elapsedMicroseconds(), cpu, total)
}
