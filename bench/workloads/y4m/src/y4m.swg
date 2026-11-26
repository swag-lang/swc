using Core, Pixel, Video

#[Swag.Safety(.Assert, true)]
#main
{
    let args = Env.arguments()
    Swag.require(args.count == 8)
    let width  = expect StrConv.toS32(args[2])
    let height = expect StrConv.toS32(args[3])
    let count  = expect StrConv.toU32(args[4])
    let layout = expect StrConv.toU32(args[5])
    let rgb    = expect File.readAllBytes(args[1])
    let pixels = cast(u64, width) * cast(u64, height)
    let bytes  = pixels * 3
    Swag.require(rgb.count == bytes * count and layout < 4 and count > 0)
    var frames: Array'Image
    for index in cast(u64, count)
    {
        let packed = rgb.toSlice()[index * bytes until (index + 1) * bytes]
        if args[6] == "rgb"
        {
            frames.add(Image.create(width, height, .RGB8, packed))
        }
        else
        {
            var img     = Image.create(width, height, .BGRA8)
            let storage = img.pixels.storage()
            for at in pixels
            {
                storage[4 * at]     = packed[at * 3 + 2]
                storage[4 * at + 1] = packed[at * 3 + 1]
                storage[4 * at + 2] = packed[at * 3]
                storage[4 * at + 3] = 255
            }

            frames.add(#move img)
        }
    }

    let rate = expect FrameRate.create(30, 1)
    var buffer: ConcatBuffer
    const Layouts = [Y4m.EncodeChromaMode.Yuv411, .Yuv420, .Yuv422, .Yuv444]
    let options = Y4m.EncodeOptions{Layouts[layout]}
    var writer  = expect Writer.createMemory("output.y4m", &buffer, width, height, rate, options)
    var cpuStart, cpuStop: Linux.timespec
    Swag.require(Linux.clock_gettime(Linux.CLOCK_PROCESS_CPUTIME_ID, &cpuStart) == 0)
    var watch: Time.Stopwatch
    watch.start()
    for &image in frames do
        expect writer.addFrame(image[])
    watch.stop()
    Swag.require(Linux.clock_gettime(Linux.CLOCK_PROCESS_CPUTIME_ID, &cpuStop) == 0)
    expect writer.end()
    let cpu = (cpuStop.tv_sec - cpuStart.tv_sec) * 1_000_000 + (cpuStop.tv_nsec - cpuStart.tv_nsec) / 1_000
    buffer.makeLinear()
    var file    = expect File.open(args[7], .Create, .Write, .Read)
    let payload = unwrap buffer.toSlice()
    expect file.writeAll(payload)
    Console.printf("Y4M frames=% us=% cpu_us=% bytes=%\n", count, watch.elapsedMicroseconds(), cpu, payload.count)
}
