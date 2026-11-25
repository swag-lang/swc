#global internal
#global namespace Print

using Core, Pixel

func writePdf(layout: const *Layout, options: JobOptions, fileName: string) fail
{
    if options.first >= options.end or options.end > layout.pageCount do
        fail PrintError{.InvalidRange}

    var output = try File.open(fileName, .CreateNew, .Write, .Delete)
    try Pdf.writeGeneratedDocument(&output, options.end - options.first, func|layout, first = options.first|(index)->Pdf.Page fail
    {
        var image = #move try layout.render(first + index, OutputDpi)
        image.convertTo(.RGB8)
        let size = layout.sheet.size
        var page = Pdf.Page.create(size.x, size.y)
        page.addImage(image, 0, 0, size.x, size.y)
        return #move page
    })
    try output.flush()
}

func savePdf(layout: const *Layout, options: JobOptions, target: string) fail
{
    let folder    = Path.directoryName(target) orelse "."
    let temporary = Path.combine(folder, Format.toString(".swag-print-%.tmp", Guid128.random()))
    defer discard catch File.delete(temporary)
    try writePdf(layout, options, temporary)
    try checkCancelled()
    try File.move(target, temporary)
}
