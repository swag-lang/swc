using Core, Pixel

#main
{
    func parseDrawing(source: string)->Svg.Drawing
    {
        #static if #hastag("Benchmark.SvgScope") do
            return expect Svg.Drawing.parse(source, {preferScanFills: true})
        else do
            return expect Svg.Drawing.parse(source)
    }

    let args = Env.arguments()
    Swag.require(args.count == 5)
    let source  = expect File.readAllText(args[1])
    let width   = expect StrConv.toS32(args[2])
    let height  = expect StrConv.toS32(args[3])
    let workers = expect StrConv.toU32(args[4])
    Swag.setWorkerCount(workers)
    Swag.startWorkers()
    Swag.require(Swag.workerCount() == workers)

    // A fresh drawing includes first-paint geometry preparation in every timed sample.
    for sample in 2
    {
        var watch: Time.Stopwatch
        watch.start()
        let drawing = parseDrawing(source.toString())
        let parse   = watch.elapsedMicroseconds()
        let image   = drawing.rasterize(width, height, 1)
        watch.stop()
        let total = watch.elapsedMicroseconds()
        Swag.require(image.isValid())
        if sample do
            Console.println(parse, " ", total - parse, " ", total, " ", Hash.Crc64.compute(image.pixels.toSlice()))
    }
}
