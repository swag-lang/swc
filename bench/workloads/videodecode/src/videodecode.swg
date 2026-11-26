using Core, Video

#main
{
    func exportPlanes(reader: *Reader, timestamps, output: string, dense: bool)
    {
        let text  = expect File.readAllText(timestamps)
        var file  = expect File.open(output, .Create, .Write, .Read)
        var picture: PlanarFrame
        var rank  = 0'u64
        let count = reader.frameCount()
        const Tolerance = 0.0000005
        for line in Tokenize.splitLines(text.toString()) where line.count
        {
            let seconds = expect StrConv.toF64(line)
            if not dense
            {
                while rank < count and reader.frameTimestamp(rank) < seconds - Tolerance do
                    rank += 1
            }

            Swag.require(rank < count and Math.abs(reader.frameTimestamp(rank) - seconds) <= Tolerance)
            Swag.require(rank + 1 == count or reader.frameTimestamp(rank + 1) > seconds + Tolerance)
            expect reader.decodeFramePlanesInto(&picture, rank)
            expect file.writeAll(picture.luma.toSlice())
            expect file.writeAll(picture.chromaB.toSlice())
            expect file.writeAll(picture.chromaR.toSlice())
            rank += 1
        }

        if dense do
            Swag.require(rank == count)
    }

    func measure(path: string, repetitions: u32, expectedCount: u64, warmup: u64)
    {
        var elapsed: Array'u64
        var count = 0'u64
        for repetition in cast(u64, repetitions) + 1
        {
            var reader       = expect Reader.open(path, pictureOnly: true)
            let indexedCount = reader.frameCount()
            count = expectedCount ? expectedCount : indexedCount
            Swag.require(not indexedCount or count == indexedCount)
            Swag.require(reader.hasPlanarFrames() and count > warmup)
            var picture: PlanarFrame
            for rank in warmup do
                expect reader.decodeFramePlanesInto(&picture, rank)

            var watch: Time.Stopwatch
            watch.start()
            for rank in warmup until count do
                expect reader.decodeFramePlanesInto(&picture, rank)
            watch.stop()
            if repetition do
                elapsed.add(watch.elapsedTicks())
        }

        for ticks in elapsed do
            Console.printf("video frames=% ticks=% frequency=%\n", count - warmup, ticks, Time.monotonicFrequency())
    }

    Swag.startWorkers()
    let args = Env.arguments()
    if (args.count == 4 or args.count == 6) and args[1] == "time"
    {
        let repetitions = expect StrConv.toU32(args[3])
        let count       = args.count == 6 ? (expect StrConv.toU64(args[4])) : 0'u64
        let warmup      = args.count == 6 ? (expect StrConv.toU64(args[5])) : 30'u64
        measure(args[2], repetitions, count, warmup)
    }
    else
    {
        Swag.require(args.count == 5 and (args[1] == "planes" or args[1] == "planes-dense"))

        // A memory source indexes the complete Matroska timeline at open.
        let data   = expect File.readAllBytes(args[2])
        var reader = expect Reader.openMemory(args[2], data.toSlice(), pictureOnly: true)
        Swag.require(reader.hasPlanarFrames() and reader.frameCount())
        exportPlanes(&reader, args[3], args[4], args[1] == "planes-dense")
    }
}
