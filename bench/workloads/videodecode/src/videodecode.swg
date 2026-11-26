using Core, Pixel, Video

private func(T) decodeTimedPicture(reader: *Reader, picture: *T, rank: u64) fail
{
    catch
    {
        #static if T == Image
        {
            try reader.decodeFrameInto(picture, rank)
        }
        else
        {
            try reader.decodeFramePlanesInto(picture, rank)
        }
    }
    {
        Console.println("cannot decode video frame ", rank)
        fail Swag.err
    }
}

#main
{
    func(T) exportPictures(reader: *Reader, timestamps, output: string, dense: bool)
    {
        let text  = expect File.readAllText(timestamps)
        var file  = expect File.open(output, .Create, .Write, .Read)
        var picture: T
        var rank  = 0_u64
        let count = reader.frameCount()
        const Tolerance = 0.0000005
        for line in Tokenize.splitLines(text.toString()) where line.count
        {
            let seconds = expect StrConv.toF64(line)
            if not dense
            {
                while rank < count and reader.frameTimestamp(rank) < seconds - Tolerance
                {
                    rank += 1
                }
            }

            Swag.require(rank < count and Math.abs(reader.frameTimestamp(rank) - seconds) <= Tolerance)
            Swag.require(rank + 1 == count or reader.frameTimestamp(rank + 1) > seconds + Tolerance)
            #static if T == Image
            {
                expect reader.decodeFrameInto(&picture, rank)
                Swag.require(picture.pixelFormat == .RGB8)
                let stride = cast(u64, picture.rowStride)
                for row in cast(u64, picture.height)
                {
                    let offset = (cast(u64, picture.height) - 1 - row) * stride
                    expect file.writeAll(picture.pixels.toSlice()[offset until offset + stride])
                }
            }
            else
            {
                expect reader.decodeFramePlanesInto(&picture, rank)
                expect file.writeAll(picture.luma.toSlice())
                expect file.writeAll(picture.chromaB.toSlice())
                expect file.writeAll(picture.chromaR.toSlice())
            }

            rank += 1
        }

        if dense
        {
            Swag.require(rank == count)
        }
    }

    func(T) measure(path: string, repetitions: u32, frameLimit: u64, warmup: u64)
    {
        var elapsed: Array!{u64}
        var count = 0_u64
        for repetition in cast(u64, repetitions) + 1
        {
            var reader       = expect Reader.open(path, pictureOnly: true)
            let indexedCount = reader.frameCount()
            count = frameLimit ? frameLimit : indexedCount
            Swag.require(not indexedCount or count <= indexedCount)
            Swag.require(count > warmup)
            #static if T == PlanarFrame
            {
                Swag.require(reader.hasPlanarFrames())
            }

            var picture: T
            for rank in warmup
            {
                expect decodeTimedPicture!{T}(&reader, &picture, rank)
            }

            var watch: Time.Stopwatch
            watch.start()
            for rank in warmup until count
            {
                expect decodeTimedPicture!{T}(&reader, &picture, rank)
            }

            watch.stop()
            if repetition
            {
                elapsed.add(watch.elapsedTicks())
            }
        }

        for ticks in elapsed
        {
            Console.printf("video frames=% ticks=% frequency=%\n", count - warmup, ticks, Time.monotonicFrequency())
        }
    }

    Swag.startWorkers()
    let args = Env.arguments()
    if (args.count == 4 or args.count == 6) and (args[1] == "time" or args[1] == "time-rgb")
    {
        let repetitions = expect StrConv.toU32(args[3])
        let frameLimit  = args.count == 6 ? (expect StrConv.toU64(args[4])) : 0_u64
        let warmup      = args.count == 6 ? (expect StrConv.toU64(args[5])) : 30_u64
        if args[1] == "time-rgb"
        {
            measure!{Image}(args[2], repetitions, frameLimit, warmup)
        }
        else
        {
            measure!{PlanarFrame}(args[2], repetitions, frameLimit, warmup)
        }
    }
    else
    {
        Swag.require(args.count == 5)

        // A memory source indexes the complete Matroska timeline at open.
        let data   = expect File.readAllBytes(args[2])
        var reader = expect Reader.openMemory(args[2], data.toSlice(), pictureOnly: true)
        Swag.require(reader.frameCount())
        if args[1] == "rgb" or args[1] == "rgb-dense"
        {
            exportPictures!{Image}(&reader, args[3], args[4], args[1] == "rgb-dense")
        }
        else
        {
            Swag.require(reader.hasPlanarFrames() and (args[1] == "planes" or args[1] == "planes-dense"))
            exportPictures!{PlanarFrame}(&reader, args[3], args[4], args[1] == "planes-dense")
        }
    }
}
