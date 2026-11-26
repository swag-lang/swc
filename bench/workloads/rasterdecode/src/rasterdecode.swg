using Core, Pixel

#main
{
    let args = Env.arguments()
    Swag.require(args.count == 2)
    Swag.setWorkerCount(1)
    Swag.startWorkers()

    // The first load warms the file cache and decoder. Read back only the measured image.
    discard expect Image.load(args[1])
    var watch: Time.Stopwatch
    watch.start()
    let image = expect Image.load(args[1])
    watch.stop()
    let format = image.pixelFormat
    Console.println(watch.elapsedMicroseconds(), " ", image.width, " ", image.height, " ", format.channels(), " ", format.bitDepth(), " ", cast(u8, format.isFloat()), " ", cast(u8, format), " ", Hash.Crc64.compute(image.pixels.toSlice()))
}
