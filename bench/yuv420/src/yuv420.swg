using Core, Pixel

#[Swag.Safety(.Assert, true)]
func measure(width, height: s32, repeats: u32)
{
    let lumaSize    = cast(u64) width * cast(u64) height
    let chromaWidth = cast(u64) ((width + 1) / 2)
    let chromaSize  = chromaWidth * cast(u64) ((height + 1) / 2)
    var storage: Array'u8
    storage.resize(lumaSize + chromaSize * 2 + 16)
    for index in storage.count do
        storage[index] = cast(u8) ((index * 37 + index / 97) & 255)
    let view     = Yuv420View{luma: storage.buffer!, chromaB: storage.buffer! + lumaSize, chromaR: storage.buffer! + lumaSize + chromaSize, lumaStride: cast(u64) width, chromaStride: chromaWidth, width: width, height: height}
    var expected = Image.create(width, height, .RGB8)
    view.convertRowsToRgb(&expected, 0, height)
    var image = Image.create(width, height, .RGB8)
    for warmup in 32 do
        view.convertToRgb(&image)
    for sample in 3
    {
        var watch: Time.Stopwatch
        watch.start()
        for repeat in repeats do
            view.convertToRgb(&image)
        watch.stop()
        for index in image.byteCount do
            Swag.assert(image.pixels[index] == expected.pixels[index])
        Console.println(width, "x", height, " workers=", Swag.workerCount(), " sample=", sample, " repeats=", repeats, " us=", watch.elapsedMicroseconds())
    }
}

#main
{
    let workers: [2] u32 = [1, 4]
    for count in workers
    {
        Swag.setWorkerCount(count)
        Swag.startWorkers()
        measure(16, 16, 10000)
        measure(320, 181, 200)
        measure(1920, 1080, 20)
        measure(3840, 2161, 5)
    }
}
