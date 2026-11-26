using Core, Gui, Gui.Pdf, Pixel

func generateDocument(kind: string)->Document
{
    var document = Document.create()
    document.metadata.title = "PDF writer benchmark"
    if kind == "vectors"
    {
        for pageIndex in 12
        {
            var page = Page.create(612, 792)
            var square: LinePathList
            let path = square.newPath()
            path.start(0, 0)
            path.lineTo(14, 0)
            path.lineTo(14, 8)
            path.lineTo(0, 8)
            path.close()
            for i in 800
            {
                let x = 20.25 + cast(f32, i % 30) * 18.5
                let y = 20.75 + cast(f32, i / 30) * 24.5
                if i % 4 == 0 do
                    page.addText("Quarterly output (USD)", x, y, 10, Color.fromRgb(64, 32, 128))
                else
                {
                    page.addPath(square, fillColor: Color.fromRgb(10, 130, 210), stroke: i % 10 == 0)
                    page.setItemTransform(i, Math.Transform2.createTranslation(x, y + cast(f32, pageIndex % 5)))
                }
            }

            document.addPage(#move page)
        }

        return document
    }

    let gray = kind == "gray"
    let rgb = kind == "rgb"
    let transparent = kind == "alpha"
    Swag.require(gray or rgb or transparent or kind == "opaque" or kind == "repeated")
    let width = 1801
    let height = 1199
    var image = Image.create(width, height, rgb ? .RGB8 : .BGRA8)
    let stride = cast(u64, image.bytesPerPixel)
    for y in cast(u64, height)
    {
        for x in cast(u64, width)
        {
            let i = (y * cast(u64, width) + x) * stride
            let shade = (x / 8 + y / 3 + (x * y) / 4096) & 255
            image.pixels[i + 0] = cast(u8, shade)
            image.pixels[i + 1] = cast(u8, gray ? shade : (shade + x / 13) & 255)
            image.pixels[i + 2] = cast(u8, gray ? shade : (shade + y / 11) & 255)
            if not rgb do
                image.pixels[i + 3] = cast(u8, transparent ? (x / 3 + y / 4) & 255 : 255)
        }
    }

    for kind == "repeated" ? 8 : 1
    {
        var page = Page.create(612, 792)
        page.addImage(image, 16, 32, 580, 380)
        document.addPage(#move page)
    }

    return document
}

#main
{
    let args = Env.arguments()
    Swag.require(args.count == 5)
    let mode = args[2]
    Swag.require(mode == "save" or mode == "encode")
    let repetitions = expect StrConv.toU32(args[3])
    let path = args[4]
    Swag.setWorkerCount(1)
    Swag.startWorkers()
    let document = Path.hasExtension(args[1], ".pdf") ? (expect Document.load(args[1])) : generateDocument(args[1])
    for iteration in repetitions + 1
    {
        var bytes: Array'u8
        let started = Time.monotonicTicks()
        if mode == "save" do
            expect document.save(path)
        else do
            bytes = #move expect document.encode()
        let finished = Time.monotonicTicks()
        if mode == "save" do
            bytes = #move expect File.readAllBytes(path)
        if iteration do
            Console.println(Time.monotonicFrequency(), " ", finished - started, " ", bytes.count, " ", Hash.Crc32.compute(bytes.toSlice()))
    }
}
