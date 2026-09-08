using Core, Pixel

#[Swag.Safety(.Assert, true)]
#main
{
    let sizes:   [5] s32 = [8, 32, 128, 512, 2048]
    let workers: [2] u32 = [1, 4]
    for count in workers
    {
        Swag.setWorkerCount(count)
        Swag.startWorkers()
        Swag.assert(Swag.workerCount() == count)
        for size in sizes
        {
            var image = Image.create(size, size, .RGBA8)
            for index in image.byteCount do
                image.pixels[index] = cast(u8) ((index * 47 + 13) & 0xFF)
            let iterations = Math.max(4, 1048576 / (size * size))
            image.invert()
            image.invert()
            for sample in 3
            {
                var watch: Time.Stopwatch
                watch.start()
                for iteration in iterations do
                    image.invert()
                watch.stop()
                for index in image.byteCount do
                    Swag.assert(image.pixels[index] == cast(u8) ((index * 47 + 13) & 0xFF))
                Console.println("invert size=", size, " workers=", count, " iterations=", iterations, " sample=", sample, " us=", watch.elapsedMicroseconds())
            }
        }
    }
}
