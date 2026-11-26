using Core, Gui, Gui.Pdf, Pixel

func measurePage(path: string, pageIndex: u32, side: s32, report: bool, stage: *string) fail
{
    stage[] = "open"
    let begin  = Time.monotonicTicks()
    var reader = try Reader.open(path)
    let opened = Time.monotonicTicks()

    stage[] = "load"
    var page   = try reader.loadPage(pageIndex)
    let loaded = Time.monotonicTicks()

    stage[] = "render"
    let scale    = cast(f32, side) / Math.max(page.width, page.height)
    let image    = try page.render({scale: scale, maxDimension: side + 1})
    let rendered = Time.monotonicTicks()
    if not report do
        return

    Swag.require(image.pixelFormat == .BGRA8)
    var items: [3] u64
    for item in page.items do
        items[cast(u32, item.kind)] += 1

    // A sampled ink count helps identify pages where one engine drew much less content.
    var ink = 0'u32
    for y in 32
    {
        for x in 32
        {
            let color = image.pixelColor(cast(s32, x) * image.width / 32, cast(s32, y) * image.height / 32)
            if (color.argb & 0x00FF_FFFF) != 0x00FF_FFFF do
                ink += 1
        }
    }

    Console.println("ok ",
                    Time.monotonicFrequency(),
                    " ",
                    opened - begin,
                    " ",
                    loaded - opened,
                    " ",
                    rendered - loaded,
                    " ",
                    image.width,
                    " ",
                    image.height,
                    " ",
                    Hash.Crc32.compute(image.pixels.toSlice()),
                    " ",
                    ink,
                    " ",
                    items[cast(u32, ItemKind.Text)],
                    " ",
                    items[cast(u32, ItemKind.Path)],
                    " ",
                    items[cast(u32, ItemKind.Image)])
}

#main
{
    let args = Env.arguments()
    Swag.require(args.count == 5)
    let pageIndex   = expect StrConv.toU32(args[2])
    let side        = expect StrConv.toS32(args[3])
    let repetitions = expect StrConv.toU32(args[4])
    Swag.setWorkerCount(1)
    Swag.startWorkers()

    for iteration in repetitions + 1
    {
        var stage = "open"
        var outcome: Swag.Error
        catch { try measurePage(args[1], pageIndex, side, iteration != 0, &stage) } as outcome
        if not outcome.isEmpty()
        {
            Console.println("error ", stage, " ", Errors.message(outcome.value()))
            return
        }
    }
}
