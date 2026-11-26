using Core, Gui.Pdf

#main
{
    let args = Env.arguments()
    Swag.require(args.count == 4)
    let copies = expect StrConv.toU32(args[2])
    let repetitions = expect StrConv.toU32(args[3])
    Swag.require(copies and repetitions)
    Swag.setWorkerCount(1)
    Swag.startWorkers()
    var reader = expect Reader.open(args[1])
    let warmup = expect reader.loadPage(0)
    Swag.require(warmup.items.count > 0)
    for repetitions
    {
        let begin = Time.monotonicTicks()
        var loaded: Array'Page
        loaded.reserve(copies)
        for copies
        {
            var page = #move expect reader.loadPage(0)
            loaded.add(#move page)
        }
        let finish = Time.monotonicTicks()
        Swag.require(loaded.count == copies and loaded[copies - 1].items.count == warmup.items.count)
        Console.println(Time.monotonicFrequency(), " ", finish - begin, " ", loaded.count)
    }
}
