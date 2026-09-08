// bin/swc.dm.exe test -f src/resize.test.swg --module-file bench/resize/module.swg -bc release --no-test-jit --num-cores 6
#global if #command == Swag.CompilerCommand.Test

using Core, Pixel

#test
{
    let sizes:   [5] s32 = [8, 32, 64, 256, 1024]
    let workers: [2] u32 = [1, 4]
    for count in workers
    {
        Swag.setWorkerCount(count)
        Swag.startWorkers()
        Swag.assert(Swag.workerCount() == count)
        for size in sizes
        {
            var source = Image.create(size * 2 + 1, size * 2 - 1, .RGBA8)
            for index in source.byteCount do
                source.pixels[index] = cast(u8) ((index * 47 + 13) & 0xFF)
            let iterations = Math.max(2, 131072 / (size * size))
            let reference  = source.resized(size, size, .Bicubic)
            for sample in 3
            {
                var watch: Time.Stopwatch
                watch.start()
                for iteration in iterations
                {
                    let output = source.resized(size, size, .Bicubic)
                    Swag.assert(output.byteCount == reference.byteCount)
                }

                watch.stop()
                let output = source.resized(size, size, .Bicubic)
                Swag.assert(Memory.compare(output.pixels.buffer, reference.pixels.buffer, output.byteCount) == 0)
                Console.println("resize size=", size, " workers=", count, " iterations=", iterations, " sample=", sample, " us=", watch.elapsedMicroseconds())
            }
        }
    }
}
